class_name SoftDot
extends RefCounted
## Radial soft-dot textures for billboards and particles, built as an ImageTexture so the pixels exist the moment the texture is used.
## (A GradientTexture2D fills itself on a deferred call; a quad drawn before that shows as a flat white translucent rectangle.)


## `g` is sampled from the centre (0) to the edge of the inscribed circle (1); outside it stays at the last colour.
static func radial(g: Gradient, size := 64) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			img.set_pixel(x, y, g.sample(clampf(d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
