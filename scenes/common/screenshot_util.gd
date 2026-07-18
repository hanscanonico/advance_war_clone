class_name ScreenshotUtil
extends RefCounted
## Shared --screenshot support for scenes: wait for the first frames to
## render, save the viewport, and quit. Used for automated visual checks.


static func capture_and_quit(node: Node, path: String) -> void:
	for i in 8:
		await node.get_tree().process_frame
	var image := node.get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("screenshot: saved to %s (err=%d)" % [path, err])
	node.get_tree().quit()
