module toys.sdf_heightmap;

import app;
import input;
import vdrive;
import erupted;


nothrow @nogc:

private {

    Core_Pipeline raymarch_pso;
    enum Scene { Classic, Shapes, Modern, Noise };
    Scene scene = Scene.Modern;

    // Noise and Hight Map related resources
    //alias Heightmap = Core_Image_T!( 11, 1, IMC.Memory | IMC.Sub_Range );  // 11 Views, 1 Sampler
    alias Heightmap = Core_Image_Memory_T!( 12, 1, IMC.Last_Range );  // 11 Views, 1 Sampler
    
    Core_Pipeline   mipmap_pso;

    Core_Pipeline   noise_pso;
    float           noise_frequency = 0.002f;
    int             noise_vis_level = 0;

    Heightmap       heightmap_img;
    bool            update_heightmap = true;

    bool            draw_axis_and_grid = false;

    VkPhysicalDeviceDescriptorIndexingFeatures indexing_features;
//  VkPhysicalDeviceVulkan12Features gpu_1_2_faetures;

}


// get toy's name and functions
App.Toy GetToy() {
    App.Toy toy;
    toy.name        = "Sdf_Heightmap";
    toy.extInstance = & getInstanceExtensions;
    toy.extDevice   = & getDeviceExtensions;
    toy.features    = & getFeatures;
    toy.descriptor  = & createDescriptor;
    toy.create      = & createPSOs;
    toy.record      = & recordCommands;
    toy.recordPreRP = & recordHeightmapCommands;
    toy.widgets     = & buildWidgets;
    toy.destroy     = & destroyResources;
    return toy;
}


// setup required extensions
void getInstanceExtensions( ref App_Meta_Init meta_init ) {
    meta_init.addInstanceExtension( VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME );
}


// setup required extensions
void getDeviceExtensions( ref App_Meta_Init meta_init ) {
    meta_init
        .addDeviceExtension( VK_EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME )
        .addDeviceExtension( VK_KHR_MAINTENANCE_3_EXTENSION_NAME );
}


// setup required features
void getFeatures( ref App_Meta_Init meta_init ) {
    // Use App app to determine if features are available, and, if not, set a my_can_run member
    meta_init.features.shaderStorageImageArrayDynamicIndexing = true;

    //*
    // indexing_features = VkPhysicalDeviceDescriptorIndexingFeatures.init;
    // indexing_features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES;
    // indexing_features.runtimeDescriptorArray = true;
    // indexing_features.pNext = null;  //features2.pNext;
    // features2.pNext = & indexing_features;

    //gpu_1_2_faetures = VkPhysicalDeviceVulkan12Features.init;

    indexing_features.shaderSampledImageArrayNonUniformIndexing = VK_TRUE;

	// These are required to support the 4 descriptor binding flags we use in this sample.
	indexing_features.descriptorBindingSampledImageUpdateAfterBind = VK_TRUE;
	indexing_features.descriptorBindingPartiallyBound              = VK_TRUE;
	indexing_features.descriptorBindingUpdateUnusedWhilePending    = VK_TRUE;
	indexing_features.descriptorBindingVariableDescriptorCount     = VK_TRUE;

    // Enables use of runtimeDescriptorArrays in SPIR-V shaders.
    indexing_features.runtimeDescriptorArray = VK_TRUE;

    meta_init.addExtendedFeature( & indexing_features );
}


