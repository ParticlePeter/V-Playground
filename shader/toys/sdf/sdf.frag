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
};

layout( binding = 2 ) uniform sampler2D noise_tex;

// rastered vertex attributes and output
layout(location = 0) in   vec2 vs_ndc_xy;  	// input from vertex shader
layout(location = 0) out  vec4 fs_color;  	// output from fragment shader


// pos : ray origin
// dir : ray direction


float sdf_plane(vec3 p) {
	return p.y;
}

float sdf_sphere(vec3 p, float s) {
	return length(p) - s;
}

float sdf_box(vec3 p, vec3 b) {
	vec3 d = abs(p) - b;
	return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}


// Hightmap Distance field
vec4 sdf_heightmap(vec3 ro, vec3 rd) {//, inout float depth, inout vec3 normal) {

	vec2 hr = Resolution * 0.5;	// half_res

	float top = HM_Height_Factor;
	vec3  eye = CAMM[3].xyz;
	//	vec3  wrd = mat3(CAMM) * rd;			// wrd: world space ray direction
	float x = (eye.y - top) / (rd.y);		// x: factor for rd to reach top plane
	vec3  p = eye - x * rd;					// p: the ppoint we hit on our plane

	for(uint step_count = 0; step_count < MaxRaySteps; ++step_count) {

		// if the hitpoint is inside the top heightmap xz bounds we draw it, otherwise the bg.
		if (any(greaterThan(abs(p.xz), vec2(0.5 * HM_Scale)))) {
			fs_color = vec4(gl_FragCoord.xy / Resolution, 0, 1);
			return vec4(fs_color.rgb, Far);
		}

		// UVs are reconstructed using plane placement and ray hit location 
		vec2 uv = (p.xz + 0.5 * HM_Scale) / HM_Scale;
		float h = textureLod(noise_tex, uv, 0).x;

		if (p.y <= h) {

			float t = float(step_count) / MaxRaySteps;
			vec3  s = mix(vec3(0,0,0.5), vec3(1,0,0), t);
			//fs_color = vec4(s, 1);
			//return length(p - ro);
			return vec4(s, length(p - ro));
		}

		float duv = 1.0 / 1024;
		p += rd * duv;
	}

	vec2 uv = (p.xz + 0.5 * HM_Scale) / HM_Scale;

	// Camera is lighsource, we want the vector from our point to towards the cam
	// which is the cam view direction, which again is the camera negative z axis.
	// We can get the z axis with either mat3(CAMM) * vec3(0, 0, 1) or CAMM[2].xyz.
	vec3 n = vec3(0,1,0);
	float l = abs(dot(mat3(CAMM) * vec3(0, 0, 1), n));	// Camera is Lightsource
	// fs_color = vec4(l * textureLod(noise_tex, uv, 0).rgb, 1);

	float duv = 1.0 / 1024;
	float du = textureLod(noise_tex, uv + vec2(duv, 0), 0).x - textureLod(noise_tex, uv - vec2(duv, 0), 0).x;
	float dv = textureLod(noise_tex, uv + vec2(0, duv), 0).x - textureLod(noise_tex, uv - vec2(0, duv), 0).x;
	//n = cross(normalize(vec3(0, dv, 2 * duv)), normalize(vec3(2 * duv, du, 0)));
	n = normalize(vec3(2 * du, -4, 2 * dv));

	l = dot(n, rd);
	vec3 s = vec3(n);
	fs_color = vec4(s, 1);

	return vec4(s, length( x * rd ));




	//
	// Quadtree Displacement Mapping basic pseudo code
	// 
	int MaxLevel = 10;	//MaxMipLevel;
	int NodeCount = int(pow(2.0, MaxLevel));
	//const float HalfTexel = 1.0 / NodeCount / 2.0;
	float d;
	vec3 p2 = p;
	int level = MaxLevel;

	// We calculate ray movement vector in inter-cell numbers.
	ivec2 DirSign = ivec2(sign(rd.xy));


	// Main loop
	uint step_count = 0;
	while (level >= 0 && step_count < MaxRaySteps) {
		step_count++;

		// We get current cell minimum plane using tex2Dlod.
		// d = tex2Dlod(HeightTexture , float4(p2.xy, 0.0 , level)).w;
		vec2 uv = (p.xz + 0.5 * HM_Scale) / HM_Scale;
		d = textureLod(noise_tex, uv, level).x;

		// If we are not blocked by the cell we move the ray.
		// if (d > p2.z) {
		if (d > p2.y) {
			// We calculate predictive new ray position.
			vec3 tmpP2 = p + rd * d;

			// We compute current and predictive position.
			// Calculations are performed in cell integer numbers.
			int NodeCount = int(pow(2, (MaxLevel - level)));
			// ivec4 NodeID = ivec4(p2.xy, tmpP2.xy) * NodeCount;
			ivec4 NodeID = ivec4(p2.xz, tmpP2.xz) * NodeCount;

			// We test if both positions are still in the same cell.
			// If not, we have to move the ray to nearest cell boundary.
			if (NodeID.x != NodeID.z || NodeID.y != NodeID.w) {
				// We compute the distance to current cell boundary.
				// We perform the calculations in continuous space.
				vec2 a = (p2.xz - p.xz);
				vec2 p3 = (NodeID.xy + DirSign) / NodeCount;
				vec2 b = (p3.xy - p.xz);

				// We are choosing the nearest cell
				// by choosing smaller distance.
				// vec2 dNC = abs(p2.z * b / a);
				vec2 dNC = abs(p2.y * b / a);
				d = min(d, min(dNC.x, dNC.y));

				// During cell crossing we ascend in hierarchy.
				level += 2;

				// Predictive refinement
				tmpP2 = p + rd * d;

			}

			// Final ray movement
			p2 = tmpP2;

		}

		// Default descent in hierarchy
		// nullified by ascend in case of cell crossing
		level--;

	}

	// float duv = 1.0 / 1024;
	// uv = (p2.xz + 0.5 * HM_Scale) / HM_Scale;
	// float du = textureLod(noise_tex, uv + vec2(duv, 0), 0).x - textureLod(noise_tex, uv - vec2(duv, 0), 0).x;
	// float dv = textureLod(noise_tex, uv + vec2(0, duv), 0).x - textureLod(noise_tex, uv - vec2(0, duv), 0).x;
	// n = cross(normalize(vec3(0, 0, dv)), normalize(vec3(du, 0, 0)));
	// l = dot(n, rd);
	// vec3 s = vec3(uv, 0);
	// fs_color = vec4(s, 1);
	// return p2;
	return vec4(0,0,0,length(p2 - ro));
}


