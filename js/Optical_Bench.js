// scene/demo-specific variables go here
let opticalBenchFolder, lensFolder, sensorFolder, chartFolder, viewFolder, sceneFolder, focusAidFolder;
let viewModeController, exposureController;
let sceneController;
let objectDistanceController, imageDistanceController, apertureDiameterController;
let stopZController;
let lensIORController, lensR1Controller, lensR2Controller, lensThicknessController, lensClearApertureController;
let lensPresetController;
let sensorWidthController, sensorHeightController;
let chartEmissionController;
let focusGridEnabledController, focusGridDistanceController, focusGridLinesController, focusAlgorithmController;

let paramsObject;
let needsUpdate = false;

let _focusMarkerCSSInstalled = false;
let _legendCSSInstalled = false;
let _legendElement = null;
let _legendBodyElement = null;
let _legendToggleButton = null;
let _legendResizeObserver = null;

const MAX_LENS_SURFACES = 12;

const LENS_PRESETS = {
	'Custom Singlet': {
		type: 'custom'
	},
	'Achromat Doublet (toy)': {
		type: 'fixed',
		defaults: {
			Lens_Thickness_mm: 8.0,
			Lens_ClearAperture_mm: 40.0
		},
		surfaces: [
			// Canonical order is object -> sensor (increasing Z). nAfter is medium after the surface in that direction.
			{ z: -4.0, R: 40.0, nAfter: 1.52 }, // air -> glass1
			{ z: -0.5, R: -30.0, nAfter: 1.62 }, // glass1 -> glass2
			{ z: 4.0, R: -70.0, nAfter: 1.0 } // glass2 -> air
		]
	},
	'Petzval-ish (toy)': {
		type: 'fixed',
		defaults: {
			Lens_Thickness_mm: 27.0,
			Lens_ClearAperture_mm: 40.0
		},
		surfaces: [
			// Front positive doublet + rear weak negative singlet (for field curvature / swirl exploration).
			{ z: -13.5, R: 40.0, nAfter: 1.52 },
			{ z: -10.0, R: -30.0, nAfter: 1.62 },
			{ z: -5.5, R: -70.0, nAfter: 1.0 },
			{ z: 7.5, R: -500.0, nAfter: 1.52 },
			{ z: 13.5, R: 500.0, nAfter: 1.0 }
		]
	},
	'2x Doublet (toy, more corrected)': {
		type: 'fixed',
		defaults: {
			Lens_Thickness_mm: 28.0,
			Lens_ClearAperture_mm: 40.0
		},
		surfaces: [
			{ z: -14.0, R: 80.0, nAfter: 1.52 },
			{ z: -10.5, R: -60.0, nAfter: 1.62 },
			{ z: -6.0, R: -140.0, nAfter: 1.0 },
			{ z: 6.0, R: 80.0, nAfter: 1.52 },
			{ z: 9.5, R: -60.0, nAfter: 1.62 },
			{ z: 14.0, R: -140.0, nAfter: 1.0 }
		]
	}
};


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

