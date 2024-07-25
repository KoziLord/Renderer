package Renderer


//


//TODO SHADERS WOW


//
import "core:fmt"
import "core:math"
import "vendor:SDL2"
import IMG "vendor:SDL2/image"
import TTF "vendor:SDL2/ttf"
import "../KGL"
import VK "vendor:vulkan"
import "core:c"
import "base:intrinsics"
import "./VKR"
import "core:strings"

SDL :: SDL2

QUAD := [6][2]f32{{-1, -1}, {1, -1}, {-1,  1},
                  {-1,  1}, {1,  1}, { 1, -1}} 

validationLayers : []cstring = {"VK_LAYER_KHRONOS_validation"}
check_validation_layer_support :: proc() -> (found : bool)
{
    count : u32
    VK.EnumerateInstanceLayerProperties(&count, nil)

    available := make([]VK.LayerProperties, count)
    VK.EnumerateInstanceLayerProperties(&count, &available[0])

    found = false
    for layer in validationLayers
    {

        for available in available
        {
            available := available
            a := cstring(&available.layerName[0])
            fmt.println(a)
            if layer == a
            {
                found = true
                break
            }
        }
    }
    return
}

main :: proc()
{
    _ = SDL2.Init(SDL2.INIT_EVERYTHING)   
    defer SDL2.Quit()
    
    window : ^SDL2.Window = SDL2.CreateWindow("Epic Window!!!", 400, 400, 800, 600, SDL2.WindowFlags{.VULKAN})
    defer SDL2.DestroyWindow((window))
    
    VK.GetInstanceProcAddr = cast(VK.ProcGetInstanceProcAddr)SDL.Vulkan_GetVkGetInstanceProcAddr()
    
    if SDL2.Vulkan_LoadLibrary(nil) == -1
    {
        fmt.println(SDL.GetError())
        
    }
    VK.load_proc_addresses(proc(p : rawptr, name : cstring)
    {
        ptr := VK.GetInstanceProcAddr(nil, name)
        if ptr == nil do return
        (cast(^rawptr) p)^ = cast(rawptr) ptr
    })

    extensionCount : c.uint
    if !SDL2.Vulkan_GetInstanceExtensions(window, &extensionCount, nil)
    {
        fmt.println("Could not get Instance Extensions count")
    }

    
    extensionNames := make([]cstring, extensionCount)
    if !SDL2.Vulkan_GetInstanceExtensions(window, &extensionCount, &extensionNames[0])
    {
        fmt.println("Could not get Instance Extensions")
    }
    check_validation_layer_support()
    vkInstance : VK.Instance
    {
        info := VK.InstanceCreateInfo{
            .INSTANCE_CREATE_INFO,
            nil,
            {},
            nil,
            //u32(len(validationLayers)),
            //&validationLayers[0],
            0,nil,
            extensionCount,
            &extensionNames[0]
        }

        try(VK.CreateInstance(&info, nil, &vkInstance))
        not_nil(vkInstance)
        VK.load_proc_addresses_instance(vkInstance)
    }

    deviceCount : u32
    not_nil(VK.EnumeratePhysicalDevices)
    try(VK.EnumeratePhysicalDevices(vkInstance, &deviceCount, nil))
    
    devices := make([]VK.PhysicalDevice, deviceCount)
    try(VK.EnumeratePhysicalDevices(vkInstance, &deviceCount, &devices[0]))
    physicalDevice := devices[0]
    
    EXTENSIONS_SUPPORT:
    {
        Unit :: struct{}
        required := map[cstring]Unit{
            VK.KHR_SWAPCHAIN_EXTENSION_NAME = {},
            VK.KHR_DYNAMIC_RENDERING_EXTENSION_NAME = {},
            VK.NV_FILL_RECTANGLE_EXTENSION_NAME = {},
        }
        defer delete(required)

        extensionsCount : u32
        try(VK.EnumerateDeviceExtensionProperties(physicalDevice, nil, &extensionsCount, nil))
        extensions := make([]VK.ExtensionProperties, extensionsCount)
        try(VK.EnumerateDeviceExtensionProperties(physicalDevice, nil, &extensionsCount, &extensions[0]))
        for &e in extensions do fmt.println(cast(cstring)&e.extensionName[0])
    
        for &e in extensions
        {
            delete_key(&required, cast(cstring)&e.extensionName[0])
        }
        //Something's missing! print it out and panic.
        if len(required) != 0
        {
            builder := strings.builder_make()
            strings.write_string(&builder, "Missing Extensions!\n")

            for e in required
            {
                for char := cast([^]byte)e; char[0] != 0; char = &char[1]  
                {
                    if char[0] == 0 do break
                    strings.write_byte(&builder, char[0])
                }
                strings.write_byte(&builder, '\n')
            }
            strings.write_string(&builder,"Exiting...")
            panic(strings.to_string(builder))
        }
    }

    queueFamilyCount : u32
    VK.GetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, nil)
    queueFamilies := make([]VK.QueueFamilyProperties, queueFamilyCount)
    VK.GetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, &queueFamilies[0])

    surface : VK.SurfaceKHR
    SDL.Vulkan_CreateSurface(window, vkInstance, &surface)

    queueIndex := max(u32)
    
    for queueFamily, i in queueFamilies
    {
        i := u32(i)
        if (queueIndex == max(u32) && queueFamilyCount > 0 && queueFamily.queueFlags >= {.GRAPHICS, .TRANSFER})
        {    
            support : b32
            VK.GetPhysicalDeviceSurfaceSupportKHR(physicalDevice, i, surface, &support)
            queueIndex = i
        }
    }

    queuePriority := f32(1)
    queueInfo := VK.DeviceQueueCreateInfo{
        VK.StructureType.DEVICE_QUEUE_CREATE_INFO,
        nil,
        nil,
        queueIndex,
        1,
        &queuePriority
    }

    deviceFeatures : VK.PhysicalDeviceFeatures
    deviceExtensionNames := cstring(VK.KHR_SWAPCHAIN_EXTENSION_NAME)
    createInfo := VK.DeviceCreateInfo{
        VK.StructureType.DEVICE_CREATE_INFO,
        nil,
        {},
        1,
        &queueInfo,
        0,
        nil,
        1,
        &deviceExtensionNames,
        &deviceFeatures
    }

    device : VK.Device
    try(VK.CreateDevice(physicalDevice, &createInfo, nil, &device))

    graphicsQueue : VK.Queue
    VK.GetDeviceQueue(device, queueIndex, 0, &graphicsQueue)

    swapchain : VKR.SwapchainData
    {
        switch v in VKR.make_swapchain(physicalDevice, device, surface, queueIndex,
                                       {800, 600}, .MAILBOX, .SRGB_NONLINEAR, {.B8G8R8A8_SRGB})
        {
            case VKR.SwapchainData: swapchain = v
            case VKR.MakeSwapchainError: panic(fmt.aprintln("Swapchain error:", v))
        } 
    }
    
    //Pipeline init
    pipeline : VK.Pipeline
    {
        pipelineCreateInfo := VK.GraphicsPipelineCreateInfo{
            sType = .GRAPHICS_PIPELINE_CREATE_INFO,
            flags = {},
        }
        //Shader modules
        {
            vertModule : VK.ShaderModule
            {
                bytecode := #load("Shaders/compiled/shader.vert.spv", []byte)
                createInfo := VK.ShaderModuleCreateInfo{
                    sType = .SHADER_MODULE_CREATE_INFO,
                    codeSize = len(bytecode),
                    pCode = cast(^u32)raw_data(bytecode)
                }
                try(VK.CreateShaderModule(device, &createInfo, nil, &vertModule))
            }
            fragModule : VK.ShaderModule
            {
                bytecode := #load("Shaders/compiled/shader.frag.spv", []byte)
                createInfo := VK.ShaderModuleCreateInfo{
                    sType = .SHADER_MODULE_CREATE_INFO,
                    codeSize = len(bytecode),
                    pCode = cast(^u32)raw_data(bytecode)
                }
                try(VK.CreateShaderModule(device, &createInfo, nil, &fragModule))
            }

            stages : [2]VK.PipelineShaderStageCreateInfo = VK.PipelineShaderStageCreateInfo{
                sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
            }
            stages[0] = {
                stage = { .VERTEX },
                module = vertModule,
                pName = "main", 
            }
            stages[1] = {
                stage = { .FRAGMENT },
                module = fragModule,
                pName = "main",
            }
            pipelineCreateInfo.stageCount = len(stages)
            pipelineCreateInfo.pStages = raw_data(stages[:])

            {
                createInfo := VK.PipelineLayoutCreateInfo{
                    sType = .PIPELINE_LAYOUT_CREATE_INFO,

                    setLayoutCount = 0,
                    pSetLayouts = nil,
                    pushConstantRangeCount = 0,
                    pPushConstantRanges = nil,
                }

                try(VK.CreatePipelineLayout(device, &createInfo, nil, &pipelineCreateInfo.layout))
            }
        }

        {
            using pipelineCreateInfo
            pVertexInputState = &VK.PipelineVertexInputStateCreateInfo{
                sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,

                vertexBindingDescriptionCount = 0,
                vertexAttributeDescriptionCount = 0,
            }
            
            pInputAssemblyState = &VK.PipelineInputAssemblyStateCreateInfo{
                sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,

                topology = .TRIANGLE_LIST,
                primitiveRestartEnable = false,
            }
            pRasterizationState = &VK.PipelineRasterizationStateCreateInfo{
                sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,

                depthClampEnable = false,
                rasterizerDiscardEnable = false,
                polygonMode = .FILL,

                cullMode = {},
                frontFace = .CLOCKWISE,
                depthBiasEnable = false,
                depthBiasClamp = 0,
                depthBiasConstantFactor = 0,
                depthBiasSlopeFactor = 0,
            }

            pMultisampleState = &VK.PipelineMultisampleStateCreateInfo{
                sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,

                sampleShadingEnable = false,
                rasterizationSamples = {._1},
                minSampleShading = 1,
                alphaToCoverageEnable = false,
                alphaToOneEnable = false,
            }

            pColorBlendState = &VK.PipelineColorBlendStateCreateInfo{
                sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                
                logicOpEnable = false,
                logicOp = .COPY,
                attachmentCount = 1,
                pAttachments = &VK.PipelineColorBlendAttachmentState{
                    colorWriteMask = {.R, .G, .B, .A},
                    blendEnable = false,
                }
            }
        
            pViewportState = &VK.PipelineViewportStateCreateInfo{
                sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,

                viewportCount = 1,
                pViewports = &VK.Viewport{
                    x = 0,
                    y = 0,
                    width = 800,
                    height = 600,
                    minDepth = 0,
                    maxDepth = 1,
                },
                pScissors = &VK.Rect2D{
                    offset = {0, 0},
                    extent = {800, 600},
                }
            }
        }
        VK.pipelinerendering
        try(VK.CreateGraphicsPipelines(device, {}, 1, &pipelineCreateInfo, nil, &pipeline))   
    }

    commandPool : VK.CommandPool
    {
        createInfo := VK.CommandPoolCreateInfo{
            sType = .COMMAND_POOL_CREATE_INFO,
            flags = {.RESET_COMMAND_BUFFER},
            queueFamilyIndex = queueIndex,
        }
        try(VK.CreateCommandPool(device, &createInfo, nil, &commandPool))
    }
    
    commandBuffer : VK.CommandBuffer
    {
        allocInfo := VK.CommandBufferAllocateInfo{
            sType = .COMMAND_BUFFER_ALLOCATE_INFO,

            commandPool = commandPool,
            level = .PRIMARY,
            commandBufferCount = 1,
        }

        try(VK.AllocateCommandBuffers(device, &allocInfo, &commandBuffer))

        beginInfo := VK.CommandBufferBeginInfo{
            sType = .COMMAND_BUFFER_BEGIN_INFO,
            flags = {},
            pInheritanceInfo = nil,
        }

        try(VK.BeginCommandBuffer(commandBuffer, &beginInfo))
    }
    
    renderPass : VK.RenderPass
    {
        beginfInfo := VK.RenderPassBeginInfo{
            sType = .RENDER_PASS_BEGIN_INFO,
            
        }
    }
    VK.CmdBeginRenderingKHR()
    proc() {panic("Ran successfully!\n")}()
    
    run := true
    for run
    {
        Input:
        {
            event := SDL2.Event{}
            for SDL2.PollEvent(&event)
            {
                #partial switch event.type
                {
                    case .APP_TERMINATING, .QUIT:
                    {
                        run = false
                    }
                }    
            }
        }
        
        Drawing:
        {

            
        }
        
    }
}

try :: proc{
    VKR.try,
}
try_sdl :: proc(r : c.int loc := #caller_location)
{
    if r == 0 do return

    error := SDL.GetError()
    fmt.println("%v: %s", loc, error)
}
not_nil :: proc(ptr : $T, loc := #caller_location)// where intrinsics.type_is_pointer(T) || intrinsics.type_is_proc(T)
{
    if ptr == nil do panic("Value was nil")
}