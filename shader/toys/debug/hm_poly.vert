#version 450

// uniform buffer
layout(std140, binding = 0) uniform ubo {
    mat4	WVPM;	// World View Projection Matrix
//	mat4	WVPI; 	// World View Projection Inverse Matrix
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
    int    	HM_Min_Level;
	int		HM_Max_Level;
};

// Push Constants
layout( push_constant ) uniform Push_Constant {
    vec4    P_Color;

};

layout( binding = 2 ) uniform sampler2D noise_tex;

// Vertex Shader Output
layout( location = 0 ) out vec4 vs_color;       // vertex shader output vertex color, will be interpolated and rasterized

out gl_PerVertex {                              // not redifining gl_PerVertex used to create a layer validation error
    vec4 gl_Position;                           // not having clip and cull distance features enabled
};                                              // error seems to have vanished by now, but it does no harm to keep this redefinition

#define VI gl_VertexIndex
#define II gl_InstanceIndex


void main() {
    
    // only top poly
    // uint cells_per_axis = 1 << (HM_Max_Level - HM_Level);
    // vec4 pos = vec4(1);
    // vec2 ins = vec2(CC / cells_per_axis, CC % cells_per_axis);
    // pos.xz = (vec2(VI >> 1, VI & 1) + ins) / cells_per_axis;
    // pos.y  = HM_Height_Factor * textureLod(noise_tex, (ins + 0.5) / cells_per_axis, HM_Level).x;
    // gl_Position = WVPM * pos;
    // vs_color = P_Color;

    // cubes without bottomn
    uint CC = II / 5;
    uint cells_per_axis = 1 << (HM_Max_Level - HM_Level);
    vec2 ins = vec2(CC / cells_per_axis, CC % cells_per_axis);
    vec4 pos = vec4(1);
    switch(II % 5) {
        case 0: pos.xyz = vec3(VI >> 1, 1, VI & 1); break;
        case 1: pos.xyz = vec3(VI >> 1, VI & 1, 0); break;
        case 2: pos.xyz = vec3(VI >> 1, VI & 1, 1); break;
        case 3: pos.xyz = vec3(0, VI & 1, VI >> 1); break;
        case 4: pos.xyz = vec3(1, VI & 1, VI >> 1); break;
    }
    pos.xz = (pos.xz + ins) / cells_per_axis;
    float h = HM_Scale * textureLod(noise_tex, (ins + 0.5) / cells_per_axis, HM_Level).x;
    pos.y *= HM_Height_Factor * h;
    gl_Position = WVPM * pos;
    vs_color = P_Color * vec4(h * (ins + 1) / cells_per_axis, 0, 1);
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