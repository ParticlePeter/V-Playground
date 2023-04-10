module gui;

import vdrive;
import erupted;

//import imgui.types;
//import ImGui = imgui.funcs_static;

import ImGui = d_imgui;   //#include "imgui.h"
import d_imgui.imgui_h;
//import d_imgui.imconfig;

import bindbc.glfw;

import app;
import resources;

import toys.all;

import settings : setting;

debug import std.stdio;


nothrow @nogc:

//
// struct of gui related data //
//
struct Gui_State {
    nothrow @nogc:

    alias                       app this;
    @setting App_State          app;

    // presentation mode handling
    Static_Array!( char, 60 )   available_present_modes;        // 64 bytes
    VkPresentModeKHR[ 4 ]       available_present_modes_map;
    int                         selected_present_mode;

    //private:

    // GLFW data
    float       time = 0.0f;
    bool[ 3 ]   mouse_pressed = [ false, false, false ];
    float       mouse_wheel = 0.0f;

    // gui resources
    Core_Pipeline               gui_graphics_pso;
    Core_Pipeline               current_pso;        // with this we keep track which pso is active to avoid rebinding of the
    Core_Image_Memory_Sampler   gui_font_tex;

    // MAX_FRAMES is the maximum storage for these buffers and also swapchains. We should only construct swapchain count resources
    alias Gui_Draw_Buffer = Core_Buffer_Memory_T!( 0, BMC.Size | BMC.Ptr );
    Gui_Draw_Buffer[ app.MAX_FRAMES ]   gui_draw_buffers;

    @setting bool               draw_gui = true;

    Static_Array!( string, 4 )  toys_names;
    int                         toy_name_idx = 0;   // Selected Toy Index



    public:

