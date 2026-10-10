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
signal station_changed(station_id: String, station_title: String, station_freq: String)

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
	"start_game_01": "res://assets/audio/sfx/start_game_01.ogg",
	"start_game_02": "res://assets/audio/sfx/start_game_02.ogg",
	"page_flip": "res://assets/audio/sfx/page_flip.wav",
	"window_open": "res://assets/audio/sfx/window_open.wav",
	"window_close": "res://assets/audio/sfx/window_close.wav",
	"event_popup": "res://assets/audio/sfx/event_popup.wav",
	"decisions_button": "res://assets/audio/sfx/decisions_button.wav",
	"decisions_checkbox": "res://assets/audio/sfx/decisions_checkbox.wav",
	"decisions_tab": "res://assets/audio/sfx/decisions_tab.wav",
	"alert_high": "res://assets/audio/sfx/alert_high.wav",
	"alert_mid": "res://assets/audio/sfx/alert_mid.wav",
	"alert_low": "res://assets/audio/sfx/alert_low.wav",
	"pause_toggle": "res://assets/audio/sfx/pause_toggle.wav",
	"counter_tick": "res://assets/audio/sfx/counter_tick.wav",
	"telemetry_beep": "res://assets/audio/sfx/telemetry_beep.wav",
	"ui_tab_switch": "res://assets/audio/sfx/ui_tab_switch.wav",
	"ui_mapmode_land": "res://assets/audio/sfx/ui_mapmode_land.wav",
	"rocket_fire": "res://assets/audio/sfx/rocket_fire.wav",
	"big_ben_bong": "res://assets/audio/sfx/big_ben_bong.wav",
	"click_province": "res://assets/audio/sfx/click_province.wav",
	"click_research": "res://assets/audio/sfx/click_research.wav",
	"click_ok": "res://assets/audio/sfx/click_ok.wav"
}

# --- Audio players ---
var music_player: AudioStreamPlayer = null
var sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_index: int = 0
const SFX_POOL_SIZE: int = 6

var _music_stream_cache: Dictionary = {}
var _sfx_stream_cache: Dictionary = {}

var radio_catalog: Dictionary = {}
var stations: Dictionary = {}
var station_keys: Array[String] = []
var current_station_id: String = "radio_free_world"
var current_playlist: Array[Dictionary] = []
var current_playlist_index: int = 0

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
	_load_radio_catalog()
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


func _load_radio_catalog() -> void:
	var catalog_path: String = "res://data/radio_stations.json"
	if FileAccess.file_exists(catalog_path):
		var fa := FileAccess.open(catalog_path, FileAccess.READ)
		if fa != null:
			var content := fa.get_as_text()
			fa.close()
			var json := JSON.new()
			if json.parse(content) == OK and json.data is Dictionary:
				radio_catalog = json.data
				stations = radio_catalog.get("stations", {})
				for k in stations.keys():
					station_keys.append(str(k))

	# Fallback если станций нет
	if stations.is_empty():
		station_keys = ["radio_free_world"]
		stations["radio_free_world"] = {
			"title": "AFN / Radio Free World",
			"frequency": "104.2 MHz",
			"tracks": TRACKS
		}

	current_station_id = station_keys[0]
	_rebuild_playlist_for_station(current_station_id)


func _rebuild_playlist_for_station(st_id: String) -> void:
	current_playlist.clear()
	if stations.has(st_id):
		var st_data: Dictionary = stations[st_id]
		var trks: Array = st_data.get("tracks", [])
		for t in trks:
			if t is Dictionary:
				current_playlist.append(t)

	# Если в станции пусто, берем базовые треки
	if current_playlist.is_empty():
		for t in TRACKS:
			current_playlist.append(t)

	current_playlist_index = 0


func _preload_audio() -> void:
	# Предзагрузка ключевых SFX
	for k in ["click_default", "click_close", "ui_menu_over", "window_open", "event_popup"]:
		if SFX_PATHS.has(k):
			var path: String = SFX_PATHS[k]
			var stream = _load_audio_stream(path)
			if stream != null:
				_sfx_stream_cache[k] = stream

	# Предзагрузка заглавного трека
	_load_track_stream(0)


func _load_audio_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is AudioStream:
			return res
	elif FileAccess.file_exists(path):
		if path.to_lower().ends_with(".ogg"):
			return AudioStreamOggVorbis.load_from_file(path)
	return null