function _installLegendCSS()
{
	if (_legendCSSInstalled)
		return;

	const style = document.createElement('style');
	style.setAttribute('data-optical-bench-legend', 'true');
	style.textContent = `
	#opticalBenchLegend {
		position: fixed;
		top: 12px;
		right: 360px;
		width: 340px;
		max-width: 42vw;
		max-height: calc(100vh - 24px);
		overflow: auto;
		z-index: 1001;
		padding: 10px 12px;
		border-radius: 6px;
		background: rgba(0, 0, 0, 0.62);
		border: 1px solid rgba(255, 255, 255, 0.14);
		color: rgba(255, 255, 255, 0.92);
		font-family: Arial, sans-serif;
		font-size: 12px;
		line-height: 1.35;
		user-select: text;
		-webkit-user-select: text;
	}
	#opticalBenchLegend .legend-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 10px;
	}
	#opticalBenchLegend .legend-toggle {
		appearance: none;
		border: 1px solid rgba(255, 255, 255, 0.18);
		background: rgba(255, 255, 255, 0.06);
		color: rgba(255, 255, 255, 0.92);
		border-radius: 6px;
		padding: 4px 8px;
		font-size: 11px;
		cursor: pointer;
	}
	#opticalBenchLegend .legend-toggle:hover {
		background: rgba(255, 255, 255, 0.10);
	}
	#opticalBenchLegend .legend-toggle:active {
		background: rgba(255, 255, 255, 0.14);
	}
	#opticalBenchLegend.collapsed .legend-body {
		display: none;
	}
	#opticalBenchLegend h3 {
		margin: 0;
		font-size: 13px;
		font-weight: 700;
		color: rgba(255, 255, 255, 0.96);
	}
	#opticalBenchLegend h4 {
		margin: 10px 0 6px 0;
		font-size: 12px;
		font-weight: 700;
		color: rgba(255, 255, 255, 0.92);
	}
	#opticalBenchLegend p { margin: 0 0 8px 0; }
	#opticalBenchLegend ul { margin: 0 0 8px 18px; padding: 0; }
	#opticalBenchLegend li { margin: 3px 0; }
	#opticalBenchLegend code {
		font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
		font-size: 11px;
		color: rgba(220, 255, 255, 0.92);
	}
	#opticalBenchLegend .muted { color: rgba(255, 255, 255, 0.70); }
	#opticalBenchLegend .kv { display: grid; grid-template-columns: auto 1fr; gap: 2px 10px; }
	#opticalBenchLegend .kv div { white-space: nowrap; }
	#opticalBenchLegend .kv div:nth-child(2n) { white-space: normal; }
	`;
	document.head.appendChild(style);
	_legendCSSInstalled = true;
}

function _formatNumber(x, digits = 2)
{
	if (!_isFiniteNumber(x))
		return '—';
	return x.toFixed(digits);
}

function _formatMm(x, digits = 1)
{
	if (!_isFiniteNumber(x))
		return '—';
	return `${x.toFixed(digits)} mm`;
}

function _getLensPresetDefinition()
{
	const presetName = paramsObject?.Lens_Preset || 'Custom Singlet';
	return LENS_PRESETS[presetName] || LENS_PRESETS['Custom Singlet'];
}

function _getLensCanonicalSurfaces(property = null, trialValue = null)
{
	const presetName = paramsObject?.Lens_Preset || 'Custom Singlet';
	if (presetName !== 'Custom Singlet')
		return _getLensPresetDefinition().surfaces;

	let n = paramsObject.Lens_IOR;
	let r1 = paramsObject.Lens_R1_mm;
	let r2 = paramsObject.Lens_R2_mm;
	let t = paramsObject.Lens_Thickness_mm;

	if (property === 'Lens_IOR') n = trialValue;
	else if (property === 'Lens_R1_mm') r1 = trialValue;
	else if (property === 'Lens_R2_mm') r2 = trialValue;
	else if (property === 'Lens_Thickness_mm') t = trialValue;

	const zFront = -0.5 * t;
	const zBack = 0.5 * t;

	return [
		{ z: zFront, R: r1, nAfter: n },
		{ z: zBack, R: r2, nAfter: 1.0 }
	];
}

function _buildLensSurfacesSensorToObject(canonicalSurfaces)
{
	if (!Array.isArray(canonicalSurfaces) || canonicalSurfaces.length === 0)
		return [];

	let nBefore = 1.0;
	const surfacesWithBefore = canonicalSurfaces.map((s) =>
	{
		const out = { z: s.z, R: s.R, nAfter: s.nAfter, nBefore };
		nBefore = s.nAfter;
		return out;
	});

	const reversed = [];
	for (let i = surfacesWithBefore.length - 1; i >= 0; i--)
	{
		const s = surfacesWithBefore[i];
		reversed.push({ z: s.z, R: s.R, nAfter: s.nBefore });
	}
	return reversed;
}

function _updateLensSurfaceUniforms()
{
	if (!pathTracingUniforms?.uLensSurfaces || !pathTracingUniforms?.uLensSurfaceCount)
		return;

	const canonical = _getLensCanonicalSurfaces();
	const sensorToObject = _buildLensSurfacesSensorToObject(canonical);
	const count = Math.min(sensorToObject.length, MAX_LENS_SURFACES);

	pathTracingUniforms.uLensSurfaceCount.value = count;

	for (let i = 0; i < MAX_LENS_SURFACES; i++)
	{
		const v = pathTracingUniforms.uLensSurfaces.value[i];
		if (i < count)
		{
			const s = sensorToObject[i];
			v.set(s.R, s.z, s.nAfter, 0.0);
		}
		else
		{
			v.set(0.0, 0.0, 1.0, 0.0);
		}
	}
}

