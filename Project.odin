package Renderer

import "core:fmt"
import "core:math"
import "vendor:SDL2"
import IMG "vendor:SDL2/image"
import TTF "vendor:SDL2/ttf"
import VK "vendor:vulkan"
import "core:c"
import "base:intrinsics"
import "./VKR"
import "core:strings"
import "core:reflect"
import "base:runtime"
import "core:mem"

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
            //fmt.println(a)
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
    dimensions := [2]u32{800, 600}
    window : ^SDL2.Window = SDL2.CreateWindow("Epic Window!!!",
                                              400,                 400,
                                              c.int(dimensions.x), c.int(dimensions.y),
                                              SDL2.WindowFlags{.VULKAN})
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

    //SDL VULKAN EXTENSIONS
    {
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
    }
    vkInstance : VK.Instance
    {
        appInfo := VK.ApplicationInfo{
            sType = .APPLICATION_INFO,
            apiVersion = VK.API_VERSION_1_3,
        }
        info := VK.InstanceCreateInfo{
            sType = .INSTANCE_CREATE_INFO,
            flags = {},
            
            pApplicationInfo = &appInfo,
            enabledExtensionCount = extensionCount,
            ppEnabledExtensionNames = &extensionNames[0],
            enabledLayerCount = u32(len(validationLayers)),
            ppEnabledLayerNames = &validationLayers[0],
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
    
    requiredExtensions := [dynamic]cstring{
        VK.KHR_SWAPCHAIN_EXTENSION_NAME,
        VK.KHR_DYNAMIC_RENDERING_EXTENSION_NAME,
            VK.KHR_DEPTH_STENCIL_RESOLVE_EXTENSION_NAME,
                VK.KHR_CREATE_RENDERPASS_2_EXTENSION_NAME,
            VK.EXT_EXTENDED_DYNAMIC_STATE_3_EXTENSION_NAME,
            VK.EXT_SHADER_OBJECT_EXTENSION_NAME,
        VK.NV_FILL_RECTANGLE_EXTENSION_NAME,
    }

    DEVICE_EXTENSIONS_SUPPORT:
    {
        Unit :: struct{}
        required := map[cstring]Unit{}
        for e in requiredExtensions do map_insert(&required, e, Unit{})
        defer delete(required)

        extensionsCount : u32
        try(VK.EnumerateDeviceExtensionProperties(physicalDevice, nil, &extensionsCount, nil))
        extensions := make([]VK.ExtensionProperties, extensionsCount)
        try(VK.EnumerateDeviceExtensionProperties(physicalDevice, nil, &extensionsCount, &extensions[0]))
        //for &e in extensions do fmt.println(cast(cstring)&e.extensionName[0])
    
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

    device : VK.Device
    {
        shaderObjects := VK.PhysicalDeviceShaderObjectFeaturesEXT{
            sType = .PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT,
        }
        features1_3 := VK.PhysicalDeviceVulkan13Features{
            sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
            pNext = &shaderObjects,
        }
        extState3 := VK.PhysicalDeviceExtendedDynamicState3FeaturesEXT{
            sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT,
            pNext = &features1_3,
        }
        deviceFeatures := VK.PhysicalDeviceFeatures2{
            sType = .PHYSICAL_DEVICE_FEATURES_2,
            pNext = &extState3,
        }
        
        VK.GetPhysicalDeviceFeatures2(physicalDevice, &deviceFeatures)

        createInfo := VK.DeviceCreateInfo{
            sType = VK.StructureType.DEVICE_CREATE_INFO,
            pNext = &deviceFeatures,
            queueCreateInfoCount = 1,
            pQueueCreateInfos = &queueInfo,
            enabledExtensionCount = u32(len(requiredExtensions)),
            ppEnabledExtensionNames = raw_data(requiredExtensions),
            pEnabledFeatures = nil,
        }
        try(VK.CreateDevice(physicalDevice, &createInfo, nil, &device))
    }

    graphicsQueue : VK.Queue
    VK.GetDeviceQueue(device, queueIndex, 0, &graphicsQueue)

    swapchain : VKR.SwapchainData
    {
        switch v in VKR.make_swapchain(physicalDevice, device, surface, queueIndex,
                                       {dimensions.x, dimensions.y}, .MAILBOX, .SRGB_NONLINEAR, {.B8G8R8A8_SRGB})
        {
            case VKR.SwapchainData: swapchain = v
            case VKR.MakeSwapchainError: panic(fmt.aprintln("Swapchain error:", v))
        } 
    }

    //CREATE SHADER OBJECTS
    shaders : [2]VK.ShaderEXT
    shaderStages : [len(shaders)]VK.ShaderStageFlags
    {
        v := #load("./Shaders/compiled/shader.vert.spv", []byte)
        vert := try(mem.make_aligned([]byte, len(v), 4))
        copy(vert, v)
        defer delete(vert)
        
        f := #load("./Shaders/compiled/shader.frag.spv", []byte)
        frag := try(mem.make_aligned([]byte, len(f), 4))
        copy(frag, f)
        defer delete(frag)

        createInfos := [len(shaders)]VK.ShaderCreateInfoEXT{
            //VertexShader = 
            {
                sType = .SHADER_CREATE_INFO_EXT,

                flags = {.LINK_STAGE},
                stage = {.VERTEX},
                nextStage = {.FRAGMENT},
                
                codeType = .SPIRV,
                codeSize = len(vert),
                pCode = raw_data(vert),
                pName = "main",
                setLayoutCount = 0,
            },
            //FragmentShader =
            {
                sType = .SHADER_CREATE_INFO_EXT,

                flags = {.LINK_STAGE},
                stage = {.FRAGMENT},
                nextStage = {},

                codeType = .SPIRV,
                codeSize = len(frag),
                pCode = raw_data(frag),
                pName = "main",
                setLayoutCount = 0,
            }
        }
        try(VK.CreateShadersEXT(device, len(createInfos), &createInfos[0], nil, &shaders[0]))
        shaderStages[0] = {.VERTEX}
        shaderStages[1] = {.FRAGMENT}
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
    }
    
    imageAvailable, renderFinished : VK.Semaphore
    {
        createInfo := VK.SemaphoreCreateInfo{
            sType = .SEMAPHORE_CREATE_INFO,
        }
        try(VK.CreateSemaphore(device, &createInfo, nil, &imageAvailable))
        try(VK.CreateSemaphore(device, &createInfo, nil, &renderFinished))
    }
    
    inFlightFence : VK.Fence
    {
        createInfo := VK.FenceCreateInfo{
            sType = .FENCE_CREATE_INFO,
            flags = { .SIGNALED },
        }
        try(VK.CreateFence(device, &createInfo, nil, &inFlightFence))
    }

    renderingInfo := VK.RenderingInfo{
        sType = .RENDERING_INFO_KHR,

        flags = {},
        renderArea = {{0, 0}, {dimensions.x, dimensions.y}},
        layerCount = 1,
        colorAttachmentCount = 1,
        
        pColorAttachments = &VK.RenderingAttachmentInfo{
            sType = .RENDERING_ATTACHMENT_INFO,

            imageView = swapchain.ImageViews[0],
            imageLayout = .ATTACHMENT_OPTIMAL,
            loadOp = .CLEAR,
            storeOp = .STORE,
            clearValue = {color = {float32 = {0, 0, 0, 1}}}
        }
    }

    imageIndex : u32
    {
        try(VK.WaitForFences(device, 1, &inFlightFence, true, max(u64)))
        
        try(VK.AcquireNextImageKHR(device, swapchain.Swapchain, max(u64),
                                   imageAvailable, 0, &imageIndex))
        
        try(VK.ResetFences(device, 1, &inFlightFence))
        try(VK.ResetCommandBuffer(commandBuffer, {}))
    }

    //BEGIN COMMAND BUFFER
    {
        beginInfo := VK.CommandBufferBeginInfo{
            sType = .COMMAND_BUFFER_BEGIN_INFO,
            flags = {},
            pInheritanceInfo = nil,
        }

        try(VK.BeginCommandBuffer(commandBuffer, &beginInfo))
    }
    //PIPELINE BARRIER
    {
        imageBarrier := VK.ImageMemoryBarrier{
            sType = .IMAGE_MEMORY_BARRIER,
            dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
            srcAccessMask = {},
            oldLayout = .UNDEFINED,
            newLayout = .COLOR_ATTACHMENT_OPTIMAL,
            image = swapchain.Images[0],
            subresourceRange = {
                aspectMask = {.COLOR},
                baseMipLevel = 0,
                levelCount = 1,
                baseArrayLayer = 0,
                layerCount = 1,
            }
        }
        VK.CmdPipelineBarrier(commandBuffer,
            {.TOP_OF_PIPE},
            {.COLOR_ATTACHMENT_OUTPUT},
            {},
            {},
            nil,
            {},
            nil,
            1,
            &imageBarrier
        )
    }
    VK.CmdBeginRendering(commandBuffer, &renderingInfo)
    {
        viewport := VK.Viewport{0, 0, f32(dimensions.x), f32(dimensions.y), 0, 1}
        scissor := VK.Rect2D{{0,0}, {dimensions.x, dimensions.y}}
        VK.CmdSetViewportWithCountEXT(commandBuffer, 1, &viewport)
        VK.CmdSetScissorWithCountEXT(commandBuffer, 1, &scissor)

        VK.CmdSetCullModeEXT(commandBuffer, {.BACK})
        VK.CmdSetFrontFaceEXT(commandBuffer, .CLOCKWISE)
        VK.CmdSetDepthTestEnableEXT(commandBuffer, true)
        VK.CmdSetDepthWriteEnableEXT(commandBuffer, true)
        VK.CmdSetDepthCompareOpEXT(commandBuffer, .LESS_OR_EQUAL)
        VK.CmdSetPrimitiveTopologyEXT(commandBuffer, .TRIANGLE_LIST)
        VK.CmdSetRasterizerDiscardEnableEXT(commandBuffer, true)
        VK.CmdSetPolygonModeEXT(commandBuffer, .FILL)
        VK.CmdSetRasterizationSamplesEXT(commandBuffer, {._1})
        VK.CmdSetAlphaToCoverageEnableEXT(commandBuffer, false)
        VK.CmdSetDepthBiasEnableEXT(commandBuffer, false)
        VK.CmdSetStencilTestEnableEXT(commandBuffer, false)
        VK.CmdSetPrimitiveRestartEnableEXT(commandBuffer, false)
        VK.CmdSetPrimitiveRestartEnableEXT(commandBuffer, false)

        mask := VK.SampleMask(0xFF)
        VK.CmdSetSampleMaskEXT(commandBuffer, {._1}, &mask)
        
        blendEnable := b32(false)
        VK.CmdSetColorBlendEnableEXT(commandBuffer, 0, 1, &blendEnable)

        VK.CmdSetColorWriteMaskEXT(commandBuffer, 0, 1, &VK.ColorComponentFlags{.R, .G, .B, .A})
        VK.CmdSetColorBlendEquationEXT(commandBuffer, 0, 1, 
                                       &VK.ColorBlendEquationEXT{
            srcColorBlendFactor = .SRC_ALPHA,
            dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
            colorBlendOp = .ADD,

            srcAlphaBlendFactor = .ONE,
            dstAlphaBlendFactor = .ZERO,
            alphaBlendOp = .ADD,
        })
    }
    VK.CmdBindShadersEXT(commandBuffer, 2, &shaderStages[0], &shaders[0])
    VK.CmdDraw(commandBuffer, 3, 1, 0, 0)
    VK.CmdEndRendering(commandBuffer)


    //DISPLAY
    when false {
        
        try(VK.WaitForFences(device, 1, &inFlightFence, true, max(u64)))
        
        try(VK.AcquireNextImageKHR(device, swapchain.Swapchain, max(u64),
                                   imageAvailable, 0, &imageIndex))
        
        try(VK.ResetFences(device, 1, &inFlightFence))
        try(VK.ResetCommandBuffer(commandBuffer, {}))
        
        {
            submitInfo := VK.SubmitInfo{
                sType = .SUBMIT_INFO,
                waitSemaphoreCount = 1,
                pWaitSemaphores = &imageAvailable,
                pWaitDstStageMask = &VK.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
                commandBufferCount = 1,
                pCommandBuffers = &commandBuffer,
                signalSemaphoreCount = 1,
                pSignalSemaphores = &renderFinished,
            }
            try(VK.QueueSubmit(graphicsQueue, 1, &submitInfo, inFlightFence))
            
            presentInfo := VK.PresentInfoKHR{
                sType = .PRESENT_INFO_KHR,
                waitSemaphoreCount = 1,
                pWaitSemaphores = &renderFinished,
                swapchainCount = 1,
                pSwapchains = &swapchain.Swapchain,
                pImageIndices = &imageIndex,
            }
            try(VK.QueuePresentKHR(graphicsQueue, &presentInfo))
        }
    }
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
    try_alloc_value,
}
try_sdl :: proc(r : c.int loc := #caller_location)
{
    if r == 0 do return

    error := SDL.GetError()
    panic(fmt.aprintf("%s", error), loc)
}
try_alloc_value :: proc(value : $T, error : runtime.Allocator_Error, loc := #caller_location) -> T
{
    if error != .None do panic(fmt.aprintfln("ALLOCATOR ERROR: %v", error), loc)
    return value
}
not_nil :: proc(ptr : $T, loc := #caller_location)// where intrinsics.type_is_pointer(T) || intrinsics.type_is_proc(T)
{
    
    if ptr == nil 
    {
        /*
        s : string
        info := type_info_of(T)
        #partial switch info in info.variant
        {
            case runtime.Type_Info_Named: s = fmt.aprintf("Value was nil | %v.%v",info.pkg, info.name)
            case runtime.runtime.Type_Info_Pointer:
            {
                for info := info; info.elem
            }
            case: s = fmt.aprintf("Value was nil | %v", typeid_of(T))
        }
        */
        panic(fmt.aprintf("Value was nil | %v", typeid_of(T)), loc)
    }
}