// create raymarch and initial noise PSOs 
void createDescriptor( ref App app, ref Meta_Descriptor meta_descriptor ) {

    ///////////////////////////////////////////
    // create and transition heightmap noise //
    ///////////////////////////////////////////
    
    auto heightmap_format = VK_FORMAT_R16_SFLOAT; //VK_FORMAT_R16G16B16A16_SFLOAT

    // specify and construct image with new Binding Rvalues to ref Parameters syntax, requires dmd v2.086.0 and higher
    auto meta_heightmap_img = Meta_Image_T!( Heightmap )( app )
        .format( heightmap_format )
        .mipLevels( 11 )
        .extent( 1024, 1024 )
        .addUsage( VK_IMAGE_USAGE_SAMPLED_BIT )
        .addUsage( VK_IMAGE_USAGE_STORAGE_BIT )
        .tiling( VK_IMAGE_TILING_OPTIMAL )
        .constructImage

        // allocate and bind image memory
        .allocateMemory( VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT )  // : VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT )   // Todo(pp): check which memory property is required for the image format

        // specify and construct image view
        .viewType( VK_IMAGE_VIEW_TYPE_2D );

    // for compute shader access
    foreach( i; 0 .. 11 )
        meta_heightmap_img
            .viewMipLevels( i,  1 )
            .constructView( i + 1 );

    // for frag shader access and transitions (subresource range)
    meta_heightmap_img
        .viewMipLevels( 0, 11 )
        .constructView( 0 ); 

    if( heightmap_img.sampler.is_null )
        meta_heightmap_img
            .filter( VK_FILTER_NEAREST, VK_FILTER_NEAREST )
            .mipmap( VK_SAMPLER_MIPMAP_MODE_NEAREST, 0.0f, 12.0f )    // mode, min_lod, max_lod, lod_bias
            .constructSampler;

    debug app.setDebugName( meta_heightmap_img.sampler, "Noise Image Sampler" );

    // extract Core_Image_T from Meta_Image_T and clear temp data
    heightmap_img = meta_heightmap_img.reset;

    // add descriptor for sampling
    meta_descriptor.addSamplerImageBinding( 2, VK_SHADER_STAGE_FRAGMENT_BIT )
        .addSamplerImage( heightmap_img.sampler, heightmap_img.view[0], VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL );

    // add descriptor for compute shader rw access
    meta_descriptor.addStorageImageBinding( 3, VK_SHADER_STAGE_COMPUTE_BIT );// | VK_SHADER_STAGE_FRAGMENT_BIT );
    foreach( ref view; heightmap_img.view[ 1 .. $ ] )
        meta_descriptor.addImage( view, VK_IMAGE_LAYOUT_GENERAL );
    // meta_descriptor.addImage( heightmap_img.view[0], VK_IMAGE_LAYOUT_GENERAL );

    // Heightmap* heightmap_ptr = & heightmap_img;  // for debugging, as module scope variables cannot be inspected in the debugger

    // use noise and mipmap psos to generate the noise and the max mipmap pyramid
    auto init_cmd_buffer = app.allocateCommandBuffer( app.cmd_pool, VK_COMMAND_BUFFER_LEVEL_PRIMARY );
    auto init_cmd_buffer_bi = createCmdBufferBI( VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT );
    init_cmd_buffer.vkBeginCommandBuffer( & init_cmd_buffer_bi );

    init_cmd_buffer.recordTransition(
        heightmap_img.image,
        heightmap_img.subresourceRange,
        VK_IMAGE_LAYOUT_UNDEFINED,
        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,   // VK_IMAGE_LAYOUT_GENERAL,
        0,  // no access mask required here
        VK_ACCESS_SHADER_READ_BIT,     // VK_ACCESS_SHADER_WRITE_BIT,
        VK_PIPELINE_STAGE_HOST_BIT,
        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT
    );

    // record dispatch commands
    //  app.recordHeightmapCommands( init_cmd_buffer );

    init_cmd_buffer.vkEndCommandBuffer;                 // finish recording and submit the command
    auto submit_info = init_cmd_buffer.queueSubmitInfo; // submit the command buffer
    app.graphics_queue.vkQueueSubmit( 1, & submit_info, VK_NULL_HANDLE ).vkAssert;
}