function _positionLegendOverlay()
{
	if (!_legendElement || !_legendElement.isConnected || !gui?.domElement)
		return;

	const margin = 12;
	const guiRect = gui.domElement.getBoundingClientRect();
	const legendWidth = _legendElement.offsetWidth || 340;

	const canPlaceLeft = (guiRect.left - margin) >= (legendWidth + margin);
	if (canPlaceLeft)
	{
		_legendElement.style.left = `${Math.round(guiRect.left - margin - legendWidth)}px`;
		_legendElement.style.right = 'auto';
		_legendElement.style.top = `${Math.round(Math.max(margin, guiRect.top))}px`;
	}
	else
	{
		_legendElement.style.left = 'auto';
		_legendElement.style.right = `${margin}px`;
		_legendElement.style.top = `${Math.round(guiRect.bottom + margin)}px`;
	}

	const top = parseFloat(_legendElement.style.top) || margin;
	_legendElement.style.maxHeight = `${Math.max(120, window.innerHeight - top - margin)}px`;
}

function _updateLegendOverlay()
{
	if (!_legendElement || !_legendElement.isConnected || !_legendBodyElement || !paramsObject)
		return;

	const u = paramsObject.Object_Distance_mm;
	const v = paramsObject.Image_Distance_mm;
	const D = paramsObject.Focus_Grid_Distance_mm;
	const lensPresetName = paramsObject.Lens_Preset || 'Custom Singlet';
	const isCustomSinglet = lensPresetName === 'Custom Singlet';
	const canonicalSurfaces = _getLensCanonicalSurfaces();
	const surfaceCount = Array.isArray(canonicalSurfaces) ? canonicalSurfaces.length : 0;

	const n = paramsObject.Lens_IOR;
	const r1 = paramsObject.Lens_R1_mm;
	const r2 = paramsObject.Lens_R2_mm;
	const t = paramsObject.Lens_Thickness_mm;
	const lensRadius = 0.5 * paramsObject.Lens_ClearAperture_mm;

	const aperture = paramsObject.Aperture_Diameter_mm;
	const stopRadius = 0.5 * aperture;
	const stopOffset = paramsObject.Stop_Offset_mm;

	const zFront = -0.5 * t;
	const zBack = 0.5 * t;
	const stopZ = zBack + Math.max(0.0, stopOffset);

	const objectZ = -u;
	const gridZ = v - D;

	const f = isCustomSinglet ? _lensmakerEFL(n, r1, r2, t) : _paraxialEFLFromSurfaces(canonicalSurfaces);
	const fStop = (_isFiniteNumber(f) && _isFiniteNumber(aperture) && aperture > 0.0) ? (f / aperture) : Infinity;

	let vThin = Infinity;
	if (_isFiniteNumber(f) && _isFiniteNumber(u) && u > 0.0 && f !== 0.0)
	{
		const denom = (1.0 / f) - (1.0 / u);
		if (Math.abs(denom) > 1e-9)
			vThin = 1.0 / denom;
	}

	const mode = paramsObject.View_Mode;
	const scene = paramsObject.Scene;

	const fStr = _isFiniteNumber(f) ? `${_formatMm(f, 1)}` : '∞';
	const fStopStr = (_isFiniteNumber(fStop) && fStop < 1e6) ? `f/${_formatNumber(fStop, 2)}` : '—';
	const vThinStr = (_isFiniteNumber(vThin) && vThin > 0.0 && vThin < 1e6) ? `${_formatMm(vThin, 1)}` : '—';

	const landscapeNote = 'Sunset Landscape uses a stage shift so the terrain front edge sits at the same object plane as the chart.';

	_legendBodyElement.innerHTML = `
		<p class="muted">All distances are in <code>mm</code>. Optical axis is <code>+Z</code> (object side is <code>-Z</code>, sensor side is <code>+Z</code>). Lens is centered at <code>z=0</code>.</p>

		<h4>Current Setup</h4>
		<div class="kv">
			<div><code>u</code> (Object Distance)</div><div>${_formatMm(u, 0)} → object plane at <code>z=${_formatNumber(objectZ, 0)}</code></div>
			<div><code>v</code> (Image Distance)</div><div>${_formatMm(v, 1)} → sensor plane at <code>z=${_formatNumber(v, 1)}</code></div>
			<div>Stop plane</div><div><code>z=${_formatNumber(stopZ, 2)}</code>, radius <code>${_formatNumber(stopRadius, 2)}</code></div>
			<div>Lens preset</div><div><code>${lensPresetName}</code> <span class="muted">(${surfaceCount} surfaces)</span></div>
			<div>Lens vertices</div><div><code>z=${_formatNumber(zFront, 2)}</code> (front), <code>z=${_formatNumber(zBack, 2)}</code> (back)</div>
			<div>EFL (approx)</div><div><code>f≈${fStr}</code> → <code>${fStopStr}</code> (using Aperture Diameter)</div>
			<div>Thin‑lens guess</div><div><code>v≈${vThinStr}</code> for current <code>u</code> (starting point; thick lens/aberrations differ)</div>
		</div>

		<h4>View & Scene</h4>
		<ul>
			<li><code>View_Mode</code>: <code>${mode}</code> — <span class="muted">${mode === 'Sensor Image' ? 'renders irradiance on the sensor by tracing through stop + lens (image is vertically flipped upright).' : 'renders simple bench geometry with a standard camera (no lens refraction).'}</span></li>
			<li><code>Scene</code>: <code>${scene}</code> — <span class="muted">${scene === 'Sunset Landscape' ? landscapeNote : 'Test Chart is an emissive chart plane at the object distance.'}</span></li>
			<li><code>Exposure</code> scales the final radiance.</li>
		</ul>

		<h4>Lens & Aperture</h4>
		<ul>
			<li><code>Lens_Preset</code> selects the lens prescription. <span class="muted">${isCustomSinglet ? 'Custom Singlet uses the editable thick singlet parameters.' : 'Preset lenses disable the singlet-parameter controls.'}</span></li>
			<li><span class="muted">${isCustomSinglet ? '<code>Lens_IOR</code>, <code>Lens_R1_mm</code>, <code>Lens_R2_mm</code>, <code>Lens_Thickness_mm</code> define the thick singlet prescription.' : 'Preset lenses are multi-surface; EFL is computed from a paraxial system matrix.'}</span></li>
			<li>Radius sign: sphere center is at <code>zVertex + R</code>. A common biconvex starter is <code>R1&gt;0</code>, <code>R2&lt;0</code> (e.g. <code>+50</code>/<code>-50</code>).</li>
			<li><code>Lens_ClearAperture_mm</code> clips rays at the glass edge (lens radius = <code>${_formatNumber(lensRadius, 1)}</code>).</li>
			<li><code>Aperture_Diameter_mm</code> (stop hole size) controls DoF + aberration visibility; stopping down increases DoF and reduces aberrations.</li>
			<li><code>Stop_Offset_mm</code> moves the stop plane along <code>+Z</code> (toward the sensor).</li>
		</ul>

		<h4>Sensor</h4>
		<ul>
			<li><code>Sensor_Width_mm</code> / <code>Sensor_Height_mm</code> set the sensor aspect and screen-to-sensor mapping in Sensor Image mode.</li>
			<li>Pixels outside the sensor bounds are rendered black.</li>
		</ul>

		<h4>Focusing Aid</h4>
		<ul>
			<li><code>Focus_Grid_Enabled</code> draws an emissive grid plane at <code>z = v - D</code> → <code>z=${_formatNumber(gridZ, 1)}</code>.</li>
			<li><code>Focus_Grid_Distance_mm</code> (<code>D</code>) is measured from the sensor toward the object (along <code>-Z</code>).</li>
			<li><code>Focus_Grid_Density</code> controls line frequency in sensor space (kept distance-invariant on screen).</li>
			<li>Hover focus-related sliders to see a predicted “in-focus” target for the current grid distance. <span class="muted">Orange marker = clamped/approximate/no-root case.</span></li>
			<li><code>Focus_Algorithm</code> selects the solver used for those hover markers (not the renderer).</li>
		</ul>

		<h4>Chart</h4>
		<ul>
			<li><code>Chart_Emission</code> controls brightness of the emissive test chart (Test Chart scene).</li>
		</ul>
	`;

	_positionLegendOverlay();
}

