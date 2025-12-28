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
