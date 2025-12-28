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
uniform int uLensSurfaceCount; // number of lens surfaces (sensor->object)
uniform vec4 uLensSurfaces[12];// (R, zVertex, iorAfter, unused)

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

#include <optical_bench_primitives>
#include <optical_bench_focus_grid>
#include <optical_bench_test_chart>
#include <optical_bench_sunset_landscape>
#include <optical_bench_lens>
#include <optical_bench_main>
