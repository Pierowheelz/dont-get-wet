class_name UISound
extends Node
## UI click/move/back sounds and the persistent menu music.
## Add one UISound per screen; it plays `ui_move` whenever keyboard/gamepad focus moves.
## Volumes follow Game.settings["sfx"/"music"] directly (no bus dependency, so it works before
## the level audio has created its buses).

const DIR := "res://assets/audio/"
const MUSIC_NODE := "MenuMusic"

var auto_focus_sound := true
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {}
var _quiet_until := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# Don't click for the initial grab_focus of a freshly built screen.
	_quiet_until = Time.get_ticks_msec() + 250
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func _on_focus_changed(_c: Control) -> void:
	if auto_focus_sound:
		play(&"ui_move", -6.0)


## Suppress the focus sound for a moment (call before rebuilding a menu page).
func hush(ms := 200) -> void:
	_quiet_until = Time.get_ticks_msec() + ms


func play(sound: StringName, db := 0.0, pitch := 1.0) -> void:
	if Time.get_ticks_msec() < _quiet_until and sound == &"ui_move":
		return
	var s := _stream(String(sound))
	if s == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = s
	p.volume_db = db + linear_to_db(maxf(0.0001, float(Game.settings.get("sfx", 1.0))))
	p.pitch_scale = pitch
	p.play()


func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var s: AudioStream = null
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(DIR + name + ext):
			s = load(DIR + name + ext)
			break
	_cache[name] = s
	return s


# --- menu music (survives scene changes between menu and map) --------------------------------

static func music_volume_db() -> float:
	return linear_to_db(maxf(0.0001, float(Game.settings.get("music", 0.7)))) - 4.0


static func start_menu_music(tree: SceneTree) -> void:
	var root := tree.root
	var existing := root.get_node_or_null(MUSIC_NODE) as AudioStreamPlayer
	if existing:
		existing.set_meta(&"stopping", false)
		_retween(existing).tween_property(existing, "volume_db", music_volume_db(), 0.6)
		return
	var path := DIR + "music_menu_loop.ogg"
	if not ResourceLoader.exists(path):
		return
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	var p := AudioStreamPlayer.new()
	p.name = MUSIC_NODE
	p.stream = s
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.volume_db = -40.0
	root.add_child.call_deferred(p)
	p.ready.connect(func() -> void:
		p.play()
		p.create_tween().tween_property(p, "volume_db", music_volume_db(), 2.0), CONNECT_ONE_SHOT)


static func update_menu_music_volume(tree: SceneTree) -> void:
	var p := tree.root.get_node_or_null(MUSIC_NODE) as AudioStreamPlayer
	if p and not p.get_meta(&"stopping", false):
		p.volume_db = music_volume_db()


static func stop_menu_music(tree: SceneTree, fade := 1.2) -> void:
	var p := tree.root.get_node_or_null(MUSIC_NODE) as AudioStreamPlayer
	if p == null or p.get_meta(&"stopping", false):
		return
	p.set_meta(&"stopping", true)
	var tw := _retween(p)
	tw.tween_property(p, "volume_db", -50.0, fade)
	tw.tween_callback(func() -> void:
		if p.get_meta(&"stopping", false):
			p.queue_free())


static func _retween(p: Node) -> Tween:
	var old: Variant = p.get_meta(&"tween", null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := p.create_tween()
	p.set_meta(&"tween", tw)
	return tw
