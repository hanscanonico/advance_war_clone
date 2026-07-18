extends SceneTree
## Generates the project-original sound effects as 16-bit mono WAVs.
## Chiptune-flavored placeholder audio, like the generated tiles.
##
## Run with:  make sfx

const RATE := 22050


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/sfx"))
	_save("select", _tone([[880.0, 0.06]], 0.35, true))
	_save("move", _tone([[240.0, 0.05], [320.0, 0.05]], 0.3, true))
	_save("capture", _tone([[660.0, 0.1], [990.0, 0.12]], 0.4, false))
	_save("fanfare", _tone([[523.25, 0.11], [659.26, 0.11], [783.99, 0.16]], 0.45, false))
	_save("shot", _noise(0.12, 0.5, 6.0))
	_save("explosion", _noise(0.4, 0.6, 3.0))
	print("generate_sfx: wrote 6 sfx wavs")
	quit()


func _tone(notes: Array, volume: float, square: bool) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	for note: Array in notes:
		var freq: float = note[0]
		var length: float = note[1]
		var count := int(length * RATE)
		for i in count:
			var t := float(i) / RATE
			var phase := fmod(t * freq, 1.0)
			var value := (1.0 if phase < 0.5 else -1.0) if square else sin(TAU * t * freq)
			var envelope := 1.0 - float(i) / count
			samples.append(value * volume * envelope)
	return samples


func _noise(length: float, volume: float, decay: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1  # reproducible art
	var count := int(length * RATE)
	var last := 0.0
	for i in count:
		var t := float(i) / count
		var envelope := exp(-decay * t)
		# random walk = lowpass-ish noise, boomier than white noise
		last = last * 0.7 + rng.randf_range(-1.0, 1.0) * 0.3
		samples.append(last * volume * envelope)
	return samples


func _save(name: String, samples: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	var err := wav.save_to_wav("res://assets/sfx/%s.wav" % name)
	if err != OK:
		push_error("generate_sfx: failed to save %s (%d)" % [name, err])
