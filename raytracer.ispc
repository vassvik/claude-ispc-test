// Whitted Raytracing (1979) + Mandelbrot Zoom Demo - v2
// Fixed orientation, optimized Mandelbrot, improved scene

// ============================================================================
// Vector math utilities
// ============================================================================

struct Vec3 {
    float x, y, z;
};

inline Vec3 make_vec3(float x, float y, float z) {
    Vec3 v;
    v.x = x; v.y = y; v.z = z;
    return v;
}

inline Vec3 vec3_add(Vec3 a, Vec3 b) {
    return make_vec3(a.x + b.x, a.y + b.y, a.z + b.z);
}

inline Vec3 vec3_sub(Vec3 a, Vec3 b) {
    return make_vec3(a.x - b.x, a.y - b.y, a.z - b.z);
}

inline Vec3 vec3_mul(Vec3 a, float s) {
    return make_vec3(a.x * s, a.y * s, a.z * s);
}

inline Vec3 vec3_mul_vec(Vec3 a, Vec3 b) {
    return make_vec3(a.x * b.x, a.y * b.y, a.z * b.z);
}

inline float vec3_dot(Vec3 a, Vec3 b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

inline float vec3_length(Vec3 v) {
    return sqrt(vec3_dot(v, v));
}

inline Vec3 vec3_normalize(Vec3 v) {
    float len = vec3_length(v);
    if (len > 0.0001f) {
        return vec3_mul(v, 1.0f / len);
    }
    return v;
}

inline Vec3 vec3_reflect(Vec3 v, Vec3 n) {
    return vec3_sub(v, vec3_mul(n, 2.0f * vec3_dot(v, n)));
}

inline Vec3 vec3_lerp(Vec3 a, Vec3 b, float t) {
    return vec3_add(vec3_mul(a, 1.0f - t), vec3_mul(b, t));
}

inline Vec3 vec3_cross(Vec3 a, Vec3 b) {
    return make_vec3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    );
}

// ============================================================================
// Ray structure
// ============================================================================

struct Ray {
    Vec3 origin;
    Vec3 dir;
};

inline Ray make_ray(Vec3 origin, Vec3 dir) {
    Ray r;
    r.origin = origin;
    r.dir = dir;
    return r;
}

inline Vec3 ray_at(Ray r, float t) {
    return vec3_add(r.origin, vec3_mul(r.dir, t));
}

// ============================================================================
// Scene definition - Classic Whitted 1979 setup
// ============================================================================

// Sphere 1: Reflective (mirror) - larger, on the left
static const uniform float sphere1_x = -0.8f;
static const uniform float sphere1_y = 1.0f;
static const uniform float sphere1_z = 1.0f;
static const uniform float sphere1_radius = 1.0f;

// Sphere 2: Refractive (glass) - smaller, on the right
static const uniform float sphere2_x = 1.2f;
static const uniform float sphere2_y = 0.6f;
static const uniform float sphere2_z = 0.0f;
static const uniform float sphere2_radius = 0.6f;

// Sphere 3: Small colored diffuse sphere
static const uniform float sphere3_x = -0.2f;
static const uniform float sphere3_y = 0.3f;
static const uniform float sphere3_z = -0.8f;
static const uniform float sphere3_radius = 0.3f;

// Light position - high and to the right
static const uniform float light_x = 8.0f;
static const uniform float light_y = 12.0f;
static const uniform float light_z = -4.0f;

// Checkerboard floor at y = 0
static const uniform float floor_y = 0.0f;

// ============================================================================
// Ray-sphere intersection
// ============================================================================

inline float intersect_sphere(Ray r, Vec3 center, float radius) {
    Vec3 oc = vec3_sub(r.origin, center);
    float a = vec3_dot(r.dir, r.dir);
    float b = 2.0f * vec3_dot(oc, r.dir);
    float c = vec3_dot(oc, oc) - radius * radius;
    float discriminant = b * b - 4.0f * a * c;

    if (discriminant < 0.0f) return -1.0f;

    float t = (-b - sqrt(discriminant)) / (2.0f * a);
    if (t > 0.001f) return t;

    t = (-b + sqrt(discriminant)) / (2.0f * a);
    if (t > 0.001f) return t;

    return -1.0f;
}

// ============================================================================
// Ray-plane intersection (floor)
// ============================================================================

inline float intersect_floor(Ray r) {
    if (abs(r.dir.y) < 0.0001f) return -1.0f;
    float t = (floor_y - r.origin.y) / r.dir.y;
    return (t > 0.001f) ? t : -1.0f;
}

