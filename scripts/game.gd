extends Node
## Global state: gems, worlds, levels, save file, settings, texts (ru/en), command-line flags.

const SAVE_PATH := "user://save.json"
const LEVELS_PATH := "res://assets/levels/levels.json"
const PER_WORLD := 10

## Gem kinds: sprite strip + the colour used for particles, beams and UI.
const GEMS := [
	{"id": "ruby", "color": Color("#ff2d55"), "en": "Ruby", "ru": "Рубин"},
	{"id": "topaz", "color": Color("#ff8a1c"), "en": "Fire Topaz", "ru": "Огненный топаз"},
	{"id": "citrine", "color": Color("#ffd51f"), "en": "Citrine", "ru": "Цитрин"},
	{"id": "emerald", "color": Color("#22e06a"), "en": "Emerald", "ru": "Изумруд"},
	{"id": "sapphire", "color": Color("#2f7bff"), "en": "Sapphire", "ru": "Сапфир"},
	{"id": "amethyst", "color": Color("#b04dff"), "en": "Amethyst", "ru": "Аметист"},
	{"id": "diamond", "color": Color("#d8f4ff"), "en": "Star Diamond", "ru": "Звёздный алмаз"},
	{"id": "rose", "color": Color("#ff6fb5"), "en": "Rose Heart", "ru": "Розовое сердце"},
]
const PRISM_COLOR := Color("#ffffff")

const WORLDS := [
	{"id": "crystal", "en": "Crystal Caves", "ru": "Хрустальные пещеры", "tint": Color("#b07cff"), "style": 0, "fx": "sparkles"},
	{"id": "ocean", "en": "Sunken Temple", "ru": "Затонувший храм", "tint": Color("#33d6e0"), "style": 1, "fx": "bubbles"},
	{"id": "desert", "en": "Golden Dunes", "ru": "Золотые дюны", "tint": Color("#ffb347"), "style": 2, "fx": "dust"},
	{"id": "forest", "en": "Firefly Forest", "ru": "Светлячковый лес", "tint": Color("#7dff8a"), "style": 3, "fx": "fireflies"},
	{"id": "volcano", "en": "Fire Forge", "ru": "Огненная кузница", "tint": Color("#ff5a36"), "style": 4, "fx": "embers"},
	{"id": "cosmos", "en": "Star Crown", "ru": "Звёздная корона", "tint": Color("#ff7ae6"), "style": 5, "fx": "stars"},
]

var levels: Array = []
var gem_tex: Array[Texture2D] = []
var prism_tex: Texture2D
var stone_tex: Texture2D
var save := {
	"unlocked": 1,
	"stars": {},
	"best": {},
	"blitz_best": 0,
	"lang": "",
	"sound": true,
	"music": true,
	"seen_gems": [],
	"tips": [],
}
var args := PackedStringArray()


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	var f := FileAccess.open(LEVELS_PATH, FileAccess.READ)
	if f:
		levels = JSON.parse_string(f.get_as_text())
	for g in GEMS:
		gem_tex.append(load("res://assets/gems/%s.png" % g.id))
	prism_tex = load("res://assets/gems/prism.png")
	stone_tex = load("res://assets/gems/stone.png")
	load_save()
	if save.lang == "":
		save.lang = "ru" if OS.get_locale_language() in ["ru", "uk", "be", "kk"] else "en"
	if has_arg("--fresh"):
		save.unlocked = 1
		save.stars = {}
		save.seen_gems = []
		save.tips = []
	if has_arg("--lang"):
		save.lang = arg_value("--lang", "en")
	if has_arg("--unlock"):
		save.unlocked = 999


func has_arg(a: String) -> bool:
	return a in args


func arg_value(a: String, def := "") -> String:
	var i := args.find(a)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def


func load_save() -> void:
	if has_arg("--autotest") or has_arg("--fresh") or has_arg("--calibrate"):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for k in d:
			save[k] = d[k]


func write_save() -> void:
	if has_arg("--autotest") or has_arg("--calibrate"):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))


func world_of(idx: int) -> int:
	return (idx / PER_WORLD) % WORLDS.size()


## Level data. Past the campaign, late levels come back with a new seed and shuffled gem kinds, forever.
func get_level(idx: int) -> Dictionary:
	if idx < levels.size():
		return levels[idx]
	var rng := RandomNumberGenerator.new()
	rng.seed = idx * 7919 + 17
	var src: Dictionary = levels[rng.randi_range(levels.size() - 3 * PER_WORLD, levels.size() - 1)].duplicate(true)
	var kinds := range(GEMS.size())
	kinds.shuffle()
	var n: int = src.colors.size()
	src.colors = kinds.slice(0, n)
	for g in src.goals:
		if g.type == "collect":
			g.color = src.colors[rng.randi_range(0, n - 1)]
	src.erase("tut")
	return src


