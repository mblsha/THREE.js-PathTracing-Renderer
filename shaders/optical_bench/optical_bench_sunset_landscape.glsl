#define TERRAIN_NX 6
#define TERRAIN_NZ 10

float hash12(vec2 p)
{
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float valueNoise2D(vec2 p)
{
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm5(vec2 p)
{
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++)
	{
		v += a * valueNoise2D(p);
		p = (p * 2.02) + vec2(13.7, 7.9);
		a *= 0.5;
	}
	return v;
}

float grassMicroHeightMm(vec2 xz)
{
	// Produces small-scale height variations (in mm) for bump shading.
	float macro = fbm5(xz * 0.002);                    // ~0.5 m scale
	float mid   = fbm5(xz * 0.020 + vec2(17.0, 91.0)); // ~5 cm scale
	float micro = fbm5(xz * 0.180 + vec2(3.0, 5.0));   // ~5 mm scale

	float h = 0.0;
	h += (macro - 0.5) * 10.0;
	h += (mid   - 0.5) * 7.0;
	h += (micro - 0.5) * 3.0;
	return h;
}

vec3 grassMicroNormal(vec2 xz, vec3 baseN)
{
	float eps = 6.0;
	float hL = grassMicroHeightMm(xz - vec2(eps, 0.0));
	float hR = grassMicroHeightMm(xz + vec2(eps, 0.0));
	float hD = grassMicroHeightMm(xz - vec2(0.0, eps));
	float hU = grassMicroHeightMm(xz + vec2(0.0, eps));

	float dHdx = (hR - hL) / (2.0 * eps);
	float dHdz = (hU - hD) / (2.0 * eps);

	vec3 up = abs(baseN.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t = normalize(cross(up, baseN));
	vec3 b = cross(baseN, t);

	float bumpStrength = 0.35;
	return normalize(baseN - bumpStrength * (dHdx * t + dHdz * b));
}

vec3 sunsetSky(vec3 rd)
{
	vec3 sunDir = normalize(vec3(0.35, 0.06, -1.0));

	float t = clamp(rd.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 horizon = vec3(1.15, 0.55, 0.20);
	vec3 zenith  = vec3(0.06, 0.18, 0.55);
	vec3 sky = mix(horizon, zenith, pow(t, 1.35));

	float sunDot = max(0.0, dot(rd, sunDir));
	float sunDisk = pow(sunDot, 1800.0);
	float sunGlow = pow(sunDot, 18.0);
	sky += vec3(4.0, 2.0, 0.8) * sunGlow;
	sky += vec3(25.0, 12.0, 4.0) * sunDisk;

	float haze = exp(-abs(rd.y) * 8.0);
	sky = mix(sky, horizon, 0.25 * haze);
	return sky;
}

vec3 shadeSunset(vec3 albedo, vec3 n, vec3 rd, float sunVis)
{
	vec3 sunDir = normalize(vec3(0.35, 0.06, -1.0));
	vec3 sunCol = vec3(1.0, 0.55, 0.25) * 6.0;

	float ndotl = max(0.0, dot(n, sunDir));
	vec3 hemi = mix(vec3(0.05, 0.06, 0.08), vec3(0.12, 0.18, 0.35), clamp(n.y * 0.5 + 0.5, 0.0, 1.0));

	vec3 col = albedo * (hemi * 2.0 + sunCol * ndotl * clamp(sunVis, 0.0, 1.0));

	// warm rim from the horizon
	float rim = pow(clamp(1.0 - max(0.0, dot(n, -rd)), 0.0, 1.0), 2.0);
	col += vec3(0.35, 0.18, 0.08) * rim * 0.2;
	return col;
}

vec3 shadeSunset(vec3 albedo, vec3 n, vec3 rd)
{
	return shadeSunset(albedo, n, rd, 1.0);
}

float terrainHeight(vec2 xz)
{
	float x = xz.x;
	float z = xz.y;
	float h = -420.0;
	h += 190.0 * sin(x * 0.0011) * cos(z * 0.00065);
	h += 90.0 * sin((x + z) * 0.0005);
	h += 50.0 * sin((x - z) * 0.00035);
	return h;
}

vec3 terrainAlbedo(vec2 xz, float h, float triRand)
{
	// Grass everywhere (subtle variation to read as "ground cover" without heavy geometry).
	vec3 grassLowA  = vec3(0.07, 0.17, 0.07);
	vec3 grassLowB  = vec3(0.10, 0.22, 0.10);
	vec3 grassHighA = vec3(0.11, 0.24, 0.09);
	vec3 grassHighB = vec3(0.18, 0.32, 0.13);

	float high = smoothstep(-560.0, -160.0, h);
	vec3 grassLow  = mix(grassLowA,  grassLowB,  triRand);
	vec3 grassHigh = mix(grassHighA, grassHighB, triRand);
	vec3 grass = mix(grassLow, grassHigh, high);

	float patchVal = hash12(floor(xz * 0.0015) + vec2(11.0, 37.0));
	grass *= (0.85 + (0.3 * patchVal));

	float clumps = fbm5(xz * 0.020 + vec2(9.0, 21.0));
	float micro  = fbm5(xz * 0.180 + vec2(5.0, 3.0));
	grass *= (0.70 + (0.55 * clumps));
	grass *= (0.85 + (0.35 * micro));

	return clamp(grass, 0.0, 1.0);
}

float SunsetLandscapeStageShiftZ()
{
	// Move the whole landscape so its front edge (zMin = -1400mm) sits at uChartZ (= -Object_Distance_mm).
	return uChartZ + 1400.0;
}

float SceneIntersectAny_SunsetLandscapeOccluders(vec3 ro, vec3 rd)
{
	float t = INFINITY;
	float d;
	vec3 n;
	int isRayExiting = FALSE;

	// Wooden shed-house (box + gable roof)
	vec3 houseC = vec3(850.0, 0.0, -4200.0);
	houseC.y = terrainHeight(houseC.xz) + 6.0;

	float wallH = 240.0;
	vec3 houseMin = houseC + vec3(-240.0, 0.0, -200.0);
	vec3 houseMax = houseC + vec3(240.0, wallH, 200.0);

	vec3 boxN;
	d = BoxIntersect(houseMin, houseMax, ro, rd, boxN, isRayExiting);
	t = min(t, d);

	float roofH = 170.0;
	vec3 r0 = houseC + vec3(-260.0, wallH, -220.0);
	vec3 r1 = houseC + vec3(260.0, wallH, -220.0);
	vec3 r2 = houseC + vec3(260.0, wallH, 220.0);
	vec3 r3 = houseC + vec3(-260.0, wallH, 220.0);
	vec3 ridge0 = houseC + vec3(0.0, wallH + roofH, -220.0);
	vec3 ridge1 = houseC + vec3(0.0, wallH + roofH, 220.0);

	d = TriangleIntersect(r0, r3, ridge1, ro, rd, n); t = min(t, d);
	d = TriangleIntersect(r0, ridge1, ridge0, ro, rd, n); t = min(t, d);
	d = TriangleIntersect(r1, ridge0, ridge1, ro, rd, n); t = min(t, d);
	d = TriangleIntersect(r1, ridge1, r2, ro, rd, n); t = min(t, d);
	d = TriangleIntersect(r3, r2, ridge1, ro, rd, n); t = min(t, d);
	d = TriangleIntersect(r0, ridge0, r1, ro, rd, n); t = min(t, d);

	// Fir trees
	vec3 treeCenters[8];
	treeCenters[0] = vec3(-900.0, 0.0, -3800.0);
	treeCenters[1] = vec3(-1400.0, 0.0, -5200.0);
	treeCenters[2] = vec3(-600.0, 0.0, -6200.0);
	treeCenters[3] = vec3(300.0, 0.0, -6800.0);
	treeCenters[4] = vec3(1600.0, 0.0, -5200.0);
	treeCenters[5] = vec3(2100.0, 0.0, -6000.0);
	treeCenters[6] = vec3(2200.0, 0.0, -3600.0);
	treeCenters[7] = vec3(450.0, 0.0, -3100.0);

	for (int i = 0; i < 8; i++)
	{
		vec3 tc = treeCenters[i];
		tc.y = terrainHeight(tc.xz) + 2.0;

		float trunkH = 140.0 + 20.0 * float(i & 1);
		vec3 trunkBase = tc;
		vec3 trunkTop  = tc + vec3(0.0, trunkH, 0.0);

		d = ConeIntersect(trunkBase, 26.0, trunkTop, 18.0, ro, rd, n);
		t = min(t, d);

		vec3 foliageBase = trunkTop + vec3(0.0, -10.0, 0.0);
		vec3 foliageTop  = trunkTop + vec3(0.0, 260.0, 0.0);
		d = ConeIntersect(foliageBase, 120.0, foliageTop, 0.0, ro, rd, n);
		t = min(t, d);
	}

	// Distant mountain (for horizon occlusion)
	vec3 mC = vec3(-6000.0, -900.0, -90000.0);
	float mHalf = 26000.0;
	vec3 mApex = mC + vec3(0.0, 24000.0, 0.0);
	vec3 m0 = mC + vec3(-mHalf, 0.0, -mHalf);
	vec3 m1 = mC + vec3(mHalf, 0.0, -mHalf);
	vec3 m2 = mC + vec3(mHalf, 0.0, mHalf);
	vec3 m3 = mC + vec3(-mHalf, 0.0, mHalf);

	d = TriangleIntersect(m0, m1, mApex, ro, rd, n); t = min(t, d);
	d = TriangleIntersect(m1, m2, mApex, ro, rd, n); t = min(t, d);
	d = TriangleIntersect(m2, m3, mApex, ro, rd, n); t = min(t, d);
	d = TriangleIntersect(m3, m0, mApex, ro, rd, n); t = min(t, d);

	return t;
}

float SunsetSunVisibility(vec3 hitPos, vec3 hitNormal)
{
	vec3 sunDir = normalize(vec3(0.35, 0.06, -1.0));
	float zShift = SunsetLandscapeStageShiftZ();
	vec3 ro = (hitPos - vec3(0.0, 0.0, zShift)) + hitNormal * 2.0;
	float t = SceneIntersectAny_SunsetLandscapeOccluders(ro, sunDir);
	return (t == INFINITY) ? 1.0 : 0.0;
}

float SceneIntersectSensor_SunsetLandscape()
{
	float t = INFINITY;
	float d;
	int objectCount = 0;
	vec3 n;
	int isRayExiting = FALSE;

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

	float zShift = SunsetLandscapeStageShiftZ();
	vec3 ro = rayOrigin - vec3(0.0, 0.0, zShift);
	vec3 rd = rayDirection;

	// Lake (flat water rectangle)
	float waterY = -360.0;
	vec3 lakePos = vec3(0.0, waterY, -7500.0);
	vec3 lakeNormal = vec3(0.0, 1.0, 0.0);
	d = RectangleIntersectTwoSided(lakePos, lakeNormal, 2600.0, 1800.0, ro, rd);
	if (d < t)
	{
		t = d;
		vec3 hitPos = ro + rd * t;
		vec3 nn = lakeNormal;
		if (dot(nn, rd) > 0.0) nn *= -1.0;

		vec3 V = normalize(-rd);
		float cosTheta = clamp(dot(V, nn), 0.0, 1.0);
		float F0 = 0.02;
		float fres = F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
		vec3 refl = sunsetSky(reflect(rd, nn));
		vec3 waterBase = vec3(0.02, 0.08, 0.12);
		vec3 col = mix(waterBase, refl, fres);

		// subtle depth tint
		float shore = smoothstep(0.0, 600.0, abs(hitPos.x) - 2200.0) + smoothstep(0.0, 600.0, abs(hitPos.z + 7500.0) - 1500.0);
		col *= 0.9 + 0.1 * clamp(shore, 0.0, 1.0);

		hitNormal = nn;
		hitColor = col;
		hitEmission = col;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	// Low-poly terrain patch (coarse triangle grid)
	const float xMin = -4200.0;
	const float xMax = 4200.0;
	const float zMin = -1400.0;
	const float zMax = -12000.0;

	float stepX = (xMax - xMin) / float(TERRAIN_NX);
	float stepZ = (zMax - zMin) / float(TERRAIN_NZ);

	for (int iz = 0; iz < TERRAIN_NZ; iz++)
	{
		for (int ix = 0; ix < TERRAIN_NX; ix++)
		{
			float x0 = xMin + stepX * float(ix);
			float x1 = x0 + stepX;
			float z0 = zMin + stepZ * float(iz);
			float z1 = z0 + stepZ;

			vec3 v00 = vec3(x0, terrainHeight(vec2(x0, z0)), z0);
			vec3 v10 = vec3(x1, terrainHeight(vec2(x1, z0)), z0);
			vec3 v01 = vec3(x0, terrainHeight(vec2(x0, z1)), z1);
			vec3 v11 = vec3(x1, terrainHeight(vec2(x1, z1)), z1);

			vec3 triN;
			float triRand = hash12(vec2(float(ix), float(iz)));

			if (((ix + iz) & 1) == 0)
			{
				d = TriangleIntersect(v00, v10, v11, ro, rd, triN);
				if (d < t)
				{
					t = d;
					vec3 hitPosLocal = ro + rd * t;
					vec3 hitPosWorld = rayOrigin + rd * t;
					vec3 alb = terrainAlbedo(hitPosLocal.xz, hitPosLocal.y, triRand);
					vec3 nDetail = grassMicroNormal(hitPosLocal.xz, triN);
					if (dot(nDetail, rd) > 0.0) nDetail *= -1.0;
					float sunVis = SunsetSunVisibility(hitPosWorld, nDetail);
					vec3 col = shadeSunset(alb, nDetail, rd, sunVis);
					hitNormal = nDetail;
					hitColor = alb;
					hitEmission = col;
					hitType = LIGHT;
					hitObjectID = float(objectCount);
				}
				objectCount++;

				d = TriangleIntersect(v00, v11, v01, ro, rd, triN);
				if (d < t)
				{
					t = d;
					vec3 hitPosLocal = ro + rd * t;
					vec3 hitPosWorld = rayOrigin + rd * t;
					vec3 alb = terrainAlbedo(hitPosLocal.xz, hitPosLocal.y, triRand * 0.97);
					vec3 nDetail = grassMicroNormal(hitPosLocal.xz, triN);
					if (dot(nDetail, rd) > 0.0) nDetail *= -1.0;
					float sunVis = SunsetSunVisibility(hitPosWorld, nDetail);
					vec3 col = shadeSunset(alb, nDetail, rd, sunVis);
					hitNormal = nDetail;
					hitColor = alb;
					hitEmission = col;
					hitType = LIGHT;
					hitObjectID = float(objectCount);
				}
				objectCount++;
			}
			else
			{
				d = TriangleIntersect(v00, v10, v01, ro, rd, triN);
				if (d < t)
				{
					t = d;
					vec3 hitPosLocal = ro + rd * t;
					vec3 hitPosWorld = rayOrigin + rd * t;
					vec3 alb = terrainAlbedo(hitPosLocal.xz, hitPosLocal.y, triRand);
					vec3 nDetail = grassMicroNormal(hitPosLocal.xz, triN);
					if (dot(nDetail, rd) > 0.0) nDetail *= -1.0;
					float sunVis = SunsetSunVisibility(hitPosWorld, nDetail);
					vec3 col = shadeSunset(alb, nDetail, rd, sunVis);
					hitNormal = nDetail;
					hitColor = alb;
					hitEmission = col;
					hitType = LIGHT;
					hitObjectID = float(objectCount);
				}
				objectCount++;

				d = TriangleIntersect(v10, v11, v01, ro, rd, triN);
				if (d < t)
				{
					t = d;
					vec3 hitPosLocal = ro + rd * t;
					vec3 hitPosWorld = rayOrigin + rd * t;
					vec3 alb = terrainAlbedo(hitPosLocal.xz, hitPosLocal.y, triRand * 0.97);
					vec3 nDetail = grassMicroNormal(hitPosLocal.xz, triN);
					if (dot(nDetail, rd) > 0.0) nDetail *= -1.0;
					float sunVis = SunsetSunVisibility(hitPosWorld, nDetail);
					vec3 col = shadeSunset(alb, nDetail, rd, sunVis);
					hitNormal = nDetail;
					hitColor = alb;
					hitEmission = col;
					hitType = LIGHT;
					hitObjectID = float(objectCount);
				}
				objectCount++;
			}
		}
	}

	// Wooden shed-house (box + simple gable roof)
	vec3 houseC = vec3(850.0, 0.0, -4200.0);
	houseC.y = terrainHeight(houseC.xz) + 6.0;

	float wallH = 240.0;
	vec3 houseMin = houseC + vec3(-240.0, 0.0, -200.0);
	vec3 houseMax = houseC + vec3(240.0, wallH, 200.0);

	vec3 boxN;
	d = BoxIntersect(houseMin, houseMax, ro, rd, boxN, isRayExiting);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		vec3 alb = vec3(0.33, 0.23, 0.12);
		float sunVis = SunsetSunVisibility(hitPos, boxN);
		vec3 col = shadeSunset(alb, boxN, rayDirection, sunVis);
		hitNormal = boxN;
		hitColor = alb;
		hitEmission = col;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	// Roof
	float roofH = 170.0;
	vec3 r0 = houseC + vec3(-260.0, wallH, -220.0);
	vec3 r1 = houseC + vec3(260.0, wallH, -220.0);
	vec3 r2 = houseC + vec3(260.0, wallH, 220.0);
	vec3 r3 = houseC + vec3(-260.0, wallH, 220.0);
	vec3 ridge0 = houseC + vec3(0.0, wallH + roofH, -220.0);
	vec3 ridge1 = houseC + vec3(0.0, wallH + roofH, 220.0);

	vec3 roofAlb = vec3(0.18, 0.08, 0.06);
	vec3 triN;

	// left slope
	d = TriangleIntersect(r0, r3, ridge1, ro, rd, triN);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		float sunVis = SunsetSunVisibility(hitPos, triN);
		vec3 col = shadeSunset(roofAlb, triN, rayDirection, sunVis);
		hitNormal = triN;
		hitColor = roofAlb;
		hitEmission = col;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}
	objectCount++;
	d = TriangleIntersect(r0, ridge1, ridge0, ro, rd, triN);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		float sunVis = SunsetSunVisibility(hitPos, triN);
		vec3 col = shadeSunset(roofAlb, triN, rayDirection, sunVis);
		hitNormal = triN;
		hitColor = roofAlb;
		hitEmission = col;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	// right slope
	d = TriangleIntersect(r1, ridge0, ridge1, ro, rd, triN);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		float sunVis = SunsetSunVisibility(hitPos, triN);
		vec3 col = shadeSunset(roofAlb, triN, rayDirection, sunVis);
		hitNormal = triN;
		hitColor = roofAlb;
		hitEmission = col;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}
	objectCount++;
	d = TriangleIntersect(r1, ridge1, r2, ro, rd, triN);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		float sunVis = SunsetSunVisibility(hitPos, triN);
		vec3 col = shadeSunset(roofAlb, triN, rayDirection, sunVis);
		hitNormal = triN;
		hitColor = roofAlb;
		hitEmission = col;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	// gables
	d = TriangleIntersect(r3, r2, ridge1, ro, rd, triN);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		vec3 alb = vec3(0.28, 0.19, 0.10);
		float sunVis = SunsetSunVisibility(hitPos, triN);
		vec3 col = shadeSunset(alb, triN, rayDirection, sunVis);
		hitNormal = triN;
		hitColor = alb;
		hitEmission = col;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}
	objectCount++;
	d = TriangleIntersect(r0, ridge0, r1, ro, rd, triN);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		vec3 alb = vec3(0.28, 0.19, 0.10);
		float sunVis = SunsetSunVisibility(hitPos, triN);
		vec3 col = shadeSunset(alb, triN, rayDirection, sunVis);
		hitNormal = triN;
		hitColor = alb;
		hitEmission = col;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	// Fir trees (trunk + cone foliage)
	vec3 treeCenters[8];
	treeCenters[0] = vec3(-900.0, 0.0, -3800.0);
	treeCenters[1] = vec3(-1400.0, 0.0, -5200.0);
	treeCenters[2] = vec3(-600.0, 0.0, -6200.0);
	treeCenters[3] = vec3(300.0, 0.0, -6800.0);
	treeCenters[4] = vec3(1600.0, 0.0, -5200.0);
	treeCenters[5] = vec3(2100.0, 0.0, -6000.0);
	treeCenters[6] = vec3(2200.0, 0.0, -3600.0);
	treeCenters[7] = vec3(450.0, 0.0, -3100.0);

	for (int i = 0; i < 8; i++)
	{
		vec3 tc = treeCenters[i];
		tc.y = terrainHeight(tc.xz) + 2.0;

		float trunkH = 140.0 + 20.0 * float(i & 1);
		vec3 trunkBase = tc;
		vec3 trunkTop  = tc + vec3(0.0, trunkH, 0.0);

		d = ConeIntersect(trunkBase, 26.0, trunkTop, 18.0, ro, rd, n);
		if (d < t)
		{
			t = d;
			vec3 alb = vec3(0.20, 0.12, 0.06);
			vec3 nn = normalize(n);
			vec3 hitPos = rayOrigin + rayDirection * t;
			float sunVis = SunsetSunVisibility(hitPos, nn);
			vec3 col = shadeSunset(alb, nn, rayDirection, sunVis);
			hitNormal = nn;
			hitColor = alb;
			hitEmission = col;
			hitType = LIGHT;
			hitObjectID = float(objectCount);
		}
		objectCount++;

		vec3 foliageBase = trunkTop + vec3(0.0, -10.0, 0.0);
		vec3 foliageTop  = trunkTop + vec3(0.0, 260.0, 0.0);
		d = ConeIntersect(foliageBase, 120.0, foliageTop, 0.0, ro, rd, n);
		if (d < t)
		{
			t = d;
			vec3 alb = vec3(0.06, 0.18, 0.08);
			vec3 nn = normalize(n);
			vec3 hitPos = rayOrigin + rayDirection * t;
			float sunVis = SunsetSunVisibility(hitPos, nn);
			vec3 col = shadeSunset(alb, nn, rayDirection, sunVis);
			hitNormal = nn;
			hitColor = alb;
			hitEmission = col;
			hitType = LIGHT;
			hitObjectID = float(objectCount);
		}
		objectCount++;
	}

	// very distant low-poly mountain (pyramid)
	vec3 mC = vec3(-6000.0, -900.0, -90000.0);
	float mHalf = 26000.0;
	vec3 mApex = mC + vec3(0.0, 24000.0, 0.0);
	vec3 m0 = mC + vec3(-mHalf, 0.0, -mHalf);
	vec3 m1 = mC + vec3(mHalf, 0.0, -mHalf);
	vec3 m2 = mC + vec3(mHalf, 0.0, mHalf);
	vec3 m3 = mC + vec3(-mHalf, 0.0, mHalf);

	vec3 mountainAlb = vec3(0.22, 0.20, 0.20);
	d = TriangleIntersect(m0, m1, mApex, ro, rd, triN);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		float sunVis = SunsetSunVisibility(hitPos, triN);
		vec3 col = shadeSunset(mountainAlb, triN, rayDirection, sunVis);
		hitNormal = triN;
		hitColor = mountainAlb;
		hitEmission = col;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}
	objectCount++;
	d = TriangleIntersect(m1, m2, mApex, ro, rd, triN);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		float sunVis = SunsetSunVisibility(hitPos, triN);
		vec3 col = shadeSunset(mountainAlb, triN, rayDirection, sunVis);
		hitNormal = triN;
		hitColor = mountainAlb;
		hitEmission = col;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}
	objectCount++;
	d = TriangleIntersect(m2, m3, mApex, ro, rd, triN);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		float sunVis = SunsetSunVisibility(hitPos, triN);
		vec3 col = shadeSunset(mountainAlb, triN, rayDirection, sunVis);
		hitNormal = triN;
		hitColor = mountainAlb;
		hitEmission = col;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}
	objectCount++;
	d = TriangleIntersect(m3, m0, mApex, ro, rd, triN);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		float sunVis = SunsetSunVisibility(hitPos, triN);
		vec3 col = shadeSunset(mountainAlb, triN, rayDirection, sunVis);
		hitNormal = triN;
		hitColor = mountainAlb;
		hitEmission = col;
		hitType = LIGHT;
		hitObjectID = float(objectCount);
	}

	return t;
}