// ============================================================================
// Checkerboard pattern - larger squares
// ============================================================================

inline Vec3 checkerboard_color(Vec3 p) {
    float scale = 1.5f;  // Larger squares
    int cx = (int)floor(p.x / scale);
    int cz = (int)floor(p.z / scale);
    if (p.x < 0) cx--;
    if (p.z < 0) cz--;

    if ((cx + cz) & 1) {
        return make_vec3(0.95f, 0.95f, 0.95f);  // White
    } else {
        return make_vec3(0.2f, 0.2f, 0.25f);    // Dark blue-gray
    }
}

// ============================================================================
// Fresnel reflectance (Schlick approximation)
// ============================================================================

inline float fresnel_schlick(float cos_theta, float n1, float n2) {
    float r0 = (n1 - n2) / (n1 + n2);
    r0 = r0 * r0;
    float x = 1.0f - cos_theta;
    return r0 + (1.0f - r0) * x * x * x * x * x;
}

// ============================================================================
// Refraction (Snell's law)
// ============================================================================

inline bool refract(Vec3 v, Vec3 n, float ni_over_nt, Vec3 &refracted) {
    Vec3 uv = vec3_normalize(v);
    float dt = vec3_dot(uv, n);
    float discriminant = 1.0f - ni_over_nt * ni_over_nt * (1.0f - dt * dt);

    if (discriminant > 0.0f) {
        refracted = vec3_sub(
            vec3_mul(vec3_sub(uv, vec3_mul(n, dt)), ni_over_nt),
            vec3_mul(n, sqrt(discriminant))
        );
        return true;
    }
    return false;
}

// ============================================================================
// Main raytracing function with recursion
// ============================================================================

inline Vec3 trace_ray(Ray r, int depth);

