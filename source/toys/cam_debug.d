module toys.cam_debug;

import app;
import input;
import vdrive;
import erupted;


nothrow @nogc:

private {
    struct Grid_PC {
        float[3]    center = [ 0.0f, 0.0f, 0.0f ];
        float       scale  = 0.0f;
        float[4]    color  = [ 0.5, 0.5, 0.5, 1.0 ];
        int         cells_per_axis = 12;
        float       crosshair_scale = 0.02f;
        float       crosshair_segment_angle = TAU / 16;
    }

    struct Axis_PC {
        float       segment_angle = TAU / 8;
        float       radius = 0.02f;
    }

    Core_Pipeline   grid_pso;
    Core_Pipeline   axis_pso;
    float[4]        center_and_scale = [ 0.0f, 0.0f, 0.0f, 1.0f ];
    int             cells_per_axis = 12;
    Grid_PC         grid;
    int             crosshair_segment_count = 16;
    int             axis_subdivs = 16;
    Axis_PC         axis;
    immutable float TAU = 6.283185307179586476925286766559;
}


// get toy's name and functions
App.Toy GetToy() {
    App.Toy toy;
    toy.name        = "Debug Camera";
    toy.create      = & createResources;
    toy.record      = & recordCommands;
    toy.destroy     = & destroyResources;
    toy.widgets     = & buildWidgets;
    return toy;
}


// create shader input assembly buffer and PSO
void createResources( ref App app ) {

    ////////////////////////////////////////
    // create grid_pso state object (PSO) //
    ////////////////////////////////////////

    // if we are recreating an old pipeline exists already, destroy it first
    if( axis_pso.pso != VK_NULL_HANDLE ) {
        app.graphics_queue.vkQueueWaitIdle;
        app.destroy( axis_pso );
    }

    if( grid_pso.pso != VK_NULL_HANDLE ) {
        app.graphics_queue.vkQueueWaitIdle;
        app.destroy( grid_pso );
    }

    // add shader stages - git repo needs only to keep track of the shader sources,
    // vdrive will compile them into spir-v with glslangValidator (must be in path!)
    import vdrive.pipeline, vdrive.shader;
    auto meta_graphics = Meta_Graphics( app );
    axis_pso = meta_graphics
        .addShaderStageCreateInfo( app.createPipelineShaderStage( "shader/toys/debug/axis.vert" ))  // deduce shader stage from file extension
        .addShaderStageCreateInfo( app.createPipelineShaderStage( "shader/toys/simple.frag" ))  // deduce shader stage from file extension
        .inputAssembly( VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP )                      // set the inputAssembly
    //  .polygonMode( VK_POLYGON_MODE_LINE )
        .addViewportAndScissors( VkOffset2D( 0, 0 ), app.swapchain.image_extent )   // add viewport and scissor state, necessary even if we use dynamic state
        .cullMode( VK_CULL_MODE_NONE )                                              // set rasterization state -  this cull mode is the default value
        .depthState                                                                 // set depth state - enable depth test with default attributes
        .addColorBlendState( VK_FALSE )                                             // color blend state - append common (default) color blend attachment state
        .addDynamicState( VK_DYNAMIC_STATE_VIEWPORT )                               // add dynamic states viewport
        .addDynamicState( VK_DYNAMIC_STATE_SCISSOR )                                // add dynamic states scissor
        .addDescriptorSetLayout( app.descriptor.descriptor_set_layout )             // describe grid_pso layout
        .addPushConstantRange( VK_SHADER_STAGE_VERTEX_BIT, 0, grid.sizeof )         // specify push constant range
        .renderPass( app.render_pass_bi.renderPass )                                // describe COMPATIBLE render pass
        .construct                                                                  // construct the Pipleine Layout and Pipleine State Object (PSO)
        .destroyShaderModules                                                       // shader modules compiled into grid_pso, not shared, can be deleted now
        .extractCore;

    grid_pso = meta_graphics
        .addShaderStageCreateInfo( app.createPipelineShaderStage( "shader/toys/debug/grid.vert" ))  // deduce shader stage from file extension
        .addShaderStageCreateInfo( app.createPipelineShaderStage( "shader/toys/simple.frag" ))  // deduce shader stage from file extension
        .inputAssembly( VK_PRIMITIVE_TOPOLOGY_LINE_LIST )
        .construct
        .destroyShaderModules
        .reset;
}


