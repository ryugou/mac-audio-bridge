import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
// AUAudioUnitV2Bridge とその `audioUnit` (legacy v2 AudioUnit) プロパティを利用するため
// 実装側ヘッダを取り込む。AVAudioEngine の inputNode / outputNode の auAudioUnit は
// macOS 上では AUHAL を v3 ブリッジしたインスタンス (AUAudioUnitV2Bridge) になる。
import AudioToolbox.AUAudioUnitImplementation

extension AUAudioUnit {
    enum DeviceError: Error, LocalizedError {
        case osStatus(OSStatus)
        case notV2Bridge

        var errorDescription: String? {
            switch self {
            case .osStatus(let s):
                return "AUAudioUnit kAudioOutputUnitProperty_CurrentDevice 設定失敗 (\(s))"
            case .notV2Bridge:
                return "AUAudioUnit が AUAudioUnitV2Bridge ではないため AudioDeviceID をバインドできません"
            }
        }
    }

    /// AUAudioUnit に CoreAudio の AudioDeviceID をバインドする。
    /// AVAudioEngine の inputNode / outputNode の auAudioUnit に対して使う。
    func setDeviceID(_ deviceID: AudioDeviceID) throws {
        guard let bridge = self as? AUAudioUnitV2Bridge else {
            throw DeviceError.notV2Bridge
        }
        var mutable = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitSetProperty(
            bridge.audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutable,
            size
        )
        guard status == noErr else {
            throw DeviceError.osStatus(status)
        }
    }
}
