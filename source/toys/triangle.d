module toys.triangle;

import app;
import input;
import vdrive;
import erupted;


nothrow @nogc:

private {
    Core_Pipeline       pipeline;
    Core_Buffer_Memory  geometry;
}


// create shader input assembly buffer and PSO
void createResources( ref App app ) {

    /////////////////////////////////
    // geometry with draw commands //
    /////////////////////////////////

    // declare a vertex structure and use its size in the PSO
    import dlsl.vector;
    struct Vertex {
        vec3 position;  // position
        vec3 color;     // color
    }

    //struct Vertex { float x, y, z; }
    Vertex[3] triangle = [
        Vertex( vec3(  1, -1, 0 ), vec3( 1, 0, 0 )),
        Vertex( vec3( -1, -1, 0 ), vec3( 0, 1, 0 )),
        Vertex( vec3(  0,  1, 0 ), vec3( 0, 0, 1 ))
    ];

    import vdrive.memory, vdrive.buffer;

    // prefer getting the vertex data into a device local heap
    // first we need to find out if such a heap exist on the current device
    // we do not check the size of the heap, the triangle will most likely fit if such heap exists
    if( !app.memory_properties.hasMemoryHeapType( VK_MEMORY_HEAP_DEVICE_LOCAL_BIT )) {

        // edit the internal Meta_Buffer via alias this
       geometry = Meta_Buffer_Memory( app )                     // init Meta_Geometry and its Meta_Buffer structs
            .usage( VK_BUFFER_USAGE_VERTEX_BUFFER_BIT )             // we want to use the geometry buffer as vertex buffer
            .bufferSize( triangle.sizeof )                          // specify the required buffer size
            .construct( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT )       // create the internal VkBuffer object and required HOST_VISIBLE VkMemory
            .copyData( triangle )                                   // copy the data to our buffer, this internally maps and unmaps the buffer
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
            .bufferSize( triangle.sizeof )                          // specify the required buffer size
            .construct( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT )       // create the internal VkBuffer object and required HOST_VISIBLE VkMemory
            .copyData( triangle, 0, VK_WHOLE_SIZE );                // copy the data to our buffer, this internally maps and unmaps the buffer
                                                                    // this usually works with the data size, but in some scenarios we need to pass in some other size
        // edit the internal Meta_Buffer via alias this
        geometry = Meta_Buffer_Memory( app )                    // init Meta_Geometry and its Meta_Buffer structs
            .usage( VK_BUFFER_USAGE_VERTEX_BUFFER_BIT               // we want to use the geometry buffer as vertex buffer
                  | VK_BUFFER_USAGE_TRANSFER_DST_BIT )              // and as transfer data (copy) destination
            .bufferSize( triangle.sizeof )                          // specify the required buffer size
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
            size        : triangle.sizeof
        };

        // record the buffer copy
        cmd_buffer.vkCmdCopyBuffer( staging_buffer.buffer, geometry.buffer, 1, & buffer_copy );

        // finish recording
        cmd_buffer.vkEndCommandBuffer;

        // submit the command buffer, combines parametrizing a VkSubmitInfo and the submission
        app.graphics_queue.queueSubmit( cmd_buffer );

        // destroy staging buffer
        app.graphics_queue.vkQueueWaitIdle;     // equivalent using a fence per Spec v1.0.48
        staging_buffer.destroyResources;        // destroy the temporary staging resources
    }


    ////////////////////////////////////////
    // create pipeline state object (PSO) //
    ////////////////////////////////////////

    // add shader stages - git repo needs only to keep track of the shader sources,
    // vdrive will compile them into spir-v with glslangValidator (must be in path!)
    import vdrive.pipeline, vdrive.shader;
    pipeline = Meta_Graphics( app )
        .addShaderStageCreateInfo( app.createPipelineShaderStage( "shader/toys/simple.vert" ))    // deduce shader stage from file extension
        .addShaderStageCreateInfo( app.createPipelineShaderStage( "shader/toys/simple.frag" ))    // deduce shader stage from file extension
        .addBindingDescription( 0, Vertex.sizeof, VK_VERTEX_INPUT_RATE_VERTEX )     // add vertex binding and attribute descriptions
        .addAttributeDescription( 0, 0, VK_FORMAT_R32G32B32_SFLOAT, 0 )             // ... interleaved in position ...
        .addAttributeDescription( 1, 0, VK_FORMAT_R32G32B32_SFLOAT, vec3.sizeof )   // ... interleaved in color ...
        .inputAssembly( VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST )                       // set the inputAssembly
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
        .reset; 
}


// record draw commands
void recordCommands( ref App app, VkCommandBuffer cmd_buffer ) {

    // bind the gui graphics pipeline
    cmd_buffer.vkCmdBindPipeline( VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline );

    cmd_buffer.vkCmdBindDescriptorSets(             // VkCommandBuffer              commandBuffer
        VK_PIPELINE_BIND_POINT_GRAPHICS,            // VkPipelineBindPoint          pipelineBindPoint
        pipeline.pipeline_layout,                   // VkPipelineLayout             layout
        0,                                          // uint32_t                     firstSet
        1,                                          // uint32_t                     descriptorSetCount
        & app.descriptor.descriptor_set,            // const( VkDescriptorSet )*    pDescriptorSets
        0,                                          // uint32_t                     dynamicOffsetCount
        null                                        // const( uint32_t )*           pDynamicOffsets
    );

    // bind vertex buffer, only one attribute stored in this buffer
    VkDeviceSize offset = 0;
    cmd_buffer.vkCmdBindVertexBuffers(
        0,                                          // first binding
        1,                                          // binding count
        & geometry.buffer,                          // pBuffers to bind
        & offset                                    // pOffsets into buffers
    );

    // simple draw command, non indexed
    cmd_buffer.vkCmdDraw(
        3,                                          // vertex count
        1,                                          // instance count
        0,                                          // first vertex
        0                                           // first instance
    );
}


// destroy resources and vulkan objects for rendering
void destroyResources( ref App app ) {
    app.destroy( pipeline );
    app.destroy( geometry );
}


// get toy's name and functions
App.Toy GetToy() {
    App.Toy toy;
    toy.name    = "Triangle";
    toy.create  = & createResources;
    toy.record  = & recordCommands;
    toy.destroy = & destroyResources;
    return toy;
}
