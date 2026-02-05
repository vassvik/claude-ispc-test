#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <math.h>
#include <timeapi.h>
#include "raytracer_ispc.h"

#pragma comment(lib, "winmm.lib")

const int HALF_WIDTH = 1024;
const int HEIGHT = 1024;
const int FULL_WIDTH = HALF_WIDTH * 2;
const int NUM_PIXELS = HALF_WIDTH * HEIGHT;

uint32_t pixels_ray[NUM_PIXELS];
uint32_t pixels_mandel[NUM_PIXELS];

BITMAPINFO bmi = {};

struct Stats {
    double sum = 0, sum_sq = 0;
    int count = 0;
    double mean = 0, stddev = 0, stderr_ = 0;

    void add(double v) {
        sum += v;
        sum_sq += v * v;
        count++;
    }

    void compute() {
        if (count > 0) {
            mean = sum / count;
            double variance = (sum_sq / count) - (mean * mean);
            stddev = sqrt(variance > 0 ? variance : 0);
            stderr_ = stddev / sqrt((double)count);
        }
    }

    void reset() {
        sum = sum_sq = mean = stddev = stderr_ = 0;
        count = 0;
    }
};

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hwnd, &ps);
            SetDIBitsToDevice(hdc, 0, 0, HALF_WIDTH, HEIGHT, 0, 0, 0, HEIGHT, pixels_ray, &bmi, DIB_RGB_COLORS);
            SetDIBitsToDevice(hdc, HALF_WIDTH, 0, HALF_WIDTH, HEIGHT, 0, 0, 0, HEIGHT, pixels_mandel, &bmi, DIB_RGB_COLORS);
            EndPaint(hwnd, &ps);
            return 0;
        }
        case WM_KEYDOWN:
            if (wParam == VK_ESCAPE) PostQuitMessage(0);
            return 0;
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProc(hwnd, msg, wParam, lParam);
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE, LPSTR, int nCmdShow) {
    timeBeginPeriod(1);

    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = HALF_WIDTH;
    bmi.bmiHeader.biHeight = -HEIGHT;
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    WNDCLASS wc = {};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = "RayMandel";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClass(&wc);

    RECT rect = {0, 0, FULL_WIDTH, HEIGHT};
    AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, FALSE);

    HWND hwnd = CreateWindow("RayMandel", "Raytracer | Mandelbrot", WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, rect.right - rect.left, rect.bottom - rect.top,
        NULL, NULL, hInstance, NULL);

    ShowWindow(hwnd, nCmdShow);

    LARGE_INTEGER freq, start, end, last_stats_time;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&last_stats_time);

    MSG msg;
    bool running = true;

    Stats ray_stats, mandel_stats;
    char title[256] = "Collecting...";
    char stats_str[128] = "";

    // Mandelbrot zoom parameters
    // Target: (-0.761574, -0.0847596) - interesting boundary point (Misiurewicz point)
    const double mandel_target_x = -0.761574;
    const double mandel_target_y = -0.0847596;
    double zoom = 1.0;
    double zoom_speed = 1.02;  // Exponential zoom factor per frame
    // Max zoom = 5^7 = 78125x; beyond this, double precision artifacts appear
    double max_zoom = 78125.0;
    bool zooming_in = true;

    while (running) {
        while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) running = false;
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        if (!running) break;

        // Render Whitted raytracer (static scene)
        QueryPerformanceCounter(&start);
        ispc::render_whitted(pixels_ray, HALF_WIDTH, HEIGHT);
        QueryPerformanceCounter(&end);
        double ray_ms = (end.QuadPart - start.QuadPart) * 1000.0 / freq.QuadPart;
        ray_stats.add(ray_ms);

        // Update zoom
        if (zooming_in) {
            zoom *= zoom_speed;
            if (zoom >= max_zoom) {
                zoom = max_zoom;
                zooming_in = false;
            }
        } else {
            zoom /= zoom_speed;
            if (zoom <= 1.0) {
                zoom = 1.0;
                zooming_in = true;
            }
        }

        // Render Mandelbrot
        QueryPerformanceCounter(&start);
        ispc::render_mandelbrot(pixels_mandel, HALF_WIDTH, HEIGHT, mandel_target_x, mandel_target_y, zoom);
        QueryPerformanceCounter(&end);
        double mandel_ms = (end.QuadPart - start.QuadPart) * 1000.0 / freq.QuadPart;
        mandel_stats.add(mandel_ms);

        // Blit both halves
        HDC hdc = GetDC(hwnd);
        SetDIBitsToDevice(hdc, 0, 0, HALF_WIDTH, HEIGHT, 0, 0, 0, HEIGHT, pixels_ray, &bmi, DIB_RGB_COLORS);
        SetDIBitsToDevice(hdc, HALF_WIDTH, 0, HALF_WIDTH, HEIGHT, 0, 0, 0, HEIGHT, pixels_mandel, &bmi, DIB_RGB_COLORS);
        ReleaseDC(hwnd, hdc);

        // Update stats every second
        LARGE_INTEGER now;
        QueryPerformanceCounter(&now);
        double elapsed = (now.QuadPart - last_stats_time.QuadPart) * 1000.0 / freq.QuadPart;

        if (elapsed >= 1000.0) {
            ray_stats.compute();
            mandel_stats.compute();

            snprintf(stats_str, sizeof(stats_str), "| Avg: Ray=%.2f+/-%.2f Mandel=%.2f+/-%.2f",
                ray_stats.mean, ray_stats.stderr_,
                mandel_stats.mean, mandel_stats.stderr_);

            ray_stats.reset();
            mandel_stats.reset();
            last_stats_time = now;
        }

        // Title bar: instantaneous + accumulated
        snprintf(title, sizeof(title), "Ray: %.2fms | Mandel: %.2fms | Zoom: %.0fx %s",
            ray_ms, mandel_ms, zoom, stats_str);
        SetWindowText(hwnd, title);
    }

    timeEndPeriod(1);
    return 0;
}
