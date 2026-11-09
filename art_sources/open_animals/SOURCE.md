# Animals (Quaternius, CC0) for the wildlife of the outskirts, the coast and the sea (wave 107)

Fetched 2026-11-09 with plain curl and a descriptive user agent (QuantumTeleportar-asset-fetch) from OpenGameArt.org. The zips are NOT committed; only the converted, size-reduced
scenes are (godot/assets/models/animals/*.scn, 17 species, 800 KB). The FBX files of the packs are rigged and animated.

| pack | page | zip | used |
|---|---|---|---|
| Farm Animals Pack | https://opengameart.org/content/lowpoly-animated-farm-animal-pack | https://opengameart.org/sites/default/files/Farm%20Animals%20by%20%40Quaternius.zip | Horse, Cow, Sheep, Llama, Pig, Zebra (Idle / Walk / Run / Death clips on Horse, Cow, Zebra; Idle / Jump on the others, which borrow the Horse and Cow clips: same bone names) |
| Animals Pack (5 low poly animals) | https://opengameart.org/content/5-low-poly-animals | https://opengameart.org/sites/default/files/Animals%20Pack%20by%20Quaternius.zip | Bird, Fish, Whale, Red Fox |
| Animal Pack Vol.2 | https://opengameart.org/content/animated-animales-low-poly | https://opengameart.org/sites/default/files/Animal%20Pack%20Vol.2%20by%20%40Quaternius.zip | Wolf (Eagle, Cat, Dog and Piranha are not used: the Eagle has 24 800 triangles) |

Species made from them (godot/tools/open_models/convert_animals.gd, run by convert_animals.sh): deer (Horse body, antlers generated), goat (Llama body, horns generated), boar (Pig body),
coyote (Wolf, sand colour), songbird / seagull / eagle (the Bird in three colours and sizes), fish / shark / dolphin / whale (Fish and Whale in other colours and sizes).
The Wild Animals pack (Deer, Bear, Boar, Fox, Rabbit, Wolf, https://opengameart.org/content/animated-wild-animals) is only a preview there (its models are a paid pack), so it is not used.

Conversion: Godot 4.6 imports the FBX itself. All surfaces are merged into one surface per animal (one draw call) with the colours baked into the vertex colour (species tints applied
there), the rig and the clips are kept (loop clips idle / walk / run / fly / swim, a one-shot dead), size in metres, facing -Z, feet on y = 0. Triangles: 158 (bird) to 1354 (zebra).
