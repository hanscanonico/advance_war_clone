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
# Generous: `aiturn` plays a whole AI turn with per-command animation delays.
# This only has to catch a genuinely stuck scene, not time anything.
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
DEFAULT_MODES=(
	attack resolve capture build buildmenu endturn
	load cargo drop transport supply mapmenu powermenu victory aiturn
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
	run_with_timeout "$SMOKE_TIMEOUT" "$GODOT" "${godot_args[@]}"
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
