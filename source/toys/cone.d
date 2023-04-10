module toys.cone;

import bindbc.glfw;

import dlsl.matrix;

import app;
import input;
import erupted;

import vdrive.util.util;
import vdrive.util.array;



string name() pure nothrow @nogc { return "Cone"; }

/*

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

    import vdrive.buffer;
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




    ///////////////////////////////////////////////////////
    // create window size dependent resources first time //
    ///////////////////////////////////////////////////////

    // this creates, among others, a render pass which is needed for PSO construction
    import triangle : resizeResources;
    app.resizeResources;



    ////////////////////////////////////////////////////////////////
    // create command pool, we might need now to move data on GPU //
    ////////////////////////////////////////////////////////////////

    import vdrive.commander;
    app.cmd_pool = app.createCommandPool( app.graphics_queue_family_index );



    /////////////////////////////////
    // geometry with draw commands //
    /////////////////////////////////

    bool draw_indexed = false;

    if( draw_indexed ) {

        //struct Vertex { float x, y, z; }
        uint16_t[14] indexes = [ 0,1,0,2,0,3,0,4,0,5,0,6,0,1 ];

        import vdrive.memory, vdrive.buffer;

        // prefer getting the vertex data into a device local heap
        // first we need to find out if such a heap exist on the current device
        // we do not check the size of the heap, the buffer will most likely fit if such heap exists
        if( !app.memory_properties.hasMemoryHeapType( VK_MEMORY_HEAP_DEVICE_LOCAL_BIT )) {

            // edit the internal Meta_Buffer via alias this
            app.geometry = Meta_Buffer_Memory( app )                    // init Meta_Geometry and its Meta_Buffer structs
                .usage( VK_BUFFER_USAGE_INDEX_BUFFER_BIT )              // we want to use the geometry buffer as index buffer
                .bufferSize( indexes.sizeof )                           // specify the required buffer size
                .construct( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT )       // create the internal VkBuffer object and required HOST_VISIBLE VkMemory
                .copyData( indexes )                                    // copy the data to our buffer, this internally maps and unmaps the buffer
                .reset;

        } else {
            // Here we create the staging Meta_Buffer resources and copy the data with a command buffer.
            // The final call staging_buffer.copyData uses a VkMappedMemoryRange to copy the data into the buffer.
            // Physical devices have a VkPhysicalDeviceLimits::nonCoherentAtomSize, which we must obey.
            // When our data fits into this (multiple of) nonCoherentAtoSize limit we can soleyly use that data object (triangle).
            // as argument to the copyData call without specifying an offset and a size.
            // But e.g. our triangle size ( 0x48 / 72 bytes ) does not obey NVidia GPU GeForce 1080 limit ( 0x40 / 64 bytes ).
            // We can pass in a corresponding (padded) data object or override the size, in particual, as the spec states, with VK_WHOLE_SIZE.
            auto staging_buffer = Meta_Buffer( app )                    // begin parametrizing the temporary staging Meta_Buffer
                .usage( VK_BUFFER_USAGE_TRANSFER_SRC_BIT )              // only purpose of this buffer is to be a transfer source
                .bufferSize( indexes.sizeof )                           // specify the required buffer size
                .construct( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT )       // create the internal VkBuffer object and required HOST_VISIBLE VkMemory
                .copyData( indexes, 0, VK_WHOLE_SIZE );                 // copy the data to our buffer, this internally maps and unmaps the buffer

            // edit the internal Meta_Buffer via alias this
            app.geometry = Meta_Buffer_Memory( app )                    // init Meta_Geometry and its Meta_Buffer structs
                .usage( VK_BUFFER_USAGE_INDEX_BUFFER_BIT                // we want to use the geometry buffer as vertex buffer
                      | VK_BUFFER_USAGE_TRANSFER_DST_BIT )              // and as transfer data (copy) destination
                .bufferSize( indexes.sizeof )                           // specify the required buffer size
                .construct( VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT )       // create the internal VkBuffer object and required device local VkMemory
                .reset;

            // allocate one command buffer
            VkCommandBuffer cmd_buffer = app.allocateCommandBuffer( app.cmd_pool, VK_COMMAND_BUFFER_LEVEL_PRIMARY );

            // begin command buffer recording, cmd_buffer_bi was declared before two scopes
            VkCommandBufferBeginInfo cmd_buffer_bi = { flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
            vkBeginCommandBuffer( cmd_buffer, & cmd_buffer_bi );

            // required for the vkCmdCopyBuffer
            VkBufferCopy buffer_copy = {
                srcOffset   : 0,
                dstOffset   : 0,
                size        : indexes.sizeof
            };

            // record the buffer copy
            cmd_buffer.vkCmdCopyBuffer( staging_buffer.buffer, app.geometry.buffer, 1, & buffer_copy );

            // finish recording
            cmd_buffer.vkEndCommandBuffer;

            // submit the command buffer, combines parametrizing a VkSubmitInfo and the submission
            app.graphics_queue.queueSubmit( cmd_buffer );

            // destroy staging buffer
            app.graphics_queue.vkQueueWaitIdle;     // equivalent using a fence per Spec v1.0.48
            staging_buffer.destroyResources;        // destroy the temporary staging resources
       }
   }



    ////////////////////////////////////////
    // create pipeline state object (PSO) //
    ////////////////////////////////////////

    // add shader stages - git repo needs only to keep track of the shader sources,
    // vdrive will compile them into spir-v with glslangValidator (must be in path!)
    import vdrive.pipeline, vdrive.shader;
    app.pipeline = Meta_Graphics( app )
        .addShaderStageCreateInfo( app.createPipelineShaderStage( "example/sw_01_triangle/shader/cone.vert" ))  // deduce shader stage from file extension
        .addShaderStageCreateInfo( app.createPipelineShaderStage( "example/sw_01_triangle/shader/cone.frag" ))  // deduce shader stage from file extension
        .inputAssembly( VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP )                      // set the inputAssembly
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

        // bind graphics app.geom_pipeline
        cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_GRAPHICS, app.pipeline.pipeline );

        // take care of dynamic state
        cmd_buffer.vkCmdSetViewport( 0, 1, & app.viewport );
        cmd_buffer.vkCmdSetScissor(  0, 1, & app.scissors );
        cmd_buffer.vkCmdBindDescriptorSets(             // VkCommandBuffer              commandBuffer
            VK_PIPELINE_BIND_POINT_GRAPHICS,            // VkPipelineBindPoint          pipelineBindPoint
            app.pipeline.pipeline_layout,               // VkPipelineLayout             layout
            0,                                          // uint32_t                     firstSet
            1,                                          // uint32_t                     descriptorSetCount
            & app.descriptor.descriptor_set,            // const( VkDescriptorSet )*    pDescriptorSets
            0,                                          // uint32_t                     dynamicOffsetCount
            null                                        // const( uint32_t )*           pDynamicOffsets
        );

        // do we want to use the index buffer to draw the cone? Minimal shader edits required!
        if( draw_indexed ) {

            // bind index buffer
            cmd_buffer.vkCmdBindIndexBuffer(
                app.geometry.buffer,
                0,
                VK_INDEX_TYPE_UINT16
            );

            // simple indexed draw command
            cmd_buffer.vkCmdDrawIndexed(
                14,                                         // index count
                1,                                          // instance count
                0,                                          // first index
                0,                                          // vertex offset, this is added to the indices
                0                                           // first instance
            );

        } else {

            // simple draw command, non indexed
            cmd_buffer.vkCmdDraw(
                2 * app.cone_segments + 2,                  // vertex count
                1,                                          // instance count
                0,                                          // first vertex
                0                                           // first instance
            );
        }

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
    if(!app.geometry.is_null )  // using geometry index buffer is conditional
        app.destroy( app.geometry);
    app.destroy( app.depth_image );
    app.destroy( app.wvpm_buffer );

    // render setup
    foreach( ref f; app.framebuffers )  app.destroy( f );
    app.destroy( app.render_pass_bi.renderPass );
    app.destroy( app.descriptor );
    app.destroy( app.pipeline );

    // command and synchronize
    foreach( ref f; app.submit_fence )  app.destroy( f );
    app.destroy( app.cmd_pool );
    app.destroy( app.acquired_semaphore );
    app.destroy( app.rendered_semaphore );
}

*/