// Set operations, no blending
float op_union(float d1, float d2) 		{ return min( d1, d2); }
float op_subtract(float d1, float d2) 	{ return max(-d1, d2); }
float op_intersect(float d1, float d2) 	{ return max( d1, d2); }


// polynomial smooth min 1 (k=0.1)	// fastest, most intuitive
float op_union_poly(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}


// exponential smooth min (k=32)	// order independant
float op_union_exp( float a, float b, float k ) {
    float res = exp2( -k*a ) + exp2( -k*b );
    return -log2( res )/k;
}

// with blen
vec2 op_union_cubic_t( float a, float b, float k ) {
    float h = max(k - abs(a - b), 0.0) / k;
    float m = h * h * h * 0.5;
    float s = m * k * (1.0 / 3.0); 
    return (a < b) ? vec2(a - s, m) : vec2(b - s, 1.0 - m);
}


// Combined / Blended Distance Filed functions
float distance_field(vec3 p, float hm) {
	/*
	return sdf_box(p, vec3(1));
	/*/
	//return op_union(
	//	sdf_box(p, vec3(1));//,
	//	sdf_plane(p));
	float ds = sdf_sphere(p + vec3(0.0, -3.5, 0.0), 1.0);
	float dp = sdf_plane(p);
	float db = sdf_box(p + vec3(0.0, -1.1, 0.0), vec3(1));

	//return op_union_poly(db, ds, 1.0);
	return op_union_poly(ds, hm);

	// return op_union_poly(op_union_poly(db, dp, 1.0), ds, 0.0);
	// return op_union_exp(op_union_exp(db, dp, 4.0), ds, 4.0);


	//*/

}

float distance_field(vec3 p) { return distance_field(p, Far); }


