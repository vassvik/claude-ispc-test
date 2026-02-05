# ISPC Raytracing + Mandelbrot Demo

A real-time demonstration of two computationally intensive graphics algorithms implemented in [ISPC](https://ispc.github.io/) (Intel SPMD Program Compiler):

- **Left**: Whitted Raytracing (1979 classic scene)
- **Right**: Animated Mandelbrot zoom

![Demo Screenshot](screenshot_final.png)

*2048x1024 window running at ~40ms raytracer + ~90ms Mandelbrot per frame on AVX2*

---

## Quick Start

### Prerequisites
- Windows 10/11
- Visual Studio 2022 (for `cl.exe`)
- [ISPC compiler](https://ispc.github.io/downloads.html) (extract to project folder as `ispc-v1.30.0-windows/`)

### Build (PowerShell)

```powershell
# ISPC compile
.\ispc-v1.30.0-windows\bin\ispc.exe raytracer.ispc -o raytracer_ispc.obj -h raytracer_ispc.h --target=avx2

# C++ compile (run from VS Developer PowerShell)
cl /nologo /EHsc /O2 main.cpp raytracer_ispc.obj user32.lib gdi32.lib /Fe:demo.exe
```

### Run

```
.\demo.exe
```

Press **Escape** to close.

---

## ISPC Parallelization

### What is ISPC?

ISPC is a compiler for a variant of C that generates highly efficient SIMD code. It uses the **SPMD** (Single Program, Multiple Data) model: you write scalar-looking code, and ISPC compiles it to run across SIMD lanes.

### The `foreach` Construct

The key to ISPC's parallelization is `foreach`, which distributes iterations across SIMD lanes:

```c
foreach (py = 0 ... height, px = 0 ... width) {
    // This body executes for 8 pixels simultaneously on AVX2
    // (4 on SSE, 16 on AVX-512)
    Vec3 color = trace_ray(ray, depth);
    pixels[py * width + px] = pack_color(color);
}
```

On AVX2, each iteration processes **8 pixels in parallel** using 256-bit SIMD registers.

### Uniform vs Varying

ISPC distinguishes between:

| Type | Description | Example |
|------|-------------|---------|
| `uniform` | Same value across all SIMD lanes | Image dimensions, time, constants |
| `varying` | Different value per lane | Pixel coordinates, ray directions, colors |

```c
export void render_whitted(
    uniform uint32 pixels[],    // uniform: one pointer for all lanes
    uniform int width,          // uniform: shared by all lanes
    uniform int height,
    uniform float time
) {
    uniform float fov = 1.0f;   // uniform: same for all pixels

    foreach (py = 0 ... height, px = 0 ... width) {
        float u = (float)px / width;   // varying: different per pixel
        float v = (float)py / height;  // varying: different per pixel
        Vec3 color = trace_ray(...);   // varying: different result per pixel
    }
}
```

The compiler automatically:
- Keeps `uniform` values in scalar registers
- Spreads `varying` values across SIMD lanes
- Generates masked operations for divergent control flow

### ISPC-Specific Optimizations in This Code

#### 1. Struct-of-Arrays for Vector Math

ISPC handles structs efficiently, but our `Vec3` struct naturally maps to SIMD:

```c
struct Vec3 {
    float x, y, z;  // Each becomes a varying (8 floats on AVX2)
};
```

When you have 8 rays in flight, `color.x` holds 8 x-components, `color.y` holds 8 y-components, etc.

#### 2. Inline Everything

All helper functions are `inline`, eliminating function call overhead and enabling the compiler to optimize across function boundaries:

```c
inline Vec3 vec3_add(Vec3 a, Vec3 b) {
    return make_vec3(a.x + b.x, a.y + b.y, a.z + b.z);
}
```

#### 3. Uniform Loop-Invariant Values

Scene constants are declared `static const uniform` to ensure they're computed once and shared:

```c
static const uniform float sphere1_x = -0.8f;
static const uniform float sphere1_y = 1.0f;
// ...
```

#### 4. Avoiding Divergent Branches Where Possible

The raytracer has inherent divergence (different rays hit different objects), but we minimize it by:
- Testing all objects for all rays (no early-out that would cause divergence)
- Using the same recursion depth for all rays
- Letting ISPC's masked execution handle material-specific shading

#### 5. Double Precision for Mandelbrot

ISPC supports `double` for when precision matters:

```c
foreach (py = 0 ... height, px = 0 ... width) {
    double x0 = center_x + ((double)px - (double)width * 0.5) * scale;
    double y0 = center_y + ((double)py - (double)height * 0.5) * scale;

    double x = 0.0, y = 0.0;
    double x2 = 0.0, y2 = 0.0;  // Cache squares to avoid redundant muls
    // ...
}
```

AVX2 provides 4-wide double SIMD (vs 8-wide float), so Mandelbrot runs at half the parallelism but with full 64-bit precision.

#### 6. Cached Squares in Mandelbrot Loop

Instead of computing `x*x` and `y*y` multiple times:

```c
// Naive (6 multiplications per iteration)
while (x*x + y*y <= 4.0) {
    double xtemp = x*x - y*y + x0;
    y = 2*x*y + y0;
    x = xtemp;
}

// Optimized (4 multiplications per iteration)
while (x2 + y2 <= 4.0) {
    y = 2.0 * x * y + y0;
    x = x2 - y2 + x0;
    x2 = x * x;
    y2 = y * y;
}
```

### Performance Characteristics

| Renderer | Time/Frame | SIMD Width | Notes |
|----------|------------|------------|-------|
| Raytracer | ~40ms | 8 (float) | Limited by recursion, divergent branches |
| Mandelbrot | ~90ms | 4 (double) | Limited by iteration count, double precision |

The raytracer is faster despite being more complex because:
1. Float (8-wide) vs double (4-wide) SIMD
2. Fixed recursion depth (5) vs variable iterations (200-800)
3. Most rays hit geometry quickly; many Mandelbrot points iterate to max

### Compiling for Different Targets

```powershell
# SSE4 (128-bit, 4-wide float)
.\ispc.exe raytracer.ispc -o raytracer_ispc.obj --target=sse4-i32x4

# AVX2 (256-bit, 8-wide float) - default for modern CPUs
.\ispc.exe raytracer.ispc -o raytracer_ispc.obj --target=avx2-i32x8

# AVX-512 (512-bit, 16-wide float) - for Xeon/Ice Lake+
.\ispc.exe raytracer.ispc -o raytracer_ispc.obj --target=avx512skx-i32x16
```

---

## Whitted Raytracing

### Historical Context

Turner Whitted's 1980 paper *"An Improved Illumination Model for Shaded Display"* introduced **recursive raytracing**. The iconic image featured spheres on a checkerboard - one reflective, one refractive - which became the "hello world" of raytracing.

**Reference:** Whitted, T. (1980). "An Improved Illumination Model for Shaded Display." *Communications of the ACM*, 23(6), 343-349.

### Scene Setup

| Object | Position | Properties |
|--------|----------|------------|
| Mirror sphere | (-0.8, 1.0, 1.0), r=1.0 | Pure reflection, warm tint |
| Glass sphere | (1.2, 0.6, 0.0), r=0.6 | IOR 1.52, Fresnel reflection/refraction |
| Orange sphere | (-0.2, 0.3, -0.8), r=0.3 | Diffuse + specular |
| Floor | y = 0 | Checkerboard, 15% reflective |
| Light | (8, 12, -4) | Point light |
| Camera | (0.5, 2.0, -4.5) | Looking at (0.2, 0.5, 1.0) |

### Features

- **Ray-sphere/plane intersection** - Quadratic formula for spheres
- **Recursive reflection** (depth 5) - Mirror surfaces
- **Refraction with Fresnel** - Schlick approximation for glass
- **Shadows** - Shadow rays to light source
- **Gamma correction** - sqrt() for proper display

---

## Mandelbrot Set

### The Algorithm

The Mandelbrot set is points `c` where `z_{n+1} = z_n² + c` (starting from `z_0 = 0`) remains bounded.

### Smooth Coloring

We use continuous potential for smooth gradients instead of banded colors:

```c
double log_zn = log(x2 + y2) * 0.5;
double nu = log(log_zn / log(2)) / log(2);
double smooth_iter = iter + 1.0 - nu;
```

### Zoom Animation

Zooms into (-0.761574, -0.0847596), a point on the boundary with infinite detail:
- Exponential zoom: 2% per frame
- Range: 1x to 78125x and back
- Adaptive iterations: 200 at 1x, up to 800 at max zoom

---

## GDI Coordinate System

Windows GDI with top-down DIB (`biHeight < 0`) has row 0 at the top. For correct orientation:

```c
// Camera basis (right-handed)
right  = cross(world_up, forward)
cam_up = cross(forward, right)

// Pixel mapping - note (0.5 - py/height) not (py/height - 0.5)
u = (px/width - 0.5) * aspect * fov    // -0.5 left, +0.5 right
v = (0.5 - py/height) * fov            // +0.5 top, -0.5 bottom
```

Since `py=0` is the screen TOP, `v` must be positive there to shoot rays upward.

---

## Development Screenshots

### Version 1 (Upside Down)
![Version 1](screenshot_v1.png)
*Camera coordinate bug - sky at bottom*

### Version 2 (Fixed)
![Version 2](screenshot_v2.png)
*Correct orientation after fixing camera basis vectors*

---

## File Structure

```
├── raytracer.ispc      # ISPC source (raytracer + Mandelbrot)
├── main.cpp            # Win32 window, timing, animation loop
├── raytracer_v1.ispc   # Backup of first working version
├── main_v1.cpp         # Backup of first working version
├── screenshot_*.png    # Screenshots for documentation
├── CLAUDE.md           # Brief build instructions
└── README.md           # This file
```

---

## References

1. Whitted, T. (1980). "An Improved Illumination Model for Shaded Display." *Communications of the ACM*, 23(6), 343-349.

2. Schlick, C. (1994). "An Inexpensive BRDF Model for Physically-based Rendering." *Computer Graphics Forum*, 13(3), 233-246.

3. Pharr, M., Jakob, W., & Humphreys, G. (2016). *Physically Based Rendering* (3rd ed.). Morgan Kaufmann.

4. Intel ISPC User's Guide. https://ispc.github.io/ispc.html

---

## License

Public domain / CC0. Do whatever you want with it.
