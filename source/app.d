import bindbc.glfw;
import erupted;
import vdrive;
import input;
import dlsl;

import settings : setting;

debug import core.stdc.stdio : printf;

enum validate_vulkan = true;
enum verbose = false;


nothrow @nogc:




//////////////////////////////
// application state struct //
//////////////////////////////
struct App {
    nothrow @nogc:

    // count of maximum per frame resources, might be less dependent on swapchain image count
    enum                        MAX_FRAMES = 2;

    // initialize
    Vulkan                      vk;
    alias                       vk this;
    VkQueue                     graphics_queue;
    uint32_t                    graphics_queue_family_index; // required for command pool
    GLFWwindow*                 window;
    bool                        window_minimized = false;
    int                         monitor_count;
    int                         monitor_fullscreen_idx = 1;

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
    mat4                        projection_inverse;         // Inverse Projection Matrix
    float                       projection_aspect;          // Projection aspect, will be computed from window dim, when updateProjection is called
    @setting float              projection_fovy =    60;    // Projection Field Of View in Y dimension
    @setting float              projection_near =   0.1;    // Projection near plane distance
    @setting float              projection_far  =  1000;    // Projection  far plane distance

    @setting mat3               look_at() @nogc { return tbb.lookingAt; }
    @setting void               look_at( ref mat3 etu ) @nogc { tbb.lookAt( etu[0], etu[1], etu[2] ); }

    // Todo(pp): calculate best possible near and far clip planes when manipulating the trackball

    // surface and swapchain
    Core_Swapchain_Queue_Extent swapchain;
    @setting VkPresentModeKHR   present_mode = VK_PRESENT_MODE_MAX_ENUM_KHR;
    VkSampleCountFlagBits       sample_count = VK_SAMPLE_COUNT_1_BIT;

    // UBO related resources
    struct UBO {
        mat4    wvpm;   // World View Projection Matrix
    //  mat4    wvpi;   // World View Projection Inverse Matrix
        mat4    view;   // View Matrix, to transfrom into view space
        mat4    camm;   // Camera Matrix, position and orientation of the cam
        float   aspect;
        float   fowy = 1.0f;
        float   near = 0.001f;
        float   far  = 1000.0f;
        vec4    mouse = vec4(0.0f);
        vec2    resolution;
        float   time  = 0.0f;
        float   time_delta = 0.0f;
        uint    frame = 0;
        float   speed = 0.0f;   // accumulated speed_amp * time_delta

        // Ray Marching
	    int	    max_ray_steps = 1;
	    float   epsilon = 0.000001f;

        // Heightmap
        float   hm_scale   = 10.0f; 
        float   hm_height_factor = 0.5f;
        int     hm_level = 0;
        int     hm_max_level = 0;
    }   

    UBO*  ubo;              // pointer to mapped memory
    float speed_amp = 1.0f; // speed amplifier for accumulation
    float last_time;

    void initUBO() {
        ubo.max_ray_steps = 1;
        ubo.epsilon  = 0.01f;
        ubo.hm_scale = 1.0f; 
        ubo.hm_height_factor = 0.5f;
        ubo.hm_level = 9;       // update sdf_hightmap.cells_per_axis !!!
        ubo.hm_max_level = 10;  // - " -
    }

    // memory Resources
    alias                       Ubo_Buffer = Core_Buffer_T!( 0, BMC.Memory | BMC.Mem_Range );
    Ubo_Buffer                  ubo_buffer;
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


    // Toys Registry
    struct Toy {
        nothrow @nogc:
        string                                      name;
        void function(ref App_Meta_Init)            extInstance;
        void function(ref App_Meta_Init)            extDevice;
        void function(ref App_Meta_Init)            features;
        void function(ref App)                      initialize;
        void function(ref App, ref Meta_Descriptor) descriptor;
        void function(ref App)                      create;
        void function(ref App, VkCommandBuffer)     record;
        void function(ref App, VkCommandBuffer)     recordPreRP;
        void function(ref App)                      widgets;
        void function(ref App)                      destroy;
    }