// Generate Rays
void genRay(out vec3 ro, out vec3 rd)  {
	/*

    // compute ray at current pixel from depth 0 ...
	vec4 projPos = vec4(vs_ndc_xy, 0, 1);
	projPos = WVPI * projPos;
	ro = projPos.xyz / projPos.w;

    // ... to depth one
	projPos = vec4(vs_ndc_xy, 1, 1);
	projPos = WVPI * projPos;
	rd = normalize(projPos.xyz / projPos.w - ro);
	
	/-/

	// tan(a) = gegkath / ankath
	// gegenkath = tan(a) * ankath
	// ankath = 1 => gegengath = tan(a)

	//vec2 rt = (gl_FragCoord.xy + 0.5) * Pixel_Size - 0.5 * Resolution;
	//rd = normalize((CAMM * vec4(rt, 1, 1)).xyz - Eye_Pos);

	//*/

	
	// vec2 xy = gl_FragCoord.xy - Resolution * 0.5;
	// const float DEG_TO_RAD = 0.01745329238474369049072265625;
	// float cot_half_fov = tan(( - 90.0 + FOV * 0.5) * DEG_TO_RAD);	
	// float z = Resolution.y * 0.5 * cot_half_fov;
	// rd = /*mat3(CAMM) */ normalize(vec3(xy, -z));
	// ro = CAMM[3].xyz;	//(VIEW * vec4(0, 0, 1, 1)).xyz;//Eye_Pos;

	

	/*
	// gltracy and Jamie Wong
	// vec3 dir = ray_dir( 45.0, iResolution.xy, fragCoord.xy );
	vec2 xy = pos - size * 0.5;
	float cot_half_fov = tan( ( 90.0 - fov * 0.5 ) * DEG_TO_RAD );	
	float z = size.y * 0.5 * cot_half_fov;
	return normalize( vec3( xy, -z ) );
	//*/

	float DEG_TO_RAD = 0.01745329238474369049072265625;
	float frag_size = 2.0 * tan(0.5 * FOV * DEG_TO_RAD) / Resolution.y;
	vec2 ray_trg = vec2(1, -1) * (gl_FragCoord.xy - 0.5 * Resolution);	// Flip gl_FragCoord.y, as world is Y-up and VK FragCoord Y-down
	rd = normalize(mat3(CAMM) * vec3(frag_size * ray_trg, 1));
	ro = CAMM[3].xyz;	//(VIEW * vec4(0, 0, 1, 1)).xyz;//Eye_Pos;
}


// get gradient in the world
vec3 gradient(vec3 pos) {
	const float gradient_epsilon = 0.00002;
	const vec3 dx = vec3(gradient_epsilon, 0.0, 0.0);
	const vec3 dy = vec3(0.0, gradient_epsilon, 0.0);
	const vec3 dz = vec3(0.0, 0.0, gradient_epsilon);
	return normalize (vec3(
		distance_field(pos + dx) - distance_field(pos - dx),
		distance_field(pos + dy) - distance_field(pos - dy),
		distance_field(pos + dz) - distance_field(pos - dz))
	);
}


// Fresnel
vec3 fresnel(vec3 F0, vec3 h, vec3 l) {
	return F0 + (1.0 - F0) * pow(clamp(1.0 - dot(h, l), 0.0, 1.0), 5.0);
}


// phong shading
vec3 shading(vec3 v, vec3 n, vec3 dir, vec3 eye) {
	// ...add lights here...
	
	float shininess = 16.0;
	
	vec3 final = vec3(0.0);
	
	vec3 ref = reflect(dir, n);
    
    vec3 Ks = vec3(0.5);
    vec3 Kd = vec3(1.0);
	
	// light 0
	{
		vec3 light_pos   = vec3(20.0, 20.0, 20.0);
		vec3 light_color = vec3(1.0, 0.7, 0.7);
	
		vec3 vl = normalize(light_pos - v);
	
		vec3 diffuse  = Kd * vec3(max(0.0, dot(vl, n)));
		vec3 specular = vec3(max(0.0, dot(vl, ref)));
		
        vec3 F = fresnel(Ks, normalize(vl - dir), vl);
		specular = pow(specular, vec3(shininess));
		
		final += light_color * mix(diffuse, specular, F); 
	}
	
	// light 1
	{
		vec3 light_pos   = vec3(-20.0, -20.0, -30.0);
		vec3 light_color = vec3(0.5, 0.7, 1.0);
	
		vec3 vl = normalize(light_pos - v);
	
		vec3 diffuse  = Kd * vec3(max(0.0, dot(vl, n)));
		vec3 specular = vec3(max(0.0, dot(vl, ref)));
        
        vec3 F = fresnel(Ks, normalize(vl - dir), vl);
		specular = pow(specular, vec3(shininess));
		
		final += light_color * mix(diffuse, specular, F);
	}

    final += fresnel(Ks, n, -dir);
    
	return final;
}


