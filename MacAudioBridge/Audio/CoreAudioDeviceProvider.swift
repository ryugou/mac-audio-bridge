import Foundation
import CoreAudio

final class CoreAudioDeviceProvider: DeviceProvider {
    var connectedInputDevices: [Device] {
        allDevices().filter { $0.hasInput }
    }

    var connectedOutputDevices: [Device] {
        allDevices().filter { $0.hasOutput }
    }

    var defaultInputDevice: Device? {
        guard let id = defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice) else { return nil }
        return makeDevice(id: id)
    }

    var defaultOutputDevice: Device? {
        guard let id = defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice) else { return nil }
        return makeDevice(id: id)
    }

    /// 1 回の `allDevices()` で入出力リストを取得し、加えてデフォルトデバイス 2 件を
    /// 解決する。`connectedInputDevices` / `connectedOutputDevices` を別個に呼ぶと
    /// HAL 列挙が二重に走るため、両方欲しい呼び出し側はこちらを使う。
    func snapshot() -> DeviceSnapshot {
        let all = allDevices()
        return DeviceSnapshot(
            connectedInputDevices: all.filter { $0.hasInput },
            connectedOutputDevices: all.filter { $0.hasOutput },
            defaultInputDevice: defaultInputDevice,
            defaultOutputDevice: defaultOutputDevice
        )
    }

    // MARK: - Internal

    /// 接続中の全デバイスを 1 度の HAL enumeration で返す。
    /// `connectedInputDevices` / `connectedOutputDevices` を個別に呼ぶより HAL 呼び出しが半分になるため、
    /// 列挙したい呼び出し側はこちらを使う。
    func allDevices() -> [Device] {
        var address = AudioObjectPropertyAddress.global(kAudioHardwarePropertyDevices)
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        )
        guard status == noErr else {
            Log.deviceMonitor.error("kAudioHardwarePropertyDevices size failed: \(status)")
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids
        )
        guard status == noErr else {
            Log.deviceMonitor.error("kAudioHardwarePropertyDevices data failed: \(status)")
            return []
        }
        return ids.compactMap(makeDevice(id:))
    }

    private func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress.global(selector)
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private func makeDevice(id: AudioDeviceID) -> Device? {
        guard let uid = stringProperty(deviceID: id, selector: kAudioDevicePropertyDeviceUID),
              let name = stringProperty(deviceID: id, selector: kAudioDevicePropertyDeviceNameCFString) else {
            return nil
        }
        let hasInput = streamCount(deviceID: id, scope: kAudioDevicePropertyScopeInput) > 0
        let hasOutput = streamCount(deviceID: id, scope: kAudioDevicePropertyScopeOutput) > 0
        return Device(id: id, uid: uid, name: name, hasInput: hasInput, hasOutput: hasOutput)
    }

    private func stringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress.global(selector)
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var unmanaged: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &unmanaged)
        guard status == noErr, let cf = unmanaged?.takeRetainedValue() else { return nil }
        return cf as String
    }

    private func streamCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress.scoped(kAudioDevicePropertyStreams, scope: scope)
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr else { return 0 }
        return Int(dataSize) / MemoryLayout<AudioStreamID>.size
    }
}
