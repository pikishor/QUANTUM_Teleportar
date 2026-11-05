class_name Tr
extends RefCounted
## Localisation table. The English text is the key: Tr.t("NEW GAME") returns the active language's text, and any string without an entry (English, or a dynamic line)
## comes back unchanged, so nothing can ever render blank. Hud._text and the story view route every drawn line through here. Languages: LANGS (English complete; Spanish for menus, HUD, story, radio, contracts, missions; Hindi for menus and HUD, Devanagari via UiUtil.font() fallbacks).
## Also holds the live text scale (1.0 / 1.25 / 1.5) that Hud._text applies, shrinking a line to fit its width instead of clipping it.

const LANGS: Array[String] = ["en", "es", "hi"]
const LANG_NAMES := {"en": "ENGLISH", "es": "ESPAÑOL", "hi": "हिन्दी"}
const SCALES: Array[float] = [1.0, 1.25, 1.5]

static var lang := "en"
static var text_scale := 1.0

const ES := {
	"QUANTUM TELEPORTAR": "QUANTUM TELEPORTAR", "NEW GAME": "NUEVA PARTIDA", "CONTINUE": "CONTINUAR", "DEPLOY": "DESPLEGAR", "CHAPTERS": "CAPÍTULOS",
	"RESUME": "REANUDAR", "UPGRADES": "MEJORAS", "ACHIEVEMENTS": "LOGROS", "ABORT TO MENU": "VOLVER AL MENÚ", "RESPAWN": "REAPARECER", "NEXT SECTOR": "SIGUIENTE SECTOR",
	"OPTIONS": "OPCIONES", "BACK": "ATRÁS", "PAUSED": "EN PAUSA", "DECOHERED": "DECOHERIDO", "SECTOR STABILIZED": "SECTOR ESTABILIZADO",
	"TAP TO RESPAWN": "TOCA PARA REAPARECER", "TAP TO CONTINUE": "TOCA PARA CONTINUAR", "TAP TO SKIP": "TOCA PARA SALTAR", "GRAPHICS": "GRÁFICOS",
	"INTEGRITY": "INTEGRIDAD", "COHERENCE": "COHERENCIA", "HULL": "CASCO", "RELOADING": "RECARGANDO", "NO ACTIVE OBJECTIVE": "SIN OBJETIVO ACTIVO",
	"QUANTUM TELEPORT": "QUANTUM TELEPORT", "ENTANGLE": "ENTANGLE", "SUPERPOSITION": "SUPERPOSITION", "COLLAPSE": "COLLAPSE",
	"EXIT VEHICLE": "SALIR DEL VEHÍCULO", "ENTER VEHICLE": "ENTRAR AL VEHÍCULO", "RADIO OFF": "RADIO APAGADA", "NEW BEST": "NUEVO RÉCORD",
	"LOOK X": "MIRAR X", "LOOK Y": "MIRAR Y", "ADS": "APUNTAR", "HUD SIZE": "TAMAÑO HUD", "BUTTONS": "BOTONES", "AIM ASSIST": "AYUDA PUNTERÍA",
	"AUTO FIRE": "AUTODISPARO", "LEFT HAND": "ZURDO", "VIBRATION": "VIBRACIÓN", "SUBTITLES": "SUBTÍTULOS", "COLOUR SAFE": "DALTONISMO",
	"FPS CAP": "LÍMITE FPS", "ON": "SÍ", "OFF": "NO", "LOW": "BAJO", "MED": "MEDIO", "HIGH": "ALTO", "MORE": "MÁS", "LANGUAGE": "IDIOMA", "TEXT SIZE": "TAMAÑO TEXTO",
	"REDUCE FLASH": "MENOS DESTELLOS", "REDUCE MOTION": "MENOS MOVIMIENTO", "SUBTITLE SIZE": "TAM. SUBTÍTULOS", "SUBTITLE BG": "FONDO SUBTÍTULOS",
	"MUSIC": "MÚSICA", "POST": "POST", "SFX": "SFX", "CINE": "CINE", "TRITAN": "TRITAN", "DEUTAN": "DEUTAN", "CLEAR": "CLARO", "SOFT": "SUAVE", "SOLID": "SÓLIDO", "REPLAY HINTS": "REPETIR AYUDAS", "HOLD TO AIM": "MANTÉN PARA APUNTAR", "DRAG TO MOVE": "ARRASTRA PARA MOVER", "TAKE SIDE MISSIONS": "TOMA MISIONES SECUNDARIAS",
}

const _ES_X := preload("res://scripts/common/strings_es.gd")
const _HI := preload("res://scripts/common/strings_hi.gd")
const _ES2 := preload("res://scripts/common/strings_es2.gd")
const _HI2 := preload("res://scripts/common/strings_hi2.gd")
const _NPC := preload("res://scripts/npc/npc_dialogue_data.gd")

