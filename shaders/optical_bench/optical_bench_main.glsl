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

	if (uSceneID == 1)
	{
		vec3 hitPos = rayOrigin + rayDirection * t;
		float sunVis = SunsetSunVisibility(hitPos, hitNormal);
		return shadeSunset(hitColor, hitNormal, rayDirection, sunVis);
	}

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
	vec3 camRight   = vec3(uCameraMatrix[0][0], uCameraMatrix[0][1], uCameraMatrix[0][2]);
	vec3 camUp      = vec3(uCameraMatrix[1][0], uCameraMatrix[1][1], uCameraMatrix[1][2]);
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
