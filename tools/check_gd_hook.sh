#!/usr/bin/env bash
#
# Claude Code PostToolUse hook: parse- and type-check the one GDScript file an
# agent just wrote, via tools/check_scripts.sh, so a compile error comes back
# as immediate feedback instead of surfacing at the next `make verify`.
#
# Reads the hook payload on stdin and exits 2 with the diagnostics on stderr
# when the file fails to compile — exit 2 is the code Claude Code feeds back to
# the agent. Anything that is not a project .gd file is silently skipped.
#
# .claude/ is gitignored, so the wiring is per-machine. To enable, add to
# .claude/settings.json:
#
#   {
#     "hooks": {
#       "PostToolUse": [
#         {
#           "matcher": "Edit|Write",
#           "hooks": [
#             { "type": "command",
#               "command": "\"$CLAUDE_PROJECT_DIR\"/tools/check_gd_hook.sh" }
#           ]
#         }
#       ]
#     }
#   }

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:?}" || exit 0

file="$(jq -r '.tool_input.file_path // empty')"
[[ "$file" == *.gd ]] || exit 0

# Normalize to a project-relative path; edits outside the project (memory,
# scratchpad) are none of our business.
case "$file" in
	"$PWD"/*) rel="${file#"$PWD"/}" ;;
	/*) exit 0 ;;
	*) rel="$file" ;;
esac

# Same exclusions as the full sweep in check_scripts.sh. Worktrees under
# .claude/ are whole nested checkouts where res:// imports don't resolve from
# here; their own session checks them.
case "$rel" in
	.godot/* | addons/* | bin/* | .claude/*) exit 0 ;;
esac

[[ -f "$rel" ]] || exit 0

if ! output="$(tools/check_scripts.sh "$rel" 2>&1)"; then
	echo "$output" >&2
	exit 2
fi
