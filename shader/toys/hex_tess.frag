#version 450

layout( location = 0 ) out vec4 fs_color;  // output from fragment shader

layout( push_constant ) uniform Push_Constant {
    vec3 color;
} pc;

void main() {
    fs_color = vec4( pc.color, 1 );
}