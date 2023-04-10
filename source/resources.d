module resources;

import erupted;

import vdrive;
import app;

import dlsl.matrix;

debug import core.stdc.stdio : printf;



nothrow @nogc:

////////////////////////////////////////////////////////////////////////
// create vulkan related command and synchronization objects and data //
////////////////////////////////////////////////////////////////////////
void createCommandObjects( ref App_State app, VkCommandPoolCreateFlags command_pool_create_flags = 0 ) {

    //
    // create command pools
    //

    // one to process and display graphics, this one is rest on window resize events
    app.cmd_pool = app.createCommandPool( app.graphics_queue_family_index, command_pool_create_flags );



    //
    // create fence and semaphores
    //

    // must create all fences as we don't know the swapchain image count yet
    // but we also don't want to recreate fences in window resize events and keep track how many exist
    foreach( ref fence; app.submit_fence )
        fence = app.createFence( VK_FENCE_CREATE_SIGNALED_BIT ); // fence to sync CPU and GPU once per frame


    // rendering and presenting semaphores for VkSubmitInfo, VkPresentInfoKHR and vkAcquireNextImageKHR
    foreach( i; 0 .. App_State.MAX_FRAMES ) {
        app.acquired_semaphore[i] = app.createSemaphore;        // signaled when a new swapchain image is acquired
        app.rendered_semaphore[i] = app.createSemaphore;        // signaled when submitted command buffer(s) complete execution
    }



    //
    // configure submit and present infos
    //

    // draw submit info for vkQueueSubmit
    with( app.submit_info ) {
        waitSemaphoreCount      = 1;
        pWaitSemaphores         = & app.acquired_semaphore[0];
        pWaitDstStageMask       = & app.submit_wait_stage_mask; // configured before entering createResources func
        commandBufferCount      = 1;
    //  pCommandBuffers         = & app.cmd_buffers[ i ];       // set before submission, choosing cmd_buffers[0/1]
        signalSemaphoreCount    = 1;
        pSignalSemaphores       = & app.rendered_semaphore[0];
    }

    // initialize present info for vkQueuePresentKHR
    with( app.present_info ) {
        waitSemaphoreCount      = 1;
        pWaitSemaphores         = & app.rendered_semaphore[0];
        swapchainCount          = 1;
        pSwapchains             = & app.swapchain.swapchain;
    //  pImageIndices           = & next_image_index;           // set before presentation, using the acquired next_image_index
    //  pResults                = null;                         // per swapchain presentation results, redundant when using only one swapchain
    }
}



//////////////////////////////////////////////
// create simulation related memory objects //
//////////////////////////////////////////////
void createMemoryObjects( ref App_State app ) {

    // create static memory resources which will be referenced in descriptor set
    // the corresponding createDescriptorSet function might be overwritten somewhere else

    //
    // create uniform buffers - called once
    //

    auto wvpm_buffer = Meta_Buffer_T!( App_State.Ubo_Buffer )( app )
        .usage( VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT )
        .bufferSize( App_State.XForm_UBO.sizeof )
        .construct( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT )
        .mapMemory( app.xform_ubo )
        .reset( app.xform_ubo_buffer );

    // update projection matrix from member data _fovy, _near, _far and aspect of
    // the swapchain extent, initialized once, resized by the input.windowSizeCallback
    // however we can set _fovy, _near, _far to desired values before calling updateProjection
    app.updateProjection;

    // multiply projection with trackball (view) matrix and upload to uniform buffer
    app.updateWVPM;
}



///////////////////////////
// create descriptor set //
///////////////////////////
void createDescriptorSet( ref App_State app ) {

    // this is required if no Meta Descriptor has been passed in from the outside
    Meta_Descriptor_T!(9,3,8,4,3,2) meta_descriptor = app;    // temporary
    //Meta_Descriptor meta_descriptor;    // temporary

    // call the real create function
    app.createDescriptorSet_T( meta_descriptor );
}

