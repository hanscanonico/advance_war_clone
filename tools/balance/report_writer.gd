class_name BalanceReportWriter
extends RefCounted
## Writes a balance run's artifacts: CSV tables, a JSON summary, and the
## per-command JSONL log.
##
## Shared by the commander matrix, the difficulty ladder and the Balance Lab so
## the three write the same shapes — and, for the two committed gates, the same
## bytes they always did. The CSV format is deliberately the plainest thing that
## a spreadsheet opens: comma-separated, one header line, LF endings, trailing
## newline. Nothing here quotes, because nothing written through it contains a
## comma; the tally fields that could are semicolon-separated at the source.
##
## Node-free, like the rest of the harness.


## Absolutizes an out-directory given relative to the project root, creating it.
static func prepare_dir(out_dir: String) -> String:
	var dir := ProjectSettings.globalize_path("res://").path_join(out_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func write_csv(path: String, rows: Array[Dictionary], columns: Array[String]) -> void:
	var lines: Array[String] = [",".join(columns)]
	for row in rows:
		var cells: Array[String] = []
		for column in columns:
			cells.append(str(row[column]))
		lines.append(",".join(cells))
	_store(path, "\n".join(lines) + "\n")


static func write_json(path: String, data: Variant) -> void:
	_store(path, JSON.stringify(data, "\t"))


## One compact JSON object per line. Written in one store rather than a line at a
## time because a big sweep's log is tens of thousands of lines and the file API
## charges per call, not per byte.
static func write_jsonl(path: String, entries: Array[Dictionary]) -> void:
	var lines: Array[String] = []
	for entry in entries:
		lines.append(JSON.stringify(entry))
	_store(path, "\n".join(lines) + "\n" if not lines.is_empty() else "")


static func write_text(path: String, text: String) -> void:
	_store(path, text)


static func _store(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("balance: cannot write %s" % path)
		return
	file.store_string(text)
