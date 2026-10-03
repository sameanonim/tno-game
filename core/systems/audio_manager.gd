class_name AudioManagerClass
extends Node

##
## AudioManager: Централизованная аудиоподсистема TNO (Autoload)
##
## Реализует:
## 1. Потоковое воспроизведение аутентичного саундтрека TNO (Modern Tordesillas, 2WRW Theme и др.)
## 2. Плеер TNO Radio с переключением станций, паузой и уведомлением о треках
## 3. Пул звуковых эффектов (SFX): наведение мыши, клики, закрытие, старт кампании
## 4. Автоматическое подключение звуков интерфейса ко всем кнопкам сцены (attach_ui_sounds)
## 5. Управление громкостями через шины Master, Music, SFX в связке с SettingsManager
##

signal track_changed(track_index: int, track_title: String)
signal playback_state_changed(is_playing: bool)

static var instance: AudioManagerClass = null

const TRACKS: Array[Dictionary] = [
	{
		"id": "modern_tordesillas",
		"title": "Modern Tordesillas (TNO Main Theme)",
		"loc_key": "TRACK_MODERN_TORDESILLAS",
		"path": "res://assets/audio/music/Modern_Tordesillas.ogg"
	},
	{
		"id": "new_main_theme",
		"title": "Second West Russian War (2WRW Theme)",
		"loc_key": "TRACK_NEW_MAIN_THEME",
		"path": "res://assets/audio/music/new_main_theme.ogg"
	},
	{
		"id": "burgundian_lullaby",
		"title": "Burgundian Lullaby (Ordenstaat Burgund)",
		"loc_key": "TRACK_BURGUNDIAN_LULLABY",
		"path": "res://assets/audio/music/Burgundian_Lullaby.ogg"
	},
	{
		"id": "silicon_dreams",
		"title": "Silicon Dreams (State of Guangdong)",
		"loc_key": "TRACK_SILICON_DREAMS",
		"path": "res://assets/audio/music/Silicon_Dreams.ogg"
	},
	{
		"id": "the_great_trial",
		"title": "The Great Trial (Omsk Black League)",
		"loc_key": "TRACK_GREAT_TRIAL",
		"path": "res://assets/audio/music/The_Great_Trial.ogg"
	}
]

const SFX_PATHS: Dictionary = {
	"ui_menu_over": "res://assets/audio/sfx/ui_menu_over.ogg",
	"click_default": "res://assets/audio/sfx/click_default.ogg",
	"click_close": "res://assets/audio/sfx/click_close.ogg",
	"click_checkbox": "res://assets/audio/sfx/click_checkbox.ogg",
	"start_game_01": "res://assets/audio/sfx/start_game_01.ogg"
}

# --- Audio players ---
var music_player: AudioStreamPlayer = null
var sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_index: int = 0
const SFX_POOL_SIZE: int = 6

var _music_stream_cache: Dictionary = {}
var _sfx_stream_cache: Dictionary = {}

var current_track_index: int = 0
var is_music_paused: bool = false
var auto_advance: bool = true


func _init() -> void:
	if instance == null:
		instance = self


func _enter_tree() -> void:
	if instance == null:
		instance = self


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_players()
	_preload_audio()
	_apply_bus_volumes_from_settings()

	# Подключение к изменению настроек громкости
	if has_node("/root/SettingsManager"):
		var sm = get_node("/root/SettingsManager")
		if sm.has_signal("audio_volume_changed"):
			sm.audio_volume_changed.connect(_on_settings_audio_changed)


static func get_instance() -> AudioManagerClass:
	return instance


# ==============================================================================
# ИНИЦИАЛИЗАЦИЯ ПЛЕЕРОВ
# ==============================================================================

func _setup_players() -> void:
	# 1. Музыкальный плеер
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.bus = "Music" if _bus_exists("Music") else "Master"
	music_player.finished.connect(_on_music_finished)
	add_child(music_player)

	# 2. Пул SFX плееров
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "SFXPlayer_%d" % i
		p.bus = "SFX" if _bus_exists("SFX") else "Master"
		add_child(p)
		sfx_pool.append(p)


func _bus_exists(bus_name: String) -> bool:
	return AudioServer.get_bus_index(bus_name) >= 0


func _preload_audio() -> void:
	# Предзагрузка SFX
	for k in SFX_PATHS.keys():
		var path = SFX_PATHS[k]
		var stream = _load_ogg_stream(path)
		if stream != null:
			_sfx_stream_cache[k] = stream

	# Предзагрузка заглавного трека
	_load_track_stream(0)


func _load_ogg_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is AudioStream:
			return res
	elif FileAccess.file_exists(path):
		return AudioStreamOggVorbis.load_from_file(path)
	return null


func _load_track_stream(idx: int) -> AudioStream:
	if idx < 0 or idx >= TRACKS.size():
		return null
	var t_data = TRACKS[idx]
	var tid = t_data["id"]
	if _music_stream_cache.has(tid):
		return _music_stream_cache[tid]

	var path = t_data["path"]
	var stream = _load_ogg_stream(path)
	if stream != null:
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_music_stream_cache[tid] = stream
		return stream
	return null


# ==============================================================================
# УПРАВЛЕНИЕ МУЗЫКОЙ И TNO RADIO
# ==============================================================================

