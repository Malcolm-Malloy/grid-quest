shader_type canvas_item;
render_mode unshaded;

// Reads the mask viewport (visible floor drawn in a magenta key, real occluders punched in)
// and paints the whole highlight: a low-opacity red fill over visible floor, plus a solid
// red edge line on the floor pixels at its boundary. Occlusion is done by the real renderer,
// so this is pixel-exact and automatically correct under walls, doors, the player and any
// object tagged onto the mask layer.

uniform sampler2D mask_tex : filter_nearest;
uniform vec2 tex_size;

bool is_floor(vec2 uv) {
	vec4 c = texture(mask_tex, uv);
	return c.a > 0.5 && c.r > 0.5 && c.g < 0.4 && c.b > 0.5; // magenta key
}

void fragment() {
	if (!is_floor(UV)) {
		COLOR = vec4(0.0);
	} else {
		vec2 p = 1.0 / tex_size;
		bool edge = !is_floor(UV + vec2(p.x, 0.0)) || !is_floor(UV - vec2(p.x, 0.0))
				|| !is_floor(UV + vec2(0.0, p.y)) || !is_floor(UV - vec2(0.0, p.y))
				|| !is_floor(UV + 2.0 * vec2(p.x, 0.0)) || !is_floor(UV - 2.0 * vec2(p.x, 0.0))
				|| !is_floor(UV + 2.0 * vec2(0.0, p.y)) || !is_floor(UV - 2.0 * vec2(0.0, p.y));
		COLOR = edge ? vec4(0.95, 0.1, 0.1, 0.95) : vec4(1.0, 0.15, 0.15, 0.22);
	}
}