inline Vec3 shade_hit(Ray r, float t, int hit_type, int depth) {
    Vec3 hit_point = ray_at(r, t);
    Vec3 light_pos = make_vec3(light_x, light_y, light_z);
    Vec3 to_light = vec3_normalize(vec3_sub(light_pos, hit_point));
    Vec3 view_dir = vec3_mul(r.dir, -1.0f);

    Vec3 color = make_vec3(0.0f, 0.0f, 0.0f);
    Vec3 normal;

    // Sphere centers for shadow tests
    Vec3 s1_center = make_vec3(sphere1_x, sphere1_y, sphere1_z);
    Vec3 s2_center = make_vec3(sphere2_x, sphere2_y, sphere2_z);
    Vec3 s3_center = make_vec3(sphere3_x, sphere3_y, sphere3_z);

    if (hit_type == 0) {
        // Floor
        normal = make_vec3(0.0f, 1.0f, 0.0f);
        Vec3 base_color = checkerboard_color(hit_point);

        // Shadow check
        Ray shadow_ray = make_ray(vec3_add(hit_point, vec3_mul(normal, 0.001f)), to_light);
        float shadow = 1.0f;

        if (intersect_sphere(shadow_ray, s1_center, sphere1_radius) > 0.0f) shadow = 0.25f;
        else if (intersect_sphere(shadow_ray, s2_center, sphere2_radius) > 0.0f) shadow = 0.6f;
        else if (intersect_sphere(shadow_ray, s3_center, sphere3_radius) > 0.0f) shadow = 0.35f;

        float diffuse = max(0.0f, vec3_dot(normal, to_light));
        color = vec3_mul(base_color, (0.15f + 0.85f * diffuse * shadow));

        // Subtle reflection on floor
        if (depth > 0) {
            Vec3 reflect_dir = vec3_reflect(r.dir, normal);
            Ray reflect_ray = make_ray(vec3_add(hit_point, vec3_mul(normal, 0.001f)), reflect_dir);
            Vec3 reflect_color = trace_ray(reflect_ray, depth - 1);
            color = vec3_lerp(color, reflect_color, 0.15f);
        }
    }
    else if (hit_type == 1) {
        // Mirror sphere - pure reflection with slight tint
        normal = vec3_normalize(vec3_sub(hit_point, s1_center));

        if (depth > 0) {
            Vec3 reflect_dir = vec3_reflect(r.dir, normal);
            Ray reflect_ray = make_ray(vec3_add(hit_point, vec3_mul(normal, 0.001f)), reflect_dir);
            color = trace_ray(reflect_ray, depth - 1);
            // Slight warm tint to mirror
            color = vec3_mul_vec(color, make_vec3(1.0f, 0.98f, 0.95f));
        }

        // Specular highlight
        Vec3 half_vec = vec3_normalize(vec3_add(to_light, view_dir));
        float spec = pow(max(0.0f, vec3_dot(normal, half_vec)), 80.0f);
        color = vec3_add(color, make_vec3(spec, spec, spec));
    }
    else if (hit_type == 2) {
        // Glass sphere (refractive)
        normal = vec3_normalize(vec3_sub(hit_point, s2_center));

        float n1 = 1.0f;   // Air
        float n2 = 1.52f;  // Crown glass
        float ni_over_nt;
        Vec3 outward_normal;
        float cos_theta;

        if (vec3_dot(r.dir, normal) > 0.0f) {
            outward_normal = vec3_mul(normal, -1.0f);
            ni_over_nt = n2 / n1;
            cos_theta = vec3_dot(r.dir, normal) / vec3_length(r.dir);
        } else {
            outward_normal = normal;
            ni_over_nt = n1 / n2;
            cos_theta = -vec3_dot(r.dir, normal) / vec3_length(r.dir);
        }

        float reflect_prob = fresnel_schlick(cos_theta, n1, n2);

        if (depth > 0) {
            Vec3 refracted;
            Vec3 reflect_dir = vec3_reflect(r.dir, outward_normal);
            Ray reflect_ray = make_ray(vec3_add(hit_point, vec3_mul(outward_normal, 0.001f)), reflect_dir);
            Vec3 reflect_color = trace_ray(reflect_ray, depth - 1);

            if (refract(r.dir, outward_normal, ni_over_nt, refracted)) {
                Ray refract_ray = make_ray(vec3_sub(hit_point, vec3_mul(outward_normal, 0.001f)), refracted);
                Vec3 refract_color = trace_ray(refract_ray, depth - 1);
                color = vec3_lerp(refract_color, reflect_color, reflect_prob);
            } else {
                color = reflect_color;
            }
        }

        // Slight cyan tint for glass
        color = vec3_mul_vec(color, make_vec3(0.95f, 0.98f, 1.0f));
    }
    else if (hit_type == 3) {
        // Small diffuse sphere - red/orange
        normal = vec3_normalize(vec3_sub(hit_point, s3_center));
        Vec3 base_color = make_vec3(0.9f, 0.3f, 0.1f);  // Orange-red

        // Shadow check
        Ray shadow_ray = make_ray(vec3_add(hit_point, vec3_mul(normal, 0.001f)), to_light);
        float shadow = 1.0f;
        if (intersect_sphere(shadow_ray, s1_center, sphere1_radius) > 0.0f) shadow = 0.3f;
        if (intersect_sphere(shadow_ray, s2_center, sphere2_radius) > 0.0f) shadow = 0.6f;

        float diffuse = max(0.0f, vec3_dot(normal, to_light));
        color = vec3_mul(base_color, (0.2f + 0.8f * diffuse * shadow));

        // Specular
        Vec3 half_vec = vec3_normalize(vec3_add(to_light, view_dir));
        float spec = pow(max(0.0f, vec3_dot(normal, half_vec)), 30.0f) * 0.5f;
        color = vec3_add(color, make_vec3(spec, spec, spec));
    }

    return color;
}

inline Vec3 trace_ray(Ray r, int depth) {
    float closest_t = 1e10f;
    int hit_type = -1;

    // Check floor
    float t_floor = intersect_floor(r);
    if (t_floor > 0.0f && t_floor < closest_t) {
        Vec3 p = ray_at(r, t_floor);
        if (p.x > -15.0f && p.x < 15.0f && p.z > -3.0f && p.z < 25.0f) {
            closest_t = t_floor;
            hit_type = 0;
        }
    }

    // Check sphere 1 (mirror)
    Vec3 s1_center = make_vec3(sphere1_x, sphere1_y, sphere1_z);
    float t1 = intersect_sphere(r, s1_center, sphere1_radius);
    if (t1 > 0.0f && t1 < closest_t) {
        closest_t = t1;
        hit_type = 1;
    }

    // Check sphere 2 (glass)
    Vec3 s2_center = make_vec3(sphere2_x, sphere2_y, sphere2_z);
    float t2 = intersect_sphere(r, s2_center, sphere2_radius);
    if (t2 > 0.0f && t2 < closest_t) {
        closest_t = t2;
        hit_type = 2;
    }

    // Check sphere 3 (diffuse)
    Vec3 s3_center = make_vec3(sphere3_x, sphere3_y, sphere3_z);
    float t3 = intersect_sphere(r, s3_center, sphere3_radius);
    if (t3 > 0.0f && t3 < closest_t) {
        closest_t = t3;
        hit_type = 3;
    }

    if (hit_type >= 0) {
        return shade_hit(r, closest_t, hit_type, depth);
    }

    // Sky gradient - nice blue gradient
    float sky_t = 0.5f * (r.dir.y + 1.0f);
    sky_t = clamp(sky_t, 0.0f, 1.0f);
    Vec3 sky_bottom = make_vec3(0.6f, 0.75f, 0.9f);
    Vec3 sky_top = make_vec3(0.25f, 0.4f, 0.7f);
    return vec3_lerp(sky_bottom, sky_top, sky_t);
}