// record draw commands
void recordCommands( ref App app, VkCommandBuffer cmd_buffer ) {

    // bind descriptor set
    cmd_buffer.vkCmdBindDescriptorSets(             // VkCommandBuffer              commandBuffer
        VK_PIPELINE_BIND_POINT_GRAPHICS,            // VkPipelineBindPoint          grid_psoBindPoint
        grid_pso.pipeline_layout,                   // VkPipelineLayout             layout
        0,                                          // uint32_t                     firstSet
        1,                                          // uint32_t                     descriptorSetCount
        & app.descriptor.descriptor_set,            // const( VkDescriptorSet )*    pDescriptorSets
        0,                                          // uint32_t                     dynamicOffsetCount
        null                                        // const( uint32_t )*           pDynamicOffsets
    );

    // bind graphics axis_pso
    cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_GRAPHICS, axis_pso.pipeline );
    cmd_buffer.vkCmdPushConstants( axis_pso.pipeline_layout, VK_SHADER_STAGE_VERTEX_BIT, 0, axis.sizeof, & axis );

    // simple draw command, non indexed
    cmd_buffer.vkCmdDraw(
        2 * axis_subdivs + 2,      // vertex count
        12,                        // instance count
        0,                         // first vertex
        0                          // first instance
    );

    // bind graphics grid_pso
    cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_GRAPHICS, grid_pso.pipeline );
    cmd_buffer.vkCmdPushConstants( grid_pso.pipeline_layout, VK_SHADER_STAGE_VERTEX_BIT, 0, grid.sizeof, & grid );

    // draw the croshair circle if its scale is greater 0.0f
    if( grid.crosshair_scale > 0.0f ) {
        // simple draw command, non indexed
        cmd_buffer.vkCmdDraw(
            2 * crosshair_segment_count,   // vertex count
            1,                                  // instance count
            0,                                  // first vertex
            0                                   // first instance
        );

        float zero = 0.0f;  // set push constant crosshair_scale to 0.0f, so that grid can be drawn
        cmd_buffer.vkCmdPushConstants( grid_pso.pipeline_layout, VK_SHADER_STAGE_VERTEX_BIT, 
            grid.crosshair_scale.offsetof, zero.sizeof, & zero );
    }

    // simple draw command, non indexed
    cmd_buffer.vkCmdDraw(
        2 * grid.cells_per_axis + 2,    // vertex count
        2,                              // instance count
        0,                              // first vertex
        0                               // first instance
    );


}


// destroy resources and vulkan objects for rendering
void destroyResources( ref App app ) {
    app.destroy( axis_pso );
    app.destroy( grid_pso );
}


// Build Gui Widgets
void buildWidgets( ref App app ) {
    import ImGui = d_imgui;            
    app.AxisAndGrid;
    ImGui.Separator;
    app.debugCamera;
}

void setGridCellCountPerAxis( int n ) { grid.cells_per_axis = n; }
void setGridScaleAndHeightFactor( float min_xz, float max_xz, float h ) {
    float c = 0.5f * (min_xz + max_xz);
    grid.scale = max_xz - min_xz;
    grid.center[0] = grid.center[2] = c;
    grid.center[1] = h;
}


// draw axis and xz-grid (y-up world)
void AxisAndGrid( ref App app ) {
    import ImGui = d_imgui;
    ImGui.DragFloat3( "#Center", grid.center, 0.01f, -20.0f, 20.0f );
    ImGui.DragFloat( "#Scale", & grid.scale, 0.01f, -20.0f, 20.0f );            
    ImGui.DragInt( "#CellsPerAxis", & grid.cells_per_axis, 1.0f, 1, 21 );
    ImGui.ColorEdit4( "#Color", grid.color, ImGui.ImGuiColorEditFlags.DisplayHSV );// | misc_flags );
    
    ImGui.Separator;
    ImGui.DragFloat( "XHair Scale", & grid.crosshair_scale, 0.001f, 0.0f, 1.0f );
    if( ImGui.DragInt( "XHair Segmenta", & crosshair_segment_count, 1.0f, 1, 32 ))
        grid.crosshair_segment_angle = TAU / crosshair_segment_count;
    
    ImGui.Separator;
    if( ImGui.DragInt( "Axis Subdivis", & axis_subdivs, 1.0f, 3, 24 ))
        axis.segment_angle = TAU / axis_subdivs;

    ImGui.DragFloat( "Axis Radius", & axis.radius, 0.001f, 0.0f, 0.25f );
    ImGui.Separator;
}


// debug and verify camera functions and matrices
void debugCamera( ref App app ) {
    import ImGui = d_imgui;
    import dlsl.trackball;
    ImGui.PushItemWidth(-50);
    ImGui.Text( "Debug Camera Looking At" );
    auto eye_trg_up = app.tbb.lookingAt();
    void updateLookAt( uint lookAtIndex, string name ) {
        if( ImGui.DragFloat3( name, eye_trg_up[lookAtIndex], 0.01f, -20.0f, 20.0f )) {
            app.tbb.lookAt( eye_trg_up[0], eye_trg_up[1], eye_trg_up[2] );
            app.updateWVPM;
        }
    }
    updateLookAt( 0, "Eye" );
    updateLookAt( 1, "Target" );
    updateLookAt( 2, "Up" );
    
    ImGui.Separator;
    import dlsl.matrix;
    ImGui.Text( "Debug Camera (XForm) Matrix" );
    auto camm_transposed = app.ubo.camm.transpose;
    ImGui.DragFloat4("Row 0", camm_transposed[0], 0.01f, 0.0f, 1.0f);
    ImGui.DragFloat4("Row 1", camm_transposed[1], 0.01f, 0.0f, 1.0f);
    ImGui.DragFloat4("Row 2", camm_transposed[2], 0.01f, 0.0f, 1.0f);
    ImGui.DragFloat4("Row 3", camm_transposed[3], 0.01f, 0.0f, 1.0f);
    ImGui.PopItemWidth();
    ImGui.Separator;
}