    //
    // initialize imgui
    //
    void initImgui() {

        // register toys names
        toys_names.append( toys.cone.name() );
        toys_names.append( toys.morton.name() );
        toys_names.append( toys.hex_tess.name() );
        toys_names.append( toys.triangle.name() );


        // display the gui
        draw_gui = true;

        ImGui.CreateContext;

        // Get static ImGuiIO struct and set the address of our Gui_State as user pointer
        auto io = & ImGui.GetIO();
        io.UserData = & this;

        // Keyboard mapping. ImGui will use those indexes to peek into the io.KeyDown[] array
        io.KeyMap[ ImGuiKey.Tab ]           = GLFW_KEY_TAB;
        io.KeyMap[ ImGuiKey.LeftArrow ]     = GLFW_KEY_LEFT;
        io.KeyMap[ ImGuiKey.RightArrow ]    = GLFW_KEY_RIGHT;
        io.KeyMap[ ImGuiKey.UpArrow ]       = GLFW_KEY_UP;
        io.KeyMap[ ImGuiKey.DownArrow ]     = GLFW_KEY_DOWN;
        io.KeyMap[ ImGuiKey.PageUp ]        = GLFW_KEY_PAGE_UP;
        io.KeyMap[ ImGuiKey.PageDown ]      = GLFW_KEY_PAGE_DOWN;
        io.KeyMap[ ImGuiKey.Home ]          = GLFW_KEY_HOME;
        io.KeyMap[ ImGuiKey.End ]           = GLFW_KEY_END;
        io.KeyMap[ ImGuiKey.Delete ]        = GLFW_KEY_DELETE;
        io.KeyMap[ ImGuiKey.Backspace ]     = GLFW_KEY_BACKSPACE;
        io.KeyMap[ ImGuiKey.Enter ]         = GLFW_KEY_ENTER;
        io.KeyMap[ ImGuiKey.Escape ]        = GLFW_KEY_ESCAPE;
        io.KeyMap[ ImGuiKey.A ]             = GLFW_KEY_A;
        io.KeyMap[ ImGuiKey.C ]             = GLFW_KEY_C;
        io.KeyMap[ ImGuiKey.V ]             = GLFW_KEY_V;
        io.KeyMap[ ImGuiKey.X ]             = GLFW_KEY_X;
        io.KeyMap[ ImGuiKey.Y ]             = GLFW_KEY_Y;
        io.KeyMap[ ImGuiKey.Z ]             = GLFW_KEY_Z;

        // specify gui font
        io.Fonts.AddFontFromFileTTF( "fonts/consola.ttf", 14 ); // size_pixels

        // set ImGui function pointer
//      io.RenderDrawListsFn    = & drawGuiData;    // called of ImGui.Render. Alternatively can be set this to null and call ImGui.GetDrawData() after ImGui.Render() to get the same ImDrawData pointer.
        io.SetClipboardTextFn   = & setClipboardString;
        io.GetClipboardTextFn   = & getClipboardString;
        io.ClipboardUserData    = window;

        // specify display size from vulkan data
        io.DisplaySize.x = windowWidth;
        io.DisplaySize.y = windowHeight;


        // define style
        ImGuiStyle* style               = & ImGui.GetStyle();
        //  style.Alpha                 = 1;    // Global Alpha
        style.WindowPadding             = ImVec2( 4, 4 );
        //  style.WindowMinSize
        style.WindowRounding            = 0;
        //  style.WindowTitleAlign
        style.ChildRounding             = 4;
        //  style.FramePadding
        style.FrameRounding             = 3;
        style.ItemSpacing               = ImVec2( 4, 4 );
        //  style.ItemInnerSpacing
        //  style.TouchExtraPadding
        //  style.IndentSpacing
        //  style.ColumnsMinSpacing
        //  style.ScrollbarSize
        style.ScrollbarRounding         = 3;
        style.GrabMinSize               = 7;
        style.GrabRounding              = 2;
        //  style.ButtonTextAlign
        //  style.DisplayWindowPadding
        //  style.DisplaySafeAreaPadding
        //  style.AntiAliasedLines
        //  style.AntiAliasedShapes
        //  style.CurveTessellationTol

        style.Colors[ ImGuiCol.Text ]                   = ImVec4( 0.90f, 0.90f, 0.90f, 1.00f ); //ImVec4( 0.90f, 0.90f, 0.90f, 1.00f );
        style.Colors[ ImGuiCol.TextDisabled ]           = ImVec4( 0.60f, 0.60f, 0.60f, 1.00f ); //ImVec4( 0.60f, 0.60f, 0.60f, 1.00f );
        style.Colors[ ImGuiCol.WindowBg ]               = ImVec4( 0.00f, 0.00f, 0.00f, 0.50f ); //ImVec4( 0.00f, 0.00f, 0.00f, 0.50f );
        style.Colors[ ImGuiCol.ChildBg ]                = ImVec4( 0.00f, 0.00f, 0.00f, 0.00f ); //ImVec4( 0.00f, 0.00f, 0.00f, 0.50f );
        style.Colors[ ImGuiCol.PopupBg ]                = ImVec4( 0.05f, 0.05f, 0.10f, 1.00f ); //ImVec4( 0.05f, 0.05f, 0.10f, 1.00f );
        style.Colors[ ImGuiCol.Border ]                 = ImVec4( 0.37f, 0.37f, 0.37f, 0.25f ); //ImVec4( 0.37f, 0.37f, 0.37f, 0.25f );
        style.Colors[ ImGuiCol.BorderShadow ]           = ImVec4( 0.00f, 0.00f, 0.00f, 0.00f ); //ImVec4( 0.00f, 0.00f, 0.00f, 0.00f );
        style.Colors[ ImGuiCol.FrameBg ]                = ImVec4( 0.25f, 0.25f, 0.25f, 1.00f ); //ImVec4( 0.25f, 0.25f, 0.25f, 1.00f );
        style.Colors[ ImGuiCol.FrameBgHovered ]         = ImVec4( 0.40f, 0.40f, 0.40f, 1.00f ); //ImVec4( 0.50f, 0.50f, 0.50f, 1.00f );
        style.Colors[ ImGuiCol.FrameBgActive ]          = ImVec4( 0.50f, 0.50f, 0.50f, 1.00f ); //ImVec4( 0.65f, 0.65f, 0.65f, 1.00f );
        style.Colors[ ImGuiCol.TitleBg ]                = ImVec4( 0.16f, 0.26f, 0.38f, 1.00f ); //ImVec4( 0.27f, 0.27f, 0.54f, 0.83f );
        style.Colors[ ImGuiCol.TitleBgCollapsed ]       = ImVec4( 0.16f, 0.26f, 0.38f, 1.00f ); //ImVec4( 0.40f, 0.40f, 0.80f, 0.20f );
        style.Colors[ ImGuiCol.TitleBgActive ]          = ImVec4( 0.19f, 0.30f, 0.41f, 1.00f ); //ImVec4( 0.22f, 0.35f, 0.50f, 1.00f );
        style.Colors[ ImGuiCol.MenuBarBg ]              = ImVec4( 0.16f, 0.26f, 0.38f, 0.50f ); //ImVec4( 0.40f, 0.40f, 0.55f, 0.80f );
        style.Colors[ ImGuiCol.ScrollbarBg ]            = ImVec4( 0.25f, 0.25f, 0.25f, 0.60f ); //ImVec4( 0.25f, 0.25f, 0.25f, 0.60f );
        style.Colors[ ImGuiCol.ScrollbarGrab ]          = ImVec4( 0.40f, 0.40f, 0.40f, 1.00f ); //ImVec4( 0.40f, 0.40f, 0.40f, 1.00f );
        style.Colors[ ImGuiCol.ScrollbarGrabHovered ]   = ImVec4( 0.22f, 0.35f, 0.50f, 1.00f ); //ImVec4( 0.50f, 0.50f, 0.50f, 1.00f );
        style.Colors[ ImGuiCol.ScrollbarGrabActive ]    = ImVec4( 0.27f, 0.43f, 0.63f, 1.00f ); //ImVec4( 0.00f, 0.50f, 1.00f, 1.00f );
    //  style.Colors[ ImGuiCol.ComboBg ]                = ImVec4( 0.20f, 0.20f, 0.20f, 1.00f ); //ImVec4( 0.20f, 0.20f, 0.20f, 1.00f );
        style.Colors[ ImGuiCol.CheckMark ]              = ImVec4( 0.41f, 0.65f, 0.94f, 1.00f ); //ImVec4( 0.27f, 0.43f, 0.63f, 1.00f ); //ImVec4( 0.90f, 0.90f, 0.90f, 1.00f );
        style.Colors[ ImGuiCol.SliderGrab ]             = ImVec4( 1.00f, 1.00f, 1.00f, 0.25f ); //ImVec4( 1.00f, 1.00f, 1.00f, 0.25f );
        style.Colors[ ImGuiCol.SliderGrabActive ]       = ImVec4( 0.27f, 0.43f, 0.63f, 1.00f ); //ImVec4( 0.00f, 0.50f, 1.00f, 1.00f );
        style.Colors[ ImGuiCol.Button ]                 = ImVec4( 0.16f, 0.26f, 0.38f, 1.00f ); //ImVec4( 0.40f, 0.40f, 0.40f, 1.00f );
        style.Colors[ ImGuiCol.ButtonHovered ]          = ImVec4( 0.22f, 0.35f, 0.50f, 1.00f ); //ImVec4( 0.50f, 0.50f, 0.50f, 1.00f );
        style.Colors[ ImGuiCol.ButtonActive ]           = ImVec4( 0.27f, 0.43f, 0.63f, 1.00f ); //ImVec4( 0.00f, 0.50f, 1.00f, 1.00f );
        style.Colors[ ImGuiCol.Header ]                 = ImVec4( 0.16f, 0.26f, 0.38f, 1.00f ); //ImVec4( 0.40f, 0.40f, 0.90f, 1.00f );
        style.Colors[ ImGuiCol.HeaderHovered ]          = ImVec4( 0.22f, 0.35f, 0.50f, 1.00f ); //ImVec4( 0.45f, 0.45f, 0.90f, 1.00f );
        style.Colors[ ImGuiCol.HeaderActive ]           = ImVec4( 0.22f, 0.35f, 0.50f, 1.00f ); //ImVec4( 0.53f, 0.53f, 0.87f, 1.00f );
        style.Colors[ ImGuiCol.Separator ]              = ImVec4( 0.22f, 0.22f, 0.22f, 1.00f ); //ImVec4( 0.50f, 0.50f, 0.50f, 1.00f );
        style.Colors[ ImGuiCol.SeparatorHovered ]       = ImVec4( 0.60f, 0.60f, 0.60f, 1.00f ); //ImVec4( 0.60f, 0.60f, 0.60f, 1.00f );
        style.Colors[ ImGuiCol.SeparatorActive ]        = ImVec4( 0.70f, 0.70f, 0.70f, 1.00f ); //ImVec4( 0.70f, 0.70f, 0.70f, 1.00f );
        style.Colors[ ImGuiCol.ResizeGrip ]             = ImVec4( 1.00f, 1.00f, 1.00f, 1.00f ); //ImVec4( 1.00f, 1.00f, 1.00f, 1.00f );
        style.Colors[ ImGuiCol.ResizeGripHovered ]      = ImVec4( 1.00f, 1.00f, 1.00f, 1.00f ); //ImVec4( 1.00f, 1.00f, 1.00f, 1.00f );
        style.Colors[ ImGuiCol.ResizeGripActive ]       = ImVec4( 1.00f, 1.00f, 1.00f, 1.00f ); //ImVec4( 1.00f, 1.00f, 1.00f, 1.00f );
    //  style.Colors[ ImGuiCol.CloseButton ]            = ImVec4( 0.22f, 0.35f, 0.50f, 1.00f ); //ImVec4( 0.50f, 0.50f, 0.90f, 1.00f );
    //  style.Colors[ ImGuiCol.CloseButtonHovered ]     = ImVec4( 0.27f, 0.43f, 0.63f, 1.00f ); //ImVec4( 0.70f, 0.70f, 0.90f, 1.00f );
    //  style.Colors[ ImGuiCol.CloseButtonActive ]      = ImVec4( 0.70f, 0.70f, 0.70f, 1.00f ); //ImVec4( 0.70f, 0.70f, 0.70f, 1.00f );
        style.Colors[ ImGuiCol.PlotLines ]              = ImVec4( 1.00f, 1.00f, 1.00f, 1.00f ); //ImVec4( 1.00f, 1.00f, 1.00f, 1.00f );
        style.Colors[ ImGuiCol.PlotLinesHovered ]       = ImVec4( 0.90f, 0.70f, 0.00f, 1.00f ); //ImVec4( 0.90f, 0.70f, 0.00f, 1.00f );
        style.Colors[ ImGuiCol.PlotHistogram ]          = ImVec4( 0.90f, 0.70f, 0.00f, 1.00f ); //ImVec4( 0.90f, 0.70f, 0.00f, 1.00f );
        style.Colors[ ImGuiCol.PlotHistogramHovered ]   = ImVec4( 1.00f, 0.60f, 0.00f, 1.00f ); //ImVec4( 1.00f, 0.60f, 0.00f, 1.00f );
        style.Colors[ ImGuiCol.TextSelectedBg ]         = ImVec4( 0.27f, 0.43f, 0.63f, 1.00f ); //ImVec4( 0.00f, 0.50f, 1.00f, 1.00f );
        style.Colors[ ImGuiCol.ModalWindowDimBg ]       = ImVec4( 0.20f, 0.20f, 0.20f, 0.35f ); //ImVec4( 0.20f, 0.20f, 0.20f, 0.35f );
    }


