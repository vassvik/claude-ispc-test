See [README.md](README.md) for full documentation.

## Quick Build

### Prerequisites
- Visual Studio 2022 with C++ tools
- ISPC compiler (extract to project folder as `ispc-v1.30.0-windows/`)

### Build Steps

Open **Developer PowerShell for VS 2022** (search in Start menu), then:

```powershell
# ISPC compile
.\ispc-v1.30.0-windows\bin\ispc.exe raytracer.ispc -o raytracer_ispc.obj -h raytracer_ispc.h --target=avx2

# C++ compile (winmm.lib is auto-linked via #pragma)
cl /nologo /EHsc /O2 main.cpp raytracer_ispc.obj user32.lib gdi32.lib /Fe:demo.exe

# Run
.\demo.exe
```

Press **Escape** to close.

## Key Files

- `raytracer.ispc` - ISPC source (Whitted raytracer + Mandelbrot)
- `main.cpp` - Win32 window, timing, animation
- `README.md` - Full technical documentation

## GDI Top-Down Bitmap

Windows GDI with `biHeight < 0` uses row 0 as screen top. To map camera rays correctly:
- `v = (0.5 - py/height)` makes v positive at top of screen
- Positive v adds the camera's up-vector to the ray direction
- Result: top of screen shoots rays upward (toward sky)

## References

- Mandelbrot zoom target (-0.761574, -0.0847596) from [Paul Bourke](https://paulbourke.net/fractals/mandelbrot/)
