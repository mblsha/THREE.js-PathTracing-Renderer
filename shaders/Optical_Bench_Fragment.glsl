precision highp float;
precision highp int;
precision highp sampler2D;

uniform int uViewMode;         // 0 = Sensor Image, 1 = Geometry View
uniform int uSceneID;          // 0 = Test Chart, 1 = Sunset Landscape
uniform float uExposure;       // simple exposure scalar
uniform float uSensorZ;        // sensor plane Z (mm), used for Geometry View overlay

uniform vec2 uSensorSize;      // (width, height) in mm
uniform float uStopOffset;     // stop plane offset from back vertex (mm, toward sensor)
uniform float uStopRadius;     // stop radius in mm

uniform float uLensIor;        // refractive index of glass
uniform float uLensR1;         // front surface radius (signed, mm)
uniform float uLensR2;         // back surface radius (signed, mm)
uniform float uLensThickness;  // center thickness (mm)
uniform float uLensRadius;     // clear aperture radius (mm)

uniform float uChartZ;         // chart plane Z (mm)
uniform vec2 uChartHalfSize;   // chart half-size (mm)
uniform float uChartEmission;  // chart emission intensity

uniform int uFocusGridEnabled;     // 0/1
uniform float uFocusGridDistance;  // distance from sensor plane (mm)
uniform float uFocusGridLines;     // grid density in sensor-NDC space (0.01..2.0)

#include <pathtracing_uniforms_and_defines>

vec3 rayOrigin, rayDirection;
// recorded intersection data:
vec3 hitNormal, hitEmission, hitColor;
float hitObjectID;
int hitType = -100;

#include <pathtracing_random_functions>
#include <pathtracing_disk_intersect>
#include <pathtracing_rectangle_intersect>
#include <pathtracing_box_intersect>
#include <pathtracing_sphere_intersect>
#include <pathtracing_cone_intersect>

#define TERRAIN_NX 6
#define TERRAIN_NZ 10


float tentFilter(float x)
{
	return (x < 0.5) ? sqrt(2.0 * x) - 1.0 : 1.0 - sqrt(2.0 - (2.0 * x));
}

float periodicDist(float x, float period)
{
	float halfPeriod = 0.5 * period;
	return abs(mod(x + halfPeriod, period) - halfPeriod);
}

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

