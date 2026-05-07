import Foundation
import CoreAudio

/// CoreAudio HAL の各種プロパティ変更を監視する。
/// コールバックは任意スレッドで呼ばれるため、常に呼び出し側のキュー（engineQueue や MainActor）にディスパッチする。
final class DeviceMonitor {
    enum Event {
        case defaultInputChanged
        case defaultOutputChanged
        case deviceListChanged
    }

    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private let queue: DispatchQueue
    private let onEvent: (Event) -> Void

    /// - Parameters:
    ///   - dispatchQueue: コールバックをディスパッチするキュー（engineQueue 推奨）
    ///   - onEvent: イベント受信時のコールバック（dispatchQueue 上で呼ばれる）
    init(dispatchQueue: DispatchQueue, onEvent: @escaping (Event) -> Void) {
        self.queue = dispatchQueue
        self.onEvent = onEvent
    }

    func start() {
        addListener(
            selector: kAudioHardwarePropertyDefaultInputDevice,
            event: .defaultInputChanged
        )
        addListener(
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            event: .defaultOutputChanged
        )
        addListener(
            selector: kAudioHardwarePropertyDevices,
            event: .deviceListChanged
        )
        Log.deviceMonitor.info("DeviceMonitor started")
    }

    func stop() {
        for (var address, block) in listeners {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                queue,
                block
            )
        }
        listeners.removeAll()
        Log.deviceMonitor.info("DeviceMonitor stopped")
    }

    deinit {
        stop()
    }

    // MARK: - Private

    private func addListener(selector: AudioObjectPropertySelector, event: Event) {
        var address = AudioObjectPropertyAddress.global(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onEvent(event)
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            block
        )
        if status == noErr {
            listeners.append((address, block))
        } else {
            Log.deviceMonitor.error("listener register failed selector=\(selector) status=\(status)")
        }
    }
}