void createDescriptorSet_T( Descriptor_T )( ref App_State app, ref Descriptor_T meta_descriptor ) {

    // configure descriptor set with required descriptors
    // the descriptor set will be constructed in createRenderRecources
    // immediately before creating the first pipeline so that additional
    // descriptors can be added through other means before finalizing
    // maybe we even might overwrite it completely in a parent struct

    app.descriptor = meta_descriptor     // App_State.descriptor is a Core_Descriptor

        // XForm_UBO
        .addUniformBufferBinding( 0, VK_SHADER_STAGE_VERTEX_BIT )
        .addBufferInfo( app.xform_ubo_buffer.buffer )

        // build and reset, returning a Core_Descriptor
        .construct
        .reset;
}



/////////////////////////////
// create render resources //
/////////////////////////////
void createResources( ref App_State app ) {

    //
    // create non-gui related render resources, currently no-op
    //
}



////////////////////////////////////////////////
// (re)create window size dependent resources //
////////////////////////////////////////////////
void resizeResources( ref App_State app, VkPresentModeKHR request_present_mode = VK_PRESENT_MODE_MAX_ENUM_KHR ) {

    //
    // destroy possibly existing swapchain and image views, but keep the surface.
    //
    if(!app.swapchain.is_null ) {
        app.device.vkDeviceWaitIdle;             // wait till device is idle
        app.destroy( app.swapchain, false );
    }



    //
    // select swapchain image format and presentation mode
    //

    // Optionally, we can pass in a request present mode, which will be preferred. It will not be checked for availability.
    // If VK_PRESENT_MODE_MAX_ENUM_KHR is passed in we check App_State.present_mode is valid and available (it's a setting, it will be set by ini file).
    // If it's value is set to VK_PRESENT_MODE_MAX_ENUM_KHR, or is not valid for the current implementation the present mode will be set
    // to VK_PRESENT_MODE_FIFO_KHR, which is mandatory for every swapchain supporting implementation.

    // Note: to get GPU swapchain capabilities to check for possible image usages
    //VkSurfaceCapabilitiesKHR surface_capabilities;
    //vkGetPhysicalDeviceSurfaceCapabilitiesKHR( swapchain.gpu, swapchain.swapchain, & surface_capabilities );
    //surface_capabilities.printTypeInfo;

    // we need to know the swapchain image format before we create a render pass
    // to render into that swapchain image. We don't have to create the swapchain itself
    // renderpass needs to be created only once in contrary to the swapchain, which must be
    // recreated if the window swapchain size changes
    // We set all required parameters here to avoid configuration at multiple locations
    // additionally configuration needs to happen only once

    // list of preferred formats and modes, the first found will be used, otherwise the first available not in lists
    VkFormat[4] request_format = [ VK_FORMAT_R8G8B8_UNORM, VK_FORMAT_B8G8R8_UNORM, VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_B8G8R8A8_UNORM ];

    // set present mode to the passed in value and trust that
    if( request_present_mode != VK_PRESENT_MODE_MAX_ENUM_KHR )
        app.present_mode = request_present_mode;

    else if( app.present_mode == VK_PRESENT_MODE_MAX_ENUM_KHR || !app.hasPresentMode( app.swapchain.surface, app.present_mode ))
        app.present_mode = VK_PRESENT_MODE_FIFO_KHR;

    // parametrize swapchain and keep Meta_Swapchain around to access extended data
    auto swapchain = Meta_Swapchain_T!( typeof( app.swapchain ))( app )
        .surface( app.swapchain.surface )
        .oldSwapchain( app.swapchain.swapchain )
        .selectSurfaceFormat( request_format )
        .presentMode( app.present_mode )
        .minImageCount( 2 )
        .imageArrayLayers( 1 )
        .imageUsage( VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT )
        .construct
        .reset( app.swapchain );

    // assign pointer of our new swapchain to the app.present_info
    app.present_info.pSwapchains = & app.swapchain.swapchain;



    //
    // create depth image
    //

    // first destroy old image and view
    if(!app.depth_image.image.is_null )
        app.destroy(  app.depth_image );

    // depth image format is also required for the renderpass
    VkFormat depth_image_format = VK_FORMAT_D32_SFLOAT;

    // prefer getting the depth image into a device local heap
    // first we need to find out if such a heap exist on the current device
    // we do not check the size of the heap, the depth image will probably fit if such heap exists
    // Todo(pp): the assumption above is NOT guaranteed, add additional functions to memory module
    // which consider a minimum heap size for the memory type, heap as well as memory creation functions
    auto depth_image_memory_property = app.memory_properties.hasMemoryHeapType( VK_MEMORY_HEAP_DEVICE_LOCAL_BIT )
        ? VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
        : VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;

    // depth_image_format can be set before this function gets called
    auto depth_image = Meta_Image_T!Core_Image_Memory_View( app )
        .format( depth_image_format )
        .extent( app.windowWidth, app.windowHeight )
        .usage( VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT )
        .sampleCount( app.sample_count )
        .constructImage
        .allocateMemory( depth_image_memory_property )
        .viewAspect( VK_IMAGE_ASPECT_DEPTH_BIT )
        .constructView
        .extractCore( app.depth_image );


    //
    // record transition of depth image from VK_IMAGE_LAYOUT_UNDEFINED to VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
    //

    // Note: allocate one command buffer
    auto cmd_buffer = app.allocateCommandBuffer( app.cmd_pool, VK_COMMAND_BUFFER_LEVEL_PRIMARY );

    VkCommandBufferBeginInfo cmd_buffer_bi = { flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    vkBeginCommandBuffer( cmd_buffer, & cmd_buffer_bi );

    cmd_buffer.recordTransition(
        depth_image.image,
        depth_image.image_view_ci.subresourceRange,
        VK_IMAGE_LAYOUT_UNDEFINED,
        VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        0,  // no access mask required here
        VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,     // this has been caught by the recent validation layers of vulkan spec v1.0.57
    );

    // finish recording
    cmd_buffer.vkEndCommandBuffer;

    // submit info stays local in this function scope
    auto submit_info = cmd_buffer.queueSubmitInfo;

    // submit the command buffer, we do not need to wait for the result here.
    app.graphics_queue.vkQueueSubmit( 1, & submit_info, VK_NULL_HANDLE ).vkAssert;



    //
    // create render pass and clear values
    //

    // clear values, stored in App_State
    app.clear_values
        .set( 0, 1.0f )                      // add depth clear value
        .set( 1, 0.0f, 0.0f, 0.0f, 1.0f );   // add color clear value

    // destroy possibly previously created render pass
    if(!app.render_pass_bi.renderPass.is_null )
        app.destroy( app.render_pass_bi.renderPass );


    //Meta_Render_Pass_T!( 2,2,1,0,1,0,0 ) render_pass;
    app.render_pass_bi = Meta_Render_Pass_T!( 2,2,1,0,1,0,0 )( app )
        .renderPassAttachment_Clear_None(  depth_image_format,    app.sample_count, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL           ).subpassRefDepthStencil
        .renderPassAttachment_Clear_Store( swapchain.imageFormat, app.sample_count, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR ).subpassRefColor( VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL )

        // Note: specify dependencies despite of only one subpass, as suggested by:
        // https://software.intel.com/en-us/articles/api-without-secrets-introduction-to-vulkan-part-4#
        //.addDependency( VK_DEPENDENCY_BY_REGION_BIT )
        //.srcDependency( VK_SUBPASS_EXTERNAL, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT         , VK_ACCESS_MEMORY_READ_BIT )
        //.dstDependency( 0                  , VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT )
        //.addDependency( VK_DEPENDENCY_BY_REGION_BIT )
        //.srcDependency( 0                  , VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT )
        //.dstDependency( VK_SUBPASS_EXTERNAL, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT         , VK_ACCESS_MEMORY_READ_BIT )

        // Note: specify dependencies despite of only one subpass, as suggested by:
        // https://github.com/KhronosGroup/Vulkan-Docs/wiki/Synchronization-Examples#swapchain-image-acquire-and-present
        .addDependency( VK_DEPENDENCY_BY_REGION_BIT )
        .srcDependency( VK_SUBPASS_EXTERNAL, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0 )
        .dstDependency( 0                  , VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT )

        .clearValues( app.clear_values )
        .construct
        .beginInfo;


    //import std.stdio;
    //writeln( render_pass.static_config );


    //
    // create framebuffers
    //
    VkImageView[1] render_targets = [ app.depth_image.view ];     // compose render targets into an array
    app.createFramebuffers(
        app.framebuffers,
        app.render_pass_bi.renderPass,              // specify render pass COMPATIBILITY
        app.swapchain.image_extent.width,           // framebuffer width
        app.swapchain.image_extent.height,          // framebuffer height
        render_targets,                             // first ( static ) attachments which will not change ( here only )
        app.swapchain.image_views.data              // next one dynamic attachment ( swapchain ) which changes per command buffer
    );

    app.render_pass_bi.renderAreaExtent( app.swapchain.image_extent );  // specify the render area extent of our render pass begin info



    //
    // update dynamic viewport and scissor state
    //
    app.viewport = VkViewport( 0, 0, app.swapchain.image_extent.width, app.swapchain.image_extent.height, 0, 1 );
    app.scissors = VkRect2D( VkOffset2D( 0, 0 ), app.swapchain.image_extent );
}



///////////////////////////////////
// (re)create draw loop commands //
///////////////////////////////////
void createCommands( ref App_State app ) nothrow {

    // we need to do this only if the gui is not displayed
//    if( app.draw_gui )
//        return;

    // reset the command pool to start recording drawing commands
    app.graphics_queue.vkQueueWaitIdle;   // equivalent using a fence per Spec v1.0.48
    app.device.vkResetCommandPool( app.cmd_pool, 0 ); // second argument is VkCommandPoolResetFlags


    // if we know how many command buffers are required we can use this static array function
    app.allocateCommandBuffers( app.cmd_pool, app.cmd_buffers[ 0 .. app.swapchain.image_count ] );


    // draw command buffer begin info for vkBeginCommandBuffer, can be used in any command buffer
    VkCommandBufferBeginInfo cmd_buffer_bi;


    // record command buffer for each swapchain image
    foreach( i, ref cmd_buffer; app.cmd_buffers[ 0 .. app.swapchain.image_count ] ) {    // remove .data if using static array

        // attach one of the framebuffers to the render pass
        app.render_pass_bi.framebuffer = app.framebuffers[ i ];

        // begin command buffer recording
        cmd_buffer.vkBeginCommandBuffer( & cmd_buffer_bi );

        // take care of dynamic state
        cmd_buffer.vkCmdSetViewport( 0, 1, & app.viewport );
        cmd_buffer.vkCmdSetScissor(  0, 1, & app.scissors );

        //
        // non-gui realted descriptor, curnently nothing to be drawn, hence calling this function should also be avoided
        //

        /*
        // bind descriptor set
        cmd_buffer.vkCmdBindDescriptorSets(         // VkCommandBuffer              commandBuffer
            VK_PIPELINE_BIND_POINT_GRAPHICS,        // VkPipelineBindPoint          pipelineBindPoint
            app.vis.display_pso.pipeline_layout,    // VkPipelineLayout             layout
            0,                                      // uint32_t                     firstSet
            1,                                      // uint32_t                     descriptorSetCount
            & app.descriptor.descriptor_set,        // const( VkDescriptorSet )*    pDescriptorSets
            0,                                      // uint32_t                     dynamicOffsetCount
            null                                    // const( uint32_t )*           pDynamicOffsets
        );
        */

        // begin the render pass
        cmd_buffer.vkCmdBeginRenderPass( & app.render_pass_bi, VK_SUBPASS_CONTENTS_INLINE );

        //
        // non-gui realted draws, curnently nothing to be drawn, hence calling this function should also be avoided
        //

        // end the render pass
        cmd_buffer.vkCmdEndRenderPass;

        // end command buffer recording
        cmd_buffer.vkEndCommandBuffer;
    }
}



//////////////////////////////
// destroy vulkan resources //
//////////////////////////////
void destroyResources( ref App_State app ) {

    import erupted;

    app.device.vkDeviceWaitIdle;

    // surface, swapchain and present image views
    app.destroy( app.swapchain );

    // memory Resources
    app.destroy( app.depth_image );
    app.destroy( app.xform_ubo_buffer );
    //app.unmapMemory( app.host_visible_memory ).destroy( app.host_visible_memory );

    // render setup
    foreach( ref f; app.framebuffers )  app.destroy( f );
    app.destroy( app.render_pass_bi.renderPass );
    app.destroy( app.descriptor );

    // command and synchronize
    app.destroy( app.cmd_pool );
    foreach( ref f; app.submit_fence )       app.destroy( f );
    foreach( ref s; app.acquired_semaphore ) app.destroy( s );
    foreach( ref s; app.rendered_semaphore ) app.destroy( s );
}

