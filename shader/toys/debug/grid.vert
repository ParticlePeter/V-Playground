#version 450

// Uniform Buffer
layout(std140, binding = 0) uniform ubo {
    mat4	WVPM;	// World View Projection Matrix
//	mat4	WVPI; 	// World View Projection Inverse Matrix
	mat4	VIEW;  	// to transfrom into View Space	(inverse of CAMM)
    mat4	CAMM; 	// Camera Position and Rotation in World Space
	float	Aspect;
};

// Push Constants
layout( push_constant ) uniform Push_Constant {
    vec3  Grid_Center;
    float Grid_Scale;
    vec4  Grid_Color;
    uint  Cells_Per_Axis;
    float Crosshair_Scale;
    float Crosshair_Segment_Angle;
};

// Vertex Shader Output
layout( location = 0 ) out vec4 vs_color;       // vertex shader output vertex color, will be interpolated and rasterized

out gl_PerVertex {                              // not redifining gl_PerVertex used to create a layer validation error
    vec4 gl_Position;                           // not having clip and cull distance features enabled
};                                              // error seems to have vanished by now, but it does no harm to keep this redefinition

#define VI gl_VertexIndex
#define II gl_InstanceIndex


void main() {

    if (Crosshair_Scale > 0.0f) {

        int vi = (VI + 1) >> 1; // we use lines, vi: 0, 1, 1, 2, 2, 3, 3, ...
        gl_Position = vec4(0, 0.5 * Crosshair_Scale, 0, 1);
        float cos_angle = cos( vi * Crosshair_Segment_Angle );
        float sin_angle = sin( vi * Crosshair_Segment_Angle );
        mat2 ROT = mat2( cos_angle, sin_angle, - sin_angle, cos_angle );
        vs_color = vec4(1);
        gl_Position.xy = ROT * gl_Position.xy;
        gl_Position.y *= Aspect;

    } else { // Grid Drawing

        vec4 pos = vec4(Grid_Center, 1);
        pos.x += Grid_Scale * (((VI / 2) - 0.5  * Cells_Per_Axis)) / Cells_Per_Axis;
        pos.z += Grid_Scale * (((VI % 2) - 0.5) * Cells_Per_Axis)  / Cells_Per_Axis;
        if (II > 0) pos.zx = pos.xz;
        vs_color = Grid_Color; //vec4(0.5, 0.5, 0.5, 1.0);
        gl_Position = WVPM * pos;

    }   
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