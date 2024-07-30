package VKR

import VK "vendor:vulkan"

State :: struct
{
    PhysicalDevice : VK.PhysicalDevice,
    Device : VK.Device,

    Swapchains : []SwapchainData,
    Pipelines : []VK.Pipeline,
}