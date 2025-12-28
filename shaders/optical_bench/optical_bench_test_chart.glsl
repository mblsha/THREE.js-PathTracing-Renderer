vec3 chartPattern(vec2 p)
{
	vec2 uv = p / uChartHalfSize; // roughly -1..1
	vec3 col = vec3(0.02);

	// Keep AA stable even under very strong magnification/defocus through the lens.
	float aa = clamp(max(fwidth(uv.x), fwidth(uv.y)), 0.0, 0.01);

	float minorPeriod = 0.1;
	float majorPeriod = 0.5;
	float minorThickness = 0.002;
	float majorThickness = 0.004;

	float dxMinor = periodicDist(uv.x, minorPeriod);
	float dyMinor = periodicDist(uv.y, minorPeriod);
	float dxMajor = periodicDist(uv.x, majorPeriod);
	float dyMajor = periodicDist(uv.y, majorPeriod);

	float minorLine = max(1.0 - smoothstep(minorThickness, minorThickness + aa, dxMinor),
			      1.0 - smoothstep(minorThickness, minorThickness + aa, dyMinor));
	float majorLine = max(1.0 - smoothstep(majorThickness, majorThickness + aa, dxMajor),
			      1.0 - smoothstep(majorThickness, majorThickness + aa, dyMajor));

	float axisThickness = 0.006;
	float axisLine = max(1.0 - smoothstep(axisThickness, axisThickness + aa, abs(uv.x)),
			     1.0 - smoothstep(axisThickness, axisThickness + aa, abs(uv.y)));

	col = mix(col, vec3(0.15), minorLine);
	col = mix(col, vec3(0.85), majorLine);
	col = mix(col, vec3(1.0), axisLine);

	// Siemens star (center focus/astig probe)
	float r = length(uv);
	float starRadius = 0.25;
	float starMask = 1.0 - smoothstep(starRadius, starRadius + (aa * 6.0), r);
	float ang = atan(uv.y, uv.x);
	float spokes = step(0.0, sin(ang * 48.0));
	vec3 starCol = mix(vec3(0.05), vec3(0.95), spokes);
	col = mix(col, starCol, starMask);

	// corner dots (edge probes)
	vec2 c = vec2(0.85, 0.85);
	float dCorner = min(min(length(uv - c), length(uv - vec2(-c.x, c.y))),
			    min(length(uv - vec2(c.x, -c.y)), length(uv + c)));
	float cornerDot = 1.0 - smoothstep(0.02, 0.03, dCorner);
	col = mix(col, vec3(1.0), cornerDot);

	return col;
}

