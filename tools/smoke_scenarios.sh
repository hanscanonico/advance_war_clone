#!/usr/bin/env bash
#
# Presentation smoke check: boots the battle scene once per demo scenario and
# proves each one still reaches its capture.
#
# This is deliberately NOT a GUT suite. GUT stays limited to core/ and ai/,
# which are Node-free; the battle scene is verified by driving it. Each demo
# runs the real handlers a player's input reaches (see _run_demo in
# battle_scenario_driver.gd), so a scenario that stops producing a frame means
# the flow it exercises has broken — a menu never opened, a state was never
# reached, or the scene crashed on the way.
#
# Usage:  tools/smoke_scenarios.sh [mode ...]   (see the `smoke` target)
#
# A mode may carry a `+fog` suffix — `victory+fog` is the victory scenario run
# with fog of war on. Fog is the one setting under which this scene *hides*
# units rather than merely drawing them, so a couple of fogged runs are part of
# the sweep; the mode name is the label and the capture filename, so a failure
# says which of the two it was.
#
# With no arguments it runs DEFAULT_MODES. Captures land in a temporary
# directory that is removed on exit unless SMOKE_KEEP is set, in which case the
# path is printed so the frames can be eyeballed.
#
# Needs a display: these runs render. They are not headless, so this is a local
# gate, not something to wire into a headless CI job as-is.

set -uo pipefail

GODOT="${GODOT:-bin/Godot.app/Contents/MacOS/Godot}"
BATTLE="${BATTLE:-scenes/battle/battle.tscn}"
# Every scenario opens a window. Launching through the wrapper keeps a
# scripted/agent run (no tty) from stealing the user's window focus 26 times;
# interactive runs exec $GODOT directly as before. The wrapper `exec`s the
# engine, so run_with_timeout's kill still lands on the Godot process itself.
export GODOT
GODOT_GUI="$(cd "$(dirname "$0")" && pwd)/godot_gui.sh"
# Generous: `aiturn` plans and applies a whole AI turn. Captures pin the Instant
# game speed, so no tween is being waited on; this only has to catch a genuinely
# stuck scene, not time anything.
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-90}"
# A frame that renders the map is tens of KB; anything this small is a blank or
# truncated capture, which means the scene never really came up.
MIN_BYTES="${SMOKE_MIN_BYTES:-2000}"

# One per branch of the interaction flow: targeting preview and resolved
# combat, capture, the build menu and a completed build, the map menu and the
# turn it ends, the load/drive/drop transport chain, supply, a Command Power
# fired from the HUD over an open menu, victory, and a full AI turn.
#
# Two of them run again under fog, where the sprite-hiding path exists at all:
# powermenu+fog fires a power, which redraws every sprite on the board at once,
# and victory+fog edits the sim behind the scene's back and resyncs. Both used
# to leak enemy positions.
#
# ambush and vanish turn fog on themselves — they are the same board with Sable
# Wren's power down and up, and only the second one may hide anything. Running
# both is what keeps `vanish` honest: a board that hid those units for some
# unrelated reason would pass on its own, but it would take `ambush` down with
# it.
# The commander-identity captures (power_ready/active/banner, commander_info and
# commander_victory) are the G3 gate: the HUD chip's charging/ready/active
# states, the activation card, the both-sides info sheet, and the victory lockup,
# each proved to still render at native 640x360.
#
# `cutin` is the odd one out: every other mode drives the flow and photographs
# what it produces, but the battle cut-in is deliberately suppressed while
# capturing (a mid-tween frame is what made the camera shake undeterministic), so
# that mode poses the overlay at a fixed moment of its own clock instead. It is
# still a real check — the pose runs the real resolver and the real staging, so a
# cut-in that stopped rendering, or a unit or terrain it could not draw, fails
# here rather than in play.
DEFAULT_MODES=(
	attack resolve cutin capture build buildmenu endturn
	load cargo drop transport supply divemenu dive mapmenu powermenu victory aiturn
	powermenu+fog victory+fog ambush vanish
	power_ready power_active power_banner commander_info commander_victory
)

if [[ ! -x "$GODOT" ]]; then
	echo "smoke: Godot binary not found at $GODOT" >&2
	echo "smoke: see README.md for engine setup, or pass GODOT=<path>" >&2
	exit 1
fi

modes=("$@")
if ((${#modes[@]} == 0)); then
	modes=("${DEFAULT_MODES[@]}")
fi

out_dir="$(mktemp -d "${TMPDIR:-/tmp}/battle-smoke.XXXXXX")"
cleanup() {
	if [[ -n "${SMOKE_KEEP:-}" ]]; then
		echo "smoke: captures kept in $out_dir"
	else
		rm -rf "$out_dir"
	fi
}
trap cleanup EXIT

# macOS ships no coreutils `timeout`, so poll the child ourselves. A scenario
# that never reaches its state would otherwise block forever in _run_demo's
# `while state != ...` loop.
run_with_timeout() {
	local seconds="$1"
	shift
	"$@" >"$out_dir/last.log" 2>&1 &
	local pid=$!
	local waited=0
	while kill -0 "$pid" 2>/dev/null; do
		if ((waited >= seconds)); then
			kill -9 "$pid" 2>/dev/null
			wait "$pid" 2>/dev/null
			return 124
		fi
		sleep 1
		waited=$((waited + 1))
	done
	wait "$pid"
}

failed=0
for mode in "${modes[@]}"; do
	shot="$out_dir/$mode.png"
	printf 'smoke: %-14s ' "$mode"
	# `victory+fog` is the victory demo with fog on; anything else is the demo
	# name as written.
	demo="${mode%+fog}"
	godot_args=(--path . "$BATTLE" -- "--screenshot=$shot" "--demo=$demo")
	if [[ "$demo" != "$mode" ]]; then
		godot_args+=(--fog)
	fi
	# The naval scenarios need a board with water on it; the default has none.
	case "$demo" in
		divemenu | dive) godot_args+=(--map=the_straits) ;;
	esac
	run_with_timeout "$SMOKE_TIMEOUT" "$GODOT_GUI" "${godot_args[@]}"
	status=$?

	if ((status == 124)); then
		echo "TIMEOUT after ${SMOKE_TIMEOUT}s"
		failed=$((failed + 1))
		continue
	fi
	# The scene quits through get_tree().quit(), so a non-zero status here is a
	# real crash and not the engine's noisy-but-harmless exit diagnostics.
	if ((status != 0)); then
		echo "FAILED (exit $status)"
		sed -n '1,20p' "$out_dir/last.log" >&2
		failed=$((failed + 1))
		continue
	fi
	if [[ ! -f "$shot" ]]; then
		echo "FAILED (no capture written)"
		failed=$((failed + 1))
		continue
	fi
	# stat's portable-ish size flag differs between BSD and GNU.
	bytes="$(wc -c <"$shot" | tr -d ' ')"
	if ((bytes < MIN_BYTES)); then
		echo "FAILED (capture only ${bytes}B, expected >= ${MIN_BYTES}B)"
		failed=$((failed + 1))
		continue
	fi
	echo "ok (${bytes}B)"
done

if ((failed > 0)); then
	echo "smoke: $failed of ${#modes[@]} scenario(s) failed" >&2
	exit 1
fi

echo "smoke: ${#modes[@]} scenarios OK"
