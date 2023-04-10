module toys.hex_tess;

import bindbc.glfw;

import dlsl.matrix;

import app;
import input;
import erupted;

import vdrive.buffer;
import vdrive.memory;
import vdrive.pipeline;
import vdrive.util.util;
import vdrive.util.array;



string name() pure nothrow @nogc { return "Hex Tesselate"; }

///////////////////////////////////////////////////////
// setup required features for device initialization //
///////////////////////////////////////////////////////
VkPhysicalDeviceFeatures getRequiredFeatures() {
    VkPhysicalDeviceFeatures features;
    features.fillModeNonSolid = true;
    features.largePoints = true;
    features.wideLines = true;
    return features;
}

/*

private {
    Core_Pipeline   pso_wire;
    Core_Pipeline   pso_pnts;

    Core_Buffer     vtx_buffer;
    Core_Buffer     idx_buffer;
    VkDeviceMemory  buffer_memory;
}



////////////////////////////////////////////////////////////////////
// create window size independent resources once before draw loop //
////////////////////////////////////////////////////////////////////

void createResources( ref App_State app, bool recreate = false ) {

    /////////////////////////////////
    // create fence and semaphores //
    /////////////////////////////////

    import vdrive.synchronizer;
    app.submit_fence[0] = app.createFence( VK_FENCE_CREATE_SIGNALED_BIT );          // fence to sync CPU and GPU once per frame
    app.submit_fence[1] = app.createFence( VK_FENCE_CREATE_SIGNALED_BIT );          // fence to sync CPU and GPU once per frame

    // rendering and presenting semaphores for VkSubmitInfo, VkPresentInfoKHR and vkAcquireNextImageKHR
    app.acquired_semaphore = app.createSemaphore;   // signaled when a new swapchain image is acquired
    app.rendered_semaphore = app.createSemaphore;   // signaled when submitted command buffer(s) complete execution



    /////////////////////////////////////
    // configure submit and present infos
    /////////////////////////////////////

    // draw submit info for vkQueueSubmit
    with( app.submit_info ) {
        waitSemaphoreCount      = 1;
        pWaitSemaphores         = & app.acquired_semaphore;
        pWaitDstStageMask       = & app.submit_wait_stage_mask; // configured before entering createResources func
        commandBufferCount      = 1;
    //  pCommandBuffers         = & app.cmd_buffers[ i ];       // set before submission, choosing cmd_buffers[0/1]
        signalSemaphoreCount    = 1;
        pSignalSemaphores       = & app.rendered_semaphore;
    }

    // present info for vkQueuePresentKHR
    with( app.present_info ) {
        waitSemaphoreCount      = 1;
        pWaitSemaphores         = & app.rendered_semaphore;
        swapchainCount          = 1;
    //  pSwapchains             = & app.swapchain.swapchain;    // set after (re)creating swapchain
    //  pImageIndices           = & next_image_index;           // set before presenting, using the acquired next_image_index
    }



    //////////////////////////////////
    // create matrix uniform buffer //
    //////////////////////////////////

    import vdrive.buffer;   // here we add
    auto wvpm_buffer = Meta_Buffer_T!( App_State.Ubo_Buffer )( app )
        .usage( VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT )
        .bufferSize( 16 * float.sizeof )   // mat4.sizeof
        .construct( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT )
        .mapMemory( app.wvpm )
        .reset( app.wvpm_buffer );

    // update projection matrix from member data _fovy, _near, _far and aspect of
    // the swapchain extent, initialized once, resized by the input.windowSizeCallback
    // however we can set _fovy, _near, _far to desired values before calling updateProjection
    app.updateProjection;

    // multiply projection with trackball (view) matrix and upload to uniform buffer
    app.updateWVPM;



    ///////////////////////////
    // create descriptor set //
    ///////////////////////////

    import vdrive.descriptor;

    {   // allocates and frees when leaving scope
        app.descriptor = Meta_Descriptor( app )
            .addUniformBufferBinding( 0, VK_SHADER_STAGE_VERTEX_BIT )
            .addBufferInfo( app.wvpm_buffer.buffer )
            .construct
            .reset;
    }



    ////////////////////////////////////////////////////////////////
    // create command pool, we might need now to move data on GPU //
    ////////////////////////////////////////////////////////////////

    import vdrive.commander;
    app.cmd_pool = app.createCommandPool( app.graphics_queue_family_index );



    ///////////////////////////////////////////////////////
    // create window size dependent resources first time //
    ///////////////////////////////////////////////////////

    // this creates, among others, a render pass which is needed for PSO construction
    app.resizeResources;



    /////////////////////////////////
    // geometry with draw commands //
    /////////////////////////////////

    uint aDivisionCount = 3;
    alias MC_Vector2f = vec2;

    // For the Vertex Count, we split the Hex into six Triangles and count the vertices of each triangle with d - 1 divisions.
    // This is very simple as we can use the triangular number scheme and little gauss sum formula (n * (n + 1)) / 2 = (n * n + n) / 2.
    // At the end we a add one for the Hex central vertex.
    uint divisions = aDivisionCount + 1;      // for d divisions vertex count per hex triangle we would use aDivisionCount + 2
    uint tri_vtx_count = (divisions * divisions + divisions) / 2;       // vertex count of a hex triangle of aDivisonCount - 1
    uint hex_tri_count = 6;
    uint vtx_count = 1 + hex_tri_count * tri_vtx_count;

    // For the Index Count, we split the Hex into six Triangles, and compute its (subdivided) Sub-Triangles
    // With each triangle, we can add a Triangle-Strip at the bottom, forming a new subdivided triangle, with the next division count.
    // Starting at division 0, each summand adding the next division count we get: 1 + 3 + 5 + 7 + 9 ... sub-triangles,
    // for a total per division of: 1, 4, 9, 16, 25. Thus the formula for the sub-triangles of a triangle count is (d + 1) ^ 2
    // for a total index count of: 3 * 6 * (d + 1) ^ 2 = 3 indexes per Tri * 6 Subdivided Triangles per Hex * (d + 1) ^ 2 Sub-Triangles
    uint idx_count = 3 * hex_tri_count * divisions * divisions;
    uint idx_offset = 0;


    {
        // create  one vertex and one index buffer backed by one memory object
        auto stage_vtx_buffer = Meta_Buffer( app )                  // begin parametrizing the temporary staging Meta_Buffer
            .usage( VK_BUFFER_USAGE_TRANSFER_SRC_BIT )              // only purpose of this buffer is to be a transfer source
            .bufferSize( vtx_count * vec2.sizeof )               // specify the required buffer size
            .constructBuffer;                                       // create the internal VkBuffer object

        auto stage_idx_buffer = Meta_Buffer( app )                  // begin parametrizing the temporary staging Meta_Buffer
            .usage( VK_BUFFER_USAGE_TRANSFER_SRC_BIT )              // only purpose of this buffer is to be a transfer source
            .bufferSize( idx_count * ushort.sizeof )               // specify the required buffer size
            .constructBuffer;                                       // create the internal VkBuffer object

        void* mapped_memory;
        auto stage_buffer_memory = Meta_Memory( app )
            .memoryType( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT )
            .allocateAndBind( stage_vtx_buffer, stage_idx_buffer )
            .mapMemory( mapped_memory );

        // map and the memory twice at different locations, once for vertex and once for index buffer
        vec2*   vrts = cast( vec2* )mapped_memory;
        short*  idxs = cast( short* )( mapped_memory + stage_idx_buffer.memOffset );

        // now use hex corners to create subdivided vertices and corresponding index data

        // hex edge length: 2.0, hex corner order: TR, T, TL, BL, B, BR
        float cos_alpha = 2.0f * 0.86602540378443864676372317075294f;
        float sin_alpha = 1.0f;

        vec2[6] hex_corners = [
            vec2(   cos_alpha,   sin_alpha ),
            vec2(   0.0f,   2.0f ),
            vec2( - cos_alpha,   sin_alpha ),
            vec2( - cos_alpha, - sin_alpha ),
            vec2(   0.0f, - 2.0f ),
            vec2(   cos_alpha, - sin_alpha )
        ];

        vrts[0] = vec2( 0.0f );
        ushort idx = 0;
        for (ushort t = 0; t < hex_tri_count; ++t)
        {
            MC_Vector2f stepA = hex_corners[ t ] / divisions;                   // invert winding with [ 5 - t ] and ...
            MC_Vector2f stepB = hex_corners[ ( t + 2 ) % 6 ] / divisions;       // [ ( 5 - t + 4 ) % 6 ]
            for (uint a = 1; a <= divisions; ++a)
            {
                MC_Vector2f v = stepA * a;
                for (uint b = 0; b < a; ++b)
                {
                    //idx++;
                    vrts[ ++idx ] = v + stepB * b;
                }
            }
        }

        import std.stdio;
        writeln( vtx_count );

        idx = 0;
        for (ushort s = 0; s < hex_tri_count; ++s)
        {
            idxs[ idx++ ] = cast( ushort )(  1 + s * tri_vtx_count );
            idxs[ idx++ ] = 0;
            idxs[ idx++ ] = cast( ushort )(( 1 + ( s + 1 ) * tri_vtx_count ) % vtx_count + s / 5 );

            uint ts = 3 * s * divisions * divisions;
            //writefln( "RS: %s, RE: %s, Indexes: %s", rs, re, idxs[ ts .. idx ] );
            //writeln( idxs[ ts .. idx ] );

            uint upp_first_vtx = 0 + s * tri_vtx_count;
            uint low_first_vtx = 1 + s * tri_vtx_count;
            uint row_tri_count = 1;

            for (ushort r = 1; r < divisions; ++r)
            {
                upp_first_vtx = low_first_vtx;
                low_first_vtx += r;

                uint t_odd;
                uint t_pair;

                for (ushort t = 0; t < row_tri_count; ++t)
                {
                    t_odd  = t & 1;
                    t_pair = t >> 1;

                    idxs[ idx++ ] = cast( ushort )( low_first_vtx + t_pair + t_odd );
                    idxs[ idx++ ] = cast( ushort )( upp_first_vtx + t_pair );
                    idxs[ idx++ ] = cast( ushort )( (t_odd ? upp_first_vtx : low_first_vtx) + t_pair + 1 );
                }

                t_odd = 1 - t_odd;

                idxs[ idx++ ] = cast( ushort )(  low_first_vtx + t_pair + t_odd );
                idxs[ idx++ ] = cast( ushort )(  upp_first_vtx + t_pair );
                idxs[ idx++ ] = cast( ushort )(( upp_first_vtx + tri_vtx_count ) % vtx_count + s / 5 );

                t_odd = 1 - t_odd;
                t_pair++;

                idxs[ idx++ ] = cast( ushort )(  low_first_vtx + t_pair + t_odd );
                idxs[ idx++ ] = cast( ushort )(( upp_first_vtx + tri_vtx_count ) % vtx_count + s / 5 );
                idxs[ idx++ ] = cast( ushort )(( low_first_vtx + tri_vtx_count ) % vtx_count + s / 5 );

                row_tri_count += 2;

                //writefln( "RS: %s, RE: %s, Indexes: %s", rs, re, idxs[ rs .. re ] );
                //writeln( idxs[ ts .. idx ] );
            }
        }

        app.flushMappedMemoryRange( stage_buffer_memory.memory );

        auto meta_vtx_buffer = Meta_Buffer( app )                   // begin parametrizing the temporary staging Meta_Buffer
            .addUsage( VK_BUFFER_USAGE_TRANSFER_DST_BIT )           // only purpose of this buffer is to be a transfer source
            .addUsage( VK_BUFFER_USAGE_VERTEX_BUFFER_BIT )
            .bufferSize( vtx_count * vec2.sizeof )                  // specify the required buffer size
            .constructBuffer                                        // create the internal VkBuffer object
            .extractCore( vtx_buffer );

        auto meta_idx_buffer = Meta_Buffer( app )                   // begin parametrizing the temporary staging Meta_Buffer
            .addUsage( VK_BUFFER_USAGE_TRANSFER_DST_BIT )           // only purpose of this buffer is to be a transfer source
            .addUsage( VK_BUFFER_USAGE_INDEX_BUFFER_BIT )
            .bufferSize( idx_count * uint16_t.sizeof )              // specify the required buffer size
            .constructBuffer                                        // create the internal VkBuffer object
            .extractCore( idx_buffer );

        buffer_memory = Meta_Memory( app )
            .memoryType( VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT )
            .allocateAndBind( meta_vtx_buffer, meta_idx_buffer )
            .memory;


        // allocate one command buffer
        VkCommandBuffer cmd_buffer = app.allocateCommandBuffer( app.cmd_pool, VK_COMMAND_BUFFER_LEVEL_PRIMARY );

        // begin command buffer recording, cmd_buffer_bi was declared before two scopes
        VkCommandBufferBeginInfo cmd_buffer_bi = { flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
        vkBeginCommandBuffer( cmd_buffer, & cmd_buffer_bi );

        // required for the vkCmdCopyBuffer
        VkBufferCopy buffer_copy = {
            srcOffset   : 0,
            dstOffset   : 0,
            size        : vtx_count * vec2.sizeof
        };

        // record vertex buffer copy
        cmd_buffer.vkCmdCopyBuffer( stage_vtx_buffer.buffer, vtx_buffer.buffer, 1, & buffer_copy );

        // reuse previous data struct
        buffer_copy.size = idx_count * uint16_t.sizeof;

        // record index buffer copy
        cmd_buffer.vkCmdCopyBuffer( stage_idx_buffer.buffer, idx_buffer.buffer, 1, & buffer_copy );

        // finish recording
        cmd_buffer.vkEndCommandBuffer;

        // submit the command buffer, combines parametrizing a VkSubmitInfo and the submission
        app.graphics_queue.queueSubmit( cmd_buffer );

        // destroy staging buffer
        app.graphics_queue.vkQueueWaitIdle;     // equivalent using a fence per Spec v1.0.48


        //vtx_count = 5;
        //idx_offset = idx_count - 12;
        //idx_count = idx_count - 12;

        //writeln( idxs[ 0 .. idx_count ] );




        // destroy the temporary staging resources
        stage_vtx_buffer.destroyResources;
        stage_idx_buffer.destroyResources;
        stage_buffer_memory.destroyResources;
    }




    ////////////////////////////////////////
    // create pipeline state object (PSO) //
    ////////////////////////////////////////

    // add shader stages - git repo needs only to keep track of the shader sources,
    // vdrive will compile them into spir-v with glslangValidator (must be in path!)
    import vdrive.pipeline, vdrive.shader;
    auto meta_graphics = Meta_Graphics( app );
    app.pipeline = meta_graphics
        .addShaderStageCreateInfo( app.createPipelineShaderStage( "example/sw_01_triangle/shader/hex_tess.vert" ))    // deduce shader stage from file extension
        .addShaderStageCreateInfo( app.createPipelineShaderStage( "example/sw_01_triangle/shader/hex_tess.frag" ))    // deduce shader stage from file extension
        .addBindingDescription( 0, vec2.sizeof, VK_VERTEX_INPUT_RATE_VERTEX )       // add vertex binding and attribute descriptions
        .addAttributeDescription( 0, 0, VK_FORMAT_R32G32_SFLOAT, 0 )                // 2D vertex coordinates
        .inputAssembly( VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST )                       // set the inputAssembly
        .addViewportAndScissors( VkOffset2D( 0, 0 ), app.swapchain.image_extent )   // add viewport and scissor state, necessary even if we use dynamic state
        .cullMode( VK_CULL_MODE_FRONT_BIT )                                         // set rasterization state -  this cull mode is the default value
        .depthState                                                                 // set depth state - enable depth test with default attributes
        .addColorBlendState( VK_FALSE )                                             // color blend state - append common (default) color blend attachment state
        .addDynamicState( VK_DYNAMIC_STATE_VIEWPORT )                               // add dynamic states viewport
        .addDynamicState( VK_DYNAMIC_STATE_SCISSOR )                                // add dynamic states scissor
        .addDescriptorSetLayout( app.descriptor.descriptor_set_layout )             // describe pipeline layout
        .addPushConstantRange( VK_SHADER_STAGE_FRAGMENT_BIT, 0, 12 )                // specify push constant range, 3 * sizeof( float )
        .renderPass( app.render_pass_bi.renderPass )                                // describe COMPATIBLE render pass
        .construct                                                                  // construct the Pipleine Layout and Pipleine State Object (PSO)
        .extractCore;                                                               // extract our core vulkan primitives for the normal shaded pipeline

    pso_wire = meta_graphics
        .cullMode( VK_CULL_MODE_NONE )                                              // set rasterization state -  this cull mode is the default value
        .polygonMode( VK_POLYGON_MODE_LINE )                                        // temp construction data was not destroyed so far, so edit it to build a wire pso
        .lineWidth( 3.0f )
        .construct
        .extractCore;

    pso_pnts = meta_graphics
        .inputAssembly( VK_PRIMITIVE_TOPOLOGY_POINT_LIST )
        .construct
        .destroyShaderModules                                                       // shader modules compiled into pipeline are shared with the prev pso, can now be deleted now
        .reset;                                                                     // build and capture points core pso data and reset state/data of Meta_Graphics struct




    /////////////////////////////////////////////////////////////
    // create draw loop command buffers with resized resources //
    /////////////////////////////////////////////////////////////

    // reset the command pool to start recording drawing commands
    app.graphics_queue.vkQueueWaitIdle;                 // equivalent using a fence per Spec v1.0.48
    app.device.vkResetCommandPool( app.cmd_pool, 0 );   // second argument is VkCommandPoolResetFlags

    // this time cmd_buffers is an DArray!VkCommandBuffer, the array itself will be destroyed after this scope
    app.allocateCommandBuffers( app.cmd_pool, app.cmd_buffers[ 0 .. app.swapchain.image_count ] );

    // define clear values
    import vdrive.renderbuffer;
    VkClearValue[ 2 ] clear_values;
    clear_values
        .set( 0, 1.0f )                      // set depth clear value
        .set( 1, 0.0f, 0.0f, 0.0f, 1.0f );   // set color clear value

    vec3 surf_color = [ 0.5f, 0.5f, 0.5f ];
    vec3 wire_color = [ 1.0f, 1.0f, 0.0f ];
    vec3 pnts_color = [ 1.0f, 0.0f, 0.0f ];

    // record command buffer for each swapchain image
    foreach( i, ref cmd_buffer; app.cmd_buffers[ 0 .. app.swapchain.image_count ] ) {

        // attach clear values and one of the framebuffers to the render pass
        app.render_pass_bi.clearValues( clear_values );
        app.render_pass_bi.framebuffer = app.framebuffers[ i ];

        // begin command buffer recording
        VkCommandBufferBeginInfo cmd_buffer_bi;
        cmd_buffer.vkBeginCommandBuffer( & cmd_buffer_bi );

        // begin the render_pass
        cmd_buffer.vkCmdBeginRenderPass( & app.render_pass_bi, VK_SUBPASS_CONTENTS_INLINE );

        // take care of dynamic state
        cmd_buffer.vkCmdSetViewport( 0, 1, & app.viewport );
        cmd_buffer.vkCmdSetScissor(  0, 1, & app.scissors );

        // bind vertex buffer, only one attribute stored in this buffer
        VkDeviceSize offset = 0;
        cmd_buffer.vkCmdBindVertexBuffers(
            0,                                          // first binding
            1,                                          // binding count
            & vtx_buffer.buffer,                        // pBuffers to bind
            & offset                                    // pOffsets into buffers
        );

        // bind index buffer
        cmd_buffer.vkCmdBindIndexBuffer(
            idx_buffer.buffer,                          // index buffer
            0,                                          // offset
            VK_INDEX_TYPE_UINT16                        // index type
        );



        // bind graphics app.geom_pipeline
        cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_GRAPHICS, app.pipeline.pipeline );

        cmd_buffer.vkCmdBindDescriptorSets(             // VkCommandBuffer              commandBuffer
            VK_PIPELINE_BIND_POINT_GRAPHICS,            // VkPipelineBindPoint          pipelineBindPoint
            app.pipeline.pipeline_layout,               // VkPipelineLayout             layout
            0,                                          // uint32_t                     firstSet
            1,                                          // uint32_t                     descriptorSetCount
            & app.descriptor.descriptor_set,            // const( VkDescriptorSet )*    pDescriptorSets
            0,                                          // uint32_t                     dynamicOffsetCount
            null                                        // const( uint32_t )*           pDynamicOffsets
        );

        // set push constant values for first, surface draw
        cmd_buffer.vkCmdPushConstants( app.pipeline.pipeline_layout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, surf_color.sizeof, surf_color.ptr );

        // simple draw command, non indexed
        cmd_buffer.vkCmdDrawIndexed(
            idx_count,                                  // index count
            1,                                          // instance count
            0,                                          // first index
            0,                                          // vertex offset
            0,                                          // first instance
        );



        // bind graphics app.geom_pipeline
        cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_GRAPHICS, pso_wire.pipeline );

        // set push constant values for second, wire draw
        cmd_buffer.vkCmdPushConstants( pso_wire.pipeline_layout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, wire_color.sizeof, wire_color.ptr );

        // simple draw command, non indexed
        cmd_buffer.vkCmdDrawIndexed(
            idx_count,                                  // index count
            1,                                          // instance count
            0,                                          // first index
            0,                                          // vertex offset
            0,                                          // first instance
        );



        // bind graphics app.geom_pipeline
        cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_GRAPHICS, pso_pnts.pipeline );

        // set push constant values for second, wire draw
        cmd_buffer.vkCmdPushConstants( pso_pnts.pipeline_layout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, pnts_color.sizeof, pnts_color.ptr );

        cmd_buffer.vkCmdDraw(
            vtx_count,                                  // vertex count
            1,                                          // instance count
            0,                                          // first vertex
            0                                           // first instance
        );

        // end the render pass
        cmd_buffer.vkCmdEndRenderPass;

        // end command buffer recording
        cmd_buffer.vkEndCommandBuffer;
    }
}


// destroy resources and vulkan objects for rendering
void destroyResources( ref App_State app ) {

    import erupted, vdrive;

    app.device.vkDeviceWaitIdle;

    // surface, swapchain and present image views
    app.destroy( app.swapchain );

    // memory Resources
    app.destroy( app.geometry );
    app.destroy( app.depth_image );
    app.destroy( app.wvpm_buffer );

    app.destroy( vtx_buffer );
    app.destroy( idx_buffer );
    app.destroy( buffer_memory );

    // render setup
    foreach( ref f; app.framebuffers )  app.destroy( f );
    app.destroy( app.render_pass_bi.renderPass );
    app.destroy( app.descriptor );
    app.destroy( app.pipeline );
    app.destroy( pso_wire );
    app.destroy( pso_pnts );

    // command and synchronize
    foreach( ref f; app.submit_fence )  app.destroy( f );
    app.destroy( app.cmd_pool );
    app.destroy( app.acquired_semaphore );
    app.destroy( app.rendered_semaphore );
}

*/