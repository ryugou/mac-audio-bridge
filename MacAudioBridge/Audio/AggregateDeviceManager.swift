import Foundation
import CoreAudio

enum AggregateDeviceError: Error, LocalizedError {
    case createFailed(OSStatus)
    case destroyFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .createFailed(let s): return "AggregateDevice 作成失敗 (\(s))"
        case .destroyFailed(let s): return "AggregateDevice 破棄失敗 (\(s))"
        }
    }
}

final class AggregateDeviceManager {
    static let uidPrefix = "com.ryugo.mac-audio-bridge.aggregate."

    /// 入力 UID と出力 UID から動的に Private AggregateDevice を作成し AudioDeviceID を返す。
    /// MainSubDevice は出力（マスタークロック）。入力にはドリフト補正キーを設定。
    func create(inputUID: String, outputUID: String) throws -> AudioDeviceID {
        let aggregateUID = Self.uidPrefix + UUID().uuidString
        let inputDict: [String: Any] = [
            kAudioSubDeviceUIDKey as String: inputUID,
            kAudioSubDeviceDriftCompensationKey as String: 1
        ]
        let outputDict: [String: Any] = [
            kAudioSubDeviceUIDKey as String: outputUID
        ]
        let dict: [String: Any] = [
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceNameKey as String: "MacAudioBridge",
            kAudioAggregateDeviceIsPrivateKey as String: 1,
            kAudioAggregateDeviceMainSubDeviceKey as String: outputUID,
            kAudioAggregateDeviceSubDeviceListKey as String: [inputDict, outputDict]
        ]

        var deviceID = AudioDeviceID(0)
        let status = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &deviceID)
        guard status == noErr else {
            Log.aggregate.error("create failed: \(status)")
            throw AggregateDeviceError.createFailed(status)
        }
        Log.aggregate.info("created \(aggregateUID) id=\(deviceID)")
        return deviceID
    }

    /// AggregateDevice を破棄する。
    func destroy(_ deviceID: AudioDeviceID) throws {
        let status = AudioHardwareDestroyAggregateDevice(deviceID)
        guard status == noErr else {
            Log.aggregate.error("destroy failed id=\(deviceID) status=\(status)")
            throw AggregateDeviceError.destroyFailed(status)
        }
        Log.aggregate.info("destroyed id=\(deviceID)")
    }

    /// 起動時に呼ぶ。前回の残骸 AggregateDevice をプレフィックス一致で全削除。
    /// 多重起動は §5.1 で防いでいるため、自プロセスのアクティブ Aggregate を消す心配はない。
    func cleanupOrphans() {
        let provider = CoreAudioDeviceProvider()
        for device in provider.connectedInputDevices + provider.connectedOutputDevices {
            if device.uid.hasPrefix(Self.uidPrefix) {
                let status = AudioHardwareDestroyAggregateDevice(device.id)
                if status == noErr {
                    Log.aggregate.info("cleaned orphan \(device.uid)")
                } else {
                    Log.aggregate.error("orphan cleanup failed \(device.uid) status=\(status)")
                }
            }
        }
    }
}
