extends RefCounted
## Words of NPC DIALOGUE v2 (alien-latin street talk, no lessons). Every entry is [English, Spanish, Hindi]; the spoken string is SPEAKER prefix + English, and that exact string is the
## Tr key (Tr.table merges `table(lang)`), so a line is always readable even without a translation. Each spoken line (prefix included) stays <= StoryData.LINE_MAX (112).
## Tags: d_<district>, night, day, rain, storm, fog, heat (1..3 stars), calm, early / mid / late (chapter), kills, theft. Exchanges are 2-3 line talks (A, B, A).

const CITIZEN := "CIVIS: "
const REPLY := "ALTER: "
const VENDOR := "MERCATOR: "

const BARKS := {
	"d_market": [
		["Market stalls hum, civis. Buy before the Observers tax the air.", "Los puestos zumban, civis. Compra antes de que los Observers graven el aire.", "बाज़ार की दुकानें गुनगुनाती हैं, सिविस। हवा पर कर लगने से पहले ख़रीद लो।"],
		["Pretium bonum today. Tomorrow, who knows?", "Buen precio hoy. Mañana, quién sabe.", "आज दाम अच्छा है। कल, कौन जाने?"],
	],
	"d_foundry": [
		["The foundry sings all night. Even the rain smells of iron.", "La fundición canta toda la noche. Hasta la lluvia huele a hierro.", "फाउंड्री रात भर गाती है। बारिश भी लोहे जैसी महकती है।"],
		["Hot slag, cold hive. Walk on the dry side, runner.", "Escoria caliente, colmena fría. Camina por el lado seco, runner.", "गरम लावा, ठंडा छत्ता। सूखी तरफ़ चलो, रनर।"],
	],
	"d_slums": [
		["Slums keep their secrets in the walls. Pay in silence.", "Los barrios guardan secretos en las paredes. Paga con silencio.", "बस्तियाँ अपने राज़ दीवारों में रखती हैं। चुप्पी से चुकाओ।"],
		["Sleep light here. The drones count the roofs.", "Aquí se duerme ligero. Los drones cuentan los tejados.", "यहाँ हल्की नींद सोओ। ड्रोन छतें गिनते हैं।"],
	],
	"d_towers": [
		["Towers look down, civis. Down is where we live.", "Las torres miran hacia abajo, civis. Abajo es donde vivimos.", "मीनारें नीचे देखती हैं, सिविस। नीचे ही हम रहते हैं।"],
		["Glass above, rust below. Same rain on both.", "Cristal arriba, óxido abajo. La misma lluvia en ambos.", "ऊपर काँच, नीचे ज़ंग। दोनों पर वही बारिश।"],
	],
	"night": [
		["Night shift, runner. The neon never learned to sleep.", "Turno de noche, runner. El neón nunca aprendió a dormir.", "रात की पाली, रनर। नियॉन ने कभी सोना नहीं सीखा।"],
		["Lamps low, ears high. Vigiles walk at night.", "Faroles bajos, oídos altos. Los Vigiles caminan de noche.", "बत्तियाँ धीमी, कान खड़े। विजिल रात में चलते हैं।"],
	],
	"day": [
		["Grey day, grey soup. Vael vigilat, we queue.", "Día gris, sopa gris. Vael vigilat, hacemos cola.", "धूसर दिन, धूसर सूप। वेल विजिलात, हम कतार में हैं।"],
		["Morning bell rang twice. Nobody asked who rang it.", "La campana de la mañana sonó dos veces. Nadie preguntó quién.", "सुबह की घंटी दो बार बजी। किसी ने नहीं पूछा किसने बजाई।"],
	],
	"rain": [
		["Rain again. Aqua, aqua, aqua. The gutters sing.", "Otra vez lluvia. Aqua, aqua, aqua. Los canalones cantan.", "फिर बारिश। अक्वा, अक्वा, अक्वा। नालियाँ गाती हैं।"],
		["Keep your collar up, civis. Wet streets carry far.", "Sube el cuello, civis. Las calles mojadas llevan lejos.", "कॉलर ऊपर रखो, सिविस। गीली सड़कें दूर तक सुनाती हैं।"],
	],
	"storm": [
		["Storm! Under the awning, quick. Tonitrus is angry.", "¡Tormenta! Bajo el toldo, rápido. Tonitrus está furioso.", "तूफ़ान! छज्जे के नीचे, जल्दी। टोनिट्रस ग़ुस्से में है।"],
		["Even the drones hide in a storm. Stay low.", "Hasta los drones se esconden en una tormenta. Agáchate.", "तूफ़ान में ड्रोन भी छिप जाते हैं। नीचे रहो।"],
	],
	"fog": [
		["Fog eats the signs. Walk by memory, runner.", "La niebla se come los letreros. Camina de memoria, runner.", "कोहरा साइनबोर्ड खा जाता है। याद के सहारे चलो, रनर।"],
	],
	"heat": [
		["Red lights ahead. I know nothing. Nihil.", "Luces rojas adelante. No sé nada. Nihil.", "आगे लाल बत्तियाँ। मैं कुछ नहीं जानता। निहिल।"],
		["Easy, runner. The Watch is sniffing this street.", "Tranquilo, runner. La Guardia olfatea esta calle.", "आराम से, रनर। गश्ती दल इस गली को सूँघ रहा है।"],
	],
	"calm": [
		["Quiet street. Enjoy it, civis, it is rare.", "Calle tranquila. Disfrútala, civis, es rara.", "शांत गली। मज़ा लो, सिविस, यह दुर्लभ है।"],
	],
	"early": [
		["New face with a fast walk. Cores are what they want.", "Cara nueva con paso rápido. Quieren los núcleos.", "नया चेहरा, तेज़ चाल। उन्हें कोर चाहिए।"],
		["They say a runner arrived. I say good luck.", "Dicen que llegó un runner. Yo digo buena suerte.", "कहते हैं एक रनर आया है। मैं कहता हूँ शुभकामनाएँ।"],
	],
	"mid": [
		["The Overseers are nervous. Their lamps flicker.", "Los Overseers están nerviosos. Sus lámparas parpadean.", "ओवरसियर घबराए हैं। उनकी बत्तियाँ झिलमिलाती हैं।"],
		["Whole sectors went quiet. Is that your doing?", "Sectores enteros callaron. ¿Es obra tuya?", "पूरे सेक्टर शांत हो गए। यह तुम्हारा काम है?"],
	],
	"late": [
		["The sky over the old rail is changing. You did that.", "El cielo sobre el viejo ferrocarril cambia. Tú lo hiciste.", "पुरानी रेल के ऊपर आसमान बदल रहा है। यह तुमने किया।"],
		["Hive voices stutter now. Keep going, runner.", "Las voces de la colmena tartamudean. Sigue, runner.", "छत्ते की आवाज़ें अब हकलाती हैं। चलते रहो, रनर।"],
	],
	"kills": [
		["Troopers down on this street. I saw nothing. Nihil.", "Soldados caídos en esta calle. No vi nada. Nihil.", "इस गली में सैनिक गिरे। मैंने कुछ नहीं देखा। निहिल।"],
		["Smoke still on the cobbles. Whose war is this?", "Aún hay humo en los adoquines. ¿De quién es esta guerra?", "पत्थरों पर अब भी धुआँ है। यह किसकी लड़ाई है?"],
		["You are the one who drops Vael. Gratias. Quietly.", "Eres quien derriba Vael. Gratias. En voz baja.", "तुम ही हो जो वेल को गिराते हो। ग्रातियास। धीरे से।"],
	],
	"theft": [
		["That was my cousin's hover! Fur, fur!", "¡Ese era el vehículo de mi primo! ¡Fur, fur!", "वह मेरे चचेरे भाई की हॉवर थी! फुर, फुर!"],
		["Commandeered, they call it. We call it stolen.", "Requisado, lo llaman. Nosotros lo llamamos robado.", "वे इसे ज़ब्ती कहते हैं। हम इसे चोरी कहते हैं।"],
		["Fast hands, runner. Mind the paint next time.", "Manos rápidas, runner. Cuida la pintura la próxima vez.", "तेज़ हाथ, रनर। अगली बार रंग का ध्यान रखना।"],
	],
}

