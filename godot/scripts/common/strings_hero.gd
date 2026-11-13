extends RefCounted
## Spanish and Hindi for the SUIT screen of wave 112 (scripts/ui/look_screen.gd): the person row labels, the scheme caption, the suit taglines and the hero plate hints. English text (the key) ->
## translation, merged by Tr.table(). Names of suits and colour schemes stay English (they are the game's own names).

const SCHEME_NAMES: Array[String] = ["CYAN", "EMBER", "VIOLET", "JADE", "MAGENTA", "GOLD", "CRIMSON", "ICE"]

const ES_BASE := {
	"PERSON": "PERSONAJE", "DRAG TO TURN": "ARRASTRA PARA GIRAR", "NO PREVIEW": "SIN VISTA PREVIA",
	"LAYERED PLATES": "PLACAS EN CAPAS", "MATTE  DIM CIRCUITS": "MATE  CIRCUITOS TENUES", "HEAVY ARMOUR": "ARMADURA PESADA", "WING MOUNTS": "SOPORTES DE ALAS",
	"GOLD PLATING": "CHAPADO EN ORO", "GLASS PLATES": "PLACAS DE CRISTAL",
	"BODY  MALE": "CUERPO  MASCULINO", "BODY  FEMALE": "CUERPO  FEMENINO", "SKIN  DARK": "PIEL  OSCURA", "SKIN  LIGHT": "PIEL  CLARA",
	"HAIR  NONE": "PELO  NINGUNO", "HAIR  BUZZED": "PELO  RAPADO", "HAIR  PARTED": "PELO  CON RAYA", "HAIR  LONG": "PELO  LARGO", "HAIR  BUNS": "PELO  MOÑOS",
	"SCHEME": "ESQUEMA", "SCHEME  CUSTOM": "ESQUEMA  PERSONAL",
}

const HI_BASE := {
	"PERSON": "किरदार", "DRAG TO TURN": "घुमाने के लिए खींचें", "NO PREVIEW": "पूर्वावलोकन नहीं",
	"LAYERED PLATES": "परतदार कवच", "MATTE  DIM CIRCUITS": "मैट  धीमे सर्किट", "HEAVY ARMOUR": "भारी कवच", "WING MOUNTS": "पंख माउंट",
	"GOLD PLATING": "सोने की परत", "GLASS PLATES": "काँच के कवच",
	"BODY  MALE": "शरीर  पुरुष", "BODY  FEMALE": "शरीर  महिला", "SKIN  DARK": "त्वचा  गहरी", "SKIN  LIGHT": "त्वचा  हल्की",
	"HAIR  NONE": "बाल  कोई नहीं", "HAIR  BUZZED": "बाल  छोटे", "HAIR  PARTED": "बाल  मांग", "HAIR  LONG": "बाल  लंबे", "HAIR  BUNS": "बाल  जूड़े",
	"SCHEME": "रंग योजना", "SCHEME  CUSTOM": "रंग योजना  अपनी",
}


static func es() -> Dictionary:
	var d := ES_BASE.duplicate()
	for n: String in SCHEME_NAMES:
		d["SCHEME  %s" % n] = "ESQUEMA  %s" % n
	return d


static func hi() -> Dictionary:
	var d := HI_BASE.duplicate()
	for n: String in SCHEME_NAMES:
		d["SCHEME  %s" % n] = "रंग योजना  %s" % n
	return d
