//module initialize;

import erupted;
import bindbc.glfw;

import core.stdc.stdio : printf;

import vdrive;

import app;


// mixin vulkan related glfw functions
// with this approach the erupted types can be used as params for the functions
mixin( bindGLFW_Vulkan );


nothrow @nogc:



VkResult initVulkan( ref App app, uint32_t win_w, uint32_t win_h ) {

    // set vulkan state verbosity
    vdrive.initializer.verbose_init = verbose;

    println();

    // Initialize GLFW3 and Vulkan related glfw functions
    loadGLFW( "glfw3_x64_3.3.8.dll" ); // load the lib found in system path
    loadGLFW_Vulkan;    // load vulkan specific glfw function pointers
    glfwInit();         // initialize glfw

    // set glfw window attributes and store it in the VDrive_State appstate
    glfwWindowHint( GLFW_CLIENT_API, GLFW_NO_API );
    app.window = glfwCreateWindow( win_w, win_h, "Vulkan Erupted", null, null );

    // first load all global level instance functions
    import erupted.vulkan_lib_loader;
    loadGlobalLevelFunctions;



    // get some useful info from the instance
    //listExtensions;   // heap allocation
    //listLayers;       // heap allocation
    //app.listInstanceExtensions; // arena sub-allocation
    //app.listLayers;     // arena sub-allocation
    //"VK_LAYER_KHRONOS_validation".isLayer;
    VK_EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME.isInstanceExtension( true );

    // get vulkan extensions which are required by glfw
    uint32_t  extension_count;
    string_z* glfw_required_extensions = glfwGetRequiredInstanceExtensions( & extension_count );

    //*
        // App info
    VkApplicationInfo app_info = {
        pEngineName         : "V-Playground",
        engineVersion       : VK_MAKE_API_VERSION( 0, 0, 1, 0 ),
        pApplicationName    : "V-Drive-App",
        applicationVersion  : VK_MAKE_API_VERSION( 0, 0, 1, 0 ),
        apiVersion          : VK_API_VERSION_1_3,
    };

    auto meta_init = App_Meta_Init( app );
    //addToysInstanceExtensions( meta_init, app );
    meta_init
        .validateVulkan( true )
        .addInstanceExtension( glfw_required_extensions[ 0 .. extension_count ] )
        .addToysInstanceExtensions( app )
        .addInstanceLayer( "VK_LAYER_KHRONOS_validation" )
        .setDebugUtilsSeverityFlags( 0
            | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT
            | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT
        //  | VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT
        //  | VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT
        )
        .setDebugUtilsTypeFlags( 0
            | VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT
            | VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT
            | VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT
        );

        // foreach( ref toy; app.my_toys )
        //     if( toy.extInst !is null )
        //         toy.extInst( meta_init );

    VkResult result = meta_init.initInstance( & app_info );

    string_z[] layers = meta_init.instance_layers.data;
    uint32_t layer_count = meta_init.instance_layers.count.to_uint;


    // create the window VkSurfaceKHR with the instance, surface is stored in the state object
    import vdrive.swapchain;
    glfwCreateWindowSurface( app.instance, app.window, app.allocator, & app.swapchain.surface ).vkAssert;
    app.swapchain.image_extent = VkExtent2D( win_w, win_h );     // Set the desired swapchain extent, this might change at swapchain creation


    // enumerate gpus
    //auto gpus = listPhysicalDevicesResult( app );
    auto gpus = app.listPhysicalDevices( false );
    //auto gpus = app.instance.listPhysicalDevices( false );


    // get some useful info from the physical devices
    foreach( ref gpu; gpus ) {
        //gpu.listProperties;
        //gpu.listProperties( GPU_Info_Flags.properties, app.scratch );
        //gpu.listProperties( GPU_Info_Flags.limits );
        //gpu.listProperties( GPU_Info_Flags.sparse_properties );
        //gpu.listFeatures;

        app.gpu = gpu;

        //auto gpu_layers = List_Layers_Result( app );
        //listLayers( gpu_layers, verbose );
        //gpu.listLayers;       // allocates
        //app.listLayers;

        //auto gpu_extensions = List_Extensions_Result( app );
        //listExtensions( gpu_extensions,  true );
        //"VK_EXT_debug_marker".isExtension( app, true );
        //gpu.listExtensions;   // heap allocation
        //app.listInstanceExtensions;
        //app.listDeviceExtensions;   // area sub-allocation

        //printf( "Present supported: %u\n", gpu.presentSupport( app.swapchain.surface ));
        //auto presentation_modes = listPresentModesResult( app );
        //listPresentModes( presentation_modes, app.swapchain.surface, verbose );
        //gpu.listPresentModes( app.swapchain.surface, true );     // stack allocation
    }


    // set the desired gpu into the state object
    // Todo(pp): find a suitable "best fit" gpu
    // - gpu must support the VK_KHR_swapchain extension
    bool presentation_supported = false;
    auto gpu_ranking = Block_Array!ubyte( app.scratch, gpus.length );

    foreach( size_t i, ref gpu; gpus ) {
        if( gpu.presentSupport( app.swapchain.surface )) {
            presentation_supported = true;
            gpu_ranking[ i ] += 100; 
        }

        auto properties = gpu.get_properties;
        if( properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU )
            gpu_ranking[ i ]++;
    }

    // sort gpus using gpu_ranking
    if( gpus.count > 1 ) {
        // Programming Pearls 2nd ed. 1999 iSort 
        uint i, j;
        for(i = 1; i < gpus.count; ++i ) {
            auto r = gpu_ranking[i];
            auto g = gpus[i];

            for(j = i; j > 0 && gpu_ranking[j-1] < r; --j ) {
                gpu_ranking[j] = gpu_ranking[j-1];
                gpus[j] = gpus[j-1];
            }

            gpu_ranking[j] = r;
            gpus[j] = g;
        } 
    }

    app.gpu = gpus[ 0 ]; 

    app.gpu.listProperties( GPU_Info_Flags.properties, app.scratch );

    // Presentation capability is required for this example, terminate if not available
    if( !presentation_supported ) {
        // Todo(pp): print to error stream
        printf( "No GPU with presentation capability detected. Terminating!" );
        app.destroyInstance;
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    // if presentation is supported on that gpu the gpu extension VK_KHR_swapchain must be available
    auto device_extensions = Block_Array!string_z( app.scratch );
    meta_init
        .addDeviceExtension( VK_KHR_SWAPCHAIN_EXTENSION_NAME )
        .addToysDeviceExtensions( app );

    // get required features for toys
    meta_init.addToysFeatures( app );

    //auto queue_families = listQueueFamiliesResult( app );
    //listQueueFamilies( queue_families, verbose, app.swapchain.surface );           // last param is optional and only for printing
    auto queue_families = app.listQueueFamilies( verbose, app.swapchain.surface );   // last param is optional and only for printing - allocates

    auto graphic_queues = queue_families.dup;
    graphic_queues
        .filterQueueFlags( VK_QUEUE_GRAPHICS_BIT )                  // .filterQueueFlags( include, exclude )
        .filterPresentSupport( app.gpu, app.swapchain.surface );    // .filterPresentSupport( gpu, swapchain )


    // treat the case of combined graphics and presentation queue first
    if( graphic_queues.length > 0 ) {

        Queue_Family[1] filtered_queues = graphic_queues.front;
        filtered_queues[0].queueCount = 1;
        filtered_queues[0].priority( 0 ) = 1;

        // initialize the logical device
        // Todo(pp): fix allocations dependent on extensions and layers type
        app.initDevice( filtered_queues, meta_init.device_extensions.data, layers, & meta_init.features, meta_init.features_ext_chain );

        // get device queues
        app.device.vkGetDeviceQueue( filtered_queues[0].family_index, 0, & app.graphics_queue );
        app.device.vkGetDeviceQueue( filtered_queues[0].family_index, 0, & app.swapchain.present_queue );

        // store queue family index, required for command pool creation
        app.graphics_queue_family_index = filtered_queues[0].family_index;

    } else {

        graphic_queues.reset( queue_families );
        graphic_queues.filterQueueFlags( VK_QUEUE_GRAPHICS_BIT );  // .filterQueueFlags( include, exclude )

        // a graphics queue is required for the example, terminate if not available
        if( graphic_queues.length == 0 ) {
            // Todo(pp): print to error stream
            printf( "No queue with VK_QUEUE_GRAPHICS_BIT found. Terminating!" );
            app.destroyInstance;
            return VK_ERROR_INITIALIZATION_FAILED;
        }

        // We know that the gpu has presentation support and can present to the swapchain
        // take the first available presentation queue
        Queue_Family[2] filtered_queues = [
            graphic_queues.front,
            queue_families.filterPresentSupport( app.gpu, app.swapchain.surface ).front // .filterPresentSupport( gpu, swapchain
        ];

        // initialize the logical device
        app.initDevice( filtered_queues, meta_init.device_extensions.data, layers, & meta_init.features, meta_init.features_ext_chain );

        // get device queues
        app.device.vkGetDeviceQueue( filtered_queues[0].family_index, 0, & app.graphics_queue );
        app.device.vkGetDeviceQueue( filtered_queues[1].family_index, 0, & app.swapchain.present_queue );

        // store queue family index, required for command pool creation
        // family_index of presentation queue seems not to be required later on
        app.graphics_queue_family_index = filtered_queues[0].family_index;

    }

    return VK_SUCCESS;

    /*
    // Enable graphic and compute queue example
    auto compute_queues = queue_families
        .filterQueueFlags( VK_QUEUE_COMPUTE_BIT, VK_QUEUE_GRAPHICS_BIT );   // .filterQueueFlags( include, exclude )
    assert( compute_queues.length );
    Queue_Family[2] filtered_queues = [ graphic_queues.front, compute_queues.front ];
    filtered_queues[0].queueCount = 1;
    filtered_queues[0].priority( 0 ) = 1;
    filtered_queues[1].queueCount = 1;          // float[2] compute_priorities = [0.8, 0.5];
    filtered_queues[1].priority( 0 ) = 0.8;     // filtered_queues[1].priorities = compute_priorities;
    //writeln( filtered_queues );
    */
}



void destroyVulkan( ref App app ) {

    app.destroyDevice;

    static if( validate_vulkan ) {
        if( !app.debug_report_callback.is_null ) app.destroy( app.debug_report_callback );
        if( !app.debug_utils_messenger.is_null ) app.destroy( app.debug_utils_messenger );
    }
    app.destroyInstance;

    // unload vulkan lib
    import erupted.vulkan_lib_loader;
    freeVulkanLib;

    glfwDestroyWindow( app.window );
    glfwTerminate();
}