    //
    // initialize vulkan
    //
    VkResult initVulkan( VkPhysicalDeviceFeatures* required_features = null ) {

        // first initialize vulkan main handles, exit early if something goes wrong
        auto vk_result = app.initVulkan( required_features );
        if( vk_result != VK_SUCCESS )
            return vk_result;

        // now collect swapchain info and populate related gui structures
        auto present_modes = app.gpu.listPresentModes( app.swapchain.surface, false );
        uint mode_name_idx = 0;
        foreach( uint i; 0 .. 4 ) {
            foreach( mode; present_modes ) {
                if( mode == cast( VkPresentModeKHR )i ) {
                    // settings have been loaded and applied by now, so we can use the last chosen present mode
                    // to initialize the selected mapped present mode (we need a mapping as not all present modes have to exist)
                    if( mode == app.present_mode )
                        selected_present_mode = cast( int )mode_name_idx;
                    // now we setup the mapping and populate the relevant imgui combo string
                    available_present_modes_map[ mode_name_idx++ ] = mode;
                    switch( mode ) {
                        case VK_PRESENT_MODE_IMMEDIATE_KHR      : available_present_modes.append( "IMMEDIATE_KHR\0" );    break;
                        case VK_PRESENT_MODE_MAILBOX_KHR        : available_present_modes.append( "MAILBOX_KHR\0" );      break;
                        case VK_PRESENT_MODE_FIFO_KHR           : available_present_modes.append( "FIFO_KHR\0" );         break;
                        case VK_PRESENT_MODE_FIFO_RELAXED_KHR   : available_present_modes.append( "FIFO_RELAXED_KHR\0" ); break;
                        default: break;
                    }
                }
            }
        }
        available_present_modes.append( '\0' );
        return vk_result;
    }



    //
    // initial draw to configure gui after all other resources were initialized
    //
    void drawInit() {

        // first forward to app drawInit
        app.drawInit;

        // Register current time
        time = cast( float )glfwGetTime();

        //
        // Initialize GUI Data //
        //

        // list available devices so the user can choose one
        getAvailableDevices;


    }


    //
    // Loop draw called in main loop
    //
    void draw() {

        // record next command buffer asynchronous
        if( draw_gui )      // this can't be a function pointer as well
            this.buildGui;  // as we wouldn't know what else has to be drawn (drawFunc or drawFuncPlay etc. )

        app.draw;
    }


    private:

    //
    // window flags for the main UI window
    //
    ImGuiWindowFlags window_flags = ImGuiWindowFlags.None
        | ImGuiWindowFlags.NoTitleBar
    //  | ImGuiWindowFlags.ShowBorders
        | ImGuiWindowFlags.NoResize
        | ImGuiWindowFlags.NoMove
        | ImGuiWindowFlags.NoScrollbar
        | ImGuiWindowFlags.NoCollapse
    //  | ImGuiWindowFlags.MenuBar
        | ImGuiWindowFlags.NoSavedSettings;


