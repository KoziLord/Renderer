package VKR

import VK "vendor:vulkan"
import "core:fmt"

@private Unit :: struct{}
try :: proc(r : VK.Result, loc := #caller_location)
{
    if r != .SUCCESS do panic(fmt.aprintfln("VULKAN ERROR: %v", r), loc)
}
SwapchainData :: struct
{
    Swapchain : VK.SwapchainKHR,
    Format : VK.Format,
    Extent : VK.Extent2D,
    Images : []VK.Image,
    ImageViews : []VK.ImageView,
}
MakeSwapchainError :: enum
{
    NoError,
    RequestedNoFormat,
    NilPhysicalDevice,
    NilDevice,
    //SomeSurfaceError?
    SwapchainExtensionUnavailable,
    NoFormatAvailable,
    SwapchainCreationFailure,
    Unimplemented,
}
//Creates a swapchain
//
//formats: A list of formats to try, ordered by preference.
//First compatible format will be used over any other.
//
//**Requires VK_KHR_swapchain to be enabled**, .
make_swapchain :: proc(device : VK.PhysicalDevice,
                       driver : VK.Device,
                       surface : VK.SurfaceKHR,
                       queueIndex : u32,
                       dimensions : [2]u32,
                       presentMode : VK.PresentModeKHR,
                       colorSpace : VK.ColorSpaceKHR,
                       formats : []VK.Format) ->
                       union {MakeSwapchainError, SwapchainData}
{
    if formats == nil do return MakeSwapchainError.RequestedNoFormat 
    if device  == nil do return MakeSwapchainError.NilPhysicalDevice 
    if driver  == nil do return MakeSwapchainError.NilDevice
    bestFormat : VK.SurfaceFormatKHR
    capabilities : VK.SurfaceCapabilitiesKHR 
    
    CheckFormats:
    {
        VK.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &capabilities)
        
        formatCount : u32
        try(VK.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, nil))
        availableFormats := make([]VK.SurfaceFormatKHR, formatCount)
        defer delete(availableFormats)
        try(VK.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, &availableFormats[0]))
        //fmt.println(availableFormats)
        EXIT: for format in formats
        {
            for v in availableFormats
            {
                if v.format == format && v.colorSpace == colorSpace
                {
                    bestFormat = v
                    break EXIT
                }
            } 
        }
        if bestFormat == {} do return MakeSwapchainError.NoFormatAvailable
    }
    chosenPresentMode : VK.PresentModeKHR
    ChoosePresentMode:
    {
        //Super smart function
        chosenPresentMode = .MAILBOX
    }

    SwapExtent:
    {
        
    }
    createInfo : VK.SwapchainCreateInfoKHR
    createInfo.sType = .SWAPCHAIN_CREATE_INFO_KHR
    createInfo.surface = surface
    createInfo.minImageCount = 3
    createInfo.imageFormat = bestFormat.format
    createInfo.imageColorSpace = bestFormat.colorSpace
    createInfo.imageExtent = transmute(VK.Extent2D)dimensions
    createInfo.imageArrayLayers = 1
    createInfo.imageUsage = {.COLOR_ATTACHMENT}
    createInfo.imageSharingMode = .EXCLUSIVE
    createInfo.queueFamilyIndexCount = 0
    createInfo.pQueueFamilyIndices = nil
    createInfo.preTransform = capabilities.currentTransform
    createInfo.compositeAlpha = {.OPAQUE}
    createInfo.presentMode = presentMode
    createInfo.clipped = true
    createInfo.oldSwapchain = {}

    swapchain : VK.SwapchainKHR
    if VK.CreateSwapchainKHR(driver, &createInfo, nil, &swapchain) != .SUCCESS
    {
        return MakeSwapchainError.SwapchainCreationFailure
    }
    images : []VK.Image

    
    imageCount : u32
    try(VK.GetSwapchainImagesKHR(driver, swapchain, &imageCount, nil))
    images = make([]VK.Image, imageCount)
    try(VK.GetSwapchainImagesKHR(driver, swapchain, &imageCount, &images[0]))

    imageViews := make([]VK.ImageView, imageCount)

    for &view, i in imageViews
    {
        createInfo : VK.ImageViewCreateInfo
        createInfo.sType = .IMAGE_VIEW_CREATE_INFO
        createInfo.image = images[i]
        createInfo.viewType = .D2
        createInfo.format = bestFormat.format
        createInfo.components.r = .IDENTITY
        createInfo.components.g = .IDENTITY
        createInfo.components.b = .IDENTITY
        createInfo.components.a = .IDENTITY

        sub := &createInfo.subresourceRange
        sub.aspectMask = {.COLOR}
        sub.baseMipLevel = 0
        sub.levelCount = 1
        sub.baseArrayLayer = 0
        sub.layerCount = 1

        try(VK.CreateImageView(driver, &createInfo, nil, &view))
    }

    return SwapchainData{
        swapchain,
        bestFormat.format,
        transmute(VK.Extent2D)dimensions,
        images,
        imageViews,
    }
}