// scene/demo-specific variables go here
let opticalBenchFolder, lensFolder, sensorFolder, chartFolder, viewFolder, sceneFolder, focusAidFolder;
let viewModeController, exposureController;
let sceneController;
let objectDistanceController, imageDistanceController, apertureDiameterController;
let stopZController;
let lensIORController, lensR1Controller, lensR2Controller, lensThicknessController, lensClearApertureController;
let sensorWidthController, sensorHeightController;
let chartEmissionController;
let focusGridEnabledController, focusGridDistanceController, focusGridLinesController, focusAlgorithmController;

let paramsObject;
let needsUpdate = false;

let _focusMarkerCSSInstalled = false;


function _installFocusMarkerCSS()
{
	if (_focusMarkerCSSInstalled)
		return;

	const style = document.createElement('style');
	style.setAttribute('data-optical-bench-focus-markers', 'true');
	style.textContent = `
.lil-gui .controller.number .slider { position: relative; }
.lil-gui .controller.number .slider .focus-marker {
	position: absolute;
	top: 2px;
	bottom: 2px;
	width: 2px;
	left: 0;
	transform: translateX(-50%);
	background: rgba(140, 255, 255, 0.95);
	box-shadow: 0 0 0 1px rgba(0,0,0,0.45);
	pointer-events: none;
	opacity: 0;
}
.lil-gui .controller.number .slider .focus-marker.visible { opacity: 1; }
.lil-gui .controller.number .slider .focus-marker.tinted { background: rgba(255, 150, 60, 0.95); }
`;
	document.head.appendChild(style);
	_focusMarkerCSSInstalled = true;
}


function _clamp(x, a, b)
{
	return Math.max(a, Math.min(b, x));
}


function _isFiniteNumber(x)
{
	return typeof x === 'number' && Number.isFinite(x);
}


function _lensmakerEFL(n, r1, r2, t)
{
	const nMinus1 = n - 1.0;
	const denom = nMinus1 * ((1.0 / r1) - (1.0 / r2) + (nMinus1 * t) / (n * r1 * r2));
	if (!_isFiniteNumber(denom) || Math.abs(denom) < 1e-9)
		return Infinity;
	return 1.0 / denom;
}


function _mul2x2(m2, m1)
{
	return {
		A: m2.A * m1.A + m2.B * m1.C,
		B: m2.A * m1.B + m2.B * m1.D,
		C: m2.C * m1.A + m2.D * m1.C,
		D: m2.C * m1.B + m2.D * m1.D
	};
}


function _translate2x2(d)
{
	return { A: 1.0, B: d, C: 0.0, D: 1.0 };
}


function _refractSurface2x2(n1, n2, r)
{
	return { A: 1.0, B: 0.0, C: (n1 - n2) / (r * n2), D: n1 / n2 };
}


function _paraxialImagingResidual_B(D, v, n, r1, r2, t)
{
	const u = D - v;
	const L1 = u - 0.5 * t;
	const L2 = v - 0.5 * t;
	if (!_isFiniteNumber(L1) || !_isFiniteNumber(L2))
		return NaN;

	const S1 = _refractSurface2x2(1.0, n, r1);
	const Tg = _translate2x2(t);
	const S2 = _refractSurface2x2(n, 1.0, r2);
	const M = _mul2x2(S2, _mul2x2(Tg, S1));
	const Mtot = _mul2x2(_translate2x2(L2), _mul2x2(M, _translate2x2(L1)));
	return Mtot.B;
}


