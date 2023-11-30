#version 450

// uniform buffer
layout(std140, binding = 0) uniform ubo {
    mat4	WVPM;	// World View Projection Matrix
	mat4	VIEW;  	// to transfrom into View Space	(inverse of CAMM)
    mat4	CAMM; 	// Camera Position and Rotation in World Space
	float	Aspect;
	float 	FOV;	// vertical field (angle) of view of the perspective projection
    float   Near;
    float   Far;
	vec4	Mouse;	// xy framebuffer coord when LMB pressed, zw when clicked
	vec2	Resolution;
	float	Time;
	float	Time_Delta;
	uint	Frame;
	float	Speed;

	// Ray Marching
	uint	MaxRaySteps;
	float	Epsilon;

	// Heightmap
	float   HM_Scale; 
	float   HM_Height_Factor;
	int    	HM_Min_Level;
	int		HM_Max_Level;
};

layout( binding = 2 ) uniform sampler2D noise_tex;

// rastered vertex attributes and output
layout(location = 0) in   vec2 vs_ndc_xy;  	// input from vertex shader
layout(location = 0) out  vec4 fs_color;  	// output from fragment shader


// Generate Rays
void genRay(out vec3 ro, out vec3 rd)  {
	float DEG_TO_RAD = 0.01745329238474369049072265625;
	float frag_size = 2.0 * tan(0.5 * FOV * DEG_TO_RAD) / Resolution.y;
	vec2 ray_trg = vec2(1, -1) * (gl_FragCoord.xy - 0.5 * (Resolution - 1));	// Flip gl_FragCoord.y, as world is Y-up and VK FragCoord Y-down
	rd = normalize(mat3(CAMM) * vec3(frag_size * ray_trg, 1));
	ro = CAMM[3].xyz;

	// Orthographic Rays
	// rd = CAMM[2].xyz;
    // ro = CAMM[3].xyz + HM_Scale / 64.0 * (ray_trg.x * CAMM[0].xyz + ray_trg.y * CAMM[1].xyz);
}

// axis aligned bounding box, returns min and max hit 
// source: https://tavianator.com/2022/ray_box_boundary.html
// Note: ray direction must be passed in inverted: rd_inv = 1.0 / rd;
bool aabb(vec3 ro, vec3 rd_inv, vec3 b_min, vec3 b_max, inout vec2 e) {
    vec3 t1 = (b_min - ro) * rd_inv;
    vec3 t2 = (b_max - ro) * rd_inv;
    vec3 t_min = min(t1, t2);
    vec3 t_max = max(t1, t2);
	e.x = max(max(t_min.x, t_min.y), max(t_min.z, e.x));
    e.y = min(min(t_max.x, t_max.y), min(t_max.z, e.y));
    return e.x < e.y;	//max(e.x, 0) < e.y;
}

// rays not hitting the heightmap
vec4 far_plane() {
	fs_color = vec4(gl_FragCoord.xy / Resolution, 0, 1);
	fs_color = vec4(vec3(0.25), 1.0);
	return vec4(fs_color.rgb, Far);
}

