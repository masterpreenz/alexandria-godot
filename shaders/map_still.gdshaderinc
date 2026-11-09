// The shaders' clock, stopped on the maps: the minimap and the world map draw the land into square pictures (the
// game's own window never is), now and then rather than every frame, so water, mist and clouds stand still there
// instead of jumping between redraws. Call from fragment() with SCREEN_PIXEL_SIZE.
float anim_time(vec2 screen_pixel_size) {
	return abs(screen_pixel_size.x - screen_pixel_size.y) < 1e-7 ? 0.0 : TIME;
}
