extends Node
## Sound effects and music. Sources and licences: assets/CREDITS.md.

const A := "res://assets/audio/"
const GROUPS := {
	"select": ["pluck1.ogg"],
	"swap": ["swap.ogg"],
	"error": ["error.ogg", "error2.ogg"],
	"match": ["lift.ogg"],
	"land": ["drop_1.ogg", "drop_2.ogg"],
	"special": ["special.ogg"],
	"line": ["line_1.ogg", "line_2.ogg", "line_3.ogg"],
	"bomb": ["bomb_1.ogg", "bomb_2.ogg"],
	"prism": ["prism_1.ogg", "prism_2.ogg"],
	"zap": ["pluck2.ogg"],
	"crack": ["crack_1.ogg", "crack_2.ogg", "crack_3.ogg"],
	"stone": ["stone_1.ogg", "stone_2.ogg", "stone_3.ogg", "stone_4.ogg"],
	"shuffle": ["shuffle.ogg"],
	"fail": ["fail.ogg"],
	"firework": ["fw_1.ogg", "fw_2.ogg", "fw_3.ogg", "fw_5.ogg", "fw_6.ogg"],
	"bell": ["bell_1.ogg", "bell_2.ogg"],
	"click": ["click.ogg"],
	"toggle": ["toggle.ogg"],
	"hint": ["hint.ogg"],
	"star": ["star.ogg"],
	"sparkle": ["sparkle.ogg"],
	"powerup": ["powerup.ogg"],
	"pop": ["pop.ogg"],
	"complete": ["complete.ogg"],
	"win": ["win_vibraphone.ogg", "win_pizzicato.ogg", "win_grandpiano.ogg", "win_fantasia.ogg", "win_steeldrums.ogg"],
}

var streams := {}
var players: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var _next := 0
var _music_started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for g in GROUPS:
		var arr: Array = []
		for f in GROUPS[g]:
			var s = load(A + f)
			if s:
				arr.append(s)
		streams[g] = arr
	for k in 10:
		streams["chime%d" % k] = [load(A + "chime_%d.ogg" % k)]
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	music = AudioStreamPlayer.new()
	add_child(music)
	var m = null
	for f in ["music.mp3", "music.ogg"]:
		if ResourceLoader.exists(A + f):
			m = load(A + f)
			break
	if m:
		m.loop = true
		music.stream = m
	music.volume_db = -11.0


func _free_player() -> AudioStreamPlayer:
	for i in players.size():
		var c := players[(_next + i) % players.size()]
		if not c.playing:
			_next += 1
			return c
	_next += 1
	return players[_next % players.size()]


func play(name: String, pitch := 1.0, vol := 0.0) -> AudioStreamPlayer:
	if not Game.save.sound:
		return null
	var arr: Array = streams.get(name, [])
	if arr.is_empty():
		return null
	var p := _free_player()
	p.stream = arr.pick_random()
	p.pitch_scale = clampf(pitch, 0.3, 4.0)
	p.volume_db = vol
	p.play()
	return p


## Browsers block audio until the first user gesture: call this from a button press.
func start_music() -> void:
	_music_started = true
	update_music()


func update_music() -> void:
	if music.stream == null:
		return
	if Game.save.music and _music_started:
		if not music.playing:
			music.play()
	else:
		music.stop()
