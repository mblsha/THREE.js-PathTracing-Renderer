float tentFilter(float x)
{
	return (x < 0.5) ? sqrt(2.0 * x) - 1.0 : 1.0 - sqrt(2.0 - (2.0 * x));
}

float periodicDist(float x, float period)
{
	float halfPeriod = 0.5 * period;
	return abs(mod(x + halfPeriod, period) - halfPeriod);
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
