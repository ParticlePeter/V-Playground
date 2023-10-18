module toys.morton;

import app;
import input;
import vdrive;
import erupted;


nothrow @nogc:

private {
    Core_Pipeline   pipeline;
    int             vtx_count = 144 * 96;

}


// create shader input assembly buffer and PSO
void createResources( ref App app )
{
    ////////////////////////////////////////
    // create pipeline state object (PSO) //
    ////////////////////////////////////////

    // add shader stages - git repo needs only to keep track of the shader sources,
    // vdrive will compile them into spir-v with glslangValidator (must be in path!)
    import vdrive.pipeline, vdrive.shader;
    pipeline = Meta_Graphics( app )
        .addShaderStageCreateInfo( app.createPipelineShaderStage( "shader/toys/morton.vert" ))  // deduce shader stage from file extension
        .addShaderStageCreateInfo( app.createPipelineShaderStage( "shader/toys/simple.frag" ))  // deduce shader stage from file extension
        .inputAssembly( VK_PRIMITIVE_TOPOLOGY_LINE_STRIP )                          // set the inputAssembly
        .addViewportAndScissors( VkOffset2D( 0, 0 ), app.swapchain.image_extent )   // add viewport and scissor state, necessary even if we use dynamic state
        .cullMode( VK_CULL_MODE_NONE )                                              // set rasterization state -  this cull mode is the default value
        .depthState                                                                 // set depth state - enable depth test with default attributes
        .addColorBlendState( VK_FALSE )                                             // color blend state - append common (default) color blend attachment state
        .addDynamicState( VK_DYNAMIC_STATE_VIEWPORT )                               // add dynamic states viewport
        .addDynamicState( VK_DYNAMIC_STATE_SCISSOR )                                // add dynamic states scissor
        .addDescriptorSetLayout( app.descriptor.descriptor_set_layout )             // describe pipeline layout
        .renderPass( app.render_pass_bi.renderPass )                                // describe COMPATIBLE render pass
        .construct                                                                  // construct the Pipleine Layout and Pipleine State Object (PSO)
        .destroyShaderModules
        .reset;                                                                     // shader modules compiled into pipeline, not shared, can be deleted now
}


// record draw commands
void recordCommands( ref App app, VkCommandBuffer cmd_buffer ) {

    // bind graphics app.geom_pipeline
    cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pso );

    cmd_buffer.vkCmdBindDescriptorSets(             // VkCommandBuffer              commandBuffer
        VK_PIPELINE_BIND_POINT_GRAPHICS,            // VkPipelineBindPoint          pipelineBindPoint
        pipeline.layout,                            // VkPipelineLayout             layout
        0,                                          // uint32_t                     firstSet
        1,                                          // uint32_t                     descriptorSetCount
        & app.descriptor.descriptor_set,            // const( VkDescriptorSet )*    pDescriptorSets
        0,                                          // uint32_t                     dynamicOffsetCount
        null                                        // const( uint32_t )*           pDynamicOffsets
    );

    // simple draw command, non indexed
    cmd_buffer.vkCmdDraw(
        vtx_count,                                  // vertex count
        1,                                          // instance count
        0,                                          // first vertex
        0                                           // first instance
    );
}


// destroy resources and vulkan objects for rendering
void destroyResources( ref App app ) {
    app.destroy( pipeline );
}


// build gui widgets
void buildWidgets( ref App app ) {
    import ImGui = d_imgui;
    ImGui.DragInt( "Vertex Count", & vtx_count, 0.1, 2, 1024 * 128 );
}


// get toys name and functions
App.Toy GetToy() {
    App.Toy toy;
    toy.name    = "Morton Z-Curve";
    toy.create  = & createResources;
    toy.record  = & recordCommands;
    toy.destroy = & destroyResources;
    toy.widgets = & buildWidgets;
    return toy;
}