func _load_track_stream(idx: int) -> AudioStream:
	if current_playlist.is_empty():
		return null
	if idx < 0 or idx >= current_playlist.size():
		idx = 0

	var t_data: Dictionary = current_playlist[idx]
	var tid: String = str(t_data.get("id", str(idx)))
	if _music_stream_cache.has(tid):
		return _music_stream_cache[tid]

	var stream: AudioStream = null

	# 1. Попытка загрузить из bundled path (res://)
	var bundled_path: String = str(t_data.get("path", ""))
	if not bundled_path.is_empty() and ResourceLoader.exists(bundled_path):
		stream = _load_audio_stream(bundled_path)

	# 2. Попытка загрузить из физического пути мода (streaming)
	if stream == null:
		var phys_path: String = str(t_data.get("physical_path", ""))
		if not phys_path.is_empty() and FileAccess.file_exists(phys_path):
			stream = _load_audio_stream(phys_path)

	# 3. Fallback на один из встроенных треков
	if stream == null and not TRACKS.is_empty():
		var fallback_idx = idx % TRACKS.size()
		var fb_path = TRACKS[fallback_idx]["path"]
		stream = _load_audio_stream(fb_path)

	if stream != null:
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = false
		_music_stream_cache[tid] = stream
		return stream

	return null


# ==============================================================================
# УПРАВЛЕНИЕ МУЗЫКОЙ И TNO RADIO
# ==============================================================================

func play_music(track_idx: int = 0, restart_if_same: bool = false) -> void:
	if current_playlist.is_empty():
		return

	if track_idx < 0 or track_idx >= current_playlist.size():
		track_idx = 0

	if current_playlist_index == track_idx and music_player.playing and not restart_if_same:
		return

	current_playlist_index = track_idx
	current_track_index = track_idx

	var stream = _load_track_stream(track_idx)
	if stream == null:
		push_warning("[AudioManager] Failed to load track: %s" % get_current_track_title())
		return

	music_player.stop()
	music_player.stream = stream
	music_player.play()
	is_music_paused = false

	var title = get_current_track_title()
	track_changed.emit(current_playlist_index, title)
	playback_state_changed.emit(true)
	print("[AudioManager] Playing [%s]: %s" % [current_station_id, title])


func set_station(station_id: String) -> void:
	if not stations.has(station_id) or station_id == current_station_id:
		return

	current_station_id = station_id
	_rebuild_playlist_for_station(current_station_id)

	var st_info = get_current_station_info()
	station_changed.emit(current_station_id, st_info.get("title", ""), st_info.get("frequency", ""))
	play_music(0, true)


func next_station() -> void:
	if station_keys.is_empty():
		return
	var cur_idx = station_keys.find(current_station_id)
	var next_idx = (cur_idx + 1) % station_keys.size()
	set_station(station_keys[next_idx])


func prev_station() -> void:
	if station_keys.is_empty():
		return
	var cur_idx = station_keys.find(current_station_id)
	var prev_idx = (cur_idx - 1 + station_keys.size()) % station_keys.size()
	set_station(station_keys[prev_idx])


func get_current_station_info() -> Dictionary:
	if stations.has(current_station_id):
		return stations[current_station_id]
	return {"title": "AFN / Radio Free World", "frequency": "104.2 MHz"}


func get_stations_dict() -> Dictionary:
	return stations


func toggle_pause() -> void:
	if not music_player.playing and not is_music_paused:
		play_music(current_playlist_index)
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
	if current_playlist.is_empty():
		return
	var next_idx = (current_playlist_index + 1) % current_playlist.size()
	play_music(next_idx, true)


func prev_track() -> void:
	if current_playlist.is_empty():
		return
	var prev_idx = (current_playlist_index - 1 + current_playlist.size()) % current_playlist.size()
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
	if current_playlist_index >= 0 and current_playlist_index < current_playlist.size():
		var t_data: Dictionary = current_playlist[current_playlist_index]
		var title: String = str(t_data.get("title", "UNKNOWN TRACK"))
		var loc_key: String = str(t_data.get("loc_key", ""))
		if has_node("/root/LocalizationManager") and not loc_key.is_empty():
			var loc = get_node("/root/LocalizationManager")
			return loc.tr_key(loc_key, title)
		return title
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
		var path: String = SFX_PATHS[sfx_name]
		stream = _load_audio_stream(path)
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