float SceneIntersectGeometry_SunsetLandscape()
//---------------------------------------------------------------------------------------
{
	float t = INFINITY;
	float d;
	int objectCount = 0;
	vec3 n;
	int isRayExiting = FALSE;

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
	objectCount++;

	float zShift = SunsetLandscapeStageShiftZ();
	vec3 roLandscape = rayOrigin - vec3(0.0, 0.0, zShift);
	vec3 rd = rayDirection;

	// Lake
	float waterY = -360.0;
	vec3 lakePos = vec3(0.0, waterY, -7500.0);
	vec3 lakeNormal = vec3(0.0, 1.0, 0.0);
	d = RectangleIntersectTwoSided(lakePos, lakeNormal, 2600.0, 1800.0, roLandscape, rd);
	if (d < t)
	{
		t = d;
		hitNormal = lakeNormal;
		if (dot(hitNormal, rd) > 0.0) hitNormal *= -1.0;
		hitColor = vec3(0.05, 0.18, 0.25);
		hitEmission = vec3(0.0);
		hitType = DIFF;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	// Terrain
	const float xMin = -4200.0;
	const float xMax = 4200.0;
	const float zMin = -1400.0;
	const float zMax = -12000.0;

	float stepX = (xMax - xMin) / float(TERRAIN_NX);
	float stepZ = (zMax - zMin) / float(TERRAIN_NZ);

	for (int iz = 0; iz < TERRAIN_NZ; iz++)
	{
		for (int ix = 0; ix < TERRAIN_NX; ix++)
		{
			float x0 = xMin + stepX * float(ix);
			float x1 = x0 + stepX;
			float z0 = zMin + stepZ * float(iz);
			float z1 = z0 + stepZ;

			vec3 v00 = vec3(x0, terrainHeight(vec2(x0, z0)), z0);
			vec3 v10 = vec3(x1, terrainHeight(vec2(x1, z0)), z0);
			vec3 v01 = vec3(x0, terrainHeight(vec2(x0, z1)), z1);
			vec3 v11 = vec3(x1, terrainHeight(vec2(x1, z1)), z1);

			vec3 triN;
			float triRand = hash12(vec2(float(ix), float(iz)));

			if (((ix + iz) & 1) == 0)
			{
				d = TriangleIntersect(v00, v10, v11, roLandscape, rd, triN);
				if (d < t)
				{
					t = d;
					vec3 hitPosLocal = roLandscape + rd * t;
					vec3 alb = terrainAlbedo(hitPosLocal.xz, hitPosLocal.y, triRand);
					vec3 nDetail = grassMicroNormal(hitPosLocal.xz, triN);
					if (dot(nDetail, rd) > 0.0) nDetail *= -1.0;
					hitNormal = nDetail;
					hitColor = alb;
					hitEmission = vec3(0.0);
					hitType = DIFF;
					hitObjectID = float(objectCount);
				}
				objectCount++;

				d = TriangleIntersect(v00, v11, v01, roLandscape, rd, triN);
				if (d < t)
				{
					t = d;
					vec3 hitPosLocal = roLandscape + rd * t;
					vec3 alb = terrainAlbedo(hitPosLocal.xz, hitPosLocal.y, triRand * 0.97);
					vec3 nDetail = grassMicroNormal(hitPosLocal.xz, triN);
					if (dot(nDetail, rd) > 0.0) nDetail *= -1.0;
					hitNormal = nDetail;
					hitColor = alb;
					hitEmission = vec3(0.0);
					hitType = DIFF;
					hitObjectID = float(objectCount);
				}
				objectCount++;
			}
			else
			{
				d = TriangleIntersect(v00, v10, v01, roLandscape, rd, triN);
				if (d < t)
				{
					t = d;
					vec3 hitPosLocal = roLandscape + rd * t;
					vec3 alb = terrainAlbedo(hitPosLocal.xz, hitPosLocal.y, triRand);
					vec3 nDetail = grassMicroNormal(hitPosLocal.xz, triN);
					if (dot(nDetail, rd) > 0.0) nDetail *= -1.0;
					hitNormal = nDetail;
					hitColor = alb;
					hitEmission = vec3(0.0);
					hitType = DIFF;
					hitObjectID = float(objectCount);
				}
				objectCount++;

				d = TriangleIntersect(v10, v11, v01, roLandscape, rd, triN);
				if (d < t)
				{
					t = d;
					vec3 hitPosLocal = roLandscape + rd * t;
					vec3 alb = terrainAlbedo(hitPosLocal.xz, hitPosLocal.y, triRand * 0.97);
					vec3 nDetail = grassMicroNormal(hitPosLocal.xz, triN);
					if (dot(nDetail, rd) > 0.0) nDetail *= -1.0;
					hitNormal = nDetail;
					hitColor = alb;
					hitEmission = vec3(0.0);
					hitType = DIFF;
					hitObjectID = float(objectCount);
				}
				objectCount++;
			}
		}
	}

	// Shed (same geometry as Sensor scene, unlit colors)
	vec3 houseC = vec3(850.0, 0.0, -4200.0);
	houseC.y = terrainHeight(houseC.xz) + 6.0;
	float wallH = 240.0;
	vec3 houseMin = houseC + vec3(-240.0, 0.0, -200.0);
	vec3 houseMax = houseC + vec3(240.0, wallH, 200.0);

	vec3 boxN;
	d = BoxIntersect(houseMin, houseMax, roLandscape, rd, boxN, isRayExiting);
	if (d < t)
	{
		t = d;
		hitNormal = boxN;
		hitColor = vec3(0.33, 0.23, 0.12);
		hitEmission = vec3(0.0);
		hitType = DIFF;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	float roofH = 170.0;
	vec3 r0 = houseC + vec3(-260.0, wallH, -220.0);
	vec3 r1 = houseC + vec3(260.0, wallH, -220.0);
	vec3 r2 = houseC + vec3(260.0, wallH, 220.0);
	vec3 r3 = houseC + vec3(-260.0, wallH, 220.0);
	vec3 ridge0 = houseC + vec3(0.0, wallH + roofH, -220.0);
	vec3 ridge1 = houseC + vec3(0.0, wallH + roofH, 220.0);

	vec3 roofAlb = vec3(0.18, 0.08, 0.06);
	vec3 triN;

	d = TriangleIntersect(r0, r3, ridge1, roLandscape, rd, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = roofAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(r0, ridge1, ridge0, roLandscape, rd, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = roofAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(r1, ridge0, ridge1, roLandscape, rd, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = roofAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(r1, ridge1, r2, roLandscape, rd, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = roofAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;

	// Trees (cones)
	vec3 treeCenters[8];
	treeCenters[0] = vec3(-900.0, 0.0, -3800.0);
	treeCenters[1] = vec3(-1400.0, 0.0, -5200.0);
	treeCenters[2] = vec3(-600.0, 0.0, -6200.0);
	treeCenters[3] = vec3(300.0, 0.0, -6800.0);
	treeCenters[4] = vec3(1600.0, 0.0, -5200.0);
	treeCenters[5] = vec3(2100.0, 0.0, -6000.0);
	treeCenters[6] = vec3(2200.0, 0.0, -3600.0);
	treeCenters[7] = vec3(450.0, 0.0, -3100.0);

	for (int i = 0; i < 8; i++)
	{
		vec3 tc = treeCenters[i];
		tc.y = terrainHeight(tc.xz) + 2.0;

		float trunkH = 140.0 + 20.0 * float(i & 1);
		vec3 trunkBase = tc;
		vec3 trunkTop  = tc + vec3(0.0, trunkH, 0.0);
		d = ConeIntersect(trunkBase, 26.0, trunkTop, 18.0, roLandscape, rd, n);
		if (d < t) { t = d; hitNormal = normalize(n); hitColor = vec3(0.20, 0.12, 0.06); hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
		objectCount++;

		vec3 foliageBase = trunkTop + vec3(0.0, -10.0, 0.0);
		vec3 foliageTop  = trunkTop + vec3(0.0, 260.0, 0.0);
		d = ConeIntersect(foliageBase, 120.0, foliageTop, 0.0, roLandscape, rd, n);
		if (d < t) { t = d; hitNormal = normalize(n); hitColor = vec3(0.06, 0.18, 0.08); hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
		objectCount++;
	}

	// Distant mountain pyramid
	vec3 mC = vec3(-6000.0, -900.0, -90000.0);
	float mHalf = 26000.0;
	vec3 mApex = mC + vec3(0.0, 24000.0, 0.0);
	vec3 m0 = mC + vec3(-mHalf, 0.0, -mHalf);
	vec3 m1 = mC + vec3(mHalf, 0.0, -mHalf);
	vec3 m2 = mC + vec3(mHalf, 0.0, mHalf);
	vec3 m3 = mC + vec3(-mHalf, 0.0, mHalf);

	vec3 mountainAlb = vec3(0.22, 0.20, 0.20);
	d = TriangleIntersect(m0, m1, mApex, roLandscape, rd, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = mountainAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(m1, m2, mApex, roLandscape, rd, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = mountainAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(m2, m3, mApex, roLandscape, rd, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = mountainAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(m3, m0, mApex, roLandscape, rd, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = mountainAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }

	return t;
}