float hash12(vec2 p)
{
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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

vec3 shadeSunset(vec3 albedo, vec3 n, vec3 rd)
{
	vec3 sunDir = normalize(vec3(0.35, 0.06, -1.0));
	vec3 sunCol = vec3(1.0, 0.55, 0.25) * 6.0;

	float ndotl = max(0.0, dot(n, sunDir));
	vec3 hemi = mix(vec3(0.05, 0.06, 0.08), vec3(0.12, 0.18, 0.35), clamp(n.y * 0.5 + 0.5, 0.0, 1.0));

	vec3 col = albedo * (hemi * 2.0 + sunCol * ndotl);

	// warm rim from the horizon
	float rim = pow(clamp(1.0 - max(0.0, dot(n, -rd)), 0.0, 1.0), 2.0);
	col += vec3(0.35, 0.18, 0.08) * rim * 0.2;
	return col;
}

float TriangleIntersect(vec3 v0, vec3 v1, vec3 v2, vec3 ro, vec3 rd, out vec3 n)
{
	vec3 e1 = v1 - v0;
	vec3 e2 = v2 - v0;
	vec3 pvec = cross(rd, e2);
	float det = dot(e1, pvec);
	if (abs(det) < 0.0000001)
		return INFINITY;
	float invDet = 1.0 / det;

	vec3 tvec = ro - v0;
	float u = dot(tvec, pvec) * invDet;
	if (u < 0.0 || u > 1.0)
		return INFINITY;

	vec3 qvec = cross(tvec, e1);
	float v = dot(rd, qvec) * invDet;
	if (v < 0.0 || (u + v) > 1.0)
		return INFINITY;

	float t = dot(e2, qvec) * invDet;
	if (t <= 0.0)
		return INFINITY;

	n = normalize(cross(e1, e2));
	if (dot(n, rd) > 0.0)
		n *= -1.0;

	return t;
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

vec3 terrainAlbedo(float h, float triRand)
{
	vec3 grassA = vec3(0.10, 0.22, 0.10);
	vec3 grassB = vec3(0.16, 0.28, 0.12);
	vec3 dirt   = vec3(0.18, 0.14, 0.09);

	float high = smoothstep(-520.0, -180.0, h);
	vec3 grass = mix(grassA, grassB, triRand);
	return mix(dirt, grass, high);
}


bool refractRay(vec3 I, vec3 N, float eta, out vec3 T)
{
	float cosThetaI = clamp(dot(-I, N), -1.0, 1.0);
	float k = 1.0 - eta * eta * (1.0 - cosThetaI * cosThetaI);
	if (k < 0.0)
		return false;
	T = normalize(eta * I + (eta * cosThetaI - sqrt(k)) * N);
	return true;
}


bool traceSinglet(inout vec3 origin, inout vec3 direction)
{
	// lens is centered on world origin, optical axis is +Z (object side is -Z, sensor side is +Z)
	float zFront = -0.5 * uLensThickness;
	float zBack = 0.5 * uLensThickness;

	vec3 cFront = vec3(0.0, 0.0, zFront + uLensR1);
	vec3 cBack  = vec3(0.0, 0.0, zBack + uLensR2);
	float rFront = abs(uLensR1);
	float rBack  = abs(uLensR2);
	float lensRad2 = uLensRadius * uLensRadius;

	// back surface (air -> glass)
	float tBack = SphereIntersect(rBack, cBack, origin, direction);
	if (tBack == INFINITY)
		return false;
	vec3 pBack = origin + direction * tBack;
	if (dot(pBack.xy, pBack.xy) > lensRad2)
		return false;

	vec3 nBack = normalize(pBack - cBack);
	if (dot(nBack, direction) > 0.0)
		nBack *= -1.0;

	vec3 dirGlass;
	if (!refractRay(direction, nBack, 1.0 / max(1.0001, uLensIor), dirGlass))
		return false;

	origin = pBack + dirGlass * uEPS_intersect;
	direction = dirGlass;

	// front surface (glass -> air)
	float tFront = SphereIntersect(rFront, cFront, origin, direction);
	if (tFront == INFINITY)
		return false;
	vec3 pFront = origin + direction * tFront;
	if (dot(pFront.xy, pFront.xy) > lensRad2)
		return false;

	vec3 nFront = normalize(pFront - cFront);
	if (dot(nFront, direction) > 0.0)
		nFront *= -1.0;

	vec3 dirAir;
	if (!refractRay(direction, nFront, max(1.0001, uLensIor), dirAir))
		return false;

	origin = pFront + dirAir * uEPS_intersect;
	direction = dirAir;
	return true;
}


//---------------------------------------------------------------------------------------
float RectangleIntersectTwoSided(vec3 pos, vec3 normal, float radiusU, float radiusV, vec3 ro, vec3 rd)
//---------------------------------------------------------------------------------------
{
	float dt = dot(normal, rd);
	if (abs(dt) < 0.0000001)
		return INFINITY;

	float t = dot(normal, pos - ro) / dt;
	if (t < 0.0)
		return INFINITY;

	vec3 hit = ro + (rd * t);
	vec3 vi = hit - pos;
	vec3 U = normalize(cross(abs(normal.y) < 0.9 ? vec3(0, 1, 0) : vec3(0, 0, 1), normal));
	vec3 V = cross(normal, U);
	return (abs(dot(U, vi)) > radiusU || abs(dot(V, vi)) > radiusV) ? INFINITY : t;
}

//---------------------------------------------------------------------------------------
float CylinderIntersect(float radius, float zMin, float zMax, vec3 ro, vec3 rd, out vec3 n)
//---------------------------------------------------------------------------------------
{
	float a = rd.x * rd.x + rd.y * rd.y;
	if (a < 0.0000001)
		return INFINITY;

	float b = 2.0 * (ro.x * rd.x + ro.y * rd.y);
	float c = ro.x * ro.x + ro.y * ro.y - (radius * radius);
	float t0, t1;
	solveQuadratic(a, b, c, t0, t1);

	float t = INFINITY;
	if (t0 > 0.0)
	{
		float z = ro.z + (t0 * rd.z);
		if (z > zMin && z < zMax)
			t = t0;
	}
	if (t == INFINITY && t1 > 0.0)
	{
		float z = ro.z + (t1 * rd.z);
		if (z > zMin && z < zMax)
			t = t1;
	}
	if (t == INFINITY)
		return INFINITY;

	vec3 hp = ro + (rd * t);
	n = normalize(vec3(hp.x, hp.y, 0.0));
	if (dot(n, rd) > 0.0)
		n *= -1.0;
	return t;
}

//---------------------------------------------------------------------------------------
float DiskCapIntersect(float radius, vec3 pos, vec3 normal, vec3 ro, vec3 rd, out vec3 n)
//---------------------------------------------------------------------------------------
{
	float t = DiskIntersect(radius, pos, normal, ro, rd);
	if (t == INFINITY)
		return INFINITY;
	n = dot(normal, rd) < 0.0 ? normal : -normal;
	return t;
}

//---------------------------------------------------------------------------------------
float AnnulusDiskIntersect(float outerRadius, float innerRadius, vec3 pos, vec3 normal, vec3 ro, vec3 rd, out vec3 n)
//---------------------------------------------------------------------------------------
{
	float t = DiskIntersect(outerRadius, pos, normal, ro, rd);
	if (t == INFINITY)
		return INFINITY;

	vec3 hp = ro + (rd * t);
	vec2 d = hp.xy - pos.xy;
	if (dot(d, d) < innerRadius * innerRadius)
		return INFINITY;

	n = dot(normal, rd) < 0.0 ? normal : -normal;
	return t;
}

vec3 shadeDebug(vec3 baseColor, vec3 n)
{
	vec3 lightDir = normalize(vec3(-0.3, 0.85, 0.35));
	float ndotl = max(0.0, dot(n, lightDir));
	float ambient = 0.2;
	return baseColor * (ambient + (0.8 * ndotl));
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

	vec3 p0 = vec3( c.x,  c.y, uChartZ + 1.0);
	vec3 p1 = vec3(-c.x,  c.y, uChartZ + 1.0);
	vec3 p2 = vec3( c.x, -c.y, uChartZ + 1.0);
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
	vec3 pFar  = vec3(0.0, 0.0, -2000.0);

	d = SphereIntersect(probeR, pNear, rayOrigin, rayDirection);
	if (d < t) { t = d; vec3 hp = rayOrigin + rayDirection * t; hitNormal = normalize(hp - pNear); hitColor = probeCol; hitEmission = probeCol * probeE; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;

	d = SphereIntersect(probeR, pFar, rayOrigin, rayDirection);
	if (d < t) { t = d; vec3 hp = rayOrigin + rayDirection * t; hitNormal = normalize(hp - pFar); hitColor = probeCol * 0.8; hitEmission = hitColor * (probeE * 0.7); hitType = LIGHT; hitObjectID = float(objectCount); }

	return t;
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

	// Lake (flat water rectangle)
	float waterY = -360.0;
	vec3 lakePos = vec3(0.0, waterY, -7500.0);
	vec3 lakeNormal = vec3(0.0, 1.0, 0.0);
	d = RectangleIntersectTwoSided(lakePos, lakeNormal, 2600.0, 1800.0, rayOrigin, rayDirection);
	if (d < t)
	{
		t = d;
		vec3 hitPos = rayOrigin + rayDirection * t;
		vec3 nn = lakeNormal;
		if (dot(nn, rayDirection) > 0.0) nn *= -1.0;

		vec3 V = normalize(-rayDirection);
		float cosTheta = clamp(dot(V, nn), 0.0, 1.0);
		float F0 = 0.02;
		float fres = F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
		vec3 refl = sunsetSky(reflect(rayDirection, nn));
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
	const float xMax =  4200.0;
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
				d = TriangleIntersect(v00, v10, v11, rayOrigin, rayDirection, triN);
				if (d < t)
				{
					t = d;
					vec3 hitPos = rayOrigin + rayDirection * t;
					vec3 alb = terrainAlbedo(hitPos.y, triRand);
					vec3 col = shadeSunset(alb, triN, rayDirection);
					hitNormal = triN;
					hitColor = alb;
					hitEmission = col;
					hitType = LIGHT;
					hitObjectID = float(objectCount);
				}
				objectCount++;

				d = TriangleIntersect(v00, v11, v01, rayOrigin, rayDirection, triN);
				if (d < t)
				{
					t = d;
					vec3 hitPos = rayOrigin + rayDirection * t;
					vec3 alb = terrainAlbedo(hitPos.y, triRand * 0.97);
					vec3 col = shadeSunset(alb, triN, rayDirection);
					hitNormal = triN;
					hitColor = alb;
					hitEmission = col;
					hitType = LIGHT;
					hitObjectID = float(objectCount);
				}
				objectCount++;
			}
			else
			{
				d = TriangleIntersect(v00, v10, v01, rayOrigin, rayDirection, triN);
				if (d < t)
				{
					t = d;
					vec3 hitPos = rayOrigin + rayDirection * t;
					vec3 alb = terrainAlbedo(hitPos.y, triRand);
					vec3 col = shadeSunset(alb, triN, rayDirection);
					hitNormal = triN;
					hitColor = alb;
					hitEmission = col;
					hitType = LIGHT;
					hitObjectID = float(objectCount);
				}
				objectCount++;

				d = TriangleIntersect(v10, v11, v01, rayOrigin, rayDirection, triN);
				if (d < t)
				{
					t = d;
					vec3 hitPos = rayOrigin + rayDirection * t;
					vec3 alb = terrainAlbedo(hitPos.y, triRand * 0.97);
					vec3 col = shadeSunset(alb, triN, rayDirection);
					hitNormal = triN;
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
	vec3 houseMax = houseC + vec3( 240.0, wallH,  200.0);

	vec3 boxN;
	d = BoxIntersect(houseMin, houseMax, rayOrigin, rayDirection, boxN, isRayExiting);
	if (d < t)
	{
		t = d;
		vec3 alb = vec3(0.33, 0.23, 0.12);
		vec3 col = shadeSunset(alb, boxN, rayDirection);
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
	vec3 r1 = houseC + vec3( 260.0, wallH, -220.0);
	vec3 r2 = houseC + vec3( 260.0, wallH,  220.0);
	vec3 r3 = houseC + vec3(-260.0, wallH,  220.0);
	vec3 ridge0 = houseC + vec3(0.0, wallH + roofH, -220.0);
	vec3 ridge1 = houseC + vec3(0.0, wallH + roofH,  220.0);

	vec3 roofAlb = vec3(0.18, 0.08, 0.06);
	vec3 triN;

	// left slope
	d = TriangleIntersect(r0, r3, ridge1, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; vec3 col = shadeSunset(roofAlb, triN, rayDirection); hitNormal = triN; hitColor = roofAlb; hitEmission = col; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(r0, ridge1, ridge0, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; vec3 col = shadeSunset(roofAlb, triN, rayDirection); hitNormal = triN; hitColor = roofAlb; hitEmission = col; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;

	// right slope
	d = TriangleIntersect(r1, ridge0, ridge1, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; vec3 col = shadeSunset(roofAlb, triN, rayDirection); hitNormal = triN; hitColor = roofAlb; hitEmission = col; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(r1, ridge1, r2, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; vec3 col = shadeSunset(roofAlb, triN, rayDirection); hitNormal = triN; hitColor = roofAlb; hitEmission = col; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;

	// gables
	d = TriangleIntersect(r3, r2, ridge1, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; vec3 alb = vec3(0.28, 0.19, 0.10); vec3 col = shadeSunset(alb, triN, rayDirection); hitNormal = triN; hitColor = alb; hitEmission = col; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(r0, ridge0, r1, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; vec3 alb = vec3(0.28, 0.19, 0.10); vec3 col = shadeSunset(alb, triN, rayDirection); hitNormal = triN; hitColor = alb; hitEmission = col; hitType = LIGHT; hitObjectID = float(objectCount); }
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

		d = ConeIntersect(trunkBase, 26.0, trunkTop, 18.0, rayOrigin, rayDirection, n);
		if (d < t)
		{
			t = d;
			vec3 alb = vec3(0.20, 0.12, 0.06);
			vec3 col = shadeSunset(alb, normalize(n), rayDirection);
			hitNormal = normalize(n);
			hitColor = alb;
			hitEmission = col;
			hitType = LIGHT;
			hitObjectID = float(objectCount);
		}
		objectCount++;

		vec3 foliageBase = trunkTop + vec3(0.0, -10.0, 0.0);
		vec3 foliageTop  = trunkTop + vec3(0.0, 260.0, 0.0);
		d = ConeIntersect(foliageBase, 120.0, foliageTop, 0.0, rayOrigin, rayDirection, n);
		if (d < t)
		{
			t = d;
			vec3 alb = vec3(0.06, 0.18, 0.08);
			vec3 col = shadeSunset(alb, normalize(n), rayDirection);
			hitNormal = normalize(n);
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
	vec3 m1 = mC + vec3( mHalf, 0.0, -mHalf);
	vec3 m2 = mC + vec3( mHalf, 0.0,  mHalf);
	vec3 m3 = mC + vec3(-mHalf, 0.0,  mHalf);

	vec3 mountainAlb = vec3(0.22, 0.20, 0.20);
	d = TriangleIntersect(m0, m1, mApex, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; vec3 col = shadeSunset(mountainAlb, triN, rayDirection); hitNormal = triN; hitColor = mountainAlb; hitEmission = col; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(m1, m2, mApex, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; vec3 col = shadeSunset(mountainAlb, triN, rayDirection); hitNormal = triN; hitColor = mountainAlb; hitEmission = col; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(m2, m3, mApex, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; vec3 col = shadeSunset(mountainAlb, triN, rayDirection); hitNormal = triN; hitColor = mountainAlb; hitEmission = col; hitType = LIGHT; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(m3, m0, mApex, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; vec3 col = shadeSunset(mountainAlb, triN, rayDirection); hitNormal = triN; hitColor = mountainAlb; hitEmission = col; hitType = LIGHT; hitObjectID = float(objectCount); }

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

	// Lake
	float waterY = -360.0;
	vec3 lakePos = vec3(0.0, waterY, -7500.0);
	vec3 lakeNormal = vec3(0.0, 1.0, 0.0);
	d = RectangleIntersectTwoSided(lakePos, lakeNormal, 2600.0, 1800.0, rayOrigin, rayDirection);
	if (d < t)
	{
		t = d;
		hitNormal = lakeNormal;
		if (dot(hitNormal, rayDirection) > 0.0) hitNormal *= -1.0;
		hitColor = vec3(0.05, 0.18, 0.25);
		hitEmission = vec3(0.0);
		hitType = DIFF;
		hitObjectID = float(objectCount);
	}
	objectCount++;

	// Terrain
	const float xMin = -4200.0;
	const float xMax =  4200.0;
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
				d = TriangleIntersect(v00, v10, v11, rayOrigin, rayDirection, triN);
				if (d < t) { t = d; vec3 hitPos = rayOrigin + rayDirection * t; vec3 alb = terrainAlbedo(hitPos.y, triRand); hitNormal = triN; hitColor = alb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
				objectCount++;

				d = TriangleIntersect(v00, v11, v01, rayOrigin, rayDirection, triN);
				if (d < t) { t = d; vec3 hitPos = rayOrigin + rayDirection * t; vec3 alb = terrainAlbedo(hitPos.y, triRand * 0.97); hitNormal = triN; hitColor = alb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
				objectCount++;
			}
			else
			{
				d = TriangleIntersect(v00, v10, v01, rayOrigin, rayDirection, triN);
				if (d < t) { t = d; vec3 hitPos = rayOrigin + rayDirection * t; vec3 alb = terrainAlbedo(hitPos.y, triRand); hitNormal = triN; hitColor = alb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
				objectCount++;

				d = TriangleIntersect(v10, v11, v01, rayOrigin, rayDirection, triN);
				if (d < t) { t = d; vec3 hitPos = rayOrigin + rayDirection * t; vec3 alb = terrainAlbedo(hitPos.y, triRand * 0.97); hitNormal = triN; hitColor = alb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
				objectCount++;
			}
		}
	}

	// Shed (same geometry as Sensor scene, unlit colors)
	vec3 houseC = vec3(850.0, 0.0, -4200.0);
	houseC.y = terrainHeight(houseC.xz) + 6.0;
	float wallH = 240.0;
	vec3 houseMin = houseC + vec3(-240.0, 0.0, -200.0);
	vec3 houseMax = houseC + vec3( 240.0, wallH,  200.0);

	vec3 boxN;
	d = BoxIntersect(houseMin, houseMax, rayOrigin, rayDirection, boxN, isRayExiting);
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
	vec3 r1 = houseC + vec3( 260.0, wallH, -220.0);
	vec3 r2 = houseC + vec3( 260.0, wallH,  220.0);
	vec3 r3 = houseC + vec3(-260.0, wallH,  220.0);
	vec3 ridge0 = houseC + vec3(0.0, wallH + roofH, -220.0);
	vec3 ridge1 = houseC + vec3(0.0, wallH + roofH,  220.0);

	vec3 roofAlb = vec3(0.18, 0.08, 0.06);
	vec3 triN;

	d = TriangleIntersect(r0, r3, ridge1, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = roofAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(r0, ridge1, ridge0, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = roofAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(r1, ridge0, ridge1, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = roofAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(r1, ridge1, r2, rayOrigin, rayDirection, triN);
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
		d = ConeIntersect(trunkBase, 26.0, trunkTop, 18.0, rayOrigin, rayDirection, n);
		if (d < t) { t = d; hitNormal = normalize(n); hitColor = vec3(0.20, 0.12, 0.06); hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
		objectCount++;

		vec3 foliageBase = trunkTop + vec3(0.0, -10.0, 0.0);
		vec3 foliageTop  = trunkTop + vec3(0.0, 260.0, 0.0);
		d = ConeIntersect(foliageBase, 120.0, foliageTop, 0.0, rayOrigin, rayDirection, n);
		if (d < t) { t = d; hitNormal = normalize(n); hitColor = vec3(0.06, 0.18, 0.08); hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
		objectCount++;
	}

	// Distant mountain pyramid
	vec3 mC = vec3(-6000.0, -900.0, -90000.0);
	float mHalf = 26000.0;
	vec3 mApex = mC + vec3(0.0, 24000.0, 0.0);
	vec3 m0 = mC + vec3(-mHalf, 0.0, -mHalf);
	vec3 m1 = mC + vec3( mHalf, 0.0, -mHalf);
	vec3 m2 = mC + vec3( mHalf, 0.0,  mHalf);
	vec3 m3 = mC + vec3(-mHalf, 0.0,  mHalf);

	vec3 mountainAlb = vec3(0.22, 0.20, 0.20);
	d = TriangleIntersect(m0, m1, mApex, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = mountainAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(m1, m2, mApex, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = mountainAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(m2, m3, mApex, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = mountainAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }
	objectCount++;
	d = TriangleIntersect(m3, m0, mApex, rayOrigin, rayDirection, triN);
	if (d < t) { t = d; hitNormal = triN; hitColor = mountainAlb; hitEmission = vec3(0.0); hitType = DIFF; hitObjectID = float(objectCount); }

	return t;
}


//-----------------------------------------------------------------------------------------------------------------------------
vec3 CalculateRadiance(out vec3 objectNormal, out vec3 objectColor, out float objectID, out float pixelSharpness)
//-----------------------------------------------------------------------------------------------------------------------------
{
	float t;
	if (uViewMode == 0)
		t = (uSceneID == 1) ? SceneIntersectSensor_SunsetLandscape() : SceneIntersectSensor_TestChart();
	else
		t = (uSceneID == 1) ? SceneIntersectGeometry_SunsetLandscape() : SceneIntersectGeometry_TestChart();

	pixelSharpness = 0.0;
	if (t == INFINITY)
	{
		objectNormal = vec3(0.0);
		objectColor = vec3(0.0);
		objectID = 0.0;
		return (uSceneID == 1) ? sunsetSky(rayDirection) : vec3(0.0);
	}

	objectNormal = hitNormal;
	objectColor = hitColor;
	objectID = hitObjectID;

	if (uViewMode == 0 || hitType == LIGHT)
		return max(hitEmission, vec3(0.0));

	return (uSceneID == 1) ? shadeSunset(hitColor, hitNormal, rayDirection) : shadeDebug(hitColor, hitNormal);
}


//-----------------------------------------------------------------------
void SetupScene(void)
//-----------------------------------------------------------------------
{
	// no-op (all scene geometry is analytic in SceneIntersect)
}


bool mapScreenToSensorNDC(vec2 pixelPos, out vec2 sensorNDC)
{
	float screenAspect = uResolution.x / uResolution.y;
	float sensorAspect = uSensorSize.x / uSensorSize.y;

	sensorNDC = pixelPos;

	if (screenAspect > sensorAspect)
	{
		float halfWidthNDC = sensorAspect / screenAspect;
		if (abs(pixelPos.x) > halfWidthNDC)
			return false;
		sensorNDC.x = pixelPos.x / halfWidthNDC;
	}
	else if (screenAspect < sensorAspect)
	{
		float halfHeightNDC = screenAspect / sensorAspect;
		if (abs(pixelPos.y) > halfHeightNDC)
			return false;
		sensorNDC.y = pixelPos.y / halfHeightNDC;
	}

	return true;
}


void main(void)
{
	vec3 camRight   = vec3( uCameraMatrix[0][0],  uCameraMatrix[0][1],  uCameraMatrix[0][2]);
	vec3 camUp      = vec3( uCameraMatrix[1][0],  uCameraMatrix[1][1],  uCameraMatrix[1][2]);
	vec3 camForward = vec3(-uCameraMatrix[2][0], -uCameraMatrix[2][1], -uCameraMatrix[2][2]);

	// calculate unique seed for rng() function
	seed = uvec2(uFrameCounter, uFrameCounter + 1.0) * uvec2(gl_FragCoord);
	// initialize rand() variables
	randNumber = 0.0;
	blueNoise = texelFetch(tBlueNoiseTexture, ivec2(mod(floor(gl_FragCoord.xy), 128.0)), 0).r;

	vec2 pixelOffset;
	if (uSampleCounter < 50.0)
	{
		pixelOffset = vec2(tentFilter(rand()), tentFilter(rand()));
		pixelOffset *= uCameraIsMoving ? 0.5 : 1.0;
	}
	else
	{
		pixelOffset = vec2(tentFilter(uRandomVec2.x), tentFilter(uRandomVec2.y));
	}

	vec2 pixelPos = ((gl_FragCoord.xy + vec2(0.5) + pixelOffset) / uResolution) * 2.0 - 1.0;

	vec3 origin = vec3(0.0);
	vec3 direction = vec3(0.0);

	// Camera model selection:
	// - Sensor Image: sample sensor plane -> stop -> thick singlet, then trace into the scene
	// - Geometry View: normal perspective camera rays (no lens), render bench geometry
	if (uViewMode == 0)
	{
		vec2 sensorNDC;
		if (!mapScreenToSensorNDC(pixelPos, sensorNDC))
		{
			pc_fragColor = vec4(0.0, 0.0, 0.0, 1.0);
			return;
		}
		// flip sensor vertical axis so the displayed sensor image is upright
		sensorNDC.y *= -1.0;

		vec2 sensorHalf = 0.5 * uSensorSize;
		vec3 sensorPoint = cameraPosition + camRight * (sensorNDC.x * sensorHalf.x) + camUp * (sensorNDC.y * sensorHalf.y);

		// sample a circular aperture stop in a plane just behind the lens (sensor side)
		float stopPlaneZ = (0.5 * uLensThickness) + max(0.0, uStopOffset);
		float angle = rng() * TWO_PI;
		float r = sqrt(rng()) * max(0.0, uStopRadius);
		vec3 stopPoint = vec3(r * cos(angle), r * sin(angle), stopPlaneZ);

		origin = sensorPoint;
		direction = normalize(stopPoint - sensorPoint);
	}
	else
	{
		vec3 rayDir = normalize((camRight * pixelPos.x * uULen) + (camUp * pixelPos.y * uVLen) + camForward);

		// optional depth of field (controlled by built-in uApertureSize / uFocusDistance)
		vec3 focalPoint = uFocusDistance * rayDir;
		float randomAngle = rng() * TWO_PI;
		float randomRadius = rng() * uApertureSize;
		vec3 randomAperturePos = ((camRight * cos(randomAngle)) + (camUp * sin(randomAngle))) * sqrt(randomRadius);
		vec3 finalRayDir = normalize(focalPoint - randomAperturePos);

		origin = cameraPosition + randomAperturePos;
		direction = finalRayDir;
	}

	SetupScene();

	vec3 objectNormal = vec3(0);
	vec3 objectColor = vec3(0);
	float objectID = 0.0;
	float pixelSharpness = 0.0;
	
	vec4 currentPixel = vec4(0.0);

	if (uViewMode == 0)
	{
		// trace through lens (camera model). If it fails (vignetting / TIR), this sample contributes 0.
		if (traceSinglet(origin, direction))
		{
			rayOrigin = origin;
			rayDirection = direction;
			currentPixel = vec4(uExposure * CalculateRadiance(objectNormal, objectColor, objectID, pixelSharpness), 0.0);
		}
	}
	else
	{
		rayOrigin = origin;
		rayDirection = direction;
		currentPixel = vec4(uExposure * CalculateRadiance(objectNormal, objectColor, objectID, pixelSharpness), 0.0);
	}

	float edge0 = 0.2;
	float edge1 = 0.6;
	float difference_Nx = fwidth(objectNormal.x);
	float difference_Ny = fwidth(objectNormal.y);
	float difference_Nz = fwidth(objectNormal.z);
	float normalDifference = smoothstep(edge0, edge1, difference_Nx) + smoothstep(edge0, edge1, difference_Ny) + smoothstep(edge0, edge1, difference_Nz);

	float objectDifference = min(fwidth(objectID), 1.0);
	float colorDifference = (fwidth(objectColor.r) + fwidth(objectColor.g) + fwidth(objectColor.b)) > 0.0 ? 1.0 : 0.0;

	vec4 previousPixel = texelFetch(tPreviousTexture, ivec2(gl_FragCoord.xy), 0);

	if (uFrameCounter == 1.0)
	{
		previousPixel.rgb *= (1.0 / uPreviousSampleCount) * 0.5;
		previousPixel.a = 0.0;
		currentPixel.rgb *= 0.5;
	}
	else if (uCameraIsMoving)
	{
		previousPixel.rgb *= 0.5;
		previousPixel.a = 0.0;
		currentPixel.rgb *= 0.5;
	}

	if (colorDifference > 0.0 || normalDifference >= 0.9 || objectDifference >= 1.0)
		pixelSharpness = 1.0;

	currentPixel.a = pixelSharpness;
	if (previousPixel.a == 1.0)
		currentPixel.a = 1.0;

	pc_fragColor = vec4(previousPixel.rgb + currentPixel.rgb, currentPixel.a);
}
