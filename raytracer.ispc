// Whitted Raytracing (1979) + Mandelbrot Zoom Demo - v2
// Fixed orientation, optimized Mandelbrot, improved scene

// ============================================================================
// Constants
// ============================================================================

// Epsilon values for numerical stability
static const uniform float EPSILON_SHADOW = 0.001f;    // Offset for shadow/reflection rays
static const uniform float EPSILON_NORMALIZE = 0.0001f; // Guard for normalization
static const uniform float EPSILON_PARALLEL = 0.0001f;  // Guard for parallel ray tests

// Mandelbrot constants
static const uniform double LOG2_E = 1.4426950408889634; // 1/ln(2) for log2 computation
static const uniform float MANDEL_COLOR_FREQ = 0.015f;   // Color palette cycle frequency

// Lighting constants
static const uniform float AMBIENT_STRENGTH = 0.15f;     // Ambient light contribution
static const uniform float DIFFUSE_STRENGTH = 0.85f;     // Diffuse light contribution
static const uniform float FLOOR_REFLECTIVITY = 0.15f;   // Floor reflection coefficient
static const uniform float MIRROR_SPEC_POWER = 80.0f;    // Mirror specular exponent
static const uniform float DIFFUSE_SPEC_POWER = 30.0f;   // Diffuse sphere specular exponent
static const uniform float DIFFUSE_SPEC_STRENGTH = 0.5f; // Diffuse sphere specular intensity

// Shadow attenuation values
static const uniform float SHADOW_OPAQUE = 0.25f;        // Shadow from opaque sphere
static const uniform float SHADOW_DIFFUSE = 0.35f;       // Shadow from diffuse sphere
static const uniform float SHADOW_GLASS = 0.6f;          // Partial shadow through glass

