// Eraser.
//
// The canvas is stored premultiplied, so a pixel's colour is already scaled
// by its own alpha. Rubbing something out therefore has to scale colour and
// alpha by the same amount, or the colour left behind would be too strong
// for the alpha still carrying it and the stroke would leave a bright ghost.
//
// blend_mul multiplies destination by source on every channel, so writing
// (1 - stamp) into all four does exactly that.
shader_type canvas_item;
render_mode blend_mul, unshaded;

void fragment() {
	float stamp = clamp(texture(TEXTURE, UV).a * COLOR.a, 0.0, 1.0);
	float keep = 1.0 - stamp;
	COLOR = vec4(keep, keep, keep, keep);
}