// Create Heightmap and Noise PSOs
void createNoisePSOs( ref App app ) nothrow @nogc {

    // if we are recreating an old pipeline exists already, destroy it first
    if( noise_pso.pso != VK_NULL_HANDLE ) {
        app.graphics_queue.vkQueueWaitIdle;
        app.destroy( noise_pso );
    }

    // create noise pso
    // tmeplate arg 1: descriptor set count, arg 2: push constant range count
    noise_pso = Meta_Compute_T!( 1, 1)( app )   // extracting the core items after construction with reset call
        .shaderStageCreateInfo( app.createPipelineShaderStage( "shader/toys/sdf/noise.comp" ))
        .addDescriptorSetLayout( app.descriptor.descriptor_set_layout )     // Storage Image to write to
        .addPushConstantRange( VK_SHADER_STAGE_COMPUTE_BIT, 0, 4 )          // edit noise parameter
        .construct( app.pipeline_cache )         // construct using pipeline cache
        .destroyShaderModule                     // destroy shader modules
        .reset;

    debug {
        app.setDebugName( noise_pso.pipeline, "Heightmap PSO" );
        app.setDebugName( noise_pso.layout, "Heightmap PSO Layout" );
    }


    // if we are recreating an old pipeline exists already, destroy it first
    if( mipmap_pso.pso != VK_NULL_HANDLE ) {
        app.graphics_queue.vkQueueWaitIdle;
        app.destroy( mipmap_pso );
    }

    // create mipmap pso
    mipmap_pso = Meta_Compute_T!( 1, 1)( app )  // we don't need push constants, we just save on d compilation time
        .shaderStageCreateInfo( app.createPipelineShaderStage( "shader/toys/sdf/mipmap_max.comp" ))
        .addDescriptorSetLayout( app.descriptor.descriptor_set_layout )     // Storage Image to read from and write to
        .addPushConstantRange( VK_SHADER_STAGE_COMPUTE_BIT, 0, 4 )          // set source mipmap level
        .construct( app.pipeline_cache )        // construct using pipeline cache
        .destroyShaderModule                    // destroy shader modules
        .reset;

    debug {
        app.setDebugName( mipmap_pso.pipeline, "MipMap PSO" );
        app.setDebugName( mipmap_pso.layout, "MipMap PSO Layout" );
    }

    update_heightmap = true;

}


