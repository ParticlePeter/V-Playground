//module input;

import bindbc.glfw;

import dlsl.vector;
import dlsl.trackball;

import app;


nothrow @nogc :


void registerCallbacks( ref App_State app ) {
    glfwSetWindowUserPointer(   app.window, & app );
    glfwSetWindowSizeCallback(  app.window, & windowSizeCallback );
    glfwSetMouseButtonCallback( app.window, & mouseButtonCallback );
    glfwSetWindowFocusCallback( app.window, & windowFocusCallback );
    glfwSetCursorPosCallback(   app.window, & cursorPosCallback );
    glfwSetScrollCallback(      app.window, & scrollCallback );
    glfwSetKeyCallback(         app.window, & keyCallback );
}

// wrap dlsl.Trackball and extracted glfw mouse buttons
struct TrackballButton {
    Trackball_Persp tb;
    alias tb this;
    ubyte button;
}

// gather mouse movement (position and velocity)
struct MouseMove {
    float pos_x = 0, pos_y = 0;
    float vel_x = 0, vel_y = 0;
}

void initTrackball(
    ref     App_State app,
    float   cam_pos_x           =  3,
    float   cam_pos_y           =  3,
    float   cam_pos_z           = -6,
    float   cam_target_x        =  0,
    float   cam_target_y        =  0,
    float   cam_target_z        =  0,
    ) {
    home_pos_x = cam_pos_x;
    home_pos_y = cam_pos_y;
    home_pos_z = cam_pos_z;
    home_trg_x = cam_target_x;
    home_trg_y = cam_target_y;
    home_trg_z = cam_target_z;

    app.tbb.perspectiveFovyWindowHeight( app.projection_fovy, app.windowHeight );
    app.camHome;
}



void initTrackball( ref App_State app ) {

    import std.math : tan;
    enum deg2rad = 0.0174532925199432957692369076849f;
    home_pos_x = 0.5f * app.win_w;
    home_pos_y = 0.5f * app.win_h;
    home_pos_z = - 0.5 / tan( 0.5 * deg2rad * app.projection_fovy );   // this vlue is not finished yet and will be scaled bellow
    home_trg_x = home_pos_x;
    home_trg_y = home_pos_y;
    home_trg_z = 0;

    app.tbb.perspectiveFovyWindowHeight( app.projection_fovy, app.windowHeight );
    //app.camHome;
}



/// private utility to get and access App_State from GLFWwindow user data
private App_State * getApp( GLFWwindow * window ) nothrow {
    return cast( App_State* )window.glfwGetWindowUserPointer;
}



/// Callback Function for capturing window resize events
extern( C ) void windowSizeCallback( GLFWwindow * window, int w, int h ) nothrow {
    // the extent might change at swapchain creation when the specified extent is not usable
    auto app = window.getApp;
    app.swapchainExtent( w, h );
    app.window_resized = true;
}


/// Callback Function for capturing mouse motion events
extern( C ) void cursorPosCallback( GLFWwindow * window, double x, double y ) nothrow {
    auto app = window.getApp;

    // Todo(pp): move this into trackball - Trackball reference should then take no args and get a snapshot of these values
    // get mouse position and compute mouse velocity
    app.mouse.vel_x = x - app.mouse.pos_x;
    app.mouse.vel_y = y - app.mouse.pos_y;
    app.mouse.pos_x = x;
    app.mouse.pos_y = y;

    if( glfwGetKey( window, GLFW_KEY_LEFT_ALT ) == GLFW_PRESS ) {
        // update camera matrix
        switch( app.tbb.button ) {
            case 1  : app.tbb.orbit( x, y ); app.updateWVPM; break;
            case 2  : app.tbb.xform( x, y ); app.updateWVPM; break;
            case 4  : app.tbb.dolly( x, y ); app.updateWVPM; break;
            default : break;
        }
    }
}


/// Callback Function for capturing mouse motion events
extern( C ) void mouseButtonCallback( GLFWwindow * window, int button, int val, int mod ) nothrow {
    auto app = window.getApp;
    // compute mouse button bittfield flags
    switch( button ) {
        case 0  : app.tbb.button += 2 * val - 1; break;
        case 1  : app.tbb.button += 8 * val - 4; break;
        case 2  : app.tbb.button += 4 * val - 2; break;
        default : app.tbb.button  = 0;
    }

    // set trackball reference if any mouse button is pressed
    if( app.tbb.button != 0 ) {
        app.tbb.reference( app.mouse.pos_x, app.mouse.pos_y );
    }
}


extern( C ) void windowFocusCallback( GLFWwindow * window, int focus ) nothrow {
    auto app = window.getApp;
    app.tbb.button = 0;
}


/// Callback Function for capturing mouse wheel events
extern( C ) void scrollCallback( GLFWwindow * window, double x, double y ) nothrow {
    auto app = window.getApp;
    app.tbb.reference( 0, 0 );
    app.tbb.dolly( 5 * x, - 10 * y );
    app.updateWVPM;
}


/// Callback Function for capturing keyboard events
extern( C ) void keyCallback( GLFWwindow * window, int key, int scancode, int val, int mod ) nothrow {
    auto app = window.getApp;
    // use key press results only
    if( val != GLFW_PRESS ) return;
    import resources : createCommands;
    switch( key ) {
        case GLFW_KEY_ESCAPE    : glfwSetWindowShouldClose( window, GLFW_TRUE );            break;
        case GLFW_KEY_HOME      : (*app).camHome;                                           break;
        case GLFW_KEY_KP_ENTER  : if( mod == GLFW_MOD_ALT ) window.toggleFullscreen;        break;
        default                 :                                                           break;
    }
}

private:
float home_pos_x, home_pos_y, home_pos_z;   // camera home position, defined when initializing the trackball
float home_trg_x, home_trg_y, home_trg_z;   // camera home target, same as above

bool fb_fullscreen = false;                 // keep track if we are in fullscreen mode
int win_x, win_y, win_w, win_h;             // remember position and size of window when switching to fullscreen mode

// set camera back to its initial state
void camHome( ref App_State app ) nothrow @nogc {
    app.tbb.lookAt( home_pos_x, home_pos_y, home_pos_z, home_trg_x, home_trg_y, home_trg_z );
    app.updateWVPM;
}

// toggle fullscreen state of window
void toggleFullscreen( GLFWwindow * window ) nothrow @nogc {
    if( fb_fullscreen ) {
        fb_fullscreen = false;
        glfwSetWindowMonitor( window, null, win_x, win_y, win_w, win_h, GLFW_DONT_CARE );
    } else {
        fb_fullscreen = true;
        glfwGetWindowPos(  window, & win_x, & win_y );
        glfwGetWindowSize( window, & win_w, & win_h );
        auto monitor = glfwGetPrimaryMonitor();
        auto vidmode = glfwGetVideoMode( monitor );
        glfwSetWindowPos(  window, 0, 0 );
        glfwSetWindowSize( window, vidmode.width, vidmode.height );
        glfwSetWindowMonitor( window, glfwGetPrimaryMonitor(), 0, 0, vidmode.width, vidmode.height, vidmode.refreshRate );
    }
}