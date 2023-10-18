// source: https://www.youtube.com/watch?v=9g8CdctxmeU&list=PL0EpikNmjs2CYUMePMGh3IjjP4tQlYqji&index=9

#version 450

// uniform buffer
layout(std140, binding = 0) uniform uboViewer {
    mat4	WVPM;	// World View Projection Matrix
	mat4	WVPI; 	// World View Projection Inverse Matrix
	mat4	VIEW;  	// to transfrom into View Space	(inverse of CAMM)
    mat4	CAMM; 	// Camera Position and Rotation in World Space
	vec3	Eye_Pos;
	float 	FOV_Y;	// vertical field (angle) of view of the perspective projection
	vec4	Mouse;	// xy framebuffer coord when LMB pressed, zw when clicked
	uvec2	Resolution;
	float	Aspect;
	float	Time;
	float	Time_Delta;
	uint	Frame;
	float	Speed;
};


// rastered vertex attributes
layout(location = 0) in   vec2 vs_ndc_xy;  	// input from vertex shader
layout(location = 0) out  vec4 fs_color;      // output from fragment shader


// ro : ray origin
// rd : ray direction

float i_sphere(in vec3 ro, in vec3 rd, in vec4 xfm) {
	vec3 oc = ro - xfm.xyz;
	float b = 2.0 * dot(oc, rd);
	float c = dot(oc, oc) - xfm.w * xfm.w;
	float h = b * b - 4.0 * c;
	return h >= 0.0
		? - 0.5 * (b + sqrt(h))
		: - 1.0;
}

vec3 n_sphere(in vec3 pos, in vec4 xfm) {
	return normalize(pos - xfm.xyz) / xfm.w;
}

float i_plane(in vec3 ro, in vec3 rd) {
    return - ro.y / rd.y;
}

vec3 n_plane() {
    return vec3(0.0, 1.0, 0.0);
}


vec4 xfm_sph_0 = vec4(0.0, 1.0, 0.0, 1.0);

float intersect(in vec3 ro, in vec3 rd, out float t_res) {
	t_res = 1000.0;
	float id = -1.0;
	float t_sph = i_sphere(ro, rd, xfm_sph_0);
	float t_pla = i_plane (ro, rd);
	if (t_sph > 0.0) {
		id = 1.0;
		t_res = t_sph;
	}
	if (t_pla > 0.0 && t_pla < t_res) {
		id = 2.0;
		t_res = t_pla;
	}
	return id;
}


void main() {
	vec3 light = normalize(vec3(0.57703));

	// move the sphere
	xfm_sph_0.xz = 0.5 * vec2(cos(Speed), sin(Speed));

	// ray origin and direction
	vec3 ro = vec3(0.0, 0.5, 3.0);
	vec3 rd = normalize(vec3(vs_ndc_xy * vec2(Aspect, 1.0), -1.0));

	
	float t;
	float id = intersect(ro, rd, t);	// id : intersect distance

	
	vec3 rgb = vec3(0.0);
	
	if (id > 0.5 && id < 1.5) {
		// if we hit the sphere
		vec3 pos = ro + t * rd;
		vec3 nor = n_sphere(pos, xfm_sph_0);
		float dif = clamp(dot(nor, light), 0, 1);
		float ao = 0.5 + 0.5 * nor.y;
		rgb = vec3(0.9, 0.8, 0.6) * dif * ao + ao * vec3(0.1, 0.2, 0.4);
	}

	else if (id > 1.5) {
		// if we hit the plane
		vec3 pos = ro + t * rd;
		vec3 nor = n_plane();
		float dif = clamp(dot(nor, light), 0.0, 1.0);
		float amb = smoothstep(0.0, 2 * xfm_sph_0.w, length(pos.xz - xfm_sph_0.xz));
		rgb = amb * vec3(0.5, 0.6, 0.7);
	
	}

	fs_color = vec4(rgb, 1.0);
}