static var _tables := {}
static var _pats := {}          ## lang -> {key with numbers as # -> translation with a \u0001 slot per number}
static var _cache := {}
static var _num_re: RegEx = null
static var _fmt_re: RegEx = null


static func table(l: String) -> Dictionary:
	if not _tables.has(l):
		var d := {}
		if l == "es":
			d.merge(ES)
			d.merge(_ES_X.S)
			d.merge(_ES2.S)
			d.merge(_NPC.table("es"))
		elif l == "hi":
			d.merge(_HI.S)
			d.merge(_HI2.S)
			d.merge(_NPC.table("hi"))
		_tables[l] = d
	return _tables[l]


static func _patterns(l: String) -> Dictionary:
	if not _pats.has(l):
		if _fmt_re == null:
			_fmt_re = RegEx.create_from_string("%0?\\d*(?:\\.\\d+)?[df]")
		var p := {}
		var tbl := table(l)
		for k: String in tbl:
			if k.contains("%d") or k.contains("%02d") or k.contains("%.1f"):
				p[_fmt_re.sub(k, "#", true).replace("%%", "%")] = _fmt_re.sub(str(tbl[k]), "\u0001", true).replace("%%", "%")
		_pats[l] = p
	return _pats[l]


## Numbers inside a drawn line ("WAVE 2 / 5", "12% DAMAGE") match the format keys of the table (WAVE %d / %d): same numbers, translated words.
static func _t_numeric(l: String, key: String) -> String:
	var pats := _patterns(l)
	if pats.is_empty():
		return key
	if _num_re == null:
		_num_re = RegEx.create_from_string("\\d+(?:\\.\\d+)?")
	var ms := _num_re.search_all(key)
	if ms.is_empty():
		return key
	var norm := _num_re.sub(key, "#", true)
	if not pats.has(norm):
		return key
	var parts := str(pats[norm]).split("\u0001")
	var out := parts[0]
	for i in range(1, parts.size()):
		out += (ms[i - 1].get_string() if i - 1 < ms.size() else "") + parts[i]
	return out


const SUFFIXES: Array[String] = [" COMPLETE", " FAILED", " TIME UP", " LEFT"]


## Composite lines ("MISSION FAILED  TIME UP", "ACHIEVEMENT  HUNTER", "COURIER: Deliver ...", "RESCUE COMPLETE  +300"): each part between two spaces or ": " is translated alone.
static func _compose(l: String, key: String) -> String:
	var tbl := table(l)
	var out := ""
	var changed := false
	var i := 0
	var start := 0
	var n := key.length()
	while i <= n:
		var sep := ""
		if i < n:
			if key.substr(i, 2) == "  ":
				sep = "  "
			elif key.substr(i, 2) == ": ":
				sep = ": "
		if i == n or sep != "":
			var seg := key.substr(start, i - start)
			var tr := seg
			if tbl.has(seg):
				tr = tbl[seg]
			else:
				var nt := _t_numeric(l, seg)
				if nt != seg:
					tr = nt
				else:
					for sf in SUFFIXES:
						if seg.ends_with(sf) and tbl.has(sf) and seg.length() > sf.length():
							var head := seg.substr(0, seg.length() - sf.length())
							tr = str(tbl.get(head, head)) + str(tbl[sf])
							break
			if tr != seg:
				changed = true
			out += tr + sep
			i += maxi(sep.length(), 1)
			start = i
		else:
			i += 1
	return out if changed else key


static func t(key: String) -> String:
	if lang == "en":
		return key
	var tbl := table(lang)
	if tbl.has(key):
		return tbl[key]
	var ck := lang + "|" + key
	if _cache.has(ck):
		return _cache[ck]
	var r := _t_numeric(lang, key)
	if r == key:
		r = _compose(lang, key)
	if _cache.size() > 600:
		_cache.clear()
	_cache[ck] = r
	return r


## True when `l` has a translation (exact or numeric pattern) for `key`.
static func has_tr(l: String, key: String) -> bool:
	return table(l).has(key) or _t_numeric(l, key) != key


static func set_lang(l: String) -> void:
	lang = l if LANGS.has(l) else "en"


static func next_lang(l: String) -> String:
	return LANGS[(maxi(LANGS.find(l), 0) + 1) % LANGS.size()]


static func next_scale(v: float) -> float:
	for i in SCALES.size():
		if is_equal_approx(SCALES[i], v):
			return SCALES[(i + 1) % SCALES.size()]
	return SCALES[0]


## Font size for a line at `base` px: scaled by text_scale, then shrunk until it fits `width` (never below `base`, never clipped when it fitted unscaled).
static func scaled_size(font: Font, text: String, width: float, base: int) -> int:
	var sz := int(round(float(base) * text_scale))
	if sz <= base or width <= 0.0:
		return base if width <= 0.0 else sz
	while sz > base and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width:
		sz -= 1
	return sz
