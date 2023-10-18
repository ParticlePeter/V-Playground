#version 450

layout(location = 0) in   vec2 vs_tex_uv;   // input from vertex shader
layout(location = 0) out  vec4 fs_color;    // output from fragment shader


// push constants
layout( push_constant ) uniform Push_Constant {
    uint noise_mip_level;
};


layout( binding = 2 ) uniform sampler2D noise_tex;


void main() {
    fs_color = textureLod(noise_tex, vs_tex_uv, noise_mip_level);
    // fs_color = texture(noise_tex, vs_tex_uv);
    // fs_color = vec4(vs_tex_uv, 0.0, 1.0);
}