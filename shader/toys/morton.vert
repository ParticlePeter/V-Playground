#version 450

layout( std140, binding = 0 ) uniform uboViewer {
    mat4 WVPM;                                  // World View Projection Matrix
};

//layout( location = 0 ) in  vec4 ia_position;  // input assembly/attributes, we passed in two vec3
//layout( location = 1 ) in  vec4 ia_color;     // they are filled automatically with 1 at the end to fit a vec4

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

uint MortonEncode(uint i)
{
    i = (i | (i << 8)) & 0x00FF00FF;
    i = (i | (i << 4)) & 0x0F0F0F0F;
    i = (i | (i << 2)) & 0x33333333;
    i = (i | (i << 1)) & 0x55555555;
    return i;
}

uint MortonDecode(uint i)
{
    i =  i & 0x55555555;
    i = (i | (i >> 1)) & 0x33333333;
    i = (i | (i >> 2)) & 0x0F0F0F0F;
    i = (i | (i >> 4)) & 0x00FF00FF;
    i = (i | (i >> 8)) & 0x0000FFFF;
    return i;
}

uvec2 IndexToZCurve(uint i) { return uvec2(MortonDecode(i), MortonDecode(i >> 1)); }
uint  ZCurveToIndex(uint x, uint y) { return MortonEncode(x) | (MortonEncode(y) << 1); }



// vkCmdDraw
void main() {
    uint divisor = 2;
    uint alignedResX = 18 / divisor;
    uint vi = VI / ( 32 * divisor * divisor );
    uint mi = VI % ( 32 * divisor * divisor );
    vec2 texCoord = divisor * vec2( 8, 4 ) * vec2( vi % alignedResX, vi / alignedResX ) + IndexToZCurve( mi );

    gl_Position = WVPM * vec4( - texCoord, 0, 1 );
    //gl_Position = WVPM * vec4( IndexToZCurve( VI ), 0, 1 );
    vs_color = vec4( 1, 0.5, 0, 1 );
}
