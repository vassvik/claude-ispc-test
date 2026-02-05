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

## Comprehensive Review Process

When asked for a "thorough review" or "comprehensive review" of the main document, Claude should check for all of the following:

1. **Mathematical inaccuracies** — incorrect formulas, inconsistent definitions (e.g., width conventions), terminology errors
2. **Internal inconsistencies** — conflicting statements between sections, inconsistent example values, duplicated content
3. **Unsubstantiated claims** — constants without justification, assertions without derivation, vague quantifications
4. **Vagueness** — sections that are too brief, "requires care" without explaining what care, missing formulas for described operations
5. **Logical gaps** — missing derivatives, incomplete coverage of piecewise cases, claims that conflate distinct concepts
6. **Redundancy** — duplicated derivations, sections that restate other sections, content that can be consolidated
7. **Writing quality** — clunky phrasing, inconsistent tone, poor flow between sections, awkward transitions

Work through each category section by section, proposing fixes. For substantive claims (e.g., design constants, scaling behavior), provide context rather than just accepting or removing them. Ensure that the review findings themselves are self-consistent—don't flag an issue in one section that contradicts feedback in another.
