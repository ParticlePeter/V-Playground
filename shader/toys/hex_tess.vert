#version 450

layout( std140, binding = 0 ) uniform uboViewer {
    mat4 WVPM;                                  // World View Projection Matrix 
};

layout( location = 0 ) in  vec4 ia_position;    // input assembly/attributes, we passed in two vec3

out gl_PerVertex {                              // not redifining gl_PerVertex used to create a layer validation error
    vec4  gl_Position;                          // not having clip and cull distance features enabled
    float gl_PointSize;
};                                              // error seems to have vanished by now, but it does no harm to keep this redefinition

void main() {
    gl_Position  = WVPM * vec4( ia_position.xy, 0.0 * dot( ia_position.xy, ia_position.xy ), 1 );
    gl_PointSize = 8.0;
}