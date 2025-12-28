bool FocusGridIntersect(vec3 ro, vec3 rd, out float t, out vec3 n, out vec3 emission)
{
	if (uFocusGridEnabled == 0)
		return false;

	float dt = rd.z;
	if (abs(dt) < 0.0000001)
		return false;

	float D = max(0.01, uFocusGridDistance);
	float gridZ = uSensorZ - D;
	t = (gridZ - ro.z) / dt;
	if (t <= 0.0)
		return false;

	vec3 hp = ro + rd * t;

	// Project the grid in "sensor space" so its on-screen density doesn't change with distance.
	// Approximate mapping: sensorXY ~= hp.xy * (uSensorZ / D)
	vec2 sensorXY = hp.xy * (uSensorZ / D);
	vec2 sensorNDC = sensorXY / (0.5 * uSensorSize);

	float density = clamp(uFocusGridLines, 0.01, 2.0);
	float period = 1.0 / density;

	float dx = periodicDist(sensorNDC.x, period);
	float dy = periodicDist(sensorNDC.y, period);

	float thickness = 0.012;
	float aa = clamp(max(fwidth(sensorNDC.x), fwidth(sensorNDC.y)), 0.0, 0.05);
	float line = 1.0 - smoothstep(thickness, thickness + aa, min(dx, dy));
	if (line <= 0.0)
		return false;

	n = vec3(0.0, 0.0, dt < 0.0 ? 1.0 : -1.0);
	emission = vec3(0.15, 0.95, 0.35) * (2.5 * line);
	return true;
}