    //
    // Create and draw User Interface
    //
    void buildGui() {

        auto io = & ImGui.GetIO();

        //
        // general per frame data
        //

        {
            // Setup time step
            auto current_time = cast( float )glfwGetTime();
            io.DeltaTime = time > 0.0f ? ( current_time - time ) : ( 1.0f / 60.0f );
            time = current_time;

            // Setup inputs
            if( glfwGetWindowAttrib( window, GLFW_FOCUSED )) {
                double mouse_x, mouse_y;
                glfwGetCursorPos( window, & mouse_x, & mouse_y );
                io.MousePos = ImVec2( cast( float )mouse_x, cast( float )mouse_y );   // Mouse position in screen coordinates (set to -1,-1 if no mouse / on another screen, etc.)
            } else {
                io.MousePos = ImVec2( -1, -1 );
            }

            // Handle mouse button data from callback
            for( int i = 0; i < 3; i++ ) {
                // If a mouse press event came, always pass it as "mouse held this frame", so we don't miss click-release events that are shorter than 1 frame.
                io.MouseDown[ i ] = mouse_pressed[ i ] || glfwGetMouseButton( window, i ) != 0;
                mouse_pressed[ i ] = false;
            }

            // Handle mouse scroll data from callback
            io.MouseWheel = mouse_wheel;
            mouse_wheel = 0.0f;

            // Hide OS mouse cursor if ImGui is drawing it
            glfwSetInputMode( window, GLFW_CURSOR, io.MouseDrawCursor ? GLFW_CURSOR_HIDDEN : GLFW_CURSOR_NORMAL );

            // Start the frame
            ImGui.NewFrame;

            // define main gui window position and size
            ImGui.SetNextWindowPos(  main_win_pos,  ImGuiCond.Always );
            ImGui.SetNextWindowSize( main_win_size, ImGuiCond.Always );
            ImGui.Begin( "Main Window", null, window_flags );

            // set width of items and their label
            ImGui.PushItemWidth( main_win_size.x / 2 );
        }



        //
        // ImGui example Widgets
        //
        if( show_imgui_examples ) {

            auto style = & ImGui.GetStyle();

            // set gui transparency
            ImGui.SliderFloat( "Gui Alpha", & style.Colors[ ImGuiCol.WindowBg ].w, 0.0f, 1.0f );

            // little hacky, but works - as we know that the corresponding clear value index
            ImGui.ColorEdit3( "Clear Color", cast( float[] )( clear_values[ 1 ].color.float32[ 1 .. 4 ] ));

            //ImGui.ColorEdit3( "clear color", clear_color );
            if( ImGui.Button( "Test Window", button_size_3 )) show_demo_window ^= 1;
            ImGui.SameLine;
            if( ImGui.Button( "Another Window", button_size_3 )) show_another_window ^= 1;
            ImGui.SameLine;
            if( ImGui.Button( "Style Editor", button_size_3 )) show_style_editor ^= 1;

            if( ImGui.GetIO().Framerate < minFramerate ) minFramerate = ImGui.GetIO().Framerate;
            if( ImGui.GetIO().Framerate > maxFramerate ) maxFramerate = ImGui.GetIO().Framerate;
            if( resetFrameMax < 100 ) {
                ++resetFrameMax;
                maxFramerate = 0.0001f;
            }
            ImGui.Text( "Refresh average %.3f ms/frame (%.1f FPS)", 1000.0f / ImGui.GetIO().Framerate, ImGui.GetIO().Framerate );
            ImGui.Text( "Refresh minimum %.3f ms/frame (%.1f FPS)", 1000.0f / minFramerate, minFramerate );
            ImGui.Text( "Refresh maximum %.3f ms/frame (%.1f FPS)", 1000.0f / maxFramerate, maxFramerate );
            ImGui.Separator;
        }



        //
        // Compute Device
        //
        if( ImGui.CollapsingHeader( "Compute Device" )) {
            ImGui.Separator;
            ImGui.PushItemWidth( -1 );

            /*
            if( ImGui.Combo( "Device", & compute_device, device_names.fromStringz )) {
                if( compute_device == 0 ) {
                    this.cpuReset;
                    this.setCpuSimFuncs;
                    use_cpu = true;
                    drawCmdBufferCount = sim_play_cmd_buffer_count = 1;
                } else {
                    this.setDefaultSimFuncs;
                    use_cpu = false;
                    sim_use_double &= feature_shader_double;
                    if( play_mode == Transport.play ) {     // in profile mode this must stay 1 (switches with play/pause )
                        sim_play_cmd_buffer_count = 2;      // as we submitted compute and draw command buffers separately
                        if( transport == Transport.play ) { // if we are in play mode
                            drawCmdBufferCount = 2;         // we must set this value immediately
                        }
                    }
                }
            }
            */
            // Using the generic BeginCombo() API, you have full control over how to display the combo contents.
            // (your selection data could be an index, a pointer to the object, an id for the object, a flag intrusively
            // stored in the object itself, etc.)

            // Expose flags as checkbox for the demo
            ImGuiComboFlags flags = ImGuiComboFlags.None;
            //ImGui.CheckboxFlags("ImGuiComboFlags_PopupAlignLeft", cast(uint*)&flags, ImGuiComboFlags.PopupAlignLeft);
            //ImGui.SameLine();// HelpMarker("Only makes a difference if the popup is larger than the combo");
            //if (ImGui.CheckboxFlags("ImGuiComboFlags_NoArrowButton", cast(uint*)&flags, ImGuiComboFlags.NoArrowButton))
            //    flags &= ~ImGuiComboFlags.NoPreview;     // Clear the other flag, as we cannot combine both
            //if (ImGui.CheckboxFlags("ImGuiComboFlags_NoPreview", cast(uint*)&flags, ImGuiComboFlags.NoPreview))
            //    flags &= ~ImGuiComboFlags.NoArrowButton; // Clear the other flag, as we cannot combine both


            const string[14] items = [ "AAAA", "BBBB", "CCCC", "DDDD", "EEEE", "FFFF", "GGGG", "HHHH", "IIII", "JJJJ", "KKKK", "LLLLLLL", "MMMM", "OOOOOOO" ];
            static int test_item_idx = 0;                // Here our selection data is an index.
            string combo_label = items[ test_item_idx ]; // Label to preview before opening the combo (technically it could be anything)(
            if( ImGui.BeginCombo( "combo 1", combo_label, flags )) {
                for( int i = 0; i < IM_ARRAYSIZE( items ); ++i ) {
                    const bool is_selected = ( test_item_idx == i );
                    if( ImGui.Selectable( items[i], is_selected ))
                        test_item_idx = i;

                    // Set the initial focus when opening the combo (scrolling + keyboard navigation focus)
                    if( is_selected )
                        ImGui.SetItemDefaultFocus();
                }
                ImGui.EndCombo();
            }

            ImGui.Separator;
            float cursor_pos_y = ImGui.GetCursorPosY();
            ImGui.SetCursorPosY(cursor_pos_y + 3);
            ImGui.Text( "VK_PRESENT_MODE_" );
            ImGui.SameLine;
            ImGui.SetCursorPosY(cursor_pos_y);

//            if( ImGui.Combo( "Present Mode", & selected_present_mode, available_present_modes.ptr )) {
//                resources.resizeResources( app, cast( VkPresentModeKHR )available_present_modes_map[ selected_present_mode ] );
//                //app.drawInit;
//            }

            const string[4] present_modes = [ "IMMEDIATE_KHR", "MAILBOX_KHR", "FIFO_KHR", "FIFO_RELAXED_KHR" ];
            static int present_mode_idx = 0;                  // Here our selection data is an index.
            combo_label = present_modes[ present_mode_idx ];  // Label to preview before opening the combo (technically it could be anything)(
            if( ImGui.BeginCombo( "combo 2", combo_label )) {
                for( int i = 0; i < IM_ARRAYSIZE( present_modes ); ++i ) {
                    const bool is_selected = ( present_mode_idx == i );
                    if( ImGui.Selectable( present_modes[ i ], is_selected ))
                        present_mode_idx = i;

                    // Set the initial focus when opening the combo (scrolling + keyboard navigation focus)
                    if( is_selected )
                        ImGui.SetItemDefaultFocus();
                }
                ImGui.EndCombo();
            }

            ImGui.PopItemWidth;
            ImGui.Separator;
            ImGui.Spacing;

        }

        if( ImGui.CollapsingHeader( "Playground with Toys" )) {
            ImGui.Separator;
            ImGui.PushItemWidth( -1 );

            string combo_label = toys_names[ toy_name_idx ];       // Label to preview before opening the combo (technically it could be anything)(
            if( ImGui.BeginCombo( "Toys", combo_label )) {
                for( int i = 0; i < toys_names.count.to_int; ++i ) {
                    const bool is_selected = ( toy_name_idx == i );
                    if( ImGui.Selectable( toys_names[ i ], is_selected ))
                        toy_name_idx = i;

                    // Set the initial focus when opening the combo (scrolling + keyboard navigation focus)
                    if( is_selected )
                        ImGui.SetItemDefaultFocus();
                }
                ImGui.EndCombo();
            }

            ImGui.PopItemWidth;
            ImGui.Separator;
            ImGui.Spacing;

        }

        ImGui.End();



        // 2. Show another simple window, this time using an explicit Begin/End pair
        if( show_another_window ) {
            auto next_win_size = ImVec2( 200, 100 ); ImGui.SetNextWindowSize( next_win_size, ImGuiCond.FirstUseEver );
            ImGui.Begin( "Another Window", & show_another_window );
            ImGui.Text( "Hello" );
            ImGui.End();
        }

        // 3. Show the ImGui test window. Most of the sample code is in ImGui.ShowTestWindow()
        if( show_demo_window ) {
            import d_imgui.imgui_demo : ShowDemoWindow;
            auto next_win_pos = ImVec2( 650, 20 ); ImGui.SetNextWindowPos( next_win_pos, ImGuiCond.FirstUseEver );
            ShowDemoWindow( & show_demo_window );
        }

        if( show_style_editor ) {
            ImGui.Begin( "Style Editor", & show_style_editor );
            ImGui.ShowStyleEditor();
            ImGui.End();
        }


        ImGui.Render;

        drawGuiData( ImGui.GetDrawData );
    }