//---------------------------------------------------------------------------------------
float SceneIntersectSensor_TestChart()
//---------------------------------------------------------------------------------------
{
	float t = INFINITY;
	float d;
	int objectCount = 0;

	hitObjectID = -INFINITY;
	hitType = -100;

	// focusing aid grid (emissive lines only)
	{
		float tg;
		vec3 gn, ge;
		if (FocusGridIntersect(rayOrigin, rayDirection, tg, gn, ge) && tg < t)
		{
			t = tg;
			hitNormal = gn;
			hitColor = vec3(0.0);
			hitEmission = ge;
			hitType = LIGHT;
			hitObjectID = float(objectCount);
		}
		objectCount++;
	}

	// emissive test chart plane (object stage)
	vec3 chartPos = vec3(0.0, 0.0, uChartZ);
	vec3 chartNormal = vec3(0.0, 0.0, 1.0);
	d = RectangleIntersect(chartPos, chartNormal, uChartHalfSize.x, uChartHalfSize.y, rayOrigin, rayDirection);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		vec3 pat = chartPattern(hitPos.xy);
		hitNormal = chartNormal;
		hitColor = pat;
		hitEmission = pat * uChartEmission;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	// emissive corner "point lights" near chart corners
	float cornerR = 2.0;
	float cornerE = 60.0;
	vec3 cornerCol = vec3(1.0);
	vec2 c = vec2(0.85) * uChartHalfSize;

	vec3 p0 = vec3(c.x, c.y, uChartZ + 1.0);
	vec3 p1 = vec3(-c.x, c.y, uChartZ + 1.0);
	vec3 p2 = vec3(c.x, -c.y, uChartZ + 1.0);
	vec3 p3 = vec3(-c.x, -c.y, uChartZ + 1.0);

	d = SphereIntersect(cornerR, p0, rayOrigin, rayDirection);
	if (d < t) { t = d; vec3 hp = rayOrigin + rayDirection * t; hitNormal = normalize(hp - p0); hitColor = cornerCol; hitEmission = cornerCol * cornerE; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;
	d = SphereIntersect(cornerR, p1, rayOrigin, rayDirection);
	if (d < t) { t = d; vec3 hp = rayOrigin + rayDirection * t; hitNormal = normalize(hp - p1); hitColor = cornerCol; hitEmission = cornerCol * cornerE; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;
	d = SphereIntersect(cornerR, p2, rayOrigin, rayDirection);
	if (d < t) { t = d; vec3 hp = rayOrigin + rayDirection * t; hitNormal = normalize(hp - p2); hitColor = cornerCol; hitEmission = cornerCol * cornerE; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;
	d = SphereIntersect(cornerR, p3, rayOrigin, rayDirection);
	if (d < t) { t = d; vec3 hp = rayOrigin + rayDirection * t; hitNormal = normalize(hp - p3); hitColor = cornerCol; hitEmission = cornerCol * cornerE; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;

	// on-axis near/far depth probes
	float probeR = 8.0;
	float probeE = 12.0;
	vec3 probeCol = vec3(1.0, 0.2, 0.2);
	vec3 pNear = vec3(0.0, 0.0, -500.0);
	vec3 pFar = vec3(0.0, 0.0, -2000.0);

	d = SphereIntersect(probeR, pNear, rayOrigin, rayDirection);
	if (d < t) { t = d; vec3 hp = rayOrigin + rayDirection * t; hitNormal = normalize(hp - pNear); hitColor = probeCol; hitEmission = probeCol * probeE; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;

	d = SphereIntersect(probeR, pFar, rayOrigin, rayDirection);
	if (d < t) { t = d; vec3 hp = rayOrigin + rayDirection * t; hitNormal = normalize(hp - pFar); hitColor = probeCol * 0.8; hitEmission = hitColor * (probeE * 0.7); hitType = LIGHT; hitObjectID = float(objectCount); }

	return t;
}

//---------------------------------------------------------------------------------------
float SceneIntersectGeometry_TestChart()
//---------------------------------------------------------------------------------------
{
	float t = INFINITY;
	float d;
	int objectCount = 0;
	vec3 n;

	hitObjectID = -INFINITY;
	hitType = -100;

	float zFront = -0.5 * uLensThickness;
	float zBack = 0.5 * uLensThickness;
	float stopPlaneZ = zBack + max(0.0, uStopOffset);

	// focusing aid grid (emissive lines only)
	{
		float tg;
		vec3 gn, ge;
		if (FocusGridIntersect(rayOrigin, rayDirection, tg, gn, ge) && tg < t)
		{
			t = tg;
			hitNormal = gn;
			hitColor = vec3(0.0);
			hitEmission = ge;
			hitType = LIGHT;
			hitObjectID = float(objectCount);
		}
		objectCount++;
	}

	// chart plane (diffuse, unlit pattern)
	vec3 chartPos = vec3(0.0, 0.0, uChartZ);
	vec3 chartNormal = vec3(0.0, 0.0, 1.0);
	d = RectangleIntersectTwoSided(chartPos, chartNormal, uChartHalfSize.x, uChartHalfSize.y, rayOrigin, rayDirection);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		vec3 pat = chartPattern(hitPos.xy);
		hitNormal = chartNormal;
		if (dot(hitNormal, rayDirection) > 0.0) hitNormal *= -1.0;
		hitColor = pat;
		hitEmission = vec3(0.0);
		hitType = DIFF;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	// sensor plane rectangle (overlay)
	vec3 sensorPos = vec3(0.0, 0.0, uSensorZ);
	vec3 sensorNormal = vec3(0.0, 0.0, 1.0);
	d = RectangleIntersectTwoSided(sensorPos, sensorNormal, 0.5 * uSensorSize.x, 0.5 * uSensorSize.y, rayOrigin, rayDirection);
	if (d < t)
	{
		t = d;
		hitNormal = sensorNormal;
		if (dot(hitNormal, rayDirection) > 0.0) hitNormal *= -1.0;
		hitColor = vec3(0.2, 1.0, 0.2);
		hitEmission = vec3(0.0);
		hitType = DIFF;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	// lens body (simple cylinder + caps)
	d = CylinderIntersect(uLensRadius, zFront, zBack, rayOrigin, rayDirection, n);
	if (d < t)
	{
		t = d;
		hitNormal = n;
		hitColor = vec3(0.15, 0.5, 1.0);
		hitEmission = vec3(0.0);
		hitType = DIFF;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	d = DiskCapIntersect(uLensRadius, vec3(0.0, 0.0, zFront), vec3(0.0, 0.0, -1.0), rayOrigin, rayDirection, n);
	if (d < t)
	{
		t = d;
		hitNormal = n;
		hitColor = vec3(0.12, 0.4, 0.9);
		hitEmission = vec3(0.0);
		hitType = DIFF;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	d = DiskCapIntersect(uLensRadius, vec3(0.0, 0.0, zBack), vec3(0.0, 0.0, 1.0), rayOrigin, rayDirection, n);
	if (d < t)
	{
		t = d;
		hitNormal = n;
		hitColor = vec3(0.12, 0.4, 0.9);
		hitEmission = vec3(0.0);
		hitType = DIFF;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	// aperture stop (black disk with circular hole)
	d = AnnulusDiskIntersect(uLensRadius * 1.15, uStopRadius, vec3(0.0, 0.0, stopPlaneZ), vec3(0.0, 0.0, 1.0), rayOrigin, rayDirection, n);
	if (d < t)
	{
		t = d;
		hitNormal = n;
		hitColor = vec3(0.03);
		hitEmission = vec3(0.0);
		hitType = DIFF;
		hitObjectID = float(objectCount);
	}

	return t;
}
