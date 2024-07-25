package VKR

import VK "vendor:vulkan"
import "core:fmt"

find_queue_familiesoo :: proc(device : VK.PhysicalDevice) -> Maybe(u32)
{
    indices : Maybe(u32)

    queueFamilyCount : u32
    VK.GetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nil)
    queueFamilies := make([]VK.QueueFamilyProperties, queueFamilyCount)
    defer delete(queueFamilies)
    VK.GetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, &queueFamilies[0])


    for family, i in queueFamilies
    {
        i := u32(i)
        if family.queueFlags >= {.GRAPHICS, .TRANSFER}
        {
            indices = i
        }
    }

    return {}
}