    //
    // helper
    //
    void showTooltip( string text, float wrap_position = 300 ) {
        //ImGui.TextDisabled("(?)");    // this should be called before showTooltip so we can customize it
        if( ImGui.IsItemHovered ) {
            ImGui.BeginTooltip;
            ImGui.PushTextWrapPos( wrap_position );
            ImGui.TextUnformatted( text );
            ImGui.PopTextWrapPos;
            ImGui.EndTooltip;
        }
    }


    bool show_demo_window           = false;
    bool show_style_editor          = false;
    bool show_another_window        = false;
    bool show_imgui_examples        = false;


    //
    // used to determine fps
    //
    int resetFrameMax   = 0;
    float minFramerate  = 10000, maxFramerate = 0.0001f;


    //
    // Base item settings
    //
    immutable auto main_win_pos     = ImVec2( 0, 0 );
    auto main_win_size              = ImVec2( 352, 900 );

    auto scale_win_pos              = ImVec2( 1540, 710 );
    immutable auto scale_win_size   = ImVec2(   60,  20 );

    immutable auto button_size_1    = ImVec2( 344, 20 );
    immutable auto button_size_2    = ImVec2( 176, 20 );
    immutable auto button_size_3    = ImVec2( 112, 20 );
    immutable auto button_size_4    = ImVec2(  85, 20 );

    immutable auto disabled_text    = ImVec4( 0.4, 0.4, 0.4, 1 );

    ubyte   device_count = 1;       // initialize with one being the CPU
    char*   device_names;           // store all names of physical devices consecutively
    int     compute_device = 1;     // select compute device, 0 = CPU


    //
    // collect available devices
    //
    void getAvailableDevices() {

        // This code here is a stub, as we have no opportunity to test on systems with multiple devices
        // Only the device which was selected in module initialize will be listed here
        // Selection is based on ability to present a swapchain while a discrete gpu is prioritized

        // get available devices, store their names concatenated in private devices pointer
        // with this we can list them in an ImGui.Combo and make them selectable
        size_t devices_char_count = 4;
        auto gpus = this.instance.listPhysicalDevices( false );
        device_count += cast( ubyte )gpus.length;
        //devices_char_count += device_count * size_t.sizeof;  // sizeof( some_pointer );

        import core.stdc.string : strlen;

        /*  // Use this loop to list all available vulkan devices
        foreach( ref gpu; gpus ) {
            devices_char_count += strlen( gpu.listProperties.deviceName.ptr ) + 1;
        }
        /*/ // Use this code to append the selected device in module initialize
        devices_char_count += strlen( this.gpu.listProperties.deviceName.ptr ) + 1;
        //*/

        import core.stdc.stdlib : malloc;
        device_names = cast( char* )malloc( devices_char_count );   // + 1 for second terminating zero
        device_names[ 0 .. 4 ] = "CPU\0";

        char* device_name_target = device_names + 4;    // offset and store the device names pointer with 4 chars for CPU\0
        import  core.stdc.string : strcpy;

        /*  // Use this loop to append all device names to the device_names char pointer
        foreach( ref gpu; gpus ) {
            strcpy( device_name_target, gpu.listProperties.deviceName.ptr );
            device_name_target += strlen( gpu.listProperties.deviceName.ptr ) + 1;
        }
        /*/ // Use this code to append the device name of the selected device in module initialize
        strcpy( device_name_target, this.gpu.listProperties.deviceName.ptr );
        device_name_target += strlen( this.gpu.listProperties.deviceName.ptr ) + 1;
        //*/


        // even though the allocated memory range seems to be \0 initialized we set the last char to \0 to be sure
        //device_names[ devices_char_count ] = '\0';  // we allocated devices_char_count + 1, hence no -1 required
    }
}



//
// create vulkan related command and synchronization objects and data updated for gui usage //
//
void createCommandObjects( ref Gui_State gui ) {
    resources.createCommandObjects( gui, VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT );
}



//
// create simulation and gui related memory objects //
//
void createMemoryObjects( ref Gui_State gui ) {

    // first forward to resources.allocateResources
    resources.createMemoryObjects( gui );

    // get imgui font atlas data
    ubyte[] pixels;
    int width, height;
    auto io = & ImGui.GetIO();
    io.Fonts.GetTexDataAsRGBA32( & pixels, & width, & height );
    size_t upload_size = width * height * 4 * ubyte.sizeof;

    // create upload buffer and upload the data
    auto stage_buffer = Meta_Buffer( gui )
        .usage( VK_BUFFER_USAGE_TRANSFER_SRC_BIT )
        .bufferSize( upload_size )
        .construct( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT )
        .copyData( pixels[ 0 .. upload_size ] );

    // create image, image view abd sampler to sample the font atlas texture
    auto meta_gui_font_tex = Meta_Image_Memory_Sampler( gui )
        .format( VK_FORMAT_R8G8B8A8_UNORM )
        .extent( width, height )
        .addUsage( VK_IMAGE_USAGE_SAMPLED_BIT )
        .addUsage( VK_IMAGE_USAGE_TRANSFER_DST_BIT )

        // combines construct image, allocate required memory, construct image view and sampler (can be called separetelly)
        .construct( VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT )

        // extract instead of reset to keep the temp Meta_Image_Memory_Sampler to use some its extended properties, in this function scope only
        .extractCore( gui.gui_font_tex );

    // use one command buffer for device resource initialization
    auto cmd_buffer = gui.allocateCommandBuffer( gui.cmd_pool, VK_COMMAND_BUFFER_LEVEL_PRIMARY );
    auto cmd_buffer_bi = createCmdBufferBI( VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT );
    vkBeginCommandBuffer( cmd_buffer, & cmd_buffer_bi );

    // record image layout transition to VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
    cmd_buffer.recordTransition(
        gui.gui_font_tex.image,
        meta_gui_font_tex.subresourceRange,
        VK_IMAGE_LAYOUT_UNDEFINED,
        VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        0,  // no access mask required here
        VK_ACCESS_TRANSFER_WRITE_BIT,
        VK_PIPELINE_STAGE_HOST_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT );

    // record a buffer to image copy
    auto subresource_range = meta_gui_font_tex.subresourceRange;
    VkBufferImageCopy buffer_image_copy = {
        imageSubresource: {
            aspectMask      : subresource_range.aspectMask,
            baseArrayLayer  : subresource_range.baseArrayLayer,
            layerCount      : subresource_range.layerCount },
        imageExtent     : meta_gui_font_tex.extent,
    };
    cmd_buffer.vkCmdCopyBufferToImage( stage_buffer.buffer, meta_gui_font_tex.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, & buffer_image_copy );

    // record image layout transition to VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
    cmd_buffer.recordTransition(
        meta_gui_font_tex.image,
        meta_gui_font_tex.image_view_ci.subresourceRange,
        VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        VK_ACCESS_TRANSFER_WRITE_BIT,
        VK_ACCESS_SHADER_READ_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT );


    // store the texture id in imgui io struct
    io.Fonts.TexID = cast( int )( gui.gui_font_tex.image );

    // finish recording
    cmd_buffer.vkEndCommandBuffer;

    // submit info stays local in this function scope
    auto submit_info = cmd_buffer.queueSubmitInfo;

    // submit the command buffer with one depth and one color image transitions
    gui.graphics_queue.vkQueueSubmit( 1, & submit_info, VK_NULL_HANDLE ).vkAssert;

    // wait on finished submission befor destroying the staging buffer
    gui.graphics_queue.vkQueueWaitIdle;   // equivalent using a fence per Spec v1.0.48
    stage_buffer.destroyResources;

    // command pool will be reset in resources.resizeResources
    //gui.device.vkResetCommandPool( gui.cmd_pool, 0 ); // second argument is VkCommandPoolResetFlags
}



