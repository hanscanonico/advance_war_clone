extends Node
## Fire-and-forget player for the generated sound effects:
## Sfx.play(&"shot"). Missing streams are silently skipped so headless
## runs and fresh checkouts (before `make sfx`) never break.

const SFX_DIR := "res://assets/sfx"
const NAMES: Array[StringName] = [
	&"select", &"move", &"shot", &"explosion", &"capture", &"fanfare",
]
const POOL_SIZE := 6

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for name in NAMES:
		var path := "%s/%s.wav" % [SFX_DIR, name]
		if ResourceLoader.exists(path):
			_streams[name] = load(path)
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


func play(name: StringName, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(name)
	if stream == null:
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.play()
