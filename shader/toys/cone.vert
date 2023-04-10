#version 450

layout( std140, binding = 0 ) uniform uboViewer {
    mat4 WVPM;                                  // World View Projection Matrix
};

//layout( location = 0 ) in  vec4 ia_position;    // input assembly/attributes, we passed in two vec3
//layout( location = 1 ) in  vec4 ia_color;       // they are filled automatically with 1 at the end to fit a vec4

layout( location = 0 ) out vec4 vs_color;       // vertex shader output vertex color, will be interpolated and rasterized

out gl_PerVertex {                              // not redifining gl_PerVertex used to create a layer validation error
    vec4 gl_Position;                           // not having clip and cull distance features enabled
};                                              // error seems to have vanished by now, but it does no harm to keep this redefinition

#define VI gl_VertexIndex

//#define deg_to_rad 0.0 1745 3292 5199 4329 5769 2369 0768 489‬

vec4[] colors = {
    vec4( 0, 0, 1, 1 ),
    vec4( 0, 1, 1, 1 ),
    vec4( 0, 1, 0, 1 ),
    vec4( 1, 1, 0, 1 ),
    vec4( 1, 0, 0, 1 ),
    vec4( 1, 0, 1, 1 ),
};



// vkCmdDraw
void main() {

    // We store the per segent step in a (usually 0) component of the world view projection matrix.
    // - Make sure that the corresponding code in App_State.updateWVPM is enabled! -
    const float alpha = WVPM[3][0];
    mat4 wvpm = WVPM;
    wvpm[3][0] = 0;

    vec4 pos = vec4( 0, 0, 0, 1 );
    vs_color = pos;

    if( VI % 2 > 0 ) {
        pos.xy = vec2( -1, -1 );

        int vi = VI >> 1;
        float cosAlpha = cos( vi * alpha );
        float sinAlpha = sin( vi * alpha );
        mat2 Rot = mat2( cosAlpha, sinAlpha, - sinAlpha, cosAlpha );

        pos.xz = Rot * pos.xz;
        vs_color = colors[ vi % 6 ];
    }

    gl_Position = wvpm * pos;
}


/*
// vkCmdDrawIndexed
void main() {

    const float alpha = 60.0 * 0.0174532925199432957692369;

    vec4 pos = vec4( 0, 0, 0, 1 );
    vs_color = pos;

    if( VI > 0 ) {
        pos.xy = vec2( -1, -1 );

        int vi = VI - 1;
        float cosAlpha = cos( vi * alpha );
        float sinAlpha = sin( vi * alpha );
        mat2 Rot = mat2( cosAlpha, sinAlpha, - sinAlpha, cosAlpha );

        pos.xz = Rot * pos.xz;
        vs_color = colors[ vi % 6 ];
    }

    gl_Position = WVPM * pos;
}
*/