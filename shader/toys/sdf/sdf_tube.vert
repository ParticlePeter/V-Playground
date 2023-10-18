#version 450

// per vertex data
out gl_PerVertex {                              // not redifining gl_PerVertex used to create a layer validation error
    vec4 gl_Position;                           // not having clip and cull distance features enabled
};                                              // error seems to have vanished by now, but it does no harm to keep this redefinition


// raster attributes
layout( location = 0 ) out vec2 vs_ndc_xy;   // vertex shader output vertex color, will be interpolated and rasterized


// vertex index
#define VI gl_VertexIndex


void main() {
    // use Verte Index to create a triangle in for XY coordinates in NDC Space with Z=0
    // the triangles rightangle is at -1 in X and Y and the other two corners are in (-1, 3) and (3, -1)
    // clipping takes care that only the interior quad spanned from (-1, -1) to (1, 1) is visible
    // we raster these coordinates and send them to the fragment stage 
    vs_ndc_xy = 4 * vec2( VI >> 1, VI & 1 ) - 1;
    gl_Position = vec4( vs_ndc_xy.x, - vs_ndc_xy.y, 0.0, 1.0 );    // for raymarch_tube.frag
}
