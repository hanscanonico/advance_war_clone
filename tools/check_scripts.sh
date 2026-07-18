#!/usr/bin/env bash
#
# Parse- and type-checks every GDScript file in the project.
#
# `godot --check-only -s <file>` runs the full GDScript analyser — it catches
# type mismatches and unknown identifiers, not just syntax — but always exits 0,
# so this wrapper scans its output for diagnostics and sets the status itself.
#
# Usage:  tools/check_scripts.sh   (see the `check` target in the Makefile)
#
# Much faster than `make test` for "does what I just wrote compile?": it skips
# booting the scene tree and GUT.

set -uo pipefail

GODOT="${GODOT:-bin/Godot.app/Contents/MacOS/Godot}"

if [[ ! -x "$GODOT" ]]; then
	echo "check: Godot binary not found at $GODOT" >&2
	echo "check: see README.md for engine setup, or pass GODOT=<path>" >&2
	exit 1
fi

# Autoload singletons are global identifiers at runtime, but --check-only never
# instantiates them, so every use reads as "Identifier not found". Build an
# ignore pattern from the names project.godot actually registers — a typo'd
# singleton name still fails, because it won't be in this list.
autoloads="$(
	awk '/^\[autoload\]/ {inside = 1; next}
	     /^\[/ {inside = 0}
	     inside && /=/ {split($0, kv, "="); print kv[1]}' project.godot |
		paste -sd '|' -
)"
if [[ -n "$autoloads" ]]; then
	ignore="Identifier not found: ($autoloads)\$"
else
	ignore='a^' # matches nothing
fi

failed=0
checked=0

# bash 3.2 (macOS system bash) has no mapfile, so stream the paths instead.
while IFS= read -r file; do
	checked=$((checked + 1))
	# Strip the leading './' so reported paths line up with res:// paths.
	output="$("$GODOT" --headless --path . --check-only -s "${file#./}" 2>&1 |
		grep -vE "$ignore")"
	if grep -qE 'SCRIPT ERROR|Parse Error' <<<"$output"; then
		grep -E 'SCRIPT ERROR|Parse Error|^ +at:' <<<"$output"
		failed=$((failed + 1))
	fi
done < <(
	# .claude/worktrees holds whole nested checkouts of this same repo; without
	# excluding it every project file gets checked twice, once at a path Godot
	# cannot resolve res:// imports for.
	find . -name '*.gd' \
		-not -path './.godot/*' \
		-not -path './addons/*' \
		-not -path './bin/*' \
		-not -path './.claude/*' |
		sort
)

if ((failed > 0)); then
	echo "check: $failed of $checked file(s) failed to parse" >&2
	exit 1
fi

echo "check: $checked files OK"