    //Static_Array!(Toy, 4) my_toys;
    alias toys = my_toys;
    Dynamic_Array!(Toy) my_toys;
    int my_toy_idx = 4;
    ref Toy active_toy() { return my_toys[ my_toy_idx ]; }



    // one descriptor for all purposes
    Core_Descriptor             descriptor;
    VkPipelineCache             pipeline_cache;


    // render setup
    VkRenderPassBeginInfo       render_pass_bi;
    VkFramebuffer[ MAX_FRAMES ] framebuffers;
    VkClearValue[ 2 ]           clear_values;
    VkViewport                  viewport;               // dynamic state viewport
    VkRect2D                    scissors;               // dynamic state scissors

    // window resize callback result
    bool                        window_resized = false;


    import init;
    VkResult initVulkan() {
        if( win_w == 0 ) win_w = 1600;
        if( win_h == 0 ) win_h =  900;
        return init.initVulkan( this, win_w, win_h ).vkAssert;
    }


    void destroyVulkan() {
        init.destroyVulkan( this );
    }


    // update projection matrix from member data _fovy, _near, _far
    // and the swapchain extent converted to aspect
    void updateProjection() {
        import dlsl.projection;
        vec2 res = vec2( win_w, win_h );
        projection_aspect = res.x / res.y;
        projection = vkPerspective(projection_fovy, projection_aspect, projection_near, projection_far);
        projection_inverse = vkPerspectiveInverse(projection_fovy, projection_aspect, projection_near, projection_far);
        ubo.resolution = res;
        ubo.aspect = projection_aspect;
        ubo.fowy = projection_fovy; //tan(dlsl.matrix.deg2rad * projection_fovy) / win_h;
        ubo.near = projection_near;
        ubo.far  = projection_far;
    }


    // multiply projection with trackball (view) matrix and upload to uniform buffer
    void updateWVPM() {
        ubo.wvpm = projection * tbb.worldTransform;
    //  ubo.wvpi = tbb.viewTransform * projection_inverse;
        ubo.view = tbb.worldTransform;  // to transfrom into View Space
        ubo.camm = tbb.viewTransform;   // position and orientation of can in world space
    //  vk.flushMappedMemoryRange( ubo_buffer.mem_range );    // we're flushing every frame anyway
    }

    void updateTime( float time ) {
        ubo.time = time;
        ubo.time_delta = time - last_time;
        ++ubo.frame;
        ubo.speed += speed_amp * ubo.time_delta;
        last_time = time; 
        vk.flushMappedMemoryRange( ubo_buffer.mem_range );
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
        import resources : resizeResources;
        this.resizeResources( present_mode );   // destroy old and recreate window size dependent resources
    }


    // this is used in windowResizeCallback
    // there only a VDrive_State pointer is available and we avoid ugly dereferencing
    void swapchainExtent( uint32_t win_w, uint32_t win_h ) {
        swapchain.image_extent = VkExtent2D( win_w, win_h );
    }


    // initial draw to overlap CPU recording and GPU drawing
    void drawInit() {

        // init ubo
        initUBO;

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



alias App_Meta_Init = Meta_Init;
ref App_Meta_Init addToysInstanceExtensions( return ref App_Meta_Init meta_init, ref App app ) {
    foreach( ref toy; app.my_toys )
        if( toy.extInstance !is null )
            toy.extInstance( meta_init );
    return meta_init;
}

ref App_Meta_Init addToysDeviceExtensions( return ref App_Meta_Init meta_init, ref App app ) {
    foreach( ref toy; app.my_toys )
        if( toy.extDevice !is null )
            toy.extDevice( meta_init );
    return meta_init;
}

ref App_Meta_Init addToysFeatures( return ref App_Meta_Init meta_init, ref App app ) {
    foreach( ref toy; app.my_toys )
        if( toy.features !is null )
            toy.features( meta_init );
    return meta_init;
}