function _setLegendExpanded(expanded)
{
	if (!_legendElement)
		return;

	const isExpanded = !!expanded;
	_legendElement.classList.toggle('collapsed', !isExpanded);
	if (_legendToggleButton)
	{
		_legendToggleButton.textContent = isExpanded ? 'Collapse' : 'Expand';
		_legendToggleButton.setAttribute('aria-expanded', isExpanded ? 'true' : 'false');
	}

	_positionLegendOverlay();
}

function _ensureLegendOverlay()
{
	_installLegendCSS();

	if (_legendElement && _legendElement.isConnected)
		return;

	_legendElement = document.createElement('div');
	_legendElement.id = 'opticalBenchLegend';

	const header = document.createElement('div');
	header.className = 'legend-header';

	const title = document.createElement('h3');
	title.textContent = 'Legend';
	header.appendChild(title);

	_legendToggleButton = document.createElement('button');
	_legendToggleButton.type = 'button';
	_legendToggleButton.className = 'legend-toggle';
	_legendToggleButton.textContent = 'Expand';
	_legendToggleButton.addEventListener('click', (e) =>
	{
		e.stopPropagation();
		if (!paramsObject)
			return;
		paramsObject.Legend_Expanded = !paramsObject.Legend_Expanded;
		_setLegendExpanded(paramsObject.Legend_Expanded);
	}, false);
	header.appendChild(_legendToggleButton);

	_legendBodyElement = document.createElement('div');
	_legendBodyElement.className = 'legend-body';

	_legendElement.appendChild(header);
	_legendElement.appendChild(_legendBodyElement);
	document.body.appendChild(_legendElement);

	// Prevent the legend from triggering pointer lock when interacting with it.
	_legendElement.addEventListener('mouseenter', () => { ableToEngagePointerLock = false; }, false);
	_legendElement.addEventListener('mouseleave', () => { ableToEngagePointerLock = true; }, false);
	_legendElement.addEventListener('click', (e) => { e.stopPropagation(); }, false);
	_legendElement.addEventListener('dblclick', (e) => { e.stopPropagation(); }, false);

	window.addEventListener('resize', () => _positionLegendOverlay(), { passive: true });

	if (typeof ResizeObserver !== 'undefined' && gui?.domElement)
	{
		_legendResizeObserver = new ResizeObserver(() => _positionLegendOverlay());
		_legendResizeObserver.observe(gui.domElement);
	}
	else if (gui?.domElement)
	{
		gui.domElement.addEventListener('click', () => requestAnimationFrame(_positionLegendOverlay));
	}

	_setLegendExpanded(paramsObject?.Legend_Expanded ?? false);
	_updateLegendOverlay();
}