// record to create noise image and its max pyramid
void recordHeightmapCommands( ref App app, VkCommandBuffer cmd_buffer ) {
    
    if(!update_heightmap ) return;
        update_heightmap = false;

    cmd_buffer.recordTransition(
        heightmap_img.image,
        heightmap_img.subresourceRange,
        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        VK_IMAGE_LAYOUT_GENERAL,
        VK_ACCESS_SHADER_READ_BIT,
        VK_ACCESS_SHADER_WRITE_BIT,
        VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
    );

    cmd_buffer.vkCmdBindDescriptorSets(         // VkCommandBuffer              commandBuffer
        VK_PIPELINE_BIND_POINT_COMPUTE,         // VkPipelineBindPoint          pipelineBindPoint
        noise_pso.layout,                       // VkPipelineLayout             layout
        0,                                      // uint32_t                     firstSet
        1,                                      // uint32_t                     descriptorSetCount
        & app.descriptor.descriptor_set,        // const( VkDescriptorSet )*    pDescriptorSets
        0,                                      // uint32_t                     dynamicOffsetCount
        null                                    // const( uint32_t )*           pDynamicOffsets
    );

    // generate noise
    float* noise_freq_ptr = & noise_frequency;
    cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_COMPUTE, noise_pso.pipeline );
    cmd_buffer.vkCmdPushConstants( noise_pso.layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, float.sizeof, noise_freq_ptr );

    uint workgroup_count = 32;     // = 1024 / 32
    cmd_buffer.vkCmdDispatch( workgroup_count, workgroup_count, 1 );
    //*
    // generate mipmaps
    cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_COMPUTE, mipmap_pso.pipeline );

    // supposed to be more efficient than buffer or image barrier
    VkMemoryBarrier memory_barrier = {
        srcAccessMask   : VK_ACCESS_SHADER_WRITE_BIT,
        dstAccessMask   : VK_ACCESS_SHADER_READ_BIT,
    };

    //uint source_mip_idx = 0;    // we omitted the first view (view of all mips) in the ImageStorage for compute descriptor

    foreach( uint trg_mip_idx; 1 .. 11 ) {
    //while( workgroup_count > 1 ) {

        cmd_buffer.vkCmdPipelineBarrier(
            VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,   // VkPipelineStageFlags                 srcStageMask,
            VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,   // VkPipelineStageFlags                 dstStageMask,
            0,                                      // VkDependencyFlags                    dependencyFlags,
            1, & memory_barrier,                    // uint32_t memoryBarrierCount,         const VkMemoryBarrier* pMemoryBarriers,
            0, null,                                // uint32_t bufferMemoryBarrierCount,   const VkBufferMemoryBarrier* pBufferMemoryBarriers,
            0, null,                                // uint32_t imageMemoryBarrierCount,    const VkImageMemoryBarrier*  pImageMemoryBarriers,
        );

        cmd_buffer.vkCmdPushConstants( mipmap_pso.layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, uint.sizeof, & trg_mip_idx );

        if( workgroup_count > 1 )
            workgroup_count >>= 1;

        cmd_buffer.vkCmdDispatch( workgroup_count, workgroup_count, 1 );

        //++source_mip_idx;
    }

    // // final barrier makes mipmaps readable in fragment shader
    // cmd_buffer.vkCmdPipelineBarrier(
    //     VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,   // VkPipelineStageFlags                 srcStageMask,
    //     VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,  // VkPipelineStageFlags                 dstStageMask,
    //     0,                                      // VkDependencyFlags                    dependencyFlags,
    //     1, & memory_barrier,                    // uint32_t memoryBarrierCount,         const VkMemoryBarrier* pMemoryBarriers,
    //     0, null,                                // uint32_t bufferMemoryBarrierCount,   const VkBufferMemoryBarrier* pBufferMemoryBarriers,
    //     0, null,                                // uint32_t imageMemoryBarrierCount,    const VkImageMemoryBarrier*  pImageMemoryBarriers,
    // );
    //*/
    cmd_buffer.recordTransition(
        heightmap_img.image,
        heightmap_img.subresourceRange,
        VK_IMAGE_LAYOUT_GENERAL,
        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        VK_ACCESS_SHADER_WRITE_BIT,
        VK_ACCESS_SHADER_READ_BIT,
        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT
    );
}


void createPSOs( ref App app ) {
    app.createRaymarchPSO;
    app.createNoisePSOs;
    import toys.cam_debug;
    app.createResources;
}


// create raymarch PSO
void createRaymarchPSO( ref App app ) {

    ////////////////////////////////////////////
    // (re)create pipeline state object (PSO) //
    ////////////////////////////////////////////

    // if we are recreating an old pipeline exists already, destroy it first
    if( raymarch_pso.pso != VK_NULL_HANDLE ) {
        app.graphics_queue.vkQueueWaitIdle;
        app.destroy( raymarch_pso );
    }

    // add shader stages - git repo needs only to keep track of the shader sources,
    // vdrive will compile them into spir-v with glslangValidator (must be in path!)
    import vdrive.pipeline, vdrive.shader;
    string_z vert_shader = null;
    string_z frag_shader = null;
    switch( scene ) {
        case Scene.Classic:
            vert_shader = "shader/toys/sdf/sdf_tube.vert";
            frag_shader = "shader/toys/sdf/sdf_tube.frag";
            break;
        case Scene.Shapes:
            vert_shader = "shader/toys/sdf/sdf.vert";
            frag_shader = "shader/toys/sdf/sdf_shapes.frag";
            break;
        case Scene.Modern:
            vert_shader = "shader/toys/sdf/sdf.vert";
            frag_shader = "shader/toys/sdf/sdf.frag";
            break;
        case Scene.Noise:
            vert_shader = "shader/toys/sdf/noise_vis.vert";
            frag_shader = "shader/toys/sdf/noise_vis.frag";
            break;
        default: break;
    }

    raymarch_pso = Meta_Graphics( app )
        .addShaderStageCreateInfo( app.createPipelineShaderStage( vert_shader ))    // deduce shader stage from file extension
        .addShaderStageCreateInfo( app.createPipelineShaderStage( frag_shader ))    // deduce shader stage from file extension
        .inputAssembly( VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP )                      // set the inputAssembly
        .addViewportAndScissors( VkOffset2D( 0, 0 ), app.swapchain.image_extent )   // add viewport and scissor state, necessary even if we use dynamic state
        .cullMode( VK_CULL_MODE_NONE )                                              // set rasterization state -  this cull mode is the default value
        .depthState                                                                 // set depth state - enable depth test with default attributes
        .addColorBlendState( VK_FALSE )                                             // color blend state - append common (default) color blend attachment state
        .addDynamicState( VK_DYNAMIC_STATE_VIEWPORT )                               // add dynamic states viewport
        .addDynamicState( VK_DYNAMIC_STATE_SCISSOR )                                // add dynamic states scissor
        .addDescriptorSetLayout( app.descriptor.descriptor_set_layout )             // describe pipeline layout
        .addPushConstantRange( VK_SHADER_STAGE_FRAGMENT_BIT, 0, 4 )                 // specify push constant range
        .renderPass( app.render_pass_bi.renderPass )                                // describe COMPATIBLE render pass
        .construct                                                                  // construct the Pipleine Layout and Pipleine State Object (PSO)
        .destroyShaderModules
        .reset;                                                                     // shader modules compiled into pipeline, not shared, can be deleted now
}


