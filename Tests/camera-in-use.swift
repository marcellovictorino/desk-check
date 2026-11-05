// Lists every camera that some app on this Mac is using right now, read from CoreMediaIO,
// the same signal that turns on the camera light. Exits 1 when any camera is in use.
// Usage: swift Tests/camera-in-use.swift
import CoreMediaIO
import Foundation

func property<T>(_ object: CMIOObjectID, _ selector: Int, _ value: inout T) -> Bool {
    var address = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(selector),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    let size = UInt32(MemoryLayout<T>.size)
    var used: UInt32 = 0
    return CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &value) == 0
}

var address = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
var size: UInt32 = 0
CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size)
var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
var used: UInt32 = 0
CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices)

var anyRunning = false
for device in devices {
    var name: Unmanaged<CFString>?
    var running: UInt32 = 0
    _ = property(device, kCMIODevicePropertyDeviceIsRunningSomewhere, &running)
    let label = property(device, kCMIOObjectPropertyName, &name) ? (name!.takeRetainedValue() as String) : "camera \(device)"
    print("\(running != 0 ? "IN USE" : "off   ") \(label)")
    if running != 0 { anyRunning = true }
}
exit(anyRunning ? 1 : 0)
