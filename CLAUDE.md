# ISPC Raytracing + Mandelbrot Demo

See [README.md](README.md) for full documentation.

## Quick Build

```powershell
# ISPC compile
.\ispc-v1.30.0-windows\bin\ispc.exe raytracer.ispc -o raytracer_ispc.obj -h raytracer_ispc.h --target=avx2

# C++ compile (VS Developer PowerShell)
cl /nologo /EHsc /O2 main.cpp raytracer_ispc.obj user32.lib gdi32.lib /Fe:demo.exe

# Run
.\demo.exe
```

Press Escape to close.

## Key Files

- `raytracer.ispc` - ISPC source (Whitted raytracer + Mandelbrot)
- `main.cpp` - Win32 window, timing, animation
- `README.md` - Full technical documentation

## GDI Top-Down Bitmap

Row 0 = screen top, so use `v = (0.5 - py/height)` to make v positive at top.

## References

- Mandelbrot zoom target (-0.761574, -0.0847596) from [Paul Bourke](https://paulbourke.net/fractals/mandelbrot/)