// record draw commands
void recordCommands( ref App app, VkCommandBuffer cmd_buffer ) {

    // if( update_heightmap )
    //     app.recordHeightmapCommands( cmd_buffer );

    // bind graphics app.geom_pipeline
    int* noise_vis_ptr = & noise_vis_level;
    cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_GRAPHICS, raymarch_pso.pipeline );
    cmd_buffer.vkCmdPushConstants( raymarch_pso.layout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, int.sizeof, noise_vis_ptr );

    cmd_buffer.vkCmdBindDescriptorSets(     // VkCommandBuffer              commandBuffer
        VK_PIPELINE_BIND_POINT_GRAPHICS,    // VkPipelineBindPoint          pipelineBindPoint
        raymarch_pso.layout,                // VkPipelineLayout             layout
        0,                                  // uint32_t                     firstSet
        1,                                  // uint32_t                     descriptorSetCount
        & app.descriptor.descriptor_set,    // const( VkDescriptorSet )*    pDescriptorSets
        0,                                  // uint32_t                     dynamicOffsetCount
        null                                // const( uint32_t )*           pDynamicOffsets
    );


    // draw screen aligned triangle
    cmd_buffer.vkCmdDraw(
        3 + (scene == Scene.Noise ? 1 : 0),  // vertex count
        1,  // instance count
        0,  // first vertex
        0   // first instance
    );

    import toys.cam_debug : AxisAndGrid_recordCommands = recordCommands;
    if( draw_axis_and_grid )
        app.AxisAndGrid_recordCommands( cmd_buffer );
}


