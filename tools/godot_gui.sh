#!/usr/bin/env bash
#
# Windowed Godot launcher that gives the user their focus back.
#
# This engine build (4.7.1) activates its window unconditionally on startup:
# no CLI flag, `open -g`, bundle-id trickery, or the no_focus window flag
# stops the app from becoming frontmost — all four were tried. So the steal
# is undone instead: watch for the moment the launched instance becomes the
# frontmost app, then re-activate whatever the user was on. The focus loss
# shrinks from the whole run to a sub-second blip.
#
# A launch from an interactive terminal execs Godot directly — a human who
# starts the game wants it focused. Agent and script launches (no tty) get
# the restore behavior.
#
# Usage: [GODOT=<binary>] tools/godot_gui.sh <godot args...>
#
# The wrapper ends in `exec`, so its pid, exit status, and stdio are Godot's
# own — timeout-and-kill callers (smoke_scenarios.sh) need no special casing.

set -u

GODOT="${GODOT:-bin/Godot.app/Contents/MacOS/Godot}"

if [[ -t 0 || -t 1 || -t 2 ]] || [[ "$(uname)" != "Darwin" ]]; then
	exec "$GODOT" "$@"
fi

# The restore helper activates an app by unix pid (see activate_pid.swift for
# why pid). Compiled once into the gitignored .godot/ cache. Without a Swift
# toolchain, fall back to LaunchServices by bundle id, which restores every
# previous app except another Godot.
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
activate_bin="$repo_dir/.godot/activate_pid"
activate_src="$repo_dir/tools/activate_pid.swift"
if command -v swiftc >/dev/null 2>&1; then
	if [[ ! -x "$activate_bin" || "$activate_src" -nt "$activate_bin" ]]; then
		mkdir -p "$repo_dir/.godot"
		swiftc -O -suppress-warnings -o "$activate_bin" "$activate_src" \
			2>/dev/null || rm -f "$activate_bin"
	fi
fi

front_pid() {
	lsappinfo info -only pid "$(lsappinfo front)" | sed -E 's/[^0-9]*([0-9]+).*/\1/'
}
front_bundle() {
	lsappinfo info -only bundleid "$(lsappinfo front)" |
		sed -E 's/.*"CFBundleIdentifier"="([^"]*)".*/\1/'
}

# $$ survives the exec below, so inside the watcher it names the game process.
game_pid=$$
(
	prev_pid="$(front_pid)"
	prev_bundle="$(front_bundle)"
	for _ in $(seq 1 100); do
		kill -0 "$game_pid" 2>/dev/null || exit 0
		now="$(front_pid)"
		if [[ "$now" == "$game_pid" ]]; then
			if [[ -x "$activate_bin" ]]; then
				"$activate_bin" "$prev_pid" 2>/dev/null
			elif [[ -n "$prev_bundle" && "$prev_bundle" != "org.godotengine.godot" ]]; then
				open -b "$prev_bundle"
			fi
			exit 0
		fi
		# Keep tracking where the user actually is: they may switch apps
		# between our launch and the steal.
		if [[ -n "$now" ]]; then
			prev_pid="$now"
			prev_bundle="$(front_bundle)"
		fi
		sleep 0.1
	done
) &

exec "$GODOT" "$@"