## Exchanges: an array of lines, spoken in turn (speaker alternates CITIZEN / REPLY).
const EXCHANGES := {
	"d_market": [[
		["Two noodles for the price of one lamp?", "¿Dos fideos por el precio de una lámpara?", "एक लैंप के दाम में दो नूडल?"],
		["Pretium ascendit. Take it or starve.", "Pretium ascendit. Tómalo o pasa hambre.", "दाम चढ़ गए। लो या भूखे रहो।"],
		["Gratias. The soup is taxed, not the steam.", "Gratias. La sopa paga impuesto, no el vapor.", "ग्रातियास। सूप पर कर है, भाप पर नहीं।"],
	]],
	"d_foundry": [[
		["Second shift is short again.", "El segundo turno vuelve a ser corto.", "दूसरी पाली फिर छोटी है।"],
		["The furnace eats faster than we pour. Vael logic.", "El horno come más rápido de lo que vertemos. Lógica Vael.", "भट्ठी हमारे ढालने से तेज़ खाती है। वेल का तर्क।"],
	]],
	"d_slums": [[
		["Did you hear the drones at three?", "¿Oíste los drones a las tres?", "तीन बजे ड्रोन सुने?"],
		["Tace, civis. The walls have ears.", "Tace, civis. Las paredes tienen oídos.", "ताचे, सिविस। दीवारों के कान हैं।"],
	]],
	"d_towers": [[
		["The lifts are down again.", "Los ascensores vuelven a estar caídos.", "लिफ़्ट फिर बंद हैं।"],
		["Good. Let the glass people walk for once.", "Bien. Que la gente de cristal camine por una vez.", "अच्छा। काँच वाले लोग एक बार पैदल चलें।"],
	]],
	"night": [[
		["Late for a walk, runner.", "Tarde para pasear, runner.", "टहलने के लिए देर हो गई, रनर।"],
		["Late is when the neon is honest. Vale.", "Tarde es cuando el neón es honesto. Vale.", "देर वह समय है जब नियॉन ईमानदार होता है। वाले।"],
	]],
	"rain": [[
		["Wet again. Is the sky leaking?", "Mojado otra vez. ¿Gotea el cielo?", "फिर गीला। क्या आसमान टपक रहा है?"],
		["The sky is a tank, civis. Someone pulls the plug.", "El cielo es un tanque, civis. Alguien quita el tapón.", "आसमान एक टंकी है, सिविस। कोई डाट खींचता है।"],
	]],
	"kills": [[
		["Did you see the troopers fall?", "¿Viste caer a los soldados?", "क्या तुमने सैनिकों को गिरते देखा?"],
		["I saw a runner. I saw nothing else.", "Vi a un runner. No vi nada más.", "मैंने एक रनर देखा। और कुछ नहीं।"],
		["Wise. Walk on, civis.", "Sabio. Sigue caminando, civis.", "समझदारी। चलते रहो, सिविस।"],
	]],
	"theft": [[
		["Somebody took a hover from the kerb!", "¡Alguien se llevó un vehículo de la acera!", "किसी ने कर्ब से हॉवर उठा ली!"],
		["The runner, I think. Fast hands, bad manners.", "El runner, creo. Manos rápidas, malos modales.", "शायद रनर। तेज़ हाथ, बुरी आदतें।"],
	]],
}

