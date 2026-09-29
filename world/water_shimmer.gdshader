shader_type canvas_item;

// Liquid shimmer (water and lava): a gentle brightness ripple travelling diagonally across the surface, so
// a liquid reads as moving rather than flat. The GPU animates it from TIME, so the floor is never redrawn
// on the CPU for it. Same wave as the old per-tile pulse, 1 + amplitude * sin(time * speed + (x + y) * k),
// but per pixel, so it rolls smoothly across a quarter instead of stepping between them.
//
// SHORE MODE (use_body): a shoreline quarter is drawn from the feathered shore atlas, but only the atlas's
// ALPHA is used -- the soft edge shape. Its colour comes from `body`, the liquid's own open-water tile,
// sampled by World position exactly as the open water tiles it, so the edge is the same smooth surface
// (same ripple scale, seamless with its neighbours) rather than the atlas's own busier, half-scale ripple.
uniform float amplitude = 0.09;
uniform float speed = 2.2;
uniform float wavenumber = 0.05; // phase per World pixel along x + y
uniform bool use_body = false;
uniform sampler2D body : repeat_enable, filter_nearest;
uniform float body_size = 128.0; // the open-water tile's size in World pixels (GridBackground.FLOOR_TEX)

varying float phase_offset;
varying vec2 world;
varying vec4 tint;

void vertex() {
	world = VERTEX; // VERTEX is World-local: GridBackground sits at the origin
	phase_offset = (VERTEX.x + VERTEX.y) * wavenumber;
	tint = COLOR;
}

void fragment() {
	if (use_body) {
		vec4 b = texture(body, world / body_size);
		COLOR = vec4(b.rgb * tint.rgb, texture(TEXTURE, UV).a * tint.a);
	}
	COLOR.rgb *= 1.0 + amplitude * sin(TIME * speed + phase_offset);
}