// Build Gui Widgets
void buildWidgets( ref App app ) {
    import ImGui = d_imgui;            
    
    int s = cast(int)scene;
    ImGui.Text( "Scene : ");

    void addRadio(string name, int index) {
        ImGui.SameLine();
        if( ImGui.RadioButton( name, &s, index )) {
            scene = cast(Scene)s;
            app.createRaymarchPSO;
        }
    }

    addRadio("Classic", 0);
    addRadio("Shapes",  1);
    addRadio("Modern",  2);
    addRadio("Noise",   3);

    switch( scene ) {

        case Scene.Classic:
            ImGui.DragFloat( "Speed Amp", & app.speed_amp, 0.01f, -16.0f, 16.0f );
            break;

        case Scene.Modern:
            if( ImGui.DragFloat( "Noise Frequency", & noise_frequency, 0.001f, 0, 255 ))
                update_heightmap = true;
            ImGui.DragInt( "Max Ray Steps", & app.ubo.max_ray_steps, 0.125, 8, 2048 );
            ImGui.DragFloat( "Epsilon Log", & app.ubo.epsilon, 0.01f, 0.0f, 1.0f, "%.4f", ImGui.ImGuiSliderFlags.Logarithmic );

            ImGui.Separator;
            ImGui.DragFloat( "HM Scale", & app.ubo.hm_scale, 0.01f, 0.1f, 100.0f, "%.3f" );
            ImGui.DragFloat( "HM Height Factor", & app.ubo.hm_height_factor, 0.01f, 0.0f, 2.0f );
            ImGui.DragInt( "HM MipMap Level", & app.ubo.hm_level, 0.125, 0, 10 );
            ImGui.DragInt( "HM Max Level", & app.ubo.hm_max_level, 0.125, 0, 10 );

            // reflect values for grid and axis
            import toys.cam_debug : setGridScaleAndHeightFactor, setGridCellCountPerAxis;
            setGridScaleAndHeightFactor( app.ubo.hm_scale, app.ubo.hm_height_factor );
            setGridCellCountPerAxis( 1 << ( app.ubo.hm_max_level - app.ubo.hm_level ));
            
            ImGui.Separator;
            if( ImGui.CollapsingHeader( "Debug Ray MipMap Intersection" ))
                app.debugQDM;

            ImGui.Separator;
            import toys.cam_debug;
            if( ImGui.CollapsingHeader( "Axis and Grid Overlay" )) {
                draw_axis_and_grid = true;
                app.AxisAndGrid;
            } else {
                draw_axis_and_grid = false;
            }

            if( ImGui.CollapsingHeader( "Debug Camera" ))
                app.debugCamera;


            break;

        case Scene.Noise:
            ImGui.DragInt( "Noise MipMap Level", & noise_vis_level, 0.125, 0, 10 );
            if( ImGui.Button( "Compile Noise PSO" ))
                app.createNoisePSOs;
            if( ImGui.DragFloat( "Noise Frequency", & noise_frequency, 0.001f, 0, 255 ))
                update_heightmap = true;
            break;

        default: break;

    }
}


// destroy resources and vulkan objects for rendering
void destroyResources( ref App app ) {
    app.destroy( raymarch_pso );
    app.destroy( mipmap_pso );
    app.destroy( noise_pso );

    app.destroy( heightmap_img );
}


