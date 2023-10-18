#version 450

// uniform buffer
layout(std140, binding = 0) uniform ubo {
    mat4	WVPM;	// World View Projection Matrix
};


// per vertex data
out gl_PerVertex {                              // not redifining gl_PerVertex used to create a layer validation error
    vec4 gl_Position;                           // not having clip and cull distance features enabled
};                                              // error seems to have vanished by now, but it does no harm to keep this redefinition


// raster attributes
layout(location = 0) out vec2 vs_tex_uv;   // vertex shader output vertex color, will be interpolated and rasterized


// vertex index
#define VI gl_VertexIndex


void main() {
    float scale = 2.0;
    vs_tex_uv = vec2(VI >> 1, VI & 1);
    gl_Position = WVPM * vec4(scale * vs_tex_uv - 0.5 * scale, 0.0, 1.0);  // for raymarch.frag
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