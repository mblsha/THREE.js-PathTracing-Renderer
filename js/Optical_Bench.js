// scene/demo-specific variables go here
let opticalBenchFolder, lensFolder, sensorFolder, chartFolder, viewFolder;
let viewModeController, exposureController;
let objectDistanceController, imageDistanceController, apertureDiameterController;
let stopZController;
let lensIORController, lensR1Controller, lensR2Controller, lensThicknessController, lensClearApertureController;
let sensorWidthController, sensorHeightController;
let chartEmissionController;

let paramsObject;
let needsUpdate = false;


// called automatically from within initTHREEjs() function (located in InitCommon.js file)
function initSceneData()
{
	demoFragmentShaderFileName = 'Optical_Bench_Fragment.glsl';

	// scene/demo-specific three.js objects setup goes here
	sceneIsDynamic = false;

	allowOrthographicCamera = false;

	// pixelRatio is resolution - range: 0.5(half resolution) to 1.0(full resolution)
	pixelRatio = mouseControl ? 1.0 : 0.75;

	EPS_intersect = 0.01;

	// set camera's field of view (used in Geometry View)
	worldCamera.fov = 60;

	paramsObject = {
		View_Mode: 'Geometry View',
		Exposure: 1.0,
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

	// scene/demo-specific uniforms go here
	pathTracingUniforms.uViewMode = { value: 1 };
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

		cameraIsMoving = true;
		needsUpdate = false;
	}

	// INFO
	cameraInfoElement.innerHTML =
		paramsObject.View_Mode +
		" / u: " + paramsObject.Object_Distance_mm.toFixed(0) + "mm" +
		" / v: " + paramsObject.Image_Distance_mm.toFixed(1) + "mm" +
		" / Aperture: " + paramsObject.Aperture_Diameter_mm.toFixed(1) + "mm" +
		"<br>Samples: " + sampleCounter;
}


init(); // init app and start animating
