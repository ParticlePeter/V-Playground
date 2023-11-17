#version 450

// uniform buffer
layout(std140, binding = 0) uniform ubo {
    mat4	WVPM;	// World View Projection Matrix
	mat4	WVPI; 	// World View Projection Inverse Matrix
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
	int    	HM_Level;
	int		HM_Max_Level;
};

// Push Constants
layout( push_constant ) uniform Push_Constant {
    mat4    RAYS;
    uvec2   R_Res;
    float   R_FOV;
};

layout( binding = 2 ) uniform sampler2D noise_tex;

// Vertex Shader Output
layout( location = 0 ) out vec4 vs_color;   // vertex shader output vertex color, will be interpolated and rasterized

out gl_PerVertex {                          // not redifining gl_PerVertex used to create a layer validation error
    vec4  gl_Position;                      // not having clip and cull distance features enabled
    float gl_PointSize;
};                                          // error seems to have vanished by now, but it does no harm to keep this redefinition

#define VI gl_VertexIndex
#define II gl_InstanceIndex

// axis aligned bounding box, returns min and max hit 
// source: https://tavianator.com/2022/ray_box_boundary.html
// Note: ray direction must be input inverted: rd_inv = 1.0 / rd;
bool aabb(vec3 ro, vec3 rd_inv, vec3 b_min, vec3 b_max, inout vec2 e) {
    vec3 t1 = (b_min - ro) * rd_inv;
    vec3 t2 = (b_max - ro) * rd_inv;
    vec3 t_min = min(t1, t2);
    vec3 t_max = max(t1, t2);
	e.x = max(max(t_min.x, t_min.y), max(t_min.z, e.x));
    e.y = min(min(t_max.x, t_max.y), min(t_max.z, e.y));
    return max(e.x, 0) < e.y;
}


// vec2 uv_to_world(vec2 uv) { return (uv - 0.5) * HM_Scale; }
// vec2 world_to_uv(vec2 xz) { return (xz + 0.5 * HM_Scale) / HM_Scale; }
// vec4 world_to_uv(vec4 xz) { return (xz + 0.5 * HM_Scale) / HM_Scale; }

// vec4 far_plane() {
// 	fs_color = vec4(gl_FragCoord.xy / Resolution, 0, 1);
// 	return vec4(fs_color.rgb, Far);
// }

vec4 result(vec3 p, inout uint vi) {
    gl_PointSize = 3 + 0.5 * vi;
    float cs = 0.05 * vi;
    vs_color = vec4(cs, 1.0 - cs, 1.0 - cs, 1.0);
    //vi = vi + 1;
    return vec4(p, 1);
}

