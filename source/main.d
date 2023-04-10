//module main;

import input;
import app;
import settings;



int main() {

    pragma( msg, "\n" );

    import core.stdc.stdio : printf;
    printf( "\n" );

    // define if we want to use a GUI or not
    enum USE_GUI = true;


    // compile time branch if gui is used or not
    static if( USE_GUI ) {
        import gui;
        Gui_State app;      // VDrive Gui state struct wrapping VDrive State struct
        app.initImgui;      // initialize imgui first, we raster additional fonts but currently don't install its glfw callbacks, they should be treated
    } else {
        import resources;
        App_State app;   // VDrive state struct
    }

    //import vdrive.util.info;
    //app.app.printTypeInfo;

    {
        // read settings
        //app.parseSettings( app.scratch );               // ubo pointers are backed by temp memory

        // initialize vulkan
        auto vkResult = app.initVulkan;                 // initialize instance and (physical) device
        if( vkResult > 0 ) return vkResult;             // exit if initialization failed, VK_SUCCESS = 0



        // ErupteD-V2 test code
        //import vulkan_windows;
        //auto hinstance = GetModuleHandle( null );
        //VkWin32SurfaceCreateInfoKHR win_32_surface_ci;
        //loadInstanceLevelFunctions( app.instance );
        //auto result = vkGetPhysicalDeviceWin32PresentationSupportKHR( app.gpu, app.graphics_queue_family_index );
        //auto amd = DispatchDevice( app.device );
        //import std.stdio;
        //writeln( "Present Support: ", result );
        //return 0;

        app.createCommandObjects;       // create command pool and sync primitives
        app.createMemoryObjects;        // create memory objects once used through out program lifetime
        app.createDescriptorSet;        // create descriptor set
        app.resizeResources;            // construct swapchain, create depth buffer and frambuffers
        app.createResources;            // configure swapchain, create renderpass and pipeline state object
        app.registerCallbacks;          // register glfw callback functions
        app.initTrackball;              // initialize trackball with window size and default perspective projection data in VDrive State
        //*
        // branch once more dependent on gui usage
        static if( !USE_GUI ) {
            app.createCommands;         // create draw loop runtime commands, only used without gui
        } else {
            if(!app.draw_gui ) {
                app.createCommands;
            }
        }
    }
    // initial draw
    app.drawInit;

//    {
//        import std.stdio;
//        printf( "Memory as ptr: %p\n", app.sim.macro_image.memory );
//        printf( "Memory as hex: %x\n", app.sim.macro_image.memory );
//        import vdrive.util.info;
//        app.sim.macro_image.extent.printTypeInfo;
//        app.sim.macro_image.subresourceRange.printTypeInfo;
//    }

    // record the first gui command buffer
    // in the draw loop this one will be submitted
    // while the next one is recorded asynchronously

    // Todo(pp):
    //import core.thread;
    //thread_detachThis();


    char[32] title;
    uint frame_count;
    import bindbc.glfw;
    double last_time = glfwGetTime();
    import core.stdc.stdio : sprintf;


    /*
    foreach(i; 0 .. 1 ) {
    /*/
    while( !glfwWindowShouldClose( app.window ))
    {
    //*/
        // compute fps
        ++frame_count;
        double delta_time = glfwGetTime() - last_time;
        if( delta_time >= 1.0 ) {
            sprintf( title.ptr, "Vulkan Erupted, FPS: %.2f", frame_count / delta_time );    // frames per second
            //sprintf( title.ptr, "Vulkan Erupted, FPS: %.2f", 1000.0 / frame_count );      // milli seconds per frame
            glfwSetWindowTitle( app.window, title.ptr );
            last_time += delta_time;
            frame_count = 0;
        }

        // draw
        app.draw();
        glfwSwapBuffers( app.window );

        // poll events in remaining frame time
        glfwPollEvents();
    }

    //amd.DestroyDevice;

    // drain work and destroy vulkan
    app.destroyResources;


    app.destroyVulkan;


    //app.writeSettings( & app.scratch );

    //import std.stdio : writeln;
    //writeln( app.point_size_line_width );
    {
        import vdrive.util.array : Block_Array;
        auto settings = Block_Array!char( app.scratch );
        settings.reserve = 1024;
        static if( USE_GUI ) {
            app.extractSettings( "gui", settings );

            //settings.write( "settings_gui.ini" );
            //settings.length = 0;
            //app.app.extractSettings( "app", settings );

        } else {
            app.extractSettings( "app", settings );
        }

        settings.writeSettings( "settings.ini" );
    }


    printf( "\n" );
    printf( "Scratch length: %u\n", app.scratch.length );

    import vdrive.util.array : debug_arena;
    static if( debug_arena ) {
        printf( "Scratch max links: %u, num links: %u\n", app.scratch.max_links, app.scratch.num_links );
        printf( "Scratch max count: %u, max capacity: %u\n\n", app.scratch.max_count, app.scratch.max_capacity );

    }

    return 0;
}

