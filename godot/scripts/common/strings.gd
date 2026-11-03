class_name Tr
extends RefCounted
## Localisation table. The English text is the key: Tr.t("NEW GAME") returns the active language's text, and any string without an entry (English, or a dynamic line)
## comes back unchanged, so nothing can ever render blank. Hud._text and the story view route every drawn line through here. Languages: LANGS (English complete, Spanish for menus/HUD).
## Also holds the live text scale (1.0 / 1.25 / 1.5) that Hud._text applies, shrinking a line to fit its width instead of clipping it.

const LANGS: Array[String] = ["en", "es"]
const LANG_NAMES := {"en": "ENGLISH", "es": "ESPAÑOL"}
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
	"MUSIC": "MÚSICA", "POST": "POST", "SFX": "SFX", "CINE": "CINE", "TRITAN": "TRITAN", "DEUTAN": "DEUTAN", "CLEAR": "CLARO", "SOFT": "SUAVE", "SOLID": "SÓLIDO",
}

static var _tables := {"es": ES}


static func t(key: String) -> String:
	if lang == "en":
		return key
	var tbl: Dictionary = _tables.get(lang, {})
	return tbl.get(key, key)


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