// ============================================================================
// Whitted Raytracer Entry Point
// ============================================================================

export void render_whitted(uniform uint32 pixels[], uniform int width, uniform int height, uniform float time) {
    // Camera setup - classic Whitted angle
    uniform Vec3 camera_pos = {0.5f, 2.0f, -4.5f};
    uniform Vec3 look_at = {0.2f, 0.5f, 1.0f};
    uniform Vec3 world_up = {0.0f, 1.0f, 0.0f};

    uniform float fov = 1.0f;  // Field of view
    uniform float aspect = (float)width / (float)height;

    // Camera basis vectors
    uniform Vec3 forward = {
        look_at.x - camera_pos.x,
        look_at.y - camera_pos.y,
        look_at.z - camera_pos.z
    };
    uniform float fwd_len = sqrt(forward.x*forward.x + forward.y*forward.y + forward.z*forward.z);
    forward.x /= fwd_len; forward.y /= fwd_len; forward.z /= fwd_len;

    // Camera basis vectors (right-handed coordinate system)
    // right = cross(world_up, forward) → points to camera's right
    uniform Vec3 right = {
        world_up.y * forward.z - world_up.z * forward.y,
        world_up.z * forward.x - world_up.x * forward.z,
        world_up.x * forward.y - world_up.y * forward.x
    };
    uniform float right_len = sqrt(right.x*right.x + right.y*right.y + right.z*right.z);
    right.x /= right_len; right.y /= right_len; right.z /= right_len;

    // cam_up = cross(forward, right) → points to camera's up
    uniform Vec3 cam_up = {
        forward.y * right.z - forward.z * right.y,
        forward.z * right.x - forward.x * right.z,
        forward.x * right.y - forward.y * right.x
    };

    foreach (py = 0 ... height, px = 0 ... width) {
        // UV mapping for GDI top-down bitmap (py=0 is screen top)
        // u: -0.5 at left edge, +0.5 at right edge
        // v: +0.5 at top edge (py=0), -0.5 at bottom edge
        // This ensures top of screen shoots rays UP (positive cam_up)
        float u = ((float)px / (float)width - 0.5f) * aspect * fov;
        float v = (0.5f - (float)py / (float)height) * fov;

        Vec3 ray_dir = make_vec3(
            forward.x + right.x * u + cam_up.x * v,
            forward.y + right.y * u + cam_up.y * v,
            forward.z + right.z * u + cam_up.z * v
        );
        ray_dir = vec3_normalize(ray_dir);

        Ray r = make_ray(make_vec3(camera_pos.x, camera_pos.y, camera_pos.z), ray_dir);
        Vec3 color = trace_ray(r, 5);

        // Gamma correction (approximate)
        color.x = sqrt(color.x);
        color.y = sqrt(color.y);
        color.z = sqrt(color.z);

        // Clamp and convert to uint32
        uint8 rb = (uint8)(clamp(color.x, 0.0f, 1.0f) * 255.0f);
        uint8 gb = (uint8)(clamp(color.y, 0.0f, 1.0f) * 255.0f);
        uint8 bb = (uint8)(clamp(color.z, 0.0f, 1.0f) * 255.0f);

        pixels[py * width + px] = (uint32)bb | ((uint32)gb << 8) | ((uint32)rb << 16) | 0xFF000000u;
    }
}

// ============================================================================
// Mandelbrot Set Renderer - Optimized
// ============================================================================