// Hightmap Distance field
vec4 sdf_heightmap(vec3 ro, vec3 rd) {//, inout float depth, inout vec3 normal) {

    uint vi = 0;
    if (VI == vi)
        return result(ro, vi);
    ++vi;

	float h = HM_Height_Factor * textureLod(noise_tex, vec2(0), HM_Max_Level).r;	//HM_Scale * HM_Height_Factor;
	// float sxy = 0.5 * HM_Scale;		// side xy
	// float hps = sxy / Resolution.x;	// half pixel size
	// float bxy = sxy - hps;			// reduce marching box with half a pixel on each side, to start on pixel center

	// build an axis aligned aounding box (AABB) arround the heightmap and test for entry points
    // aabb test requires inverted ray direction: rd_inv = 1.0 / rd with extra code to avoid div by 0
    vec3 rd_inv = 1.0 / rd; //mix(1.0 / rd, sign(rd) * 1e30, equal(rd, vec3(0.0)));
	vec2 bb_near_far = vec2(Near, Far);
	if (!aabb(ro, rd_inv, vec3(0), vec3(1, h, 1), bb_near_far)) {
		// return far_plane();
        return vec4(ro + Far * rd, 1);
	}


	// reaching here we have a AABB hit and can compute the WS hit point
	// vec2 uv = world_to_uv(p.xz);
    // vec3 p = ro + bb_near_far[ clamp(0, 1, VI - 1) ] * rd;
	vec3 p = ro + 1.0001 * bb_near_far.x * rd;
    if (VI == vi)   // vi = 1
        return result(p, vi);
    ++vi;

    //
    // Quadtree Displacement Mapping basic pseudo code
    // 

    int level = HM_Max_Level - 1;   // HM_Max_Level is already used for our bounding box
    //int lod_res = int(pow(2.0, level));	// MipMap resolution in x or y
    //const float HalfTexel = 1.0 * lod_res_inv / 2.0;
    vec3 p2 = p;

    // We calculate ray movement vector in inter-cell numbers.
    ivec2 DirSign = ivec2(sign(rd.xz));

    // Main loop
    uint step_count = 0;
    while (level >= 0 && step_count < MaxRaySteps) {
        //  for(uint step_count = 0; step_count < MaxRaySteps; ++step_count) {
        
        //if (distance(p, p2) > bb_near_far.y) {
        if (any(lessThanEqual(p2.xz, vec2(0))) || any(greaterThan(p2.xz, vec2(1)))) {
            return vec4(ro + Far * rd, 1);
        }

        ++step_count;

        // We get current cell minimum plane using tex2Dlod.
        // h = tex2Dlod(HeightTexture , float4(p2.xy, 0.0 , level)).w;
        vec2 uv = p2.xz;	//world_to_uv(p2.xz);
        h = HM_Height_Factor * textureLod(noise_tex, uv, level).r;
        // h = HM_Max_Level - HM_Max_Level * textureLod(noise_tex, uv, level).r;

        // If we are not blocked by the cell we move the ray.
        if (h < p2.y) {

            // We calculate predictive new ray position.
            vec3 tmpP2 = p2 - rd * rd_inv.y * (p2.y - h);

            // We compute current and predictive position.
            // Calculations are performed in cell integer numbers.
            int     lod_res = 1 << (HM_Max_Level - level);
            float   lod_res_inv = 1.0 / lod_res;
            // ivec4 texel_idx = ivec4((vec4(p2.xz, tmpP2.xz) + 0.5 * HM_Scale) / HM_Scale) * lod_res;
            ivec4 texel_idx = ivec4(vec4(p2.xz, tmpP2.xz) * lod_res);

            // We test if both positions are still in the same cell.
            // If not, we have to move the ray to nearest cell boundary.
            // if (texel_idx.x != texel_idx.z || texel_idx.y != texel_idx.w) {
            if (any(notEqual(texel_idx.xy, texel_idx.zw))) {
                // We compute the distance to current cell boundary.
                // We perform the calculations in continuous space.
                vec2 p3 = vec2(texel_idx.xy + DirSign) * lod_res_inv;
                vec2 a = (p2.xz - p.xz);
                vec2 b = (p3.xy - p.xz);

                // We are choosing the nearest cell
                // by choosing smaller distance.
                // vec2 dNC = abs(p2.z * b / a);
                vec2 neighbor_cell_dist = abs(p2.y * b / a);
                //float d = min(p2.y - h, min(dNC.x, dNC.y));
                float d = min(neighbor_cell_dist.x, neighbor_cell_dist.y);
                //float d = min((p2.y - h) * rd_inv.y, min(neighbor_cell_dist.x, neighbor_cell_dist.y));


                // Compute ray plane intersection of X and Z planes of current cell where ray direction points to and Y Heightmap min plane
                // We use Matrix vector multiplication to get the 2 * 3 required dot products. Algorithm used (one 2 dot products):
                // https://www.scratchapixel.com/lessons/3d-basic-rendering/minimal-ray-tracer-rendering-simple-shapes/ray-plane-and-ray-disk-intersection.html  
                vec2 po = (texel_idx.xy + (DirSign + 1) * 0.5) * lod_res_inv;   // plane origin of X, Z planes
                vec3 t = vec3(po.x, 0, po.y);                                   // t initialized with all (X, Y, Z) planes origin
                t = (mat3(1.0) * (t - p2)) / (mat3(1.0) * rd);                  // compute 3 distances (t) for ray plane hit of the 3 planes, choose the smallest later 
                tmpP2 = p2 + 1.0001 * min(t.x, min(t.y, t.z)) * rd;             // we use a bias to move sligtly further than computed, otherwise we get stuck due to inprecisions  

                level += 2;//min(HM_Max_Level, level + 2);
            }

            // Final ray movement
            p2 = tmpP2;
        }

        if (VI == vi)   // vi = 2
            return result(p2, vi);
        ++vi;

        --level;
    }

    return result(p2, vi);
}

// Generate Rays
void genRay(out vec3 ro, out vec3 rd)  {
    uint yres = 5;
    //mat4 RAYS = mat4(0,0,1,0, 0,1,0,0, -1,0,0,0, 0,0,0,1) * CAMM;
	float DEG_TO_RAD = 0.01745329238474369049072265625;
	float frag_size = 2.0 * tan(0.5 * R_FOV * DEG_TO_RAD) / R_Res.y;
	vec2 ray_trg = /*vec2(1, -1) */ (vec2(II % R_Res.x, II / R_Res.x) - 0.5 * (R_Res - 1));
	rd = normalize(mat3(RAYS) * vec3(frag_size * ray_trg, 1));
	ro = RAYS[3].xyz;
    // rd = RAYS[2].xyz;
}


void main() {

    // set in result func
    //gl_PointSize = 16.0;
    //vs_color = vec4(0,0.8,1,1);

    vec3 ro, rd;
    genRay(ro, rd);

    gl_Position = WVPM * sdf_heightmap(ro, rd);

    //gl_Position = WVPM * vec4( ro + VI * rd, 1);
}


/*
// vkCmdDrawIndexed
void main() {

    const float Angle = 60.0 * 0.0174532925199432957692369;

    vec4 pos = vec4( 0, 0, 0, 1 );
    vs_color = pos;

    if( VI > 0 ) {
        pos.xy = vec2( -1, -1 );

        int vi = VI - 1;
        float cos_angle = cos( vi * Angle );
        float sin_angle = sin( vi * Angle );
        mat2 ROT = mat2( cos_angle, sin_angle, - sin_angle, cos_angle );

        pos.xz = ROT * pos.xz;
        vs_color = colors[ vi % 6 ];
    }

    gl_Position = WVPM * pos;
}
*/