function _setLegendVisible(visible)
{
	if (!_legendElement)
		return;
	_legendElement.style.display = visible ? '' : 'none';
	if (visible)
		_setLegendExpanded(paramsObject?.Legend_Expanded ?? false);
	if (visible)
		_updateLegendOverlay();
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

function _lensSystemMatrixFromSurfaces(canonicalSurfaces)
{
	if (!Array.isArray(canonicalSurfaces) || canonicalSurfaces.length === 0)
		return null;

	let M = { A: 1.0, B: 0.0, C: 0.0, D: 1.0 };
	let n1 = 1.0;

	for (let i = 0; i < canonicalSurfaces.length; i++)
	{
		const s = canonicalSurfaces[i];
		const n2 = s.nAfter;
		M = _mul2x2(_refractSurface2x2(n1, n2, s.R), M);
		if (i < canonicalSurfaces.length - 1)
		{
			const d = canonicalSurfaces[i + 1].z - s.z;
			M = _mul2x2(_translate2x2(d), M);
		}
		n1 = n2;
	}

	return {
		M,
		zFront: canonicalSurfaces[0].z,
		zBack: canonicalSurfaces[canonicalSurfaces.length - 1].z
	};
}

function _paraxialEFLFromSurfaces(canonicalSurfaces)
{
	const sys = _lensSystemMatrixFromSurfaces(canonicalSurfaces);
	if (!sys || !_isFiniteNumber(sys.M.C) || Math.abs(sys.M.C) < 1e-9)
		return Infinity;
	return -1.0 / sys.M.C;
}

function _paraxialImagingResidual_B_FromSurfaces(D, v, canonicalSurfaces)
{
	if (!_isFiniteNumber(D) || !_isFiniteNumber(v) || D <= 0.0)
		return NaN;

	const sys = _lensSystemMatrixFromSurfaces(canonicalSurfaces);
	if (!sys)
		return NaN;

	const gridZ = v - D;
	const L1 = sys.zFront - gridZ;
	const L2 = v - sys.zBack;
	if (!_isFiniteNumber(L1) || !_isFiniteNumber(L2))
		return NaN;

	const Mtot = _mul2x2(_translate2x2(L2), _mul2x2(sys.M, _translate2x2(L1)));
	return Mtot.B;
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

	const presetName = paramsObject.Lens_Preset || 'Custom Singlet';
	const isCustom = presetName === 'Custom Singlet';
	if (!isCustom && property !== 'Image_Distance_mm')
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

		const canonicalSurfaces = _getLensCanonicalSurfaces(property, x);

		if (algorithm === 'Paraxial (ABCD)')
		{
			return _paraxialImagingResidual_B_FromSurfaces(D, v, canonicalSurfaces);
		}

		if (algorithm === 'Ray (Snell)')
		{
			const stopPlaneZ = 0.5 * t + Math.max(0.0, stopOffset);
			const rSample = Math.min(Math.max(0.0, stopRadius), Math.max(0.0, lensRadius)) * 0.7;
			if (rSample <= 0.0001)
				return NaN;

			const sensorZ = v;
			const gridZ = sensorZ - D;
			const sensorToObject = _buildLensSurfacesSensorToObject(canonicalSurfaces);
			const ray = _traceRayThroughLensFromSensor(sensorZ, stopPlaneZ, rSample, sensorToObject, lensRadius);
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
		const f = isCustom ? _lensmakerEFL(n, r1, r2, t) : _paraxialEFLFromSurfaces(canonicalSurfaces);
		if (!_isFiniteNumber(f) || f === 0.0)
			return NaN;
		const requiredPower = (1.0 / v) + (1.0 / (D - v));
		return (1.0 / f) - requiredPower;
	};
	return residual;
}


function _traceRayThroughLensFromSensor(sensorZ, stopPlaneZ, stopX, sensorToObjectSurfaces, lensRadius)
{
	const eps = 0.01;

	let ro = { x: 0.0, y: 0.0, z: sensorZ };
	let rd = (function () {
		const dx = stopX - ro.x;
		const dy = 0.0 - ro.y;
		const dz = stopPlaneZ - ro.z;
		const invLen = 1.0 / Math.sqrt(dx * dx + dy * dy + dz * dz);
		return { x: dx * invLen, y: dy * invLen, z: dz * invLen };
	})();

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

		if (!Array.isArray(sensorToObjectSurfaces) || sensorToObjectSurfaces.length === 0)
			return null;

		let n1 = 1.0;
		for (const s of sensorToObjectSurfaces)
		{
			const R = s.R;
			const zV = s.z;
			const n2 = s.nAfter;
			const c = { x: 0.0, y: 0.0, z: zV + R };
			const rAbs = Math.abs(R);

			const tt = sphereIntersect(rAbs, c, ro, rd);
			if (!Number.isFinite(tt))
				return null;
			const p = add(ro, mul(rd, tt));
			if ((p.x * p.x + p.y * p.y) > lensRad2)
				return null;

			let N = normalize(sub(p, c));
			if (dot(N, rd) > 0.0) N = mul(N, -1.0);

			const dirT = refractRay(rd, N, n1 / Math.max(1.0001, n2));
			if (!dirT)
				return null;

			ro = add(p, mul(dirT, eps));
			rd = dirT;
			n1 = n2;
		}

		return { origin: ro, dir: rd };
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
		demoShaderChunkFiles = [
			{ name: 'optical_bench_primitives', file: 'optical_bench/optical_bench_primitives.glsl' },
			{ name: 'optical_bench_focus_grid', file: 'optical_bench/optical_bench_focus_grid.glsl' },
			{ name: 'optical_bench_test_chart', file: 'optical_bench/optical_bench_test_chart.glsl' },
			{ name: 'optical_bench_sunset_landscape', file: 'optical_bench/optical_bench_sunset_landscape.glsl' },
			{ name: 'optical_bench_lens', file: 'optical_bench/optical_bench_lens.glsl' },
			{ name: 'optical_bench_main', file: 'optical_bench/optical_bench_main.glsl' }
		];

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
		Legend_Visible: mouseControl,
		Legend_Expanded: false,
		Focus_Grid_Enabled: false,
		Focus_Grid_Distance_mm: 1000.0,
		Focus_Grid_Lines: 1.0,
		Focus_Algorithm: 'Lensmaker (EFL)',
		Object_Distance_mm: 1000.0,
		Image_Distance_mm: 53.0,
		Aperture_Diameter_mm: 36.0,
		Stop_Offset_mm: 1.0,
		Lens_Preset: 'Custom Singlet',
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

		function applyLensPreset()
		{
			const presetName = paramsObject.Lens_Preset || 'Custom Singlet';
			const preset = LENS_PRESETS[presetName] || LENS_PRESETS['Custom Singlet'];
			const isCustom = presetName === 'Custom Singlet';

			lensIORController?.disable(!isCustom);
			lensR1Controller?.disable(!isCustom);
			lensR2Controller?.disable(!isCustom);
			lensThicknessController?.disable(!isCustom);

			if (!isCustom && preset?.defaults)
			{
				if (_isFiniteNumber(preset.defaults.Lens_Thickness_mm))
					paramsObject.Lens_Thickness_mm = preset.defaults.Lens_Thickness_mm;
				if (_isFiniteNumber(preset.defaults.Lens_ClearAperture_mm))
					paramsObject.Lens_ClearAperture_mm = preset.defaults.Lens_ClearAperture_mm;

				// Provide a reasonable starting focus for the current object plane (thin-lens guess).
				const u = paramsObject.Object_Distance_mm;
				const f = _paraxialEFLFromSurfaces(_getLensCanonicalSurfaces());
				if (_isFiniteNumber(f) && _isFiniteNumber(u) && u > 0.0 && f !== 0.0)
				{
					const denom = (1.0 / f) - (1.0 / u);
					if (Math.abs(denom) > 1e-9)
						paramsObject.Image_Distance_mm = 1.0 / denom;
				}
			}

			lensIORController?.updateDisplay();
			lensR1Controller?.updateDisplay();
			lensR2Controller?.updateDisplay();
			lensThicknessController?.updateDisplay();
			lensClearApertureController?.updateDisplay();
			imageDistanceController?.updateDisplay();

			cameraIsMoving = true;
			needsUpdate = true;
		}


		// GUI
		opticalBenchFolder = gui.addFolder('Optical Bench');
		viewFolder = opticalBenchFolder.addFolder('View');
	viewModeController = viewFolder.add(paramsObject, 'View_Mode', ['Geometry View', 'Sensor Image']).onChange(() => { needsUpdate = true; applyViewMode(); });
	exposureController = viewFolder.add(paramsObject, 'Exposure', 0.05, 4.0, 0.01).onChange(() => { needsUpdate = true; });
	viewFolder.add(paramsObject, 'Legend_Visible').name('Show Legend').onChange(() =>
	{
		_ensureLegendOverlay();
		_setLegendVisible(paramsObject.Legend_Visible);
		_positionLegendOverlay();
	});

	sceneFolder = opticalBenchFolder.addFolder('Scene');
	sceneController = sceneFolder.add(paramsObject, 'Scene', ['Test Chart', 'Sunset Landscape']).onChange(() => { needsUpdate = true; });

	focusAidFolder = opticalBenchFolder.addFolder('Focusing Aid');
	focusGridEnabledController = focusAidFolder.add(paramsObject, 'Focus_Grid_Enabled').onChange(() => { needsUpdate = true; });
	focusGridDistanceController = focusAidFolder.add(paramsObject, 'Focus_Grid_Distance_mm', 200.0, 20000.0, 10.0).onChange(() => { needsUpdate = true; });
	focusGridLinesController = focusAidFolder.add(paramsObject, 'Focus_Grid_Lines', 0.01, 2.0, 0.01).name('Focus_Grid_Density').onChange(() => { needsUpdate = true; });
	focusAlgorithmController = focusAidFolder.add(paramsObject, 'Focus_Algorithm', ['Lensmaker (EFL)', 'Paraxial (ABCD)', 'Ray (Snell)']).onChange(() => { needsUpdate = true; });

	objectDistanceController = opticalBenchFolder.add(paramsObject, 'Object_Distance_mm', 300.0, 3000.0, 10.0).onChange(() => { needsUpdate = true; });
	imageDistanceController = opticalBenchFolder.add(paramsObject, 'Image_Distance_mm', 30.0, 90.0, 0.1).onChange(() => { needsUpdate = true; });
	apertureDiameterController = opticalBenchFolder.add(paramsObject, 'Aperture_Diameter_mm', 2.0, 40.0, 0.1).onChange(() => { needsUpdate = true; });
		stopZController = opticalBenchFolder.add(paramsObject, 'Stop_Offset_mm', 0.0, 10.0, 0.1).onChange(() => { needsUpdate = true; });

		lensFolder = opticalBenchFolder.addFolder('Lens');
		lensPresetController = lensFolder.add(paramsObject, 'Lens_Preset', Object.keys(LENS_PRESETS)).name('Lens Preset').onChange(() => { applyLensPreset(); });
		lensIORController = lensFolder.add(paramsObject, 'Lens_IOR', 1.0, 2.0, 0.001).onChange(() => { needsUpdate = true; });
		lensR1Controller = lensFolder.add(paramsObject, 'Lens_R1_mm', 10.0, 200.0, 0.1).onChange(() => { needsUpdate = true; });
		lensR2Controller = lensFolder.add(paramsObject, 'Lens_R2_mm', -200.0, -10.0, 0.1).onChange(() => { needsUpdate = true; });
		lensThicknessController = lensFolder.add(paramsObject, 'Lens_Thickness_mm', 1.0, 60.0, 0.1).onChange(() => { needsUpdate = true; });
		lensClearApertureController = lensFolder.add(paramsObject, 'Lens_ClearAperture_mm', 10.0, 80.0, 0.1).onChange(() => { needsUpdate = true; });

	sensorFolder = opticalBenchFolder.addFolder('Sensor');
	sensorWidthController = sensorFolder.add(paramsObject, 'Sensor_Width_mm', 10.0, 60.0, 0.1).onChange(() => { needsUpdate = true; });
	sensorHeightController = sensorFolder.add(paramsObject, 'Sensor_Height_mm', 10.0, 60.0, 0.1).onChange(() => { needsUpdate = true; });

		chartFolder = opticalBenchFolder.addFolder('Chart');
		chartEmissionController = chartFolder.add(paramsObject, 'Chart_Emission', 0.1, 40.0, 0.1).onChange(() => { needsUpdate = true; });

		applyLensPreset();

		opticalBenchFolder.open();
		viewFolder.open();
		sceneFolder.open();
		focusAidFolder.open();
		lensFolder.open();
		_ensureLegendOverlay();
		_setLegendVisible(paramsObject.Legend_Visible);

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

		pathTracingUniforms.uLensSurfaceCount = { value: 0 };
		pathTracingUniforms.uLensSurfaces = { value: [] };
		for (let i = 0; i < MAX_LENS_SURFACES; i++)
			pathTracingUniforms.uLensSurfaces.value.push(new THREE.Vector4());

		pathTracingUniforms.uChartZ = { value: -paramsObject.Object_Distance_mm };
		pathTracingUniforms.uChartHalfSize = { value: new THREE.Vector2(350.0, 233.3333333) };
		pathTracingUniforms.uChartEmission = { value: paramsObject.Chart_Emission };

		pathTracingUniforms.uFocusGridEnabled = { value: paramsObject.Focus_Grid_Enabled ? 1 : 0 };
		pathTracingUniforms.uFocusGridDistance = { value: paramsObject.Focus_Grid_Distance_mm };
		pathTracingUniforms.uFocusGridLines = { value: paramsObject.Focus_Grid_Lines };

		_updateLensSurfaceUniforms();

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
			_updateLensSurfaceUniforms();

			pathTracingUniforms.uChartZ.value = -paramsObject.Object_Distance_mm;
			pathTracingUniforms.uChartEmission.value = paramsObject.Chart_Emission;

		pathTracingUniforms.uFocusGridEnabled.value = paramsObject.Focus_Grid_Enabled ? 1 : 0;
		pathTracingUniforms.uFocusGridDistance.value = paramsObject.Focus_Grid_Distance_mm;
		pathTracingUniforms.uFocusGridLines.value = paramsObject.Focus_Grid_Lines;

		if (paramsObject.Legend_Visible)
			_updateLegendOverlay();

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