inline Vec3 hsv_to_rgb(float h, float s, float v) {
    float c = v * s;
    float hh = h * 6.0f;
    float x = c * (1.0f - abs(hh - 2.0f * floor(hh * 0.5f) - 1.0f));
    float m = v - c;

    float r1, g1, b1;
    int hi = (int)hh;
    if (hi < 0) hi = 0;
    if (hi > 5) hi = 5;

    if (hi == 0)      { r1 = c; g1 = x; b1 = 0; }
    else if (hi == 1) { r1 = x; g1 = c; b1 = 0; }
    else if (hi == 2) { r1 = 0; g1 = c; b1 = x; }
    else if (hi == 3) { r1 = 0; g1 = x; b1 = c; }
    else if (hi == 4) { r1 = x; g1 = 0; b1 = c; }
    else              { r1 = c; g1 = 0; b1 = x; }

    return make_vec3(r1 + m, g1 + m, b1 + m);
}

// Fire/plasma color palette - more vibrant
inline Vec3 palette(float t) {
    // Attempt a nice fire-like palette
    t = clamp(t, 0.0f, 1.0f);

    // Dark blue -> blue -> cyan -> yellow -> orange -> red -> dark
    Vec3 c;
    if (t < 0.16f) {
        float s = t / 0.16f;
        c = vec3_lerp(make_vec3(0.0f, 0.0f, 0.1f), make_vec3(0.1f, 0.1f, 0.4f), s);
    } else if (t < 0.33f) {
        float s = (t - 0.16f) / 0.17f;
        c = vec3_lerp(make_vec3(0.1f, 0.1f, 0.4f), make_vec3(0.2f, 0.5f, 0.8f), s);
    } else if (t < 0.5f) {
        float s = (t - 0.33f) / 0.17f;
        c = vec3_lerp(make_vec3(0.2f, 0.5f, 0.8f), make_vec3(0.9f, 0.9f, 0.2f), s);
    } else if (t < 0.67f) {
        float s = (t - 0.5f) / 0.17f;
        c = vec3_lerp(make_vec3(0.9f, 0.9f, 0.2f), make_vec3(1.0f, 0.5f, 0.0f), s);
    } else if (t < 0.83f) {
        float s = (t - 0.67f) / 0.16f;
        c = vec3_lerp(make_vec3(1.0f, 0.5f, 0.0f), make_vec3(0.8f, 0.1f, 0.1f), s);
    } else {
        float s = (t - 0.83f) / 0.17f;
        c = vec3_lerp(make_vec3(0.8f, 0.1f, 0.1f), make_vec3(0.2f, 0.0f, 0.0f), s);
    }
    return c;
}

export void render_mandelbrot(uniform uint32 pixels[], uniform int width, uniform int height,
                              uniform double center_x, uniform double center_y, uniform double zoom) {
    // Adaptive iterations based on zoom - fewer at low zoom for speed
    uniform int max_iter = 200 + (int)(100.0 * log(zoom + 1.0));
    if (max_iter > 800) max_iter = 800;

    uniform double scale = 2.5 / (zoom * (double)height);

    foreach (py = 0 ... height, px = 0 ... width) {
        double x0 = center_x + ((double)px - (double)width * 0.5) * scale;
        double y0 = center_y + ((double)py - (double)height * 0.5) * scale;

        double x = 0.0;
        double y = 0.0;
        double x2 = 0.0;
        double y2 = 0.0;
        int iter = 0;

        // Optimized iteration with cached squares
        while (x2 + y2 <= 4.0 && iter < max_iter) {
            y = 2.0 * x * y + y0;
            x = x2 - y2 + x0;
            x2 = x * x;
            y2 = y * y;
            iter++;
        }

        uint32 color;
        if (iter == max_iter) {
            color = 0xFF000000u;  // Black for points in set
        } else {
            // Smooth coloring
            double log_zn = log(x2 + y2) * 0.5;
            double nu = log(log_zn * 1.4426950408889634) * 1.4426950408889634;  // log2 constants
            double smooth_iter = (double)iter + 1.0 - nu;
            if (smooth_iter < 0.0) smooth_iter = 0.0;

            // Map to color palette
            float t = (float)(smooth_iter * 0.015);
            t = t - floor(t);  // Wrap to 0-1

            Vec3 rgb = palette(t);

            uint8 rb = (uint8)(clamp(rgb.x, 0.0f, 1.0f) * 255.0f);
            uint8 gb = (uint8)(clamp(rgb.y, 0.0f, 1.0f) * 255.0f);
            uint8 bb = (uint8)(clamp(rgb.z, 0.0f, 1.0f) * 255.0f);

            color = (uint32)bb | ((uint32)gb << 8) | ((uint32)rb << 16) | 0xFF000000u;
        }

        pixels[py * width + px] = color;
    }
}