// ray marching pp
bool ray_marching_1(vec3 ro, vec3 rd, out float depth, out vec3 normal) {

	float accumulate_d = 0.0;

	for(int i = 0; i < MaxRaySteps; ++i)  {
		float d = distance_field(ro);
		accumulate_d += d;

		if (accumulate_d > Far)
			return false;

		if (d <= Epsilon)  {
			normal = gradient(ro);//, d);
			return true;
		}

		ro += rd * d;
	}
	return false;
}


// ray marching
bool ray_marching_2(vec3 ro, vec3 rd, inout float depth, inout vec3 normal) {
	//float epsilon = 0.001;	//0.000001;
	float t = 0.0;
    float d = depth;	//10000.0;
    float dt = 0.0;
	
    for(int i = 0; i < MaxRaySteps; ++i) {
        vec3 v = ro + rd * t;
        d = distance_field(v);

        if (d < Epsilon)
			break;

		// improves quality (epsilon banding?) but limits the step size to 0.1
		// investigate Inigos suggestion for unlimitted, distance_field driven step size
        dt = min(abs(d), 0.1);	
        t += dt;

        if (t >= depth)
			return false;
    }
    
    if (d >= Epsilon)
		return false;
    
    t -= dt;
    for(int i = 0; i < 4; ++i) {
        dt *= 0.5;
        
        vec3 v = ro + rd * (t + dt);
        if (distance_field(v) >= Epsilon) {
            t += dt;
        }
    }
    
    depth = t;
    normal = normalize(gradient(ro + rd * t));
    return true;
}


// PP main, with artefacts
void main_1(vec3 ro, vec3 rd) {
	float d = Far;
	vec3  n = vec3(0, 1, 0);
	if (ray_marching_1(ro, rd, d, n)) {
		float l = abs(dot(mat3(CAMM) * vec3(0, 0, 1), n));	// Camera is Lightsource
		fs_color = vec4(l, l, l, 1);
		return;
	}

	fs_color = vec4(gl_FragCoord.xy / Resolution, 0, 1);
}


// gltracy (https://www.shadertoy.com/view/XsB3Rm) and
// Jamie Wong (https://jamie-wong.com/2016/07/15/ray-marching-signed-distance-functions/)
vec4 main_2(vec3 ro, vec3 rd, float depth) {
	// float depth = Far;
    vec3 n = vec3(0.0);
	if (!ray_marching_2(ro, rd, depth, n)) {
		fs_color = vec4(gl_FragCoord.xy / Resolution, 0, 1);
        return vec4(fs_color.rgb, Far);
	}
	
	// shading
	// vec3 pos = ro + rd * depth;
    // vec3 color = shading(pos, n, rd, ro);
	// fs_color = vec4(pow(color, vec3(1.0 / 1.2)), 1.0);

	float l = abs(dot(mat3(CAMM) * vec3(0, 0, 1), n));	// Camera is Lightsource
	fs_color = vec4(l, l, l, 1);

	return vec4(fs_color.rgb, depth);
}

void main() {
	vec3 ro;
	vec3 rd;
	genRay(ro, rd);

	//*
	//sdf_heightmap(ro, rd);
	/*/
    main_2(ro, rd);
	/*/

	// raymarch heightmap, get color and depth
	vec4 sdf_hm = sdf_heightmap(ro, rd);
	fs_color = vec4(sdf_hm.rgb, 1);

	//*
	// raymarch distance functions, get shaded color and depth
	vec4 sdf_rm = main_2(ro, rd, Far);	//sdf_hm;
	//ray_marching_2(ro, rd, sdf_rm, n);
	//op_union_poly(sdf_rm, sdf_hm, 1.0);

	// minimum distance of heightmap and distance function, hard cut, same as op_union
	fs_color = vec4(sdf_hm.a < sdf_rm.a
		? sdf_hm.rgb
		: sdf_rm.rgb
		, 1);

	//*

	// try to blobby-blend the distances, including blend parameter t for colors
	// this does not work, as we are using fixed (directional) distances
	// blobbyness occurs only whith blending non-directional raymarch stepping,
	// when blending close distances
	vec2 depth_blend = op_union_cubic_t(sdf_rm.a, sdf_hm.a, 1.0);
	fs_color = vec4(mix(sdf_rm.rgb, sdf_hm.rgb, depth_blend.g), 1);
	//*/

	// main_1(ro, rd);
	//
	//fs_color = vec4(-ro, 1);
	//fs_color = vec4(0, 0, 0, 1);
}