func play_music(track_idx: int = 0, restart_if_same: bool = false) -> void:
	if track_idx < 0 or track_idx >= TRACKS.size():
		track_idx = 0

	if current_track_index == track_idx and music_player.playing and not restart_if_same:
		return

	current_track_index = track_idx
	var stream = _load_track_stream(track_idx)
	if stream == null:
		push_warning("[AudioManager] Failed to load track: %s" % TRACKS[track_idx]["title"])
		return

	music_player.stop()
	music_player.stream = stream
	music_player.play()
	is_music_paused = false

	var title = get_current_track_title()
	track_changed.emit(current_track_index, title)
	playback_state_changed.emit(true)
	print("[AudioManager] Playing: %s" % title)


func toggle_pause() -> void:
	if not music_player.playing and not is_music_paused:
		# Если не играло вообще, запускаем текущий трек
		play_music(current_track_index)
		return

	if is_music_paused:
		music_player.stream_paused = false
		is_music_paused = false
		playback_state_changed.emit(true)
	else:
		music_player.stream_paused = true
		is_music_paused = true
		playback_state_changed.emit(false)


func next_track() -> void:
	var next_idx = (current_track_index + 1) % TRACKS.size()
	play_music(next_idx, true)


func prev_track() -> void:
	var prev_idx = (current_track_index - 1 + TRACKS.size()) % TRACKS.size()
	play_music(prev_idx, true)


func stop_music() -> void:
	music_player.stop()
	is_music_paused = false
	playback_state_changed.emit(false)


var _was_playing_before_super_event: bool = false


func pause_music_for_super_event() -> void:
	if music_player != null and music_player.playing:
		_was_playing_before_super_event = true
		music_player.stream_paused = true
		playback_state_changed.emit(false)
	else:
		_was_playing_before_super_event = false


func resume_music_after_super_event() -> void:
	if music_player != null and _was_playing_before_super_event:
		music_player.stream_paused = false
		_was_playing_before_super_event = false
		playback_state_changed.emit(true)


func get_current_track_title() -> String:
	if current_track_index >= 0 and current_track_index < TRACKS.size():
		var t_data = TRACKS[current_track_index]
		if has_node("/root/LocalizationManager"):
			var loc = get_node("/root/LocalizationManager")
			var loc_key = t_data.get("loc_key", "")
			if not loc_key.is_empty():
				return loc.tr_key(loc_key, t_data["title"])
		return t_data["title"]
	return "UNKNOWN FREQUENCY"


func _on_music_finished() -> void:
	if auto_advance:
		next_track()


# ==============================================================================
# ВОСПРОИЗВЕДЕНИЕ SFX
# ==============================================================================

func play_sfx(sfx_name: String, pitch_scale: float = 1.0) -> void:
	var stream: AudioStream = null
	if _sfx_stream_cache.has(sfx_name):
		stream = _sfx_stream_cache[sfx_name]
	elif SFX_PATHS.has(sfx_name):
		var path = SFX_PATHS[sfx_name]
		stream = _load_ogg_stream(path)
		if stream != null:
			_sfx_stream_cache[sfx_name] = stream

	if stream == null:
		return

	var p = sfx_pool[_sfx_pool_index]
	_sfx_pool_index = (_sfx_pool_index + 1) % sfx_pool.size()

	p.stop()
	p.stream = stream
	p.pitch_scale = pitch_scale
	p.play()


# ==============================================================================
# АВТОМАТИЧЕСКАЯ ПРИВЯЗКА ЗВУКОВ К UI
# ==============================================================================

func attach_ui_sounds(root_node: Node) -> void:
	if root_node == null:
		return

	if root_node is BaseButton:
		_wire_button_sounds(root_node as BaseButton)

	for child: Node in root_node.get_children():
		attach_ui_sounds(child)


func _wire_button_sounds(btn: BaseButton) -> void:
	# Проверяем, не подключены ли уже слушатели
	if not btn.mouse_entered.is_connected(_on_button_hovered):
		btn.mouse_entered.connect(_on_button_hovered)

	if btn.has_signal("toggled") and btn.is_class("CheckBox"):
		if not btn.is_connected("toggled", _on_checkbox_toggled):
			btn.connect("toggled", _on_checkbox_toggled)
	elif btn.has_signal("pressed"):
		if not btn.pressed.is_connected(_on_button_pressed):
			btn.pressed.connect(_on_button_pressed)


func _on_button_hovered() -> void:
	play_sfx("ui_menu_over", 1.0)


func _on_button_pressed() -> void:
	play_sfx("click_default", 1.0)


func _on_checkbox_toggled(_active: bool) -> void:
	play_sfx("click_checkbox", 1.0)


# ==============================================================================
# СИНХРОНИЗАЦИЯ С SETTINGSMANAGER
# ==============================================================================

func _apply_bus_volumes_from_settings() -> void:
	if not has_node("/root/SettingsManager"):
		return
	var sm = get_node("/root/SettingsManager")
	var audio_cfg = sm.audio_settings

	var m_vol = float(audio_cfg.get("master_volume", 0.8))
	var s_vol = float(audio_cfg.get("sfx_volume", 0.85))
	var a_vol = float(audio_cfg.get("ambient_volume", 0.7))

	_set_bus_vol("Master", m_vol)
	_set_bus_vol("Music", a_vol)
	_set_bus_vol("SFX", s_vol)


func _set_bus_vol(bus_name: String, linear_vol: float) -> void:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear_vol, 0.001, 1.0)))


func _on_settings_audio_changed(bus_name: String, vol_linear: float) -> void:
	_set_bus_vol(bus_name, vol_linear)
