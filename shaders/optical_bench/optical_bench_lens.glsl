bool refractRay(vec3 I, vec3 N, float eta, out vec3 T)
{
	float cosThetaI = clamp(dot(-I, N), -1.0, 1.0);
	float k = 1.0 - eta * eta * (1.0 - cosThetaI * cosThetaI);
	if (k < 0.0)
		return false;
	T = normalize(eta * I + (eta * cosThetaI - sqrt(k)) * N);
	return true;
}

bool traceLens(inout vec3 origin, inout vec3 direction)
{
	float lensRad2 = uLensRadius * uLensRadius;

	float n1 = 1.0;
	for (int i = 0; i < 12; i++)
	{
		if (i >= uLensSurfaceCount)
			break;

		vec4 s = uLensSurfaces[i];
		float R = s.x;
		float zV = s.y;
		float n2 = s.z;

		vec3 c = vec3(0.0, 0.0, zV + R);
		float rAbs = abs(R);

		float t = SphereIntersect(rAbs, c, origin, direction);
		if (t == INFINITY)
			return false;

		vec3 p = origin + direction * t;
		if (dot(p.xy, p.xy) > lensRad2)
			return false;

		vec3 N = normalize(p - c);
		if (dot(N, direction) > 0.0)
			N *= -1.0;

		vec3 T;
		if (!refractRay(direction, N, n1 / max(1.0001, n2), T))
			return false;

		origin = p + T * uEPS_intersect;
		direction = T;
		n1 = n2;
	}

	return true;
}
