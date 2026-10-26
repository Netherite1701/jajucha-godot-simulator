shader_type canvas_item;
render_mode unshaded;

uniform vec2 image_size = vec2(640.0, 400.0);
uniform vec2 focal_length = vec2(310.70, 309.58);
uniform vec2 principal_point = vec2(309.52, 222.31);
uniform vec3 radial = vec3(0.084568, -0.072728, 0.0);
uniform vec2 tangential = vec2(-0.000606, 0.004212);

void fragment() {
	// For each raw sensor pixel, invert Brown-Conrady distortion and sample
	// the ideal pinhole render. The user's OpenCV undistortion then recovers
	// the calibrated image instead of undistorting an already ideal render.
	vec2 distorted = (UV * image_size - principal_point) / focal_length;
	vec2 point = distorted;
	for (int i = 0; i < 8; i++) {
		float r2 = dot(point, point);
		float scale = 1.0 + r2 * (radial.x + r2 * (radial.y + r2 * radial.z));
		vec2 tangent = vec2(
			2.0 * tangential.x * point.x * point.y + tangential.y * (r2 + 2.0 * point.x * point.x),
			tangential.x * (r2 + 2.0 * point.y * point.y) + 2.0 * tangential.y * point.x * point.y);
		point = (distorted - tangent) / scale;
	}
	// Godot's frustum uses square pixels with fy. This sample conversion also
	// preserves the small fx/fy difference in the supplied intrinsic matrix.
	vec2 source_uv = (point * focal_length.y + principal_point) / image_size;
	if (any(lessThan(source_uv, vec2(0.0))) || any(greaterThan(source_uv, vec2(1.0)))) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		COLOR = texture(TEXTURE, source_uv);
	}
}