## Vendor lines (opening a trade window and greeting at the counter).
const VENDOR_LINES := {
	"greet_weapons": [["Barrels pulled from Vael wrecks. Look, do not breathe on them.", "Cañones sacados de naves Vael. Mira, no respires sobre ellos.", "वेल मलबे से निकली नालियाँ। देखो, उन पर साँस मत लो।"]],
	"greet_clinic": [["Sit, civis. We patch what the Observers drain.", "Siéntate, civis. Reparamos lo que drenan los Observers.", "बैठो, सिविस। जो ऑब्ज़र्वर सोखते हैं, हम जोड़ते हैं।"]],
	"greet_tech": [["Rift salvage in every drawer. Ask the bench.", "Chatarra de la grieta en cada cajón. Pregunta al banco.", "हर दराज़ में दरार का कबाड़। बेंच से पूछो।"]],
	"greet_bar": [["Drink, rumour, or both? The neon pays me by the hour.", "¿Bebida, rumor o ambos? El neón me paga por hora.", "पेय, अफ़वाह, या दोनों? नियॉन मुझे घंटे के हिसाब से देता है।"]],
	"greet_bodega": [["Fresh shelf today. Do not look at the Observers.", "Estante fresco hoy. No mires a los Observers.", "आज ताज़ा शेल्फ़। ऑब्ज़र्वरों की ओर मत देखना।"]],
	"night": [["Open late, runner. Prices rise with the dark.", "Abierto hasta tarde, runner. Los precios suben con la oscuridad.", "देर तक खुला, रनर। अँधेरे के साथ दाम चढ़ते हैं।"]],
	"rain": [["Wet boots by the door, please. Aqua everywhere.", "Botas mojadas junto a la puerta, por favor. Aqua por todas partes.", "गीले जूते दरवाज़े पर, कृपया। हर जगह अक्वा।"]],
	"heat": [["Quick, runner. The Watch walks past my shutter.", "Rápido, runner. La Guardia pasa frente a mi persiana.", "जल्दी, रनर। गश्ती दल मेरे शटर के पास से गुज़रता है।"]],
	"kills": [["I heard what you did outside. Pay first, talk later.", "Oí lo que hiciste afuera. Paga primero, habla después.", "बाहर जो तुमने किया मैंने सुना। पहले भुगतान, फिर बात।"]],
	"theft": [["Nice hover outside. Is it yours? Do not answer.", "Bonito vehículo afuera. ¿Es tuyo? No contestes.", "बाहर अच्छी हॉवर है। तुम्हारी है? जवाब मत दो।"]],
}

