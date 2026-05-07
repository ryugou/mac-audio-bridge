import Foundation

/// 一度の HAL 列挙で取得できる device 情報のスナップショット。
/// 個別 property を順に呼ぶと `connected*Devices` だけでも全 device 列挙が
/// 2 回走ってしまうので、呼び出し側が両方欲しいときは `snapshot()` を使う。
struct DeviceSnapshot {
    let connectedInputDevices: [Device]
    let connectedOutputDevices: [Device]
    let defaultInputDevice: Device?
    let defaultOutputDevice: Device?
}

protocol DeviceProvider: AnyObject {
    var connectedInputDevices: [Device] { get }
    var connectedOutputDevices: [Device] { get }
    var defaultInputDevice: Device? { get }
    var defaultOutputDevice: Device? { get }

    /// 入出力リストとデフォルトデバイスを 1 回の HAL 列挙で取得する。
    /// 既定実装は個別プロパティを順に呼ぶ（重複列挙）ので、CoreAudio 実装側で
    /// 効率化のために override する。
    func snapshot() -> DeviceSnapshot

    /// Device を `ResolvedDevice` に変換するヘルパー。
    func resolvedDevice(for device: Device) -> ResolvedDevice
}

extension DeviceProvider {
    func snapshot() -> DeviceSnapshot {
        DeviceSnapshot(
            connectedInputDevices: connectedInputDevices,
            connectedOutputDevices: connectedOutputDevices,
            defaultInputDevice: defaultInputDevice,
            defaultOutputDevice: defaultOutputDevice
        )
    }

    func resolvedDevice(for device: Device) -> ResolvedDevice {
        ResolvedDevice(uid: device.uid, name: device.name, isConnected: true)
    }
}