function _solveRootInRange(fn, min, max, preferX)
{
	const N = 24;
	const samples = [];
	let bestX = null;
	let bestAbs = Infinity;

	for (let i = 0; i <= N; i++)
	{
		const x = min + (max - min) * (i / N);
		const y = fn(x);
		if (!_isFiniteNumber(y))
			continue;
		samples.push({ x, y });
		const ay = Math.abs(y);
		if (ay < bestAbs)
		{
			bestAbs = ay;
			bestX = x;
		}
	}

	if (samples.length < 2)
		return null;

	const intervals = [];
	for (let i = 1; i < samples.length; i++)
	{
		const a = samples[i - 1];
		const b = samples[i];
		if (a.y === 0.0)
			intervals.push({ lo: a.x, hi: a.x });
		else if (a.y * b.y < 0.0)
			intervals.push({ lo: a.x, hi: b.x });
	}

	if (intervals.length === 0)
	{
		if (!_isFiniteNumber(bestX))
			return null;
		return { x: bestX, tinted: true };
	}

	let chosen = intervals[0];
	for (const iv of intervals)
	{
		if (preferX >= iv.lo && preferX <= iv.hi)
		{
			chosen = iv;
			break;
		}
	}

	// If nothing contained preferX, choose the closest interval.
	if (!(preferX >= chosen.lo && preferX <= chosen.hi))
	{
		let best = Infinity;
		for (const iv of intervals)
		{
			const mid = 0.5 * (iv.lo + iv.hi);
			const d = Math.abs(mid - preferX);
			if (d < best)
			{
				best = d;
				chosen = iv;
			}
		}
	}

	let lo = chosen.lo;
	let hi = chosen.hi;
	let yLo = fn(lo);
	let yHi = fn(hi);

	if (!_isFiniteNumber(yLo) || !_isFiniteNumber(yHi))
		return { x: _clamp(bestX ?? preferX, min, max), tinted: true };

	if (lo === hi)
		return { x: lo, tinted: false };

	for (let iter = 0; iter < 32; iter++)
	{
		const mid = 0.5 * (lo + hi);
		const yMid = fn(mid);
		if (!_isFiniteNumber(yMid))
			break;

		if (Math.abs(yMid) < 1e-6)
			return { x: mid, tinted: false };

		if (yLo * yMid <= 0.0)
		{
			hi = mid;
			yHi = yMid;
		}
		else
		{
			lo = mid;
			yLo = yMid;
		}
	}

	return { x: 0.5 * (lo + hi), tinted: false };
}


function _computeFocusTargetForProperty(property, trialValue)
{
	const D = paramsObject.Focus_Grid_Distance_mm;
	if (!_isFiniteNumber(D) || D <= 0.0)
		return null;

	const v0 = paramsObject.Image_Distance_mm;
	const n0 = paramsObject.Lens_IOR;
	const r10 = paramsObject.Lens_R1_mm;
	const r20 = paramsObject.Lens_R2_mm;
	const t0 = paramsObject.Lens_Thickness_mm;

	const stopOffset = paramsObject.Stop_Offset_mm;
	const stopRadius = paramsObject.Aperture_Diameter_mm * 0.5;
	const lensRadius = paramsObject.Lens_ClearAperture_mm * 0.5;

	const algorithm = paramsObject.Focus_Algorithm;

	const residual = (x) =>
	{
		let v = v0;
		let n = n0;
		let r1 = r10;
		let r2 = r20;
		let t = t0;

		if (property === 'Image_Distance_mm') v = x;
		else if (property === 'Lens_IOR') n = x;
		else if (property === 'Lens_R1_mm') r1 = x;
		else if (property === 'Lens_R2_mm') r2 = x;
		else if (property === 'Lens_Thickness_mm') t = x;

		if (algorithm === 'Paraxial (ABCD)')
		{
			return _paraxialImagingResidual_B(D, v, n, r1, r2, t);
		}

		if (algorithm === 'Ray (Snell)')
		{
			const stopPlaneZ = 0.5 * t + Math.max(0.0, stopOffset);
			const rSample = Math.min(Math.max(0.0, stopRadius), Math.max(0.0, lensRadius)) * 0.7;
			if (rSample <= 0.0001)
				return NaN;

			const sensorZ = v;
			const gridZ = sensorZ - D;
			const ray = _traceRayThroughSingletFromSensor(sensorZ, stopPlaneZ, rSample, n, r1, r2, t, lensRadius);
			if (!ray)
				return NaN;

			const dt = ray.dir.z;
			if (Math.abs(dt) < 1e-9)
				return NaN;
			const tt = (gridZ - ray.origin.z) / dt;
			if (tt <= 0.0)
				return NaN;
			const xHit = ray.origin.x + ray.dir.x * tt;
			return xHit;
		}

		// default: Lensmaker (EFL)
		const f = _lensmakerEFL(n, r1, r2, t);
		if (!_isFiniteNumber(f) || f === 0.0)
			return NaN;
		const requiredPower = (1.0 / v) + (1.0 / (D - v));
		return (1.0 / f) - requiredPower;
	};
	return residual;
}


