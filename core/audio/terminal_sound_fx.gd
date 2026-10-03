class_name TerminalSoundFx
extends Node

##
## TerminalSoundFx: Процедурный синтезатор звуковых эффектов ЭЛТ-терминала
## Генерирует механические щелчки переключателей, гул сервоприводов, зуммеры тревоги и телеграф.
##

var _sfx_player: AudioStreamPlayer
var _generator: AudioStreamGenerator


func _ready() -> void:
	_init_synthesizer()


func _init_synthesizer() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "TerminalAudioPlayer"
	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = 22050
	_generator.buffer_length = 0.2
	_sfx_player.stream = _generator
	_sfx_player.volume_db = -8.0
	add_child(_sfx_player)
	_sfx_player.play()


func play_switch_click(pitch_hz: float = 950.0, duration_sec: float = 0.035) -> void:
	_synthesize_tone(pitch_hz, duration_sec, 90.0, "square")


func play_alarm_buzz(pitch_hz: float = 480.0, duration_sec: float = 0.18) -> void:
	_synthesize_tone(pitch_hz, duration_sec, 12.0, "sawtooth")


func play_pan_hum(duration_sec: float = 0.08) -> void:
	_synthesize_tone(85.0, duration_sec, 25.0, "sine")


func play_telegraph_chirp() -> void:
	_synthesize_tone(1400.0, 0.025, 120.0, "square")


func play_crt_flyback_hum(duration_sec: float = 0.25) -> void:
	# Высокочастотный аналоговый свист строчного трансформатора ЭЛТ (flyback transformer ~7.5 kHz)
	_synthesize_tone(7500.0, duration_sec, 6.0, "sine")


func play_crt_warmup() -> void:
	# Прогрев катода и щелчок высокого напряжения
	play_switch_click(450.0, 0.04)
	play_crt_flyback_hum(0.35)


func _synthesize_tone(freq: float, duration_sec: float, decay_rate: float, wave_type: String = "sine") -> void:
	if _sfx_player == null or not _sfx_player.playing:
		return

	var playback = _sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return

	var sample_rate = _generator.mix_rate
	var total_frames = int(duration_sec * sample_rate)
	var available = playback.get_frames_available()
	var frames_to_push = mini(total_frames, available)

	for i in range(frames_to_push):
		var t = float(i) / float(sample_rate)
		var decay = exp(-t * decay_rate)
		var phase = TAU * freq * t
		var sample_val := 0.0

		match wave_type:
			"square":
				sample_val = 0.45 if sin(phase) >= 0.0 else -0.45
			"sawtooth":
				sample_val = (fmod(phase, TAU) / PI - 1.0) * 0.40
			_: # sine
				sample_val = sin(phase) * 0.50

		var final_sample = Vector2.ONE * (sample_val * decay)
		playback.push_frame(final_sample)