## Rumours that hint at collectibles (a district with shards left) and side jobs. Spoken by citizens and bought-rumour vendors.
const HINTS := {
	"shards_market": [["Rumour: a shard glints in the Market, low in the alleys and high on the roofs.", "Rumor: un fragmento brilla en el Mercado, bajo en los callejones y alto en los tejados.", "अफ़वाह: बाज़ार में एक शार्ड चमकता है, गलियों में नीचे और छतों पर ऊपर।"]],
	"shards_foundry": [["Rumour: the Foundry hides a shard near the stacks. Mind the heat.", "Rumor: la Fundición esconde un fragmento junto a las chimeneas. Cuidado con el calor.", "अफ़वाह: फाउंड्री चिमनियों के पास एक शार्ड छिपाती है। गर्मी से सावधान।"]],
	"shards_slums": [["Rumour: somebody left a shard in the Slums. Kids talk about it.", "Rumor: alguien dejó un fragmento en los Barrios. Los niños hablan de eso.", "अफ़वाह: किसी ने बस्तियों में एक शार्ड छोड़ा है। बच्चे उसकी बातें करते हैं।"]],
	"shards_towers": [["Rumour: the Towers keep a shard on a roof nobody climbs.", "Rumor: las Torres guardan un fragmento en un tejado que nadie escala.", "अफ़वाह: मीनारों में एक छत पर शार्ड है जिस पर कोई नहीं चढ़ता।"]],
	"side_market": [["Rumour: the Market board pays for fast legs. Ask at the shutter.", "Rumor: el tablón del Mercado paga por piernas rápidas. Pregunta en la persiana.", "अफ़वाह: बाज़ार का बोर्ड तेज़ पैरों को पैसे देता है। शटर पर पूछो।"]],
	"side_foundry": [["Rumour: the Foundry wants a hand with a job. Pay is good, questions few.", "Rumor: la Fundición busca una mano para un trabajo. Buen pago, pocas preguntas.", "अफ़वाह: फाउंड्री को एक काम के लिए हाथ चाहिए। पैसा अच्छा, सवाल कम।"]],
	"side_slums": [["Rumour: a job waits in the Slums for someone who does not talk.", "Rumor: un trabajo espera en los Barrios a alguien que no hable.", "अफ़वाह: बस्तियों में एक काम उसका इंतज़ार करता है जो बोलता नहीं।"]],
	"side_towers": [["Rumour: the Towers post a job for anyone who dislikes heights.", "Rumor: las Torres publican un trabajo para quien no ame las alturas.", "अफ़वाह: मीनारों में ऊँचाई से डरने वालों के लिए एक काम है।"]],
}