function _traceRayThroughSingletFromSensor(sensorZ, stopPlaneZ, stopX, lensIor, lensR1, lensR2, lensThickness, lensRadius)
{
	const eps = 0.01;

	const ro = { x: 0.0, y: 0.0, z: sensorZ };
	let rd = (function () {
		const dx = stopX - ro.x;
		const dy = 0.0 - ro.y;
		const dz = stopPlaneZ - ro.z;
		const invLen = 1.0 / Math.sqrt(dx * dx + dy * dy + dz * dz);
		return { x: dx * invLen, y: dy * invLen, z: dz * invLen };
	})();

	const zFront = -0.5 * lensThickness;
	const zBack = 0.5 * lensThickness;
	const cFront = { x: 0.0, y: 0.0, z: zFront + lensR1 };
	const cBack = { x: 0.0, y: 0.0, z: zBack + lensR2 };
	const rFront = Math.abs(lensR1);
	const rBack = Math.abs(lensR2);

	const lensRad2 = lensRadius * lensRadius;

	function dot(a, b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
	function norm(a) { return Math.sqrt(dot(a, a)); }
	function sub(a, b) { return { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z }; }
	function add(a, b) { return { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z }; }
	function mul(a, s) { return { x: a.x * s, y: a.y * s, z: a.z * s }; }
	function normalize(a) { const inv = 1.0 / norm(a); return mul(a, inv); }

	function sphereIntersect(radius, center, origin, direction)
	{
		const oc = sub(origin, center);
		const a = dot(direction, direction);
		const b = 2.0 * dot(oc, direction);
		const c = dot(oc, oc) - radius * radius;
		const disc = b * b - 4.0 * a * c;
		if (disc < 0.0)
			return Infinity;
		const sqrtDisc = Math.sqrt(disc);
		let t0 = (-b - sqrtDisc) / (2.0 * a);
		let t1 = (-b + sqrtDisc) / (2.0 * a);
		if (t0 > t1) { const tmp = t0; t0 = t1; t1 = tmp; }
		if (t0 > 0.0) return t0;
		if (t1 > 0.0) return t1;
		return Infinity;
	}

	function refractRay(I, N, eta)
	{
		const cosThetaI = _clamp((-dot(I, N)), -1.0, 1.0);
		const k = 1.0 - eta * eta * (1.0 - cosThetaI * cosThetaI);
		if (k < 0.0)
			return null;
		const a = mul(I, eta);
		const b = mul(N, eta * cosThetaI - Math.sqrt(k));
		return normalize(add(a, b));
	}

	// back surface (air -> glass)
	const tBack = sphereIntersect(rBack, cBack, ro, rd);
	if (!Number.isFinite(tBack))
		return null;
	const pBack = add(ro, mul(rd, tBack));
	if ((pBack.x * pBack.x + pBack.y * pBack.y) > lensRad2)
		return null;

	let nBack = normalize(sub(pBack, cBack));
	if (dot(nBack, rd) > 0.0) nBack = mul(nBack, -1.0);
	const dirGlass = refractRay(rd, nBack, 1.0 / Math.max(1.0001, lensIor));
	if (!dirGlass)
		return null;

	// front surface (glass -> air)
	const ro2 = add(pBack, mul(dirGlass, eps));
	const tFront = sphereIntersect(rFront, cFront, ro2, dirGlass);
	if (!Number.isFinite(tFront))
		return null;
	const pFront = add(ro2, mul(dirGlass, tFront));
	if ((pFront.x * pFront.x + pFront.y * pFront.y) > lensRad2)
		return null;

	let nFront = normalize(sub(pFront, cFront));
	if (dot(nFront, dirGlass) > 0.0) nFront = mul(nFront, -1.0);
	const dirAir = refractRay(dirGlass, nFront, Math.max(1.0001, lensIor));
	if (!dirAir)
		return null;

	return { origin: add(pFront, mul(dirAir, eps)), dir: dirAir };
}


function _attachFocusMarker(controller, propertyName)
{
	if (!controller || !controller.domElement)
		return;

	const slider = controller.domElement.querySelector('.slider');
	if (!slider)
		return;

	const marker = document.createElement('div');
	marker.className = 'focus-marker';
	slider.appendChild(marker);

	function hide()
	{
		marker.classList.remove('visible');
		marker.classList.remove('tinted');
	}

	function showAtValue(target, tinted)
	{
		const min = controller._min;
		const max = controller._max;
		if (!_isFiniteNumber(min) || !_isFiniteNumber(max) || max === min)
			return hide();

		const t = _clamp((target - min) / (max - min), 0.0, 1.0);
		marker.style.left = `${t * 100.0}%`;
		marker.classList.toggle('tinted', !!tinted);
		marker.classList.add('visible');
	}

	slider.addEventListener('mouseenter', () =>
	{
		if (!paramsObject.Focus_Grid_Enabled)
			return hide();

		const min = controller._min;
		const max = controller._max;
		const currentValue = paramsObject[propertyName];

		const fn = _computeFocusTargetForProperty(propertyName, currentValue);
		if (!fn)
			return hide();

		const solved = _solveRootInRange(fn, min, max, currentValue);
		if (!solved)
			return hide();

		const clamped = _clamp(solved.x, min, max);
		const tinted = !!solved.tinted || (clamped !== solved.x);
		showAtValue(clamped, tinted);
	});

	slider.addEventListener('mouseleave', hide);
}


// called automatically from within initTHREEjs() function (located in InitCommon.js file)
function initSceneData()
{
	demoFragmentShaderFileName = 'Optical_Bench_Fragment.glsl';

	// scene/demo-specific three.js objects setup goes here
	sceneIsDynamic = false;

	allowOrthographicCamera = false;

	_installFocusMarkerCSS();

	// pixelRatio is resolution - range: 0.5(half resolution) to 1.0(full resolution)
	pixelRatio = mouseControl ? 1.0 : 0.75;

	EPS_intersect = 0.01;

	// set camera's field of view (used in Geometry View)
	worldCamera.fov = 60;

	paramsObject = {
		View_Mode: 'Geometry View',
		Scene: 'Test Chart',
		Exposure: 1.0,
		Focus_Grid_Enabled: false,
		Focus_Grid_Distance_mm: 1000.0,
		Focus_Grid_Lines: 13,
		Focus_Algorithm: 'Lensmaker (EFL)',
		Object_Distance_mm: 1000.0,
		Image_Distance_mm: 53.0,
		Aperture_Diameter_mm: 36.0,
		Stop_Offset_mm: 1.0,
		Lens_IOR: 1.52,
		Lens_R1_mm: 50.0,
		Lens_R2_mm: -50.0,
		Lens_Thickness_mm: 8.0,
		Lens_ClearAperture_mm: 40.0,
		Sensor_Width_mm: 36.0,
		Sensor_Height_mm: 24.0,
		Chart_Emission: 4.0
	};

	function applyViewMode()
	{
		let isGeometryView = paramsObject.View_Mode === 'Geometry View';

		useGenericInput = isGeometryView;
		cameraRotationSpeed = isGeometryView ? 1.0 : 0.0;
		cameraFlightSpeed = isGeometryView ? 400.0 : 0.0;

		if (pathTracingUniforms.uViewMode)
			pathTracingUniforms.uViewMode.value = isGeometryView ? 1 : 0;

		if (isGeometryView)
		{
			cameraControlsObject.position.set(0, 120, 450);
			cameraControlsYawObject.rotation.y = 0.0;
			cameraControlsPitchObject.rotation.x = -0.25;
			cameraControlsObject.updateMatrixWorld(true);
		}
		else
		{
			cameraControlsObject.position.set(0, 0, paramsObject.Image_Distance_mm);
			cameraControlsYawObject.rotation.y = 0.0;
			cameraControlsPitchObject.rotation.x = 0.0;
			cameraControlsObject.updateMatrixWorld(true);
		}

		cameraIsMoving = true;
	}


	// GUI
	opticalBenchFolder = gui.addFolder('Optical Bench');
	viewFolder = opticalBenchFolder.addFolder('View');
	viewModeController = viewFolder.add(paramsObject, 'View_Mode', ['Geometry View', 'Sensor Image']).onChange(() => { needsUpdate = true; applyViewMode(); });
	exposureController = viewFolder.add(paramsObject, 'Exposure', 0.05, 4.0, 0.01).onChange(() => { needsUpdate = true; });

	sceneFolder = opticalBenchFolder.addFolder('Scene');
	sceneController = sceneFolder.add(paramsObject, 'Scene', ['Test Chart', 'Sunset Landscape']).onChange(() => { needsUpdate = true; });

	focusAidFolder = opticalBenchFolder.addFolder('Focusing Aid');
	focusGridEnabledController = focusAidFolder.add(paramsObject, 'Focus_Grid_Enabled').onChange(() => { needsUpdate = true; });
	focusGridDistanceController = focusAidFolder.add(paramsObject, 'Focus_Grid_Distance_mm', 200.0, 20000.0, 10.0).onChange(() => { needsUpdate = true; });
	focusGridLinesController = focusAidFolder.add(paramsObject, 'Focus_Grid_Lines', 2, 41, 1).onChange(() => { needsUpdate = true; });
	focusAlgorithmController = focusAidFolder.add(paramsObject, 'Focus_Algorithm', ['Lensmaker (EFL)', 'Paraxial (ABCD)', 'Ray (Snell)']).onChange(() => { needsUpdate = true; });

	objectDistanceController = opticalBenchFolder.add(paramsObject, 'Object_Distance_mm', 300.0, 3000.0, 10.0).onChange(() => { needsUpdate = true; });
	imageDistanceController = opticalBenchFolder.add(paramsObject, 'Image_Distance_mm', 30.0, 90.0, 0.1).onChange(() => { needsUpdate = true; });
	apertureDiameterController = opticalBenchFolder.add(paramsObject, 'Aperture_Diameter_mm', 2.0, 40.0, 0.1).onChange(() => { needsUpdate = true; });
	stopZController = opticalBenchFolder.add(paramsObject, 'Stop_Offset_mm', 0.0, 10.0, 0.1).onChange(() => { needsUpdate = true; });

	lensFolder = opticalBenchFolder.addFolder('Lens');
	lensIORController = lensFolder.add(paramsObject, 'Lens_IOR', 1.0, 2.0, 0.001).onChange(() => { needsUpdate = true; });
	lensR1Controller = lensFolder.add(paramsObject, 'Lens_R1_mm', 10.0, 200.0, 0.1).onChange(() => { needsUpdate = true; });
	lensR2Controller = lensFolder.add(paramsObject, 'Lens_R2_mm', -200.0, -10.0, 0.1).onChange(() => { needsUpdate = true; });
	lensThicknessController = lensFolder.add(paramsObject, 'Lens_Thickness_mm', 1.0, 20.0, 0.1).onChange(() => { needsUpdate = true; });
	lensClearApertureController = lensFolder.add(paramsObject, 'Lens_ClearAperture_mm', 10.0, 80.0, 0.1).onChange(() => { needsUpdate = true; });

	sensorFolder = opticalBenchFolder.addFolder('Sensor');
	sensorWidthController = sensorFolder.add(paramsObject, 'Sensor_Width_mm', 10.0, 60.0, 0.1).onChange(() => { needsUpdate = true; });
	sensorHeightController = sensorFolder.add(paramsObject, 'Sensor_Height_mm', 10.0, 60.0, 0.1).onChange(() => { needsUpdate = true; });

	chartFolder = opticalBenchFolder.addFolder('Chart');
	chartEmissionController = chartFolder.add(paramsObject, 'Chart_Emission', 0.1, 40.0, 0.1).onChange(() => { needsUpdate = true; });

	opticalBenchFolder.open();
	viewFolder.open();
	sceneFolder.open();
	focusAidFolder.open();

	// scene/demo-specific uniforms go here
	pathTracingUniforms.uViewMode = { value: 1 };
	pathTracingUniforms.uSceneID = { value: 0 };
	pathTracingUniforms.uExposure = { value: paramsObject.Exposure };
	pathTracingUniforms.uSensorZ = { value: paramsObject.Image_Distance_mm };

	pathTracingUniforms.uSensorSize = { value: new THREE.Vector2(paramsObject.Sensor_Width_mm, paramsObject.Sensor_Height_mm) };
	pathTracingUniforms.uStopOffset = { value: paramsObject.Stop_Offset_mm };
	pathTracingUniforms.uStopRadius = { value: paramsObject.Aperture_Diameter_mm * 0.5 };

	pathTracingUniforms.uLensIor = { value: paramsObject.Lens_IOR };
	pathTracingUniforms.uLensR1 = { value: paramsObject.Lens_R1_mm };
	pathTracingUniforms.uLensR2 = { value: paramsObject.Lens_R2_mm };
	pathTracingUniforms.uLensThickness = { value: paramsObject.Lens_Thickness_mm };
	pathTracingUniforms.uLensRadius = { value: paramsObject.Lens_ClearAperture_mm * 0.5 };

	pathTracingUniforms.uChartZ = { value: -paramsObject.Object_Distance_mm };
	pathTracingUniforms.uChartHalfSize = { value: new THREE.Vector2(350.0, 233.3333333) };
	pathTracingUniforms.uChartEmission = { value: paramsObject.Chart_Emission };

	pathTracingUniforms.uFocusGridEnabled = { value: paramsObject.Focus_Grid_Enabled ? 1 : 0 };
	pathTracingUniforms.uFocusGridDistance = { value: paramsObject.Focus_Grid_Distance_mm };
	pathTracingUniforms.uFocusGridLines = { value: paramsObject.Focus_Grid_Lines };

	_attachFocusMarker(imageDistanceController, 'Image_Distance_mm');
	_attachFocusMarker(lensIORController, 'Lens_IOR');
	_attachFocusMarker(lensR1Controller, 'Lens_R1_mm');
	_attachFocusMarker(lensR2Controller, 'Lens_R2_mm');
	_attachFocusMarker(lensThicknessController, 'Lens_Thickness_mm');

	applyViewMode();
	needsUpdate = true;
}


// called automatically from within the animate() function (located in InitCommon.js file)
function updateVariablesAndUniforms()
{
	if (needsUpdate)
	{
		let isGeometryView = paramsObject.View_Mode === 'Geometry View';

		pathTracingUniforms.uViewMode.value = isGeometryView ? 1 : 0;
		pathTracingUniforms.uSceneID.value = (paramsObject.Scene === 'Sunset Landscape') ? 1 : 0;
		pathTracingUniforms.uExposure.value = paramsObject.Exposure;
		pathTracingUniforms.uSensorZ.value = paramsObject.Image_Distance_mm;

		if (!isGeometryView)
		{
			cameraControlsObject.position.set(0, 0, paramsObject.Image_Distance_mm);
			cameraControlsYawObject.rotation.y = 0.0;
			cameraControlsPitchObject.rotation.x = 0.0;
			cameraControlsObject.updateMatrixWorld(true);
		}

		pathTracingUniforms.uSensorSize.value.set(paramsObject.Sensor_Width_mm, paramsObject.Sensor_Height_mm);
		pathTracingUniforms.uStopOffset.value = paramsObject.Stop_Offset_mm;
		pathTracingUniforms.uStopRadius.value = paramsObject.Aperture_Diameter_mm * 0.5;

		pathTracingUniforms.uLensIor.value = paramsObject.Lens_IOR;
		pathTracingUniforms.uLensR1.value = paramsObject.Lens_R1_mm;
		pathTracingUniforms.uLensR2.value = paramsObject.Lens_R2_mm;
		pathTracingUniforms.uLensThickness.value = paramsObject.Lens_Thickness_mm;
		pathTracingUniforms.uLensRadius.value = paramsObject.Lens_ClearAperture_mm * 0.5;

		pathTracingUniforms.uChartZ.value = -paramsObject.Object_Distance_mm;
		pathTracingUniforms.uChartEmission.value = paramsObject.Chart_Emission;

		pathTracingUniforms.uFocusGridEnabled.value = paramsObject.Focus_Grid_Enabled ? 1 : 0;
		pathTracingUniforms.uFocusGridDistance.value = paramsObject.Focus_Grid_Distance_mm;
		pathTracingUniforms.uFocusGridLines.value = paramsObject.Focus_Grid_Lines;

		cameraIsMoving = true;
		needsUpdate = false;
	}

	// INFO
	cameraInfoElement.innerHTML =
		paramsObject.View_Mode + " / " + paramsObject.Scene +
		" / u: " + paramsObject.Object_Distance_mm.toFixed(0) + "mm" +
		" / v: " + paramsObject.Image_Distance_mm.toFixed(1) + "mm" +
		" / Aperture: " + paramsObject.Aperture_Diameter_mm.toFixed(1) + "mm" +
		"<br>Samples: " + sampleCounter;
}


init(); // init app and start animating
