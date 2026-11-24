// WebGL2-safe WGSL for Bevy 0.18's automatically instanced Mesh3d pipeline.
// MeshTag bit layout: f0:6, fractional-frame:6, opacity:8, tint RGB:4+4+4.
// The PNG atlases contain premultiplied RGB; the output uses premultiplied blending.
#import bevy_pbr::{
    mesh_functions,
    view_transformations::position_world_to_clip
}

@group(#{MATERIAL_BIND_GROUP}) @binding(0) var flipbook: texture_2d<f32>;
@group(#{MATERIAL_BIND_GROUP}) @binding(1) var flipbook_sampler: sampler;

struct VertexInput {
    @builtin(instance_index) instance_index: u32,
    @location(0) position: vec3<f32>,
    @location(2) uv: vec2<f32>,
};
struct FragmentInput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) @interpolate(flat) tag: u32,
};

@vertex
fn vertex(input: VertexInput) -> FragmentInput {
    var output: FragmentInput;
    let model = mesh_functions::get_world_from_local(input.instance_index);
    let world_pos = mesh_functions::mesh_position_local_to_world(model, vec4<f32>(input.position, 1.0));
    output.clip_position = position_world_to_clip(world_pos.xyz);
    output.uv = input.uv;
    output.tag = mesh_functions::get_tag(input.instance_index);
    return output;
}

fn atlas_uv(frame: u32, input_uv: vec2<f32>) -> vec2<f32> {
    // A half-texel inset plus a 2-pixel transparent gutter prevents frame bleeding.
    let texel = 0.5 / f32(textureDimensions(flipbook).x);
    let xy = vec2<f32>(f32(frame % 8u), f32(frame / 8u));
    return clamp((xy + input_uv) * 0.125,
                 (xy * 0.125) + vec2<f32>(texel),
                 ((xy + vec2<f32>(1.0)) * 0.125) - vec2<f32>(texel));
}

@fragment
fn fragment(input: FragmentInput) -> @location(0) vec4<f32> {
    let index = input.tag & 63u;
    let subframe = f32((input.tag >> 6u) & 63u) / 63.0;
    let alpha = f32((input.tag >> 12u) & 255u) / 255.0;
    let tint = vec3<f32>(
        f32((input.tag >> 20u) & 15u),
        f32((input.tag >> 24u) & 15u),
        f32((input.tag >> 28u) & 15u)) / 15.0;
    let a = textureSample(flipbook, flipbook_sampler, atlas_uv(index, input.uv));
    let b = textureSample(flipbook, flipbook_sampler, atlas_uv(min(index + 1u, 63u), input.uv));
    let sample_color = mix(a, b, subframe);
    let edge = smoothstep(0.0, 0.10, input.uv.x)
        * smoothstep(0.0, 0.10, input.uv.y)
        * smoothstep(0.0, 0.10, 1.0 - input.uv.x)
        * smoothstep(0.0, 0.10, 1.0 - input.uv.y);
    let coverage = alpha * edge;
    return vec4<f32>(sample_color.rgb * tint * coverage, sample_color.a * coverage);
}