//
// create simulation and gui related descriptor set //
//
void createDescriptorSet( ref Gui_State gui ) {

    // start configuring descriptor set, pass the temporary meta_descriptor
    // as a pointer to references.createDescriptorSet, where additional
    // descriptors will be added, the set constructed and stored in
    // app.descriptor of type Core_Descriptor

    auto meta_descriptor = Meta_Descriptor_T!(9,3,8,4,3,2)( gui )
        .addImmutableSamplerImageBinding( 1, VK_SHADER_STAGE_FRAGMENT_BIT )
        .addSamplerImage( gui.gui_font_tex.sampler, gui.gui_font_tex.view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL );

    // forward to app createDescriptorSet with the currently being configured meta_descriptor
    resources.createDescriptorSet_T( gui, meta_descriptor );
}



//
// create app and gui related render resources //
//
void createResources( ref Gui_State gui ) {

    // first forward to resources.createResources
    resources.createResources( gui );

    // create pipeline for gui rendering
    gui.gui_graphics_pso = Meta_Graphics_T!(2,1,3,1,1,1,2,1,1)( gui )
        .addShaderStageCreateInfo( gui.createPipelineShaderStage( "shader/imgui.vert" ))// auto-detect shader stage through file extension
        .addShaderStageCreateInfo( gui.createPipelineShaderStage( "shader/imgui.frag" ))// auto-detect shader stage through file extension
        .addBindingDescription( 0, ImDrawVert.sizeof, VK_VERTEX_INPUT_RATE_VERTEX )     // add vertex binding and attribute descriptions
        .addAttributeDescription( 0, 0, VK_FORMAT_R32G32_SFLOAT,  0 )                   // interleaved attributes of ImDrawVert ...
        .addAttributeDescription( 1, 0, VK_FORMAT_R32G32_SFLOAT,  ImDrawVert.uv.offsetof  )
        .addAttributeDescription( 2, 0, VK_FORMAT_R8G8B8A8_UNORM, ImDrawVert.col.offsetof )
        .inputAssembly( VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST )                           // set the input assembly
        .addViewportAndScissors( VkOffset2D( 0, 0 ), gui.swapchain.image_extent )       // add viewport and scissor state, necessary even if we use dynamic state
        .cullMode( VK_CULL_MODE_NONE )                                                  // set rasterization state cull mode
        .depthState                                                                     // set depth state - enable depth test with default attributes
        .addColorBlendState( VK_TRUE )                                                  // color blend state - append common (default) color blend attachment state
        .addDynamicState( VK_DYNAMIC_STATE_VIEWPORT )                                   // add dynamic states viewport
        .addDynamicState( VK_DYNAMIC_STATE_SCISSOR )                                    // add dynamic states scissor
        .addDescriptorSetLayout( gui.descriptor.descriptor_set_layout )                 // describe pipeline layout
        .addPushConstantRange( VK_SHADER_STAGE_VERTEX_BIT, 0, 16 )                      // specify push constant range
        .renderPass( gui.render_pass_bi.renderPass )                                    // describe compatible render pass
        .construct                                                                      // construct the PSO
        .destroyShaderModules                                                           // shader modules compiled into pipeline, not shared, can be deleted now
        .reset;

    debug {
        gui.setDebugName( gui.gui_graphics_pso.pipeline,        "Gui Graphics Pipeline" );
        gui.setDebugName( gui.gui_graphics_pso.pipeline_layout, "Gui Graphics Pipeline Layout" );
    }
}


//
// register glfw callbacks //
//
void registerCallbacks( ref Gui_State gui ) {

    // first forward to input.registerCallbacks
    import input : input_registerCallbacks = registerCallbacks;
    input_registerCallbacks( gui.app ); // here we use gui.app to ensure that only the wrapped VDrive State struct becomes the user pointer

    // now overwrite some of the input callbacks (some of them also forward to input callbacks)
    glfwSetWindowSizeCallback(  gui.window, & guiWindowSizeCallback );
    glfwSetMouseButtonCallback( gui.window, & guiMouseButtonCallback );
    glfwSetCursorPosCallback(   gui.window, & guiCursorPosCallback );
    glfwSetScrollCallback(      gui.window, & guiScrollCallback );
    glfwSetCharCallback(        gui.window, & guiCharCallback );
    glfwSetKeyCallback(         gui.window, & guiKeyCallback );
}



//
// (re)create window size dependent resources //
//
void resizeResources( ref Gui_State gui, VkPresentModeKHR request_present_mode = VK_PRESENT_MODE_MAX_ENUM_KHR ) {
    // forward to app resizeResources
    resources.resizeResources( gui, request_present_mode );

    // if we use gui (default) than resources.createCommands is not being called
    // there we would have reset the command pool which was used to initialize GPU memory objects
    // hence we reset it now here and rerecord the two command buffers each frame

    // reset the command pool to start recording drawing commands
    gui.graphics_queue.vkQueueWaitIdle;   // equivalent using a fence per Spec v1.0.48
    gui.device.vkResetCommandPool( gui.cmd_pool, 0 ); // second argument is VkCommandPoolResetFlags

    // allocate swapchain image count command buffers
    gui.allocateCommandBuffers( gui.cmd_pool, gui.cmd_buffers[ 0 .. gui.swapchain.image_count ] );

    debug {
        // set debug name of each command buffer in use
        import core.stdc.stdio : sprintf;
        char[ 24 ] debug_name = "Gui Command Buffer ";
        foreach( i; 0 .. gui.swapchain.image_count ) {
            sprintf( debug_name.ptr + 19, "%u", i );
            gui.setDebugName( gui.cmd_buffers[ i ], debug_name.ptr );
        }
    }

    // set gui io display size from swapchain extent
    auto io = & ImGui.GetIO();
    io.DisplaySize = ImVec2( gui.windowWidth, gui.windowHeight );
}



