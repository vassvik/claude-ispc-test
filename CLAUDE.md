# ISPC Raytracing + Mandelbrot Demo

2048x1024 window with two ISPC-rendered demos:
- **Left (1024x1024)**: Whitted raytracing (1979 classic scene)
- **Right (1024x1024)**: Animated Mandelbrot zoom

## Build

**Use PowerShell** (cmd /c doesn't capture output properly):

```powershell
# ISPC compile (no VS env needed)
cd C:\Users\mv2\Dropbox\Claude\test-ispc
.\ispc-v1.30.0-windows\bin\ispc.exe raytracer.ispc -o raytracer_ispc.obj -h raytracer_ispc.h --target=avx2

# C++ compile (needs VS env)
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -SkipAutomaticLocation
cd C:\Users\mv2\Dropbox\Claude\test-ispc
cl /nologo /EHsc /O2 main.cpp raytracer_ispc.obj user32.lib gdi32.lib /Fe:demo.exe
```

## Run

```
.\demo.exe
```

Press Escape to close.

## Title Bar Stats

Format: `Ray: X.XXms | Mandel: X.XXms | Zoom: Nx | Avg: Ray=X.XX+/-X.XX Mandel=X.XX+/-X.XX`

- Instantaneous frame times for both renderers
- Current Mandelbrot zoom level
- Rolling 1-second average with standard error

## Whitted Raytracer (Left)

Classic 1979 recursive raytracing scene:
- **Mirror sphere** (left) - pure reflection with warm tint
- **Glass sphere** (right) - refraction with Fresnel, IOR 1.52
- **Orange diffuse sphere** (front) - Lambertian + specular
- **Checkerboard floor** - with shadows and subtle reflections
- **Sky gradient** background

Features:
- Ray-sphere and ray-plane intersection
- Recursive reflection/refraction (max depth 5)
- Fresnel-Schlick approximation for glass
- Soft shadows from spheres
- Gamma correction

## Mandelbrot Zoom (Right)

Animated zoom into (-0.761574, -0.0847596):
- Exponential zoom in to 78125x, then back out, repeating
- Double precision for accuracy at deep zoom
- Adaptive iteration count (200-800 based on zoom level)
- Fire/plasma color palette with smooth coloring

## Camera Coordinate System

For GDI top-down bitmap (`biHeight < 0`, row 0 = screen top):

```
right  = cross(world_up, forward)   // camera's right vector
cam_up = cross(forward, right)      // camera's up vector

u = (px/width - 0.5) * aspect * fov // left=-0.5, right=+0.5
v = (0.5 - py/height) * fov         // top=+0.5, bottom=-0.5
```

Key insight: `v = (0.5 - py/height)` because py=0 is screen TOP in GDI, so v must be POSITIVE there to shoot rays upward.

## Files

| File | Description |
|------|-------------|
| `raytracer.ispc` | ISPC source for both renderers |
| `main.cpp` | Window, timing, animation loop |
| `raytracer_ispc.h` | Auto-generated header |
| `raytracer_v1.ispc` | Backup of first working version |
| `main_v1.cpp` | Backup of first working version |

## Performance

Typical on modern CPU:
- Raytracer: ~40ms/frame
- Mandelbrot: ~110-130ms/frame (varies with zoom/iteration count)