// Hightmap Distance field
vec4 sd_heightmap(vec3 ro, vec3 rd) {//, inout float depth, inout vec3 normal) {

	// if (rd.y >= 0.0f)
	// 	return far_plane();

	float h = HM_Height_Factor * textureLod(noise_tex, vec2(0.5), HM_Max_Level).r;	//HM_Scale * HM_Height_Factor;

	// build an axis aligned aounding box (AABB) arround the heightmap and test for entry points
    // aabb test requires inverted ray direction: rd_inv = 1.0 / rd with extra code to avoid div by 0
    vec3 rd_inv = 1.0 / rd; //mix(1.0 / rd, sign(rd) * 1e30, equal(rd, vec3(0.0)));
	vec2 bb_near_far = vec2(Near, Far);

	if (!aabb(ro, rd_inv, vec3(0), vec3(1, h, 1), bb_near_far)) {
		return far_plane();
	}

	// reaching here we have a AABB hit and can compute the WS hit point
	// we need an epsilon, to guerantee that the hit point ends up slightly inside the box
	vec3 p = ro + (Epsilon + bb_near_far.x) * rd;

	//
	// Quadtree Displacement Mapping basic pseudo code
	// 

	// Compute starting Mip Level
	int level = HM_Max_Level;
	int lod_res = 1;

	// We calculate ray movement vector in inter-cell numbers.
	uvec2 texelPlaneOffset = uvec2(sign(rd.xz) + 1) / 2;

	// Main loop
	uint step_count = 0;
	while (level >= HM_Min_Level && step_count < MaxRaySteps) {

		// Early out if the ray exists the AABB, Todo(pp): substitute 0 and 1 with editable BBox bounds
        if (any(lessThanEqual(p.xz, vec2(0))) || any(greaterThanEqual(p.xz, vec2(1)))) {
            return far_plane();
        }

		// default descent in hierarchy, nullified by ascend in case of cell crossing
		// level = HM_Max_Level is already used for our bounding box, so we take the next higher one
		level -= 1;
		++step_count;

		// We get current cell minimum plane using tex2Dlod.
		vec2 uv = p.xz;	//world_to_uv(p2.xz);	// Use the latter with user defined BBox bounds
		h = HM_Height_Factor * textureLod(noise_tex, uv, level).r;
		lod_res = 1 << (HM_Max_Level - level);

        // If we are not blocked by the cell we move the ray.
        if (h < p.y) {

			// We calculate predictive new ray position, which moves as far as the hight of the current cell
			vec3 q = p + rd * rd_inv.y * (h - p.y);

			// We compute current and predictive position.
			// Calculations are performed in cell integer numbers.
            
            float lod_res_inv = 1.0 / lod_res;
            ivec4 texel_idx = ivec4(floor(vec4(p.xz, q.xz) * lod_res));	// Todo(pp): map texel_idx from user defined bbox bounds
            // ivec4 texel_idx = ivec4((vec4(p.xz, q.xz) + 0.5 * HM_Scale) / HM_Scale) * lod_res;

			// we test if both positions are still in the same cell
			// if not, we have to move the ray to nearest cell boundary
			if (any(notEqual(texel_idx.xy, texel_idx.zw))) {

                // Compute ray plane intersection of X and Z planes of current cell where ray direction points to and Y Heightmap min plane
                // We use Matrix vector multiplication to get the 2 * 3 required dot products. Algorithm used (one 2 dot products):
                // https://www.scratchapixel.com/lessons/3d-basic-rendering/minimal-ray-tracer-rendering-simple-shapes/ray-plane-and-ray-disk-intersection.html  
                // With matrix multiply: t = (mat3(1.0) * (pp - p)) / (mat3(1.0) * rd);
                // As the planes are axis aligned, we use an identity matrix, which results in no-ops, hence not needed
				//
				// plane point (pp) of X, Z and Y planes, then swizzled back into X, Y and Z planes
                vec3 pp = vec3((texel_idx.xy + texelPlaneOffset) * lod_res_inv, 0);   
                vec3 t = (pp.xzy - p) * rd_inv;                     // we swizzele, to move the Y plane coord (0) into the propper position
                
				// Epsilon is needed to guarantee that we end up in the next texel, otherwise we might get stuck
				q = p + (Epsilon + min(t.x, min(t.y, t.z))) * rd;	// Epsilon os needed to guarantee that we end up in the next texel, otherwise we might get stuck
                level += 2;
			}

			// Final ray movement
			p = q;

		}
	}

	// Get the final point on the slope between the current cell and its closest cell (in +- ray dir)
	// 1. decide to use previous or next pixel in major ray direction (the larger one of absolute rd x and z components)
	//	- multiply uv coordinate with Mip Level 0 Resolution and store its fractional part
	//	- if major ray direction is positive
	//		- fractional part >= 0.5 ? advance ray with one texel width in pos rd : ... neg rd
	//	- if major ray direction is negative
	//		- fractional part >= 0.5 ? advance ray with one texel width in neg rd : ... pos rd
	// 2. set q to the point further away from ro, snap to pixel center on major direction axis
	// 3. set p to the point closer to ro, snap to pixel center on major direction axis
	// 4. sample hight from texture corresponding to p and q uv values to get line segment
	// 5. intersect ray with line segment (in 2D, ignoring major ray direction)
	//
	// vec3 rd_abs = abs(rd);
	// uint max_comp = 2 * uint(rd_abs.x < rd_abs.z);
	// vec3 q = p + rd * rd_inv[ max_comp ] * (p[ max_comp ] + sign(rd)[ max_comp ] / Resolution.x);
	// p = mix(q, p, Resolution.x * fract(p[ max_comp ]));

	// Coloring of resulting sampling points
	float t = p.y / HM_Height_Factor;
	float checker = float((uint(32.0 * p.x) % 2) ^ (uint(32.0 * p.z) % 2));
	vec3 cell_color = vec3(floor(p.xz * lod_res) / (lod_res - 1), 0);	// vec3(1,0,0);
	cell_color = mix(vec3(0, 0, 0.25), cell_color, t);
	fs_color = vec4(cell_color, 1);
	return vec4(cell_color, length(p - ro));
}


void main() {
	vec3 ro;
	vec3 rd;
	genRay(ro, rd);
	sd_heightmap(ro, rd);
}