## Stock rotation: three specials per vendor type, one on the shelf at a time (NpcDialogue.rotation_index). name = [en, es, hi]; hp restored; price before the reputation discount.
const ROTATION := {
	&"weapons": [
		{"name": ["FIELD DRESSING  +35 HP", "VENDAJE DE CAMPO  +35 HP", "फ़ील्ड पट्टी  +35 HP"], "hp": 35, "price": 60},
		{"name": ["STIM SHOT  +50 HP", "INYECCIÓN ESTIMULANTE  +50 HP", "स्टिम शॉट  +50 HP"], "hp": 50, "price": 85},
		{"name": ["ARMOURER TEA  +20 HP", "TÉ DEL ARMERO  +20 HP", "हथियारसाज़ की चाय  +20 HP"], "hp": 20, "price": 30},
	],
	&"clinic": [
		{"name": ["RIFT TONIC  +40 HP", "TÓNICO DE GRIETA  +40 HP", "दरार टॉनिक  +40 HP"], "hp": 40, "price": 70},
		{"name": ["CALM DRIP  +60 HP", "GOTERO CALMANTE  +60 HP", "शांत ड्रिप  +60 HP"], "hp": 60, "price": 100},
		{"name": ["WARD BROTH  +30 HP", "CALDO DE SALA  +30 HP", "वार्ड शोरबा  +30 HP"], "hp": 30, "price": 45},
	],
	&"tech": [
		{"name": ["BENCH COFFEE  +20 HP", "CAFÉ DE BANCO  +20 HP", "बेंच कॉफ़ी  +20 HP"], "hp": 20, "price": 30},
		{"name": ["CELL TONIC  +35 HP", "TÓNICO DE CELDA  +35 HP", "सेल टॉनिक  +35 HP"], "hp": 35, "price": 55},
		{"name": ["SOLDER SOUP  +25 HP", "SOPA DE SOLDADURA  +25 HP", "सोल्डर सूप  +25 HP"], "hp": 25, "price": 40},
	],
	&"bar": [
		{"name": ["HOUSE SPECIAL  +40 HP", "ESPECIAL DE LA CASA  +40 HP", "हाउस स्पेशल  +40 HP"], "hp": 40, "price": 60},
		{"name": ["NIGHT CAP  +30 HP", "COPA NOCTURNA  +30 HP", "नाइट कैप  +30 HP"], "hp": 30, "price": 45},
		{"name": ["NEON SHOT  +50 HP", "TRAGO NEÓN  +50 HP", "नियॉन शॉट  +50 HP"], "hp": 50, "price": 85},
	],
	&"bodega": [
		{"name": ["HOT NOODLES  +30 HP", "FIDEOS CALIENTES  +30 HP", "गरम नूडल  +30 HP"], "hp": 30, "price": 40},
		{"name": ["STREET BUN  +20 HP", "PAN CALLEJERO  +20 HP", "गली का बन  +20 HP"], "hp": 20, "price": 25},
		{"name": ["RATION BAR  +45 HP", "BARRA DE RACIÓN  +45 HP", "राशन बार  +45 HP"], "hp": 45, "price": 65},
	],
}

const DISTRICTS: Array[String] = ["market", "foundry", "slums", "towers"]


## Every [en, es, hi] entry with the speaker prefix it is spoken with.
static func _each() -> Array:
	var out: Array = []
	for k: String in BARKS:
		for e: Array in BARKS[k]:
			out.append([CITIZEN, e])
	for k: String in EXCHANGES:
		for ex: Array in EXCHANGES[k]:
			for j in ex.size():
				out.append([CITIZEN if j % 2 == 0 else REPLY, ex[j]])
	for k: String in VENDOR_LINES:
		for e: Array in VENDOR_LINES[k]:
			out.append([VENDOR, e])
	for k: String in HINTS:
		for e: Array in HINTS[k]:
			out.append([CITIZEN, e])
			out.append([VENDOR, e])
	return out


## Tr table for `lang` ("es" / "hi"): the spoken string (prefix + English) -> translation (prefix kept).
static func table(lang: String) -> Dictionary:
	var idx := 1 if lang == "es" else 2
	var d := {}
	for pair: Array in _each():
		var e: Array = pair[1]
		d[str(pair[0]) + str(e[0])] = str(pair[0]) + str(e[idx])
	for t: StringName in ROTATION:
		for e: Dictionary in ROTATION[t]:
			d[str((e["name"] as Array)[0])] = str((e["name"] as Array)[idx])
	return d


## All spoken English strings (prefix included), for tests.
static func spoken() -> Array[String]:
	var out: Array[String] = []
	for pair: Array in _each():
		out.append(str(pair[0]) + str((pair[1] as Array)[0]))
	return out