// debug and verify camera functions and matrices
void debugQDM(ref App app) {
    import ImGui = d_imgui;
    import dlsl;
    ImGui.PushItemWidth(-50);

    ImGui.Text("Ray Origin and Direction");
    auto camm = app.tbb.viewTransform;
    vec3 ro = camm[3][ 0 .. 3];
    vec3 rd = camm[2][ 0 .. 3];
    ImGui.DragFloat3("ro", ro, 0.01f, -20.0f, 20.0f);
    ImGui.DragFloat3("rd", rd, 0.01f, -1.0f, 1.0f);

    ImGui.Separator;
    ImGui.Text("Bounding Box (AABB)");

    // ubo data
	float	Aspect              = app.ubo.aspect;
	float 	FOV                 = app.ubo.fowy;	// vertical field (angle) of view of the perspective projection
    float   Near                = app.ubo.near;
    float   Far                 = app.ubo.far;
	vec4	Mouse               = app.ubo.mouse;	// xy framebuffer coord when LMB pressed, zw when clicked
	vec2	Resolution          = app.ubo.resolution;
	float	Time                = app.ubo.time;
	float	Time_Delta          = app.ubo.time_delta;
	uint	Frame               = app.ubo.frame;
	float	Speed               = app.ubo.speed;

	// Ray Marching
	uint	MaxRaySteps         = app.ubo.max_ray_steps;
	float	Epsilon             = app.ubo.epsilon;

	// Heightmap
	float   HM_Scale            = app.ubo.hm_scale; 
	float   HM_Height_Factor    = app.ubo.hm_height_factor;
	int    	HM_Level            = app.ubo.hm_level;
	int		HM_Max_Level        = app.ubo.hm_max_level;



	float top = HM_Scale * HM_Height_Factor;
	float sxy = 0.5 * HM_Scale;		// side xy
	float hps = sxy / Resolution.x;	// half pixel size
	float bxy = sxy;// - hps;

    // axis aligned bounding box, returns min and max hit 
    // source: https://tavianator.com/2022/ray_box_boundary.html
    bool aabb(vec3 ro, vec3 rd, vec3 b_min, vec3 b_max, ref vec2 e1, ref vec2 e2) {
        vec3 rd_inv = 1.0f / rd;
        vec3 t1 = (b_min - ro) * rd_inv;
        vec3 t2 = (b_max - ro) * rd_inv;
        vec3 t_min = min(t1, t2);
        vec3 t_max = max(t1, t2);
        e1.x = max(max(t_min.x, t_min.y), max(t_min.z, e1.x));
        e1.y = min(min(t_max.x, t_max.y), min(t_max.z, e1.y));
        //return max(e.x, 0) < e.y;
        //return e.x < e.y;

        // original code
        float tmin = Near, tmax = Far;
        float tmi2 = Near, tma2 = Far;

        for (int d = 0; d < 3; ++d) {
            float s1 = t1[d];
            float s2 = t2[d];

            tmin = max(tmin, min(s1, s2));
            tmax = min(tmax, max(s1, s2));

            tmi2 = max(tmi2, t_min[d]);
            tma2 = min(tma2, t_max[d]);
        }

        e2 = vec2(tmin, tmax);

    //  return t_min < t_max;
        return tmin < tmax;
    }

    vec2 uv_to_world(vec2 UV) { return (UV - 0.5) * HM_Scale; }
    vec2 world_to_uv(vec2 xz) { return (xz + 0.5 * HM_Scale) / HM_Scale; }
//  vec4 world_to_uv(vec4 xz) { return (xz + 0.5 * HM_Scale) / HM_Scale; }


	// build an axis aligned aounding box (AABB) arround the heightmap and test for entry points
	// the AABB does not bind the whole heightmap, but rather minus half a pixel on each side
    vec3 b_min = -vec3(bxy,   0, bxy);
    vec3 b_max =  vec3(bxy, top, bxy);
    ImGui.DragFloat3("b_min", b_min, 0.01f, -24.0f, 24.0f);
    ImGui.DragFloat3("b_max", b_max, 0.01f, -24.0f, 24.0f);

    ImGui.Separator;
    vec3 p;
    vec2 uv;
	vec2 bb_near_far = vec2(Near, Far);
    vec2 bb_near_far_orig = vec2(Near, Far);
    ImGui.Text("Bounding Box: "); ImGui.SameLine;
	if (!aabb(ro, rd, -vec3(bxy, 0, bxy), vec3(bxy, top, bxy), bb_near_far, bb_near_far_orig)) {
        ImGui.TextColored(ImGui.ImVec4(1.0f, 0.0f, 0.0f, 1.0f), "Miss");
        p  = vec3(0.0f);
        uv = vec2(0.0f);
	} else {
        ImGui.TextColored(ImGui.ImVec4(0.0f, 1.0f, 0.0f, 1.0f), "Hit");
        p = ro + bb_near_far.x * rd;
        uv = world_to_uv(p.xz);
    }

    ImGui.DragFloat2("nf", bb_near_far, 0.01f, -20.0f, 20.0f);
//  ImGui.DragFloat2("nf orig", bb_near_far_orig, 0.01f, -20.0f, 20.0f);

    ImGui.DragFloat3("hp", p,  0.01f, -20.0f, 20.0f);
    ImGui.DragFloat2("uv", uv, 0.01f,   0.0f,  1.0f);

    int lod_res = 1 << (HM_Max_Level - HM_Level);
    ivec2 NodeIdx = clamp(ivec2(uv * lod_res), ivec2(0), ivec2(lod_res - 1));
    ImGui.DragInt2("idx", NodeIdx, 1.0f, 0,  1024);

}

