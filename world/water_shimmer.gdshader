shader_type canvas_item;

// Liquid shimmer (water and lava): a gentle brightness ripple travelling diagonally across the surface, so
// a liquid reads as moving rather than flat. The GPU animates it from TIME, so the floor is never redrawn
// on the CPU for it. Same wave as the old per-tile pulse, 1 + amplitude * sin(time * speed + (x + y) * k),
// but per pixel, so it rolls smoothly across a quarter instead of stepping between them.
uniform float amplitude = 0.09;
uniform float speed = 2.2;
uniform float wavenumber = 0.05; // phase per World pixel along x + y

varying float phase_offset;

void vertex() {
	phase_offset = (VERTEX.x + VERTEX.y) * wavenumber; // VERTEX is World-local: GridBackground sits at the origin
}

void fragment() {
	COLOR.rgb *= 1.0 + amplitude * sin(TIME * speed + phase_offset);
}