func stars_of(idx: int) -> int:
	return int(save.stars.get(str(idx), 0))


func total_stars() -> int:
	var n := 0
	for k in save.stars:
		n += int(save.stars[k])
	return n


func record_win(idx: int, stars: int, score: int) -> void:
	if stars > stars_of(idx):
		save.stars[str(idx)] = stars
	if score > int(save.best.get(str(idx), 0)):
		save.best[str(idx)] = score
	save.unlocked = maxi(int(save.unlocked), idx + 2)
	write_save()


func world_name(w: int) -> String:
	return WORLDS[w % WORLDS.size()][lang()]


func gem_name(k: int) -> String:
	return GEMS[k][lang()]


func lang() -> String:
	return "ru" if save.lang == "ru" else "en"


# ================================================================== text

const TEXT := {
	"title": ["Gem Swap", "Gem Swap"],
	"subtitle": ["Swap. Match. Sparkle!", "Меняй. Собирай. Сияй!"],
	"play": ["Play", "Играть"],
	"blitz": ["Blitz 90s", "Блиц 90 с"],
	"levels": ["Levels", "Уровни"],
	"settings": ["Settings", "Настройки"],
	"level": ["Level", "Уровень"],
	"moves": ["Moves", "Ходы"],
	"score": ["Score", "Очки"],
	"time": ["Time", "Время"],
	"best": ["Best", "Рекорд"],
	"goal": ["Goal", "Цель"],
	"goal_score": ["Score %s points", "Наберите %s очков"],
	"goal_collect": ["Collect the gems", "Соберите камни"],
	"goal_ice": ["Break all the ice", "Разбейте весь лёд"],
	"goal_stone": ["Smash all the stones", "Разбейте все камни-глыбы"],
	"start": ["Start", "Начать"],
	"combo2": ["Good!", "Хорошо!"],
	"combo3": ["Great!", "Отлично!"],
	"combo4": ["Amazing!", "Потрясающе!"],
	"combo5": ["Brilliant!", "Блестяще!"],
	"combo6": ["Unbelievable!", "Невероятно!"],
	"bonus": ["Bonus!", "Бонус!"],
	"win": ["Level complete!", "Уровень пройден!"],
	"lose": ["Out of moves", "Ходы закончились"],
	"lose_sub": ["So close! Try again?", "Совсем чуть-чуть! Ещё раз?"],
	"plus5": ["+5 moves", "+5 ходов"],
	"retry": ["Retry", "Заново"],
	"next": ["Next", "Дальше"],
	"menu": ["Menu", "Меню"],
	"time_up": ["Time's up!", "Время вышло!"],
	"new_best": ["New record!", "Новый рекорд!"],
	"no_moves": ["No moves — shuffling!", "Ходов нет — перемешиваем!"],
	"new_gem": ["New gem!", "Новый камень!"],
	"tip_swap": ["Swipe a gem to swap it with a neighbour and line up 3 of a kind", "Проведите по камню, чтобы поменять его с соседом и собрать 3 в ряд"],
	"tip_line": ["Match 4 to make a Line gem — it clears a whole row!", "Соберите 4 — получится камень-молния, он очищает целый ряд!"],
	"tip_bomb": ["Match in an L or T shape to make a Bomb gem!", "Соберите уголком или буквой Т — получится камень-бомба!"],
	"tip_prism": ["Match 5 in a row for a Prism. Swap it with any gem to clear that colour!", "Соберите 5 в ряд — получится Призма. Поменяйте её с камнем — исчезнут все такого цвета!"],
	"tip_combo": ["Swap two special gems together for a huge combo!", "Поменяйте местами два особых камня — будет огромное комбо!"],
	"tip_ice": ["Match gems on ice to break it", "Собирайте камни на льду, чтобы разбить его"],
	"tip_stone": ["Make matches next to stones to smash them", "Собирайте ряды рядом с глыбами, чтобы разбить их"],
	"sound": ["Sound", "Звуки"],
	"music": ["Music", "Музыка"],
	"language": ["Language", "Язык"],
	"close": ["Close", "Закрыть"],
	"locked": ["Win the previous level first", "Сначала пройдите предыдущий уровень"],
	"pause": ["Pause", "Пауза"],
	"resume": ["Resume", "Продолжить"],
	"stars_total": ["Stars", "Звёзды"],
	"reset": ["Reset progress", "Сбросить прогресс"],
	"reset_q": ["Tap again to erase all progress", "Нажмите ещё раз, чтобы стереть прогресс"],
	"privacy": ["Privacy", "Конфиденциальность"],
	"world": ["World", "Мир"],
	"endless": ["Bonus levels", "Бонусные уровни"],
}


func tr_(key: String) -> String:
	var row: Array = TEXT.get(key, [key, key])
	return row[1] if save.lang == "ru" else row[0]
