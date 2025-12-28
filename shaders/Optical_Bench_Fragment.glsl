precision highp float;
precision highp int;
precision highp sampler2D;

uniform int uViewMode;         // 0 = Sensor Image, 1 = Geometry View
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

#include <pathtracing_uniforms_and_defines>

vec3 rayOrigin, rayDirection;
// recorded intersection data:
vec3 hitNormal, hitEmission, hitColor;
float hitObjectID;
int hitType = -100;

#include <pathtracing_random_functions>
#include <pathtracing_disk_intersect>
#include <pathtracing_rectangle_intersect>
#include <pathtracing_sphere_intersect>


float tentFilter(float x)
{
	return (x < 0.5) ? sqrt(2.0 * x) - 1.0 : 1.0 - sqrt(2.0 - (2.0 * x));
}

float periodicDist(float x, float period)
{
	float halfPeriod = 0.5 * period;
	return abs(mod(x + halfPeriod, period) - halfPeriod);
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
float SceneIntersectSensor()
//---------------------------------------------------------------------------------------
{
	float t = INFINITY;
	float d;
	int objectCount = 0;

	hitObjectID = -INFINITY;
	hitType = -100;

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

//---------------------------------------------------------------------------------------
float SceneIntersectGeometry()
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


//-----------------------------------------------------------------------------------------------------------------------------
vec3 CalculateRadiance(out vec3 objectNormal, out vec3 objectColor, out float objectID, out float pixelSharpness)
//-----------------------------------------------------------------------------------------------------------------------------
{
	float t = (uViewMode == 0) ? SceneIntersectSensor() : SceneIntersectGeometry();
	pixelSharpness = 0.0;
	if (t == INFINITY)
	{
		objectNormal = vec3(0.0);
		objectColor = vec3(0.0);
		objectID = 0.0;
		return vec3(0.0);
	}

	objectNormal = hitNormal;
	objectColor = hitColor;
	objectID = hitObjectID;

	if (uViewMode == 0 || hitType == LIGHT)
		return max(hitEmission, vec3(0.0));

	return shadeDebug(hitColor, hitNormal);
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
