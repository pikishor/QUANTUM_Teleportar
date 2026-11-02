# assets_incoming

Drop CC0 PBR sets here, one folder per set, name containing the kind: `asphalt`, `concrete`, `metal`, `brick` or `tile`
(e.g. `Asphalt012/`, `Bricks075A` is not matched: rename to `brick_075`). Each folder needs ambientCG / Poly Haven files:
`*_Color`, `*_NormalGL`, `*_Roughness`, `*_AmbientOcclusion`, optional `*_Displacement`.

Then from `godot/`: `python3 tools/materials/import_scanned.py --size 2048` (or 1024). Output goes to `assets/textures/scanned_<kind>_{albedo,normal,orm}[_half].png`
(ORM: R=AO, G=roughness, B=metal). Godot imports them; LOW tier uses the `_half` files. With nothing dropped here the game keeps its procedural surfaces.
Add every set you use to `docs/THIRD_PARTY.md`.
