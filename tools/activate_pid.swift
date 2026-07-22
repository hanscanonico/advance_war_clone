// Bring the app owning the given unix pid back to the front. Used by
// tools/godot_gui.sh to hand focus back to whatever the user was on after a
// Godot launch steals it. By pid, not bundle id, because the app to restore
// may itself be a Godot (the editor) and bundle-id lookups can't tell the
// editor from the game instance that just stole the focus.
import AppKit

guard CommandLine.arguments.count == 2,
	let pid = Int32(CommandLine.arguments[1]),
	let app = NSRunningApplication(processIdentifier: pid)
else {
	exit(1)
}
exit(app.activate(options: [.activateIgnoringOtherApps]) ? 0 : 1)
