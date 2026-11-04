/*
 * Yantra mini-libc — math.h
 *
 * KEY INSIGHT: on wasm32 many libm functions are NOT library calls at all — they
 * lower directly to wasm instructions (f32/f64.sqrt, .abs, .ceil, .floor,
 * .trunc, .nearest, .min, .max, .copysign). clang exposes those as builtins and
 * emits the instruction inline. So sqrt/abs/ceil/floor/trunc/round cost nothing
 * here and are exact.
 *
 * The transcendental functions (sin/cos/exp/log/pow) have no wasm instruction and
 * would need real implementations. They are declared but implemented with simple
 * series/polynomial approximations sufficient for UI maths (transforms, easing).
 * If an app needs correctly-rounded transcendentals, that is the signal to move
 * to WASI, and this file should say so rather than pretend.
 */
#ifndef YANTRA_MATH_H
#define YANTRA_MATH_H

#ifdef __cplusplus
extern "C" {
#endif

#define HUGE_VAL (__builtin_huge_val())
#define INFINITY (__builtin_inff())
#define NAN      (__builtin_nanf(""))
#define M_PI     3.14159265358979323846
#define M_E      2.7182818284590452354

/* --- exact: lower to single wasm instructions ---------------------------- */
static inline double sqrt(double x)  { return __builtin_sqrt(x); }
static inline float  sqrtf(float x)  { return __builtin_sqrtf(x); }
static inline double fabs(double x)  { return __builtin_fabs(x); }
static inline float  fabsf(float x)  { return __builtin_fabsf(x); }
static inline float  floorf(float x) { return (float)__builtin_floor((double)x); }
static inline float  ceilf(float x)  { return (float)__builtin_ceil((double)x); }
static inline float  roundf(float x) { return (float)__builtin_round((double)x); }
static inline float  truncf(float x) { return (float)__builtin_trunc((double)x); }
static inline double ceil(double x)  { return __builtin_ceil(x); }
static inline double floor(double x) { return __builtin_floor(x); }
static inline double trunc(double x) { return __builtin_trunc(x); }
static inline double round(double x) { return __builtin_round(x); }
static inline double nearbyint(double x) { return __builtin_nearbyint(x); }
static inline double rint(double x)  { return __builtin_rint(x); }
static inline double fmin(double a, double b) { return __builtin_fmin(a, b); }
static inline double fmax(double a, double b) { return __builtin_fmax(a, b); }
static inline double copysign(double x, double y) { return __builtin_copysign(x, y); }

/* fmod is NOT a wasm instruction: clang would emit a libcall to `fmod`, i.e. to
 * itself, so __builtin_fmod here would recurse forever. It is therefore a real
 * function in minilibc.c (binary power-of-two reduction). */
double fmod(double x, double y);

/* --- approximate: no wasm instruction, see note above -------------------- */
double sin(double x);
double cos(double x);
double tan(double x);
double asin(double x);
double acos(double x);
double atan(double x);
double atan2(double y, double x);
static inline float  atan2f(float y, float x)  { return (float)atan2((double)y, (double)x); }

double exp(double x);
double log(double x);
double log2(double x);
double log10(double x);
double pow(double base, double exponent);
double sinh(double x);
double cosh(double x);
double tanh(double x);
double hypot(double x, double y);
double fmod_slow(double x, double y);

/* The float twins of the trig functions. Nim emits `cosf`/`sinf` for a
 * float32 argument, and mini-libc has no such symbols; these forward to the
 * double versions. Same reasoning as atan2f above - wasm has no instruction for
 * them either, so the real work is in minilibc.c. */
static inline float  cosf(float x)  { return (float)cos((double)x); }
static inline float  sinf(float x)  { return (float)sin((double)x); }
static inline float  tanf(float x)  { return (float)tan((double)x); }
static inline float  asinf(float x) { return (float)asin((double)x); }
static inline float  acosf(float x) { return (float)acos((double)x); }
static inline float  atanf(float x) { return (float)atan((double)x); }
static inline float  expf(float x)  { return (float)exp((double)x); }
static inline float  logf(float x)  { return (float)log((double)x); }
static inline float  powf(float x, float y) { return (float)pow((double)x, (double)y); }
static inline float  hypotf(float x, float y) { return (float)hypot((double)x, (double)y); }

#ifdef __cplusplus
}
#endif

#endif /* YANTRA_MATH_H */
