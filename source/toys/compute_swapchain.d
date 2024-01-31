module toys.compute_swapchain;

import app;
import input;
import vdrive;
import erupted;


nothrow @nogc:

private {
    Core_Pipeline       pipeline;
}


// get toy's name and functions
App.Toy GetToy() {
    App.Toy toy;
    toy.name        = "Compute Swapchain";
    toy.create      = & createPSO;
    toy.recordPreRP = & recordCommands;
//  toy.widgets     = & buildWidgets;
    toy.destroy     = & destroyResources;
    return toy;
}



// create shader input assembly buffer and PSO
void createPSO( ref App app )
{
    ////////////////////////////////////////
    // create pipeline state object (PSO) //
    ////////////////////////////////////////

    // if we are recreating an old pipeline, destroy it first
    if( pipeline.pso != VK_NULL_HANDLE ) {
        app.graphics_queue.vkQueueWaitIdle;
        app.destroy( pipeline );
    }

    // create noise pso
    // tmeplate arg 1: descriptor set count, arg 2: push constant range count
    pipeline = Meta_Compute_T!( 1, 1)( app )   // extracting the core items after construction with reset call
        .shaderStageCreateInfo( app.createPipelineShaderStage( "shader/toys/sdf/noise_sc.comp" ))
        .addDescriptorSetLayout( app.descriptor.descriptor_set_layout )     // Storage Image to write to
        .addPushConstantRange( VK_SHADER_STAGE_COMPUTE_BIT, 0, 4 )          // edit noise parameter
        .construct( app.pipeline_cache )         // construct using pipeline cache
        .destroyShaderModule                     // destroy shader modules
        .reset;

    debug {
        app.setDebugName( pipeline.pipeline, "Compute Swapchain PSO" );
        app.setDebugName( pipeline.layout, "Compute Swapchain PSO Layout" );
    }
}


// record draw commands
void recordCommands( ref App app, VkCommandBuffer cmd_buffer ) {

    // bind graphics app.geom_pipeline
    cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.pipeline );
    cmd_buffer.vkCmdPushConstants( pipeline.pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, float.sizeof, & app.last_time );

    cmd_buffer.vkCmdBindDescriptorSets(             // VkCommandBuffer              commandBuffer
        VK_PIPELINE_BIND_POINT_COMPUTE,             // VkPipelineBindPoint          pipelineBindPoint
        pipeline.pipeline_layout,                   // VkPipelineLayout             layout
        0,                                          // uint32_t                     firstSet
        1,                                          // uint32_t                     descriptorSetCount
        & app.descriptor.descriptor_set,            // const( VkDescriptorSet )*    pDescriptorSets
        0,                                          // uint32_t                     dynamicOffsetCount
        null                                        // const( uint32_t )*           pDynamicOffsets
    );

    uint workgroup_count_x = app.win_w.aligned( 32 ) / 32;
    uint workgroup_count_y = app.win_h.aligned( 32 ) / 32;
    cmd_buffer.vkCmdDispatch( workgroup_count_x, workgroup_count_y, 1 );
}


// Build Gui Widgets
void buildWidgets( ref App app ) {
    import ImGui = d_imgui;            
    // if( ImGui.DragInt( "Cone Segment Count", & cone_segments, 0.1, 3, 256 )) {
    //     segment_angle = TAU / cone_segments;
    // }
}


// destroy resources and vulkan objects for rendering
void destroyResources( ref App app ) {
    app.destroy( pipeline );
}