//
// (re)create draw loop commands, convenienece forwarding to module resources //
//
void createCommands( ref Gui_State gui ) {
    // forward to app createCommands
    resources.createCommands( gui );
}



//
// exit destroying all resources //
//
void destroyResources( ref Gui_State gui ) {

    // forward to app destroyResources, this also calls device.vkDeviceWaitIdle;
    resources.destroyResources( gui );

    // now destroy all remaining gui resources
    foreach( ref draw_buffer; gui.gui_draw_buffers )
        gui.vk.destroy( draw_buffer );


    // descriptor set and layout is destroyed in module resources
    gui.destroy( gui.cmd_pool );
    gui.destroy( gui.gui_graphics_pso );
    gui.destroy( gui.gui_font_tex );

    import core.stdc.stdlib : free;
    free( gui.device_names );

    ImGui.DestroyContext;
}



//
// callback for C++ ImGui lib, in particular draw function //
//

//extern( C++ ):

//
// main rendering function which draws all data including gui //
//
void drawGuiData( ImDrawData* draw_data ) {

    // get Gui_State pointer from ImGuiIO.UserData
    auto gui = cast( Gui_State* )( & ImGui.GetIO()).UserData;
    uint32_t next_image_index = gui.next_image_index;

    //
    // begin command buffer recording
    //

    // first attach the swapchain image related framebuffer to the render pass
    gui.render_pass_bi.framebuffer = gui.framebuffers[ next_image_index ];

    // convenience copy
    auto cmd_buffer = gui.cmd_buffers[ next_image_index ];

    // begin the command buffer
    VkCommandBufferBeginInfo cmd_buffer_bi = { flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    cmd_buffer.vkBeginCommandBuffer( & cmd_buffer_bi );

    // begin the render pass
    cmd_buffer.vkCmdBeginRenderPass( & gui.render_pass_bi, VK_SUBPASS_CONTENTS_INLINE );

    // dynamic state
    cmd_buffer.vkCmdSetViewport( 0, 1, & gui.viewport );
    cmd_buffer.vkCmdSetScissor(  0, 1, & gui.scissors );


    //
    // create gui index and vertex data buffer as one buffer, align the index buffer on 16 bytes
    //
    import vdrive.util.util : aligned;
    size_t vrts_data_size = aligned( draw_data.TotalVtxCount * ImDrawVert.sizeof, 16 );
    {
        auto draw_buffer = & gui.gui_draw_buffers[ next_image_index ];
        size_t draw_data_size = vrts_data_size + draw_data.TotalIdxCount * ImDrawIdx.sizeof;
        size_t draw_buffer_size = draw_buffer.size;
        if( draw_buffer_size < draw_data_size ) {
            gui.vk.destroy( *draw_buffer );
            Meta_Buffer_T!( Gui_State.Gui_Draw_Buffer )( gui.vk )
                .addUsage( VK_BUFFER_USAGE_VERTEX_BUFFER_BIT )
                .addUsage( VK_BUFFER_USAGE_INDEX_BUFFER_BIT )
                .bufferSize( draw_data_size + ( draw_data_size >> 4 ))  // add draw_data_size / 16 to required size so that we need to reallocate less often
                .construct( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT )
                .mapMemory( draw_buffer.ptr )
                .reset( *draw_buffer );
        }

        // upload vertex and index data
        //draw_buffer.ptr = gui.vk.mapMemory( draw_buffer.memory );
        auto vert_ptr = cast( ImDrawVert* )( draw_buffer.ptr );
        auto elem_ptr = cast( ImDrawIdx*  )( draw_buffer.ptr + vrts_data_size );

        import core.stdc.string : memcpy;
        int cmd_lists_count = draw_data.CmdListsCount;
        for( int i = 0; i < cmd_lists_count; ++i ) {
            const ImDrawList* cmd_list = draw_data.CmdLists[ i ];
            memcpy( vert_ptr, cmd_list.VtxBuffer.Data, cmd_list.VtxBuffer.Size * ImDrawVert.sizeof );
            memcpy( elem_ptr, cmd_list.IdxBuffer.Data, cmd_list.IdxBuffer.Size * ImDrawIdx.sizeof  );
            vert_ptr += cmd_list.VtxBuffer.Size;
            elem_ptr += cmd_list.IdxBuffer.Size;
        }

        gui.vk.flushMappedMemoryRange( draw_buffer.memory );    // draw_buffer.flushMappedMemoryRange;
    }


    // bind the gui graphics pipeline
    cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_GRAPHICS, gui.gui_graphics_pso.pipeline );

    // bind descriptor set - we should not have to rebind this for other pipelines as long as the pipeline layouts are compatible, but validation layers claim otherwise
    cmd_buffer.vkCmdBindDescriptorSets(         // VkCommandBuffer              commandBuffer
        VK_PIPELINE_BIND_POINT_GRAPHICS,        // VkPipelineBindPoint          pipelineBindPoint
        gui.gui_graphics_pso.pipeline_layout,   // VkPipelineLayout             layout
        0,                                      // uint32_t                     firstSet
        1,                                      // uint32_t                     descriptorSetCount
        & gui.descriptor.descriptor_set,        // const( VkDescriptorSet )*    pDescriptorSets
        0,                                      // uint32_t                     dynamicOffsetCount
        null                                    // const( uint32_t )*           pDynamicOffsets
    );

    // bind vertex and index buffer
    VkDeviceSize vertex_offset = 0;
    cmd_buffer.vkCmdBindVertexBuffers( 0, 1, & gui.gui_draw_buffers[ next_image_index ].buffer, & vertex_offset );
    cmd_buffer.vkCmdBindIndexBuffer( gui.gui_draw_buffers[ next_image_index ].buffer, vrts_data_size, VK_INDEX_TYPE_UINT16 );

    // setup scale and translation
    float[2] scale = [ 2.0f / gui.windowWidth, 2.0f / gui.windowHeight ];
    float[2] trans = [ -1.0f, -1.0f ];
    cmd_buffer.vkCmdPushConstants( gui.gui_graphics_pso.pipeline_layout, VK_SHADER_STAGE_VERTEX_BIT,            0, scale.sizeof, scale.ptr );
    cmd_buffer.vkCmdPushConstants( gui.gui_graphics_pso.pipeline_layout, VK_SHADER_STAGE_VERTEX_BIT, scale.sizeof, trans.sizeof, trans.ptr );

    // record the command lists
    int vtx_offset = 0;
    int idx_offset = 0;
    foreach( int i; 0 .. draw_data.CmdListsCount ) {
        ImDrawList* cmd_list = draw_data.CmdLists[ i ];

        foreach( int cmd_i; 0 .. cmd_list.CmdBuffer.Size ) {
            ImDrawCmd* pcmd = & cmd_list.CmdBuffer[ cmd_i ];

            if( pcmd.UserCallback ) {
                pcmd.UserCallback( cmd_list, pcmd );
            } else {
                VkRect2D scissor;
                scissor.offset.x = cast( int32_t )( pcmd.ClipRect.x );
                scissor.offset.y = cast( int32_t )( pcmd.ClipRect.y );
                scissor.extent.width  = cast( uint32_t )( pcmd.ClipRect.z - pcmd.ClipRect.x );
                scissor.extent.height = cast( uint32_t )( pcmd.ClipRect.w - pcmd.ClipRect.y + 1 ); // TODO: + 1??????
                cmd_buffer.vkCmdSetScissor( 0, 1, & scissor );
                cmd_buffer.vkCmdDrawIndexed( pcmd.ElemCount, 1, idx_offset, vtx_offset, 0 );
            }
            idx_offset += pcmd.ElemCount;
        }
        vtx_offset += cmd_list.VtxBuffer.Size;
    }



    // end the render pass
    cmd_buffer.vkCmdEndRenderPass;

    // finish recording
    cmd_buffer.vkEndCommandBuffer;
}