// Hit type enumeration
enum HitType {
    HIT_NONE = -1,
    HIT_FLOOR = 0,
    HIT_MIRROR = 1,
    HIT_GLASS = 2,
    HIT_DIFFUSE = 3
};

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
    if (len > EPSILON_NORMALIZE) {
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
static const uniform float sphere1_radius = 1.0f;
static const uniform Vec3 sphere1_center = {-0.8f, 1.0f, 1.0f};

// Sphere 2: Refractive (glass) - smaller, on the right
static const uniform float sphere2_radius = 0.6f;
static const uniform Vec3 sphere2_center = {1.2f, 0.6f, 0.0f};

// Sphere 3: Small colored diffuse sphere
static const uniform float sphere3_radius = 0.3f;
static const uniform Vec3 sphere3_center = {-0.2f, 0.3f, -0.8f};

// Light position - high and to the right
static const uniform Vec3 light_pos = {8.0f, 12.0f, -4.0f};

// Checkerboard floor at y = 0
static const uniform float floor_y = 0.0f;

// Floor visibility bounds (asymmetric in Z to match camera view)
static const uniform float floor_x_min = -15.0f;
static const uniform float floor_x_max = 15.0f;
static const uniform float floor_z_min = -3.0f;
static const uniform float floor_z_max = 25.0f;

// ============================================================================
// Ray-sphere intersection
// ============================================================================

// Ray-sphere intersection using simplified quadratic (assumes normalized ray direction)
inline float intersect_sphere(Ray r, Vec3 center, float radius) {
    Vec3 oc = vec3_sub(r.origin, center);
    // Since ray direction is normalized, a = dot(dir, dir) = 1.0
    float half_b = vec3_dot(oc, r.dir);
    float c = vec3_dot(oc, oc) - radius * radius;
    float discriminant = half_b * half_b - c;

    if (discriminant < 0.0f) return -1.0f;

    float sqrt_disc = sqrt(discriminant);
    float t = -half_b - sqrt_disc;
    if (t > EPSILON_SHADOW) return t;

    t = -half_b + sqrt_disc;
    if (t > EPSILON_SHADOW) return t;

    return -1.0f;
}

// ============================================================================
// Ray-plane intersection (floor)
// ============================================================================

inline float intersect_floor(Ray r) {
    if (abs(r.dir.y) < EPSILON_PARALLEL) return -1.0f;
    float t = (floor_y - r.origin.y) / r.dir.y;
    return (t > EPSILON_SHADOW) ? t : -1.0f;
}

// ============================================================================
// Checkerboard pattern - larger squares
// ============================================================================

inline Vec3 checkerboard_color(Vec3 p) {
    float scale = 1.5f;  // Larger squares
    int cx = (int)floor(p.x / scale);
    int cz = (int)floor(p.z / scale);
    // floor() already handles negative coordinates correctly

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

// Note: assumes v is already normalized (ray directions are normalized at creation)
inline bool refract(Vec3 v, Vec3 n, float ni_over_nt, Vec3 &refracted) {
    float dt = vec3_dot(v, n);
    float discriminant = 1.0f - ni_over_nt * ni_over_nt * (1.0f - dt * dt);

    if (discriminant > 0.0f) {
        refracted = vec3_sub(
            vec3_mul(vec3_sub(v, vec3_mul(n, dt)), ni_over_nt),
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
    Vec3 to_light = vec3_normalize(vec3_sub(light_pos, hit_point));
    Vec3 view_dir = vec3_mul(r.dir, -1.0f);

    Vec3 color = make_vec3(0.0f, 0.0f, 0.0f);
    Vec3 normal;

    if (hit_type == HIT_FLOOR) {
        // Floor
        normal = make_vec3(0.0f, 1.0f, 0.0f);
        Vec3 base_color = checkerboard_color(hit_point);

        // Shadow check - test all spheres, first in code order wins
        Ray shadow_ray = make_ray(vec3_add(hit_point, vec3_mul(normal, EPSILON_SHADOW)), to_light);
        float shadow = 1.0f;

        if (intersect_sphere(shadow_ray, sphere1_center, sphere1_radius) > 0.0f) shadow = SHADOW_OPAQUE;
        else if (intersect_sphere(shadow_ray, sphere2_center, sphere2_radius) > 0.0f) shadow = SHADOW_GLASS;
        else if (intersect_sphere(shadow_ray, sphere3_center, sphere3_radius) > 0.0f) shadow = SHADOW_DIFFUSE;

        float diffuse = max(0.0f, vec3_dot(normal, to_light));
        color = vec3_mul(base_color, (AMBIENT_STRENGTH + DIFFUSE_STRENGTH * diffuse * shadow));

        // Subtle reflection on floor
        if (depth > 0) {
            Vec3 reflect_dir = vec3_reflect(r.dir, normal);
            Ray reflect_ray = make_ray(vec3_add(hit_point, vec3_mul(normal, EPSILON_SHADOW)), reflect_dir);
            Vec3 reflect_color = trace_ray(reflect_ray, depth - 1);
            color = vec3_lerp(color, reflect_color, FLOOR_REFLECTIVITY);
        }
    }
    else if (hit_type == HIT_MIRROR) {
        // Mirror sphere - pure reflection with slight tint
        normal = vec3_normalize(vec3_sub(hit_point, sphere1_center));

        if (depth > 0) {
            Vec3 reflect_dir = vec3_reflect(r.dir, normal);
            Ray reflect_ray = make_ray(vec3_add(hit_point, vec3_mul(normal, EPSILON_SHADOW)), reflect_dir);
            color = trace_ray(reflect_ray, depth - 1);
            // Slight warm tint to mirror
            color = vec3_mul_vec(color, make_vec3(1.0f, 0.98f, 0.95f));
        }

        // Specular highlight
        Vec3 half_vec = vec3_normalize(vec3_add(to_light, view_dir));
        float spec = pow(max(0.0f, vec3_dot(normal, half_vec)), MIRROR_SPEC_POWER);
        color = vec3_add(color, make_vec3(spec, spec, spec));
    }
    else if (hit_type == HIT_GLASS) {
        // Glass sphere (refractive)
        normal = vec3_normalize(vec3_sub(hit_point, sphere2_center));

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
            Ray reflect_ray = make_ray(vec3_add(hit_point, vec3_mul(outward_normal, EPSILON_SHADOW)), reflect_dir);
            Vec3 reflect_color = trace_ray(reflect_ray, depth - 1);

            if (refract(r.dir, outward_normal, ni_over_nt, refracted)) {
                Ray refract_ray = make_ray(vec3_sub(hit_point, vec3_mul(outward_normal, EPSILON_SHADOW)), refracted);
                Vec3 refract_color = trace_ray(refract_ray, depth - 1);
                color = vec3_lerp(refract_color, reflect_color, reflect_prob);
            } else {
                color = reflect_color;
            }
        }

        // Slight cyan tint for glass
        color = vec3_mul_vec(color, make_vec3(0.95f, 0.98f, 1.0f));
    }
    else if (hit_type == HIT_DIFFUSE) {
        // Small diffuse sphere - red/orange
        normal = vec3_normalize(vec3_sub(hit_point, sphere3_center));
        Vec3 base_color = make_vec3(0.9f, 0.3f, 0.1f);  // Orange-red

        // Shadow check - first in code order wins
        Ray shadow_ray = make_ray(vec3_add(hit_point, vec3_mul(normal, EPSILON_SHADOW)), to_light);
        float shadow = 1.0f;
        if (intersect_sphere(shadow_ray, sphere1_center, sphere1_radius) > 0.0f) shadow = SHADOW_OPAQUE;
        else if (intersect_sphere(shadow_ray, sphere2_center, sphere2_radius) > 0.0f) shadow = SHADOW_GLASS;

        float diffuse = max(0.0f, vec3_dot(normal, to_light));
        color = vec3_mul(base_color, (0.2f + 0.8f * diffuse * shadow));

        // Specular
        Vec3 half_vec = vec3_normalize(vec3_add(to_light, view_dir));
        float spec = pow(max(0.0f, vec3_dot(normal, half_vec)), DIFFUSE_SPEC_POWER) * DIFFUSE_SPEC_STRENGTH;
        color = vec3_add(color, make_vec3(spec, spec, spec));
    }

    return color;
}

inline Vec3 trace_ray(Ray r, int depth) {
    float closest_t = 1e10f;
    int hit_type = HIT_NONE;

    // Check floor (bounded rectangle to avoid artifacts at horizon)
    float t_floor = intersect_floor(r);
    if (t_floor > 0.0f && t_floor < closest_t) {
        Vec3 p = ray_at(r, t_floor);
        if (p.x > floor_x_min && p.x < floor_x_max &&
            p.z > floor_z_min && p.z < floor_z_max) {
            closest_t = t_floor;
            hit_type = HIT_FLOOR;
        }
    }

    // Check sphere 1 (mirror)
    float t1 = intersect_sphere(r, sphere1_center, sphere1_radius);
    if (t1 > 0.0f && t1 < closest_t) {
        closest_t = t1;
        hit_type = HIT_MIRROR;
    }

    // Check sphere 2 (glass)
    float t2 = intersect_sphere(r, sphere2_center, sphere2_radius);
    if (t2 > 0.0f && t2 < closest_t) {
        closest_t = t2;
        hit_type = HIT_GLASS;
    }

    // Check sphere 3 (diffuse)
    float t3 = intersect_sphere(r, sphere3_center, sphere3_radius);
    if (t3 > 0.0f && t3 < closest_t) {
        closest_t = t3;
        hit_type = HIT_DIFFUSE;
    }

    if (hit_type != HIT_NONE) {
        return shade_hit(r, closest_t, hit_type, depth);
    }

    // Sky gradient - lerp from light blue (horizon) to deeper blue (zenith)
    float sky_t = 0.5f * (r.dir.y + 1.0f);
    sky_t = clamp(sky_t, 0.0f, 1.0f);
    Vec3 sky_bottom = make_vec3(0.6f, 0.75f, 0.9f);
    Vec3 sky_top = make_vec3(0.25f, 0.4f, 0.7f);
    return vec3_lerp(sky_bottom, sky_top, sky_t);
}

// ============================================================================
// Whitted Raytracer Entry Point
// ============================================================================

export void render_whitted(uniform uint32 pixels[], uniform int width, uniform int height) {
    // Camera setup - classic Whitted angle
    uniform Vec3 camera_pos = {0.5f, 2.0f, -4.5f};
    uniform Vec3 look_at = {0.2f, 0.5f, 1.0f};
    uniform Vec3 world_up = {0.0f, 1.0f, 0.0f};

    uniform float fov = 1.0f;  // Field of view (radians)
    uniform float aspect = (float)width / (float)height;

    // Camera basis vectors - forward direction from camera to look_at
    uniform Vec3 forward = {
        look_at.x - camera_pos.x,
        look_at.y - camera_pos.y,
        look_at.z - camera_pos.z
    };
    uniform float fwd_len = sqrt(forward.x*forward.x + forward.y*forward.y + forward.z*forward.z);
    if (fwd_len < EPSILON_NORMALIZE) return;  // Guard against camera at look_at
    forward.x /= fwd_len; forward.y /= fwd_len; forward.z /= fwd_len;

    // right = cross(world_up, forward) → camera's rightward direction
    uniform Vec3 right = {
        world_up.y * forward.z - world_up.z * forward.y,
        world_up.z * forward.x - world_up.x * forward.z,
        world_up.x * forward.y - world_up.y * forward.x
    };
    uniform float right_len = sqrt(right.x*right.x + right.y*right.y + right.z*right.z);
    if (right_len < EPSILON_NORMALIZE) return;  // Guard against looking straight up/down
    right.x /= right_len; right.y /= right_len; right.z /= right_len;

    // cam_up = cross(forward, right) → camera's upward direction
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

// Fire/plasma color palette - vibrant gradient through blue-cyan-yellow-orange-red
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

        int iter = 0;
        bool in_set = false;

        // Early-out for main cardioid: q*(q + (x0 - 0.25)) < 0.25*y0^2
        // where q = (x0 - 0.25)^2 + y0^2
        double q = (x0 - 0.25) * (x0 - 0.25) + y0 * y0;
        if (q * (q + (x0 - 0.25)) < 0.25 * y0 * y0) {
            in_set = true;
            iter = max_iter;
        }
        // Early-out for period-2 bulb: (x0 + 1)^2 + y0^2 < 1/16
        else if ((x0 + 1.0) * (x0 + 1.0) + y0 * y0 < 0.0625) {
            in_set = true;
            iter = max_iter;
        }

        double x = 0.0;
        double y = 0.0;
        double x2 = 0.0;
        double y2 = 0.0;

        // Optimized iteration with cached squares (skip if already known to be in set)
        if (!in_set) {
            while (x2 + y2 <= 4.0 && iter < max_iter) {
                y = 2.0 * x * y + y0;
                x = x2 - y2 + x0;
                x2 = x * x;
                y2 = y * y;
                iter++;
            }
        }

        uint32 color;
        if (iter == max_iter) {
            color = 0xFF000000u;  // Black for points in set
        } else {
            // Smooth coloring using continuous potential method
            // log2(|z|) = log(|z|) * log2(e) = log(x2+y2) * 0.5 * LOG2_E
            double log_zn = log(x2 + y2) * 0.5;
            double nu = log(log_zn * LOG2_E) * LOG2_E;
            double smooth_iter = (double)iter + 1.0 - nu;
            if (smooth_iter < 0.0) smooth_iter = 0.0;

            // Map to color palette with wrapping
            float t = (float)(smooth_iter * MANDEL_COLOR_FREQ);
            t = t - floor(t);  // Wrap to [0, 1]

            Vec3 rgb = palette(t);

            uint8 rb = (uint8)(clamp(rgb.x, 0.0f, 1.0f) * 255.0f);
            uint8 gb = (uint8)(clamp(rgb.y, 0.0f, 1.0f) * 255.0f);
            uint8 bb = (uint8)(clamp(rgb.z, 0.0f, 1.0f) * 255.0f);

            color = (uint32)bb | ((uint32)gb << 8) | ((uint32)rb << 16) | 0xFF000000u;
        }

        pixels[py * width + px] = color;
    }
}
