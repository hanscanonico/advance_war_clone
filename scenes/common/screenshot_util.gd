class_name ScreenshotUtil
extends RefCounted
## Shared --screenshot support for scenes: wait for the first frames to
## render, save the viewport, and quit. Used for automated visual checks.

const SCREENSHOT_ARG := "--screenshot="


## The path `--screenshot=` asked for, or "" on an ordinary run. A scene that
## photographs itself asks this instead of rescanning the command line — and it
## is also how it knows to pin whatever a capture must not vary on, such as the
## device's speed preference.
static func requested() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(SCREENSHOT_ARG):
			return arg.get_slice("=", 1)
	return ""


static func capture_and_quit(node: Node, path: String) -> void:
	for i in 8:
		await node.get_tree().process_frame
	var image := node.get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("screenshot: saved to %s (err=%d)" % [path, err])
	node.get_tree().quit()