//
// imgui get clipboard function pointer implementation //
//
private string getClipboardString( void* user_data ) {
    import std.exception : assumeUnique;
    return glfwGetClipboardString( cast( GLFWwindow* )user_data ).fromStringz.assumeUnique;
}



//
// imgui set clipboard function pointer implementation //
//
private void setClipboardString( void* user_data, string text ) {
    //glfwSetClipboardString( cast( GLFWwindow* )user_data, text );
}



//
// glfw C callbacks for C GLFW lib //
//

extern( C ) nothrow:

// Callback function for capturing mouse button events
void guiMouseButtonCallback( GLFWwindow* window, int button, int val, int mod ) {
    auto io = & ImGui.GetIO();
    auto gui = cast( Gui_State* )io.UserData; // get Gui_State pointer from ImGuiIO.UserData

    if( io.WantCaptureMouse ) {
        if( button >= 0 && button < 3 ) {
            if( val == GLFW_PRESS ) {
                gui.mouse_pressed[ button ] = true;
            } else if ( val == GLFW_RELEASE ) {
                gui.mouse_pressed[ button ] = true;
            }
        }
    } else {
        // forward to input.mouseButtonCallback
        import input : mouseButtonCallback;
        mouseButtonCallback( window, button, val, mod );
    }
}

// Callback function for capturing mouse scroll wheel events
void guiScrollCallback( GLFWwindow* window, double offset_x, double offset_y ) {
    auto io = & ImGui.GetIO();
    auto gui = cast( Gui_State* )io.UserData; // get Gui_State pointer from ImGuiIO.UserData

    if( io.WantCaptureMouse ) {
        gui.mouse_wheel += cast( float )offset_y;     // Use fractional mouse wheel, 1.0 unit 5 lines.
    } else {
        // forward to input.scrollCallback
        import input : scrollCallback;
        scrollCallback( window, offset_x, offset_y );
    }
}

// Callback function for capturing character input events
void guiCharCallback( GLFWwindow*, uint c ) {
    auto io = & ImGui.GetIO();
    if( c > 0 && c < 0x10000 ) {
        io.AddInputCharacter( cast( ImWchar )c );
    }
}

// Callback function for capturing keyboard events
void guiKeyCallback( GLFWwindow* window, int key, int scancode, int val, int mod ) {
    auto io = & ImGui.GetIO();
    io.KeysDown[ key ] = val > 0;

    // interpret KP Enter as Key Enter
    if( key == GLFW_KEY_KP_ENTER )
        io.KeysDown[ GLFW_KEY_ENTER ] = val > 0;

    //( void )mods; // Modifiers are not reliable across systems
    io.KeyCtrl  = io.KeysDown[ GLFW_KEY_LEFT_CONTROL    ] || io.KeysDown[ GLFW_KEY_RIGHT_CONTROL    ];
    io.KeyShift = io.KeysDown[ GLFW_KEY_LEFT_SHIFT      ] || io.KeysDown[ GLFW_KEY_RIGHT_SHIFT      ];
    io.KeyAlt   = io.KeysDown[ GLFW_KEY_LEFT_ALT        ] || io.KeysDown[ GLFW_KEY_RIGHT_ALT        ];
    io.KeySuper = io.KeysDown[ GLFW_KEY_LEFT_SUPER      ] || io.KeysDown[ GLFW_KEY_RIGHT_SUPER      ];

    // return here on key up events, all functionality bellow requires key up events only
    if( val == 0 ) return;

    // forward to input.keyCallback
    import input : keyCallback;
    keyCallback( window, key, scancode, val, mod );

    // if window fullscreen event happened we will not be notified, we must catch the key itself
    auto gui = cast( Gui_State* )io.UserData; // get Gui_State pointer from ImGuiIO.UserData

    if( key == GLFW_KEY_KP_ENTER && mod == GLFW_MOD_ALT ) {
        io.DisplaySize = ImVec2( gui.windowWidth, gui.windowHeight );
        gui.main_win_size.y = gui.windowHeight;       // this sets the window gui height to the window height
    } else

    // turn gui on or off with tab key
    switch( key ) {
        case GLFW_KEY_F1    : gui.draw_gui ^= 1;            break;
        case GLFW_KEY_F2    : gui.show_imgui_examples ^= 1; break;
        default             :                               break;
    }
}

// Callback function for capturing window resize events
void guiWindowSizeCallback( GLFWwindow * window, int w, int h ) {
    auto io = & ImGui.GetIO();
    auto gui = cast( Gui_State* )io.UserData; // get Gui_State pointer from ImGuiIO.UserData
    io.DisplaySize  = ImVec2( w, h );

    //import std.stdio;
    //printf( "WindowSize: %d, %d\n", w, h );

    gui.scale_win_pos.x = w -  60;     // set x - position of scale window
    gui.scale_win_pos.y = h - 190;     // set y - position of scale window
    gui.main_win_size.y = h;           // this sets the window gui height to the window height

    // the extent might change at swapchain creation when the specified extent is not usable
    gui.swapchainExtent( w, h );
    gui.window_resized = true;
}

// Callback Function for capturing mouse motion events
void guiCursorPosCallback( GLFWwindow * window, double x, double y ) {
    auto io = & ImGui.GetIO();
    //if( !io.WantCaptureMouse ) {
        // forward to input.cursorPosCallback
        import input : cursorPosCallback;
        cursorPosCallback( window, x, y );
    //}
}




