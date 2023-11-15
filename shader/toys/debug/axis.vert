#version 450

// Uniform Buffer
layout(std140, binding = 0) uniform uboViewer {
    mat4 WVPM;                                  // World View Projection Matrix
};

// Push Constants
layout(push_constant) uniform Push_Constant {
    float Axis_Segment_Angle;
    float Axis_Radius;
};

// Vertex Shader Output
layout(location = 0) out vec4 vs_color;       // vertex shader output vertex color, will be interpolated and rasterized

out gl_PerVertex {                              // not redifining gl_PerVertex used to create a layer validation error
    vec4 gl_Position;                           // not having clip and cull distance features enabled
};                                              // error seems to have vanished by now, but it does no harm to keep this redefinition

#define VI gl_VertexIndex
#define II gl_InstanceIndex

/*
const vec4[] colors = {
    vec4(0, 0, 1, 1),
    vec4(0, 1, 1, 1),
    vec4(0, 1, 0, 1),
    vec4(1, 1, 0, 1),
    vec4(1, 0, 0, 1),
    vec4(1, 0, 1, 1),
};
*/

const vec2[] profile = {
    vec2(0, 1),
    vec2(1.0,  0.6),
    vec2(0.5, 0.6),
    vec2(0.5, 0.0),
    vec2(0)
};


void main() {
    vec4 pos = vec4(0,0,0,1);
    float cos_angle = cos(VI / 2 * Axis_Segment_Angle);
    float sin_angle = sin(VI / 2 * Axis_Segment_Angle);
    mat2 ROT = mat2(cos_angle, sin_angle, - sin_angle, cos_angle);
    pos.xy = vec2(Axis_Radius, 1.0) * profile[((II % 4) + (VI % 2))];
    pos.xz = ROT * pos.xz;

    // an axis consists of 4 instanced triangle strips
    // every 4th instance we rotat the axis and color it differently
    uint IA = II / 4;

    if (IA == 1) pos.xy = vec2(pos.y, -pos.x);
    if (IA == 2) pos.zy = vec2(pos.y, -pos.z);

    vs_color = vec4(0, 0, 0, 1);
    vs_color[ (1 + 3 - IA) % 3 ] = 1;
    gl_Position = WVPM * pos;
}


/*
// vkCmdDrawIndexed
void main() {

    const float Angle = 60.0 * 0.0174532925199432957692369;

    vec4 pos = vec4(0, 0, 0, 1);
    vs_color = pos;

    if(VI > 0) {
        pos.xy = vec2(-1, -1);

        int vi = VI - 1;
        float cos_angle = cos(vi * Angle);
        float sin_angle = sin(vi * Angle);
        mat2 ROT = mat2(cos_angle, sin_angle, - sin_angle, cos_angle);

        pos.xz = ROT * pos.xz;
        vs_color = colors[ vi % 6 ];
    }

    gl_Position = WVPM * pos;
}
*/