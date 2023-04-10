
import bindbc.glfw;
import dlsl.matrix;
import erupted;
import vdrive;
import input;

import settings : setting;

debug import core.stdc.stdio : printf;

enum validate_vulkan = true;
enum verbose = false;


nothrow @nogc:


//////////////////////////////
// application state struct //
//////////////////////////////
struct App_State {
    nothrow @nogc:

    // count of maximum per frame resources, might be less dependent on swapchain image count
    enum                        MAX_FRAMES = 2;

    // initialize
    Vulkan                      vk;
    alias                       vk this;
    VkQueue                     graphics_queue;
    uint32_t                    graphics_queue_family_index; // required for command pool
    GLFWwindow*                 window;

    // trackball and mouse
    TrackballButton             tbb;                        // Trackball manipulator updating View Matrix
    MouseMove                   mouse;

    // return window width and height stored in Meta_Swapchain struct
    @setting auto windowWidth()  @nogc { return swapchain.image_extent.width;  }
    @setting auto windowHeight() @nogc { return swapchain.image_extent.height; }

    // set window width and hight before recreating swapchain
    @setting void windowWidth(  uint32_t w ) @nogc { swapchain.image_extent.width  = w; }
    @setting void windowHeight( uint32_t h ) @nogc { swapchain.image_extent.height = h; }

    alias win_w = windowWidth;
    alias win_h = windowHeight;

    mat4                        projection;                 // Projection Matrix
    @setting float              projection_fovy =    60;    // Projection Field Of View in Y dimension
    @setting float              projection_near =   0.1;    // Projection near plane distance
    @setting float              projection_far  =  1000;    // Projection  far plane distance
    float                       projection_aspect;          // Projection aspect, will be computed from window dim, when updateProjection is called

    @setting mat3               look_at() @nogc { return tbb.lookingAt; }
    @setting void               look_at( ref mat3 etu ) @nogc { tbb.lookAt( etu[0], etu[1], etu[2] ); }

    // Todo(pp): calculate best possible near and far clip planes when manipulating the trackball

    // surface and swapchain
    Core_Swapchain_Queue_Extent swapchain;
    @setting VkPresentModeKHR   present_mode = VK_PRESENT_MODE_MAX_ENUM_KHR;
    VkSampleCountFlagBits       sample_count = VK_SAMPLE_COUNT_1_BIT;

    // UBO related resources
    struct XForm_UBO {
        mat4        wvpm;   // World View Projection Matrix
        float[3]    eyep = [ 0, 0, 0 ];
        float       time_step = 0.0;
    }

    XForm_UBO*  xform_ubo;      // pointer to mapped memory

    // memory Resources
    alias                       Ubo_Buffer = Core_Buffer_T!( 0, BMC.Memory | BMC.Mem_Range );
    Ubo_Buffer                  xform_ubo_buffer;
    Core_Image_Memory_View      depth_image;
    VkDeviceMemory              host_visible_memory;


    // command and related
    VkCommandPool               cmd_pool;
    VkCommandBuffer[MAX_FRAMES] cmd_buffers;
    VkPipelineStageFlags        submit_wait_stage_mask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkPresentInfoKHR            present_info;
    VkSubmitInfo                submit_info;


    // synchronize
    VkFence[ MAX_FRAMES ]       submit_fence;
    VkSemaphore[ MAX_FRAMES ]   acquired_semaphore;
    VkSemaphore[ MAX_FRAMES ]   rendered_semaphore;
    uint32_t                    next_image_index;


    // one descriptor for all purposes
    Core_Descriptor             descriptor;


    // render setup
    VkRenderPassBeginInfo       render_pass_bi;
    VkFramebuffer[ MAX_FRAMES ] framebuffers;
    VkClearValue[ 2 ]           clear_values;
    VkViewport                  viewport;               // dynamic state viewport
    VkRect2D                    scissors;               // dynamic state scissors

    // window resize callback result
    bool                        window_resized = false;


    import init;
    VkResult initVulkan( VkPhysicalDeviceFeatures* required_features = null ) {
        if( win_w == 0 ) win_w = 1600;
        if( win_h == 0 ) win_h =  900;
        return init.initVulkan( this, win_w, win_h, required_features ).vkAssert;
    }


    void destroyVulkan() {
        init.destroyVulkan( this );
    }


    // update projection matrix from member data _fovy, _near, _far
    // and the swapchain extent converted to aspect
    void updateProjection() {
        import dlsl.projection;
        projection = vkPerspective( projection_fovy, cast( float )windowWidth / windowHeight, projection_near, projection_far );
    }


    // multiply projection with trackball (view) matrix and upload to uniform buffer
    void updateWVPM() {
        xform_ubo.wvpm = projection * tbb.worldTransform;

        // prcompute cone segment rotation angle and store in wvpm[3][0]
        //(*wvpm)[3][0] = 2.0f * 3.14159265f / cone_segments;

        vk.flushMappedMemoryRange( xform_ubo_buffer.mem_range );
    }


    // recreate swapchain, called initially and if window size changes
    void recreateSwapchain() {
        // swapchain might not have the same extent as the window dimension
        // the data we use for projection computation is the glfw window extent at this place
        updateProjection;            // compute projection matrix from new window extent
        updateWVPM;                  // multiplies projection trackball (view) matrix and uploads to uniform buffer

        // notify trackball manipulator about win height change, this has effect on panning speed
        tbb.windowHeight( windowHeight );

        // recreate swapchain and other dependent resources
        try {
            //swapchain.create_info.imageExtent  = VkExtent2D( win_w, win_h );  // Set the desired swapchain extent, this might change at swapchain creation
            import resources : resizeResources;
            this.resizeResources( present_mode );   // destroy old and recreate window size dependent resources

        } catch( Exception ) {}
    }


    // this is used in windowResizeCallback
    // there only a VDrive_State pointer is available and we avoid ugly dereferencing
    void swapchainExtent( uint32_t win_w, uint32_t win_h ) {
        swapchain.image_extent = VkExtent2D( win_w, win_h );
    }


    // initial draw to overlap CPU recording and GPU drawing
    void drawInit() {

        // check if window was resized and handle the case
        if( window_resized ) {
            window_resized = false;
            recreateSwapchain;
            //import resources : createCommands;
            //this.createCommands;
        }

        // acquire next swapchain image, we use semaphore[0] which is also the first one on which we wait before our first real draw
        vk.device.vkAcquireNextImageKHR( swapchain.swapchain, uint64_t.max, acquired_semaphore[0], VK_NULL_HANDLE, & next_image_index );

        // reset the fence corresponding to the currently acquired image index, will be signal after next draw
        vk.device.vkResetFences( 1, & submit_fence[ next_image_index ] ).vkAssert;
    }


    // draw the simulation display and step ahead in the simulation itself (if in play or profile mode)
    void draw() @system {

        // select and draw command buffers
        //VkCommandBuffer[2] cmd_buffers = [ cmd_buffers[ next_image_index ], sim.cmd_buffers[ sim.ping_pong ]];
        submit_info.pCommandBuffers = & cmd_buffers[ next_image_index ];
        graphics_queue.vkQueueSubmit( 1, & submit_info, submit_fence[ next_image_index ] );   // or VK_NULL_HANDLE, fence is only required if syncing to CPU for e.g. UBO updates per frame

        // present rendered image
        present_info.pImageIndices = & next_image_index;
        swapchain.present_queue.vkQueuePresentKHR( & present_info );

        // edit semaphore attachment
        submit_info.pWaitSemaphores     = & acquired_semaphore[ next_image_index ];
        submit_info.pSignalSemaphores   = & rendered_semaphore[ next_image_index ];
        present_info.pWaitSemaphores    = & rendered_semaphore[ next_image_index ];

        // check if window was resized and handle the case
        if( window_resized ) {
            window_resized = false;
            recreateSwapchain;
            //import resources : createCommands;
            //this.createCommands;
        }

        // acquire next swapchain image
        vk.device.vkAcquireNextImageKHR( swapchain.swapchain, uint64_t.max, acquired_semaphore[ next_image_index ], VK_NULL_HANDLE, & next_image_index );

        // wait for finished drawing
        auto vkResult = vk.device.vkWaitForFences( 1, & submit_fence[ next_image_index ], VK_TRUE, uint64_t.max );
        debug if( vkResult != VK_SUCCESS )
            printf( "%s\n", vkResult.toCharPtr );
        vk.device.vkResetFences( 1, & submit_fence[ next_image_index ] ).vkAssert;
    }

    /*
    void draw() {

        // this bool and and the swapchain.create_info.imageExtent
        // was set in the window resize callback
        if( window_resized ) {
            window_resized = false;

            // swapchain might not have the same extent as the window dimension
            // the data we use for projection computation is the glfw window extent at this place
            updateProjection;            // compute projection matrix from new window extent
            updateWVPM;                  // multiplies projection trackball (view) matrix and uploads to uniform buffer

            // notify trackball manipulator about height change, this has effect on panning speed
            tbb.windowHeight( windowHeight );

            // destroy old and recreate new window size dependent resources
            import resources : resizeResources;
            this.resizeResources;
        }

        uint32_t next_image_index;
        // acquire next swapchain image
        device.vkAcquireNextImageKHR( swapchain.swapchain, uint64_t.max, acquired_semaphore, VK_NULL_HANDLE, & next_image_index );

        // wait for finished drawing
        device.vkWaitForFences( 1, & submit_fence[ next_image_index ], VK_TRUE, uint64_t.max );
        device.vkResetFences( 1, & submit_fence[ next_image_index ] ).vkAssert;

        // submit command buffer to queue
        submit_info.pCommandBuffers = &cmd_buffers[ next_image_index ];
        graphics_queue.vkQueueSubmit( 1, & submit_info, submit_fence[ next_image_index ] );   // or VK_NULL_HANDLE, fence is only requieed if syncing to CPU for e.g. UBO updates per frame

        // present rendered image
        present_info.pImageIndices = & next_image_index;
        swapchain.present_queue.vkQueuePresentKHR( & present_info );
    }
    */
}