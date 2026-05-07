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

    // MARK: - Private

    private func allDevices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
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
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
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
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        var cfString: CFString?
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &cfString)
        guard status == noErr, let cf = cfString else { return nil }
        return cf as String
    }

    private func streamCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr else { return 0 }
        return Int(dataSize) / MemoryLayout<AudioStreamID>.size
    }
}
