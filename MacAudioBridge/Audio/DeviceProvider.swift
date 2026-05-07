import Foundation

protocol DeviceProvider: AnyObject {
    var connectedInputDevices: [Device] { get }
    var connectedOutputDevices: [Device] { get }
    var defaultInputDevice: Device? { get }
    var defaultOutputDevice: Device? { get }

    /// Device を `ResolvedDevice` に変換するヘルパー。
    func resolvedDevice(for device: Device) -> ResolvedDevice
}

extension DeviceProvider {
    func resolvedDevice(for device: Device) -> ResolvedDevice {
        ResolvedDevice(uid: device.uid, name: device.name, isConnected: true)
    }
}
