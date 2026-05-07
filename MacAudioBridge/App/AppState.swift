import Foundation
import AVFoundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published（UI 用）

    @Published private(set) var status: BridgeStatus = .idle
    @Published private(set) var inputChoice: DeviceChoice = .systemDefault
    @Published private(set) var outputChoice: DeviceChoice = .systemDefault
    @Published private(set) var connectedInputDevices: [Device] = []
    @Published private(set) var connectedOutputDevices: [Device] = []
    @Published private(set) var defaultInputDevice: Device?
    @Published private(set) var defaultOutputDevice: Device?
    @Published var autoRun: Bool = false {
        didSet { applyAutoRunChange() }
    }

    // MARK: - Dependencies

    private let preferences: Preferences
    private let provider: DeviceProvider
    private let engine: AudioBridgeEngine
    private let engineQueue = DispatchQueue(
        label: "com.ryugo.mac-audio-bridge.engine",
        qos: .userInitiated
    )
    private var monitor: DeviceMonitor?
    private var rebuildObserver: NSObjectProtocol?
    private var debounceWorkItem: DispatchWorkItem?
    // engineQueue 上でのみ読み書きする「動作中」フラグ。
    // main.sync で MainActor の status を読みに行くと shutdown とのデッドロックが起きるため、
    // engineQueue 内で完結する別フラグを持つ。
    private var engineRunningOnEngineQ: Bool = false

    // MARK: - Init

    init(
        preferences: Preferences = Preferences(),
        provider: DeviceProvider = CoreAudioDeviceProvider(),
        engine: AudioBridgeEngine = AudioBridgeEngine()
    ) {
        self.preferences = preferences
        self.provider = provider
        self.engine = engine
        self.inputChoice = preferences.inputChoice
        self.outputChoice = preferences.outputChoice
        self.autoRun = preferences.autoRun

        refreshDeviceLists()
    }

    // MARK: - Lifecycle

    func bootstrap() {
        engineQueue.async { [weak self] in
            self?.engine.cleanupOrphans()
        }

        let monitor = DeviceMonitor(dispatchQueue: engineQueue) { [weak self] event in
            self?.handleMonitorEvent(event)
        }
        monitor.start()
        self.monitor = monitor

        rebuildObserver = NotificationCenter.default.addObserver(
            forName: .audioBridgeShouldRebuild,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.engineQueue.async {
                self?.rebuildSync()
            }
        }

        if preferences.autoRun {
            Task { @MainActor in
                self.toggleOn()
            }
        }
    }

    func shutdown() {
        if let observer = rebuildObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        monitor?.stop()
        engineQueue.sync {
            engine.stop()
            engineRunningOnEngineQ = false
        }
    }

    // MARK: - User Actions (called from UI on MainActor)

    func toggleOn() {
        guard status != .running, status != .starting else { return }
        status = .starting
        requestPermissionAndStart()
    }

    private func requestPermissionAndStart() {
        PermissionHelper.requestMicrophoneAccess { [weak self] auth in
            guard let self else { return }
            switch auth {
            case .authorized:
                self.engineQueue.async {
                    self.startSync()
                }
            case .denied, .notDetermined:
                self.status = .stopped(.micPermissionDenied)
            }
        }
    }

    func toggleOff() {
        engineQueue.async { [weak self] in
            self?.engine.stop()
            self?.engineRunningOnEngineQ = false
            Task { @MainActor in
                self?.status = .stopped(.userToggledOff)
            }
        }
    }

    func setInputChoice(_ choice: DeviceChoice) {
        inputChoice = choice
        preferences.inputChoice = choice
        scheduleRebuild()
    }

    func setOutputChoice(_ choice: DeviceChoice) {
        outputChoice = choice
        preferences.outputChoice = choice
        scheduleRebuild()
    }

    // MARK: - Private (engineQueue)

    private func handleMonitorEvent(_ event: DeviceMonitor.Event) {
        // engineQueue 上で呼ばれる
        switch event {
        case .deviceListChanged:
            Task { @MainActor in
                self.refreshDeviceLists()
            }
            // 切断検知 → 動作中なら停止判定（main へ）
            scheduleRebuildOnEngineQueue()
        case .defaultInputChanged, .defaultOutputChanged:
            Task { @MainActor in
                self.refreshDeviceLists()
            }
            scheduleRebuildOnEngineQueue()
        }
    }

    private func scheduleRebuild() {
        engineQueue.async { [weak self] in
            self?.scheduleRebuildOnEngineQueue()
        }
    }

    private func scheduleRebuildOnEngineQueue() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildSync()
        }
        debounceWorkItem = work
        engineQueue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func startSync() {
        // engineQueue 上で実行。permission チェックは toggleOn 経由で MainActor で済んでいる前提。
        let inputResolved = resolve(choice: preferences.inputChoice, defaultDevice: provider.defaultInputDevice, list: provider.connectedInputDevices)
        let outputResolved = resolve(choice: preferences.outputChoice, defaultDevice: provider.defaultOutputDevice, list: provider.connectedOutputDevices)

        guard let inputUID = inputResolved?.uid, let outputUID = outputResolved?.uid else {
            engineRunningOnEngineQ = false
            Task { @MainActor in
                self.status = .stopped(.engineFailed(message: "no system default"))
            }
            return
        }

        if FeedbackLoopDetector.isLoop(inputUID: inputUID, outputUID: outputUID) {
            engineRunningOnEngineQ = false
            Task { @MainActor in
                self.status = .stopped(.feedbackLoop)
            }
            return
        }

        do {
            try engine.start(inputUID: inputUID, outputUID: outputUID)
            engineRunningOnEngineQ = true
            Task { @MainActor in
                self.status = .running
            }
        } catch {
            engineRunningOnEngineQ = false
            Log.engine.error("start failed: \(error.localizedDescription)")
            Task { @MainActor in
                self.status = .stopped(.engineFailed(message: error.localizedDescription))
            }
        }
    }

    private func rebuildSync() {
        // engineQueue 上で実行。動作中のみ再構築（idle のままなら何もしない）。
        // main.sync は使わず、engineQueue ローカルの engineRunningOnEngineQ で判定する。
        guard engineRunningOnEngineQ else { return }
        engine.stop()
        engineRunningOnEngineQ = false
        startSync()
    }

    private func resolve(choice: DeviceChoice, defaultDevice: Device?, list: [Device]) -> ResolvedDevice? {
        let resolvedDefault = defaultDevice.map { provider.resolvedDevice(for: $0) }
        let resolvedList = list.map { provider.resolvedDevice(for: $0) }
        return DeviceSelection.resolve(
            choice: choice,
            systemDefault: resolvedDefault,
            connectedDevices: resolvedList
        )
    }

    private func refreshDeviceLists() {
        connectedInputDevices = provider.connectedInputDevices
        connectedOutputDevices = provider.connectedOutputDevices
        defaultInputDevice = provider.defaultInputDevice
        defaultOutputDevice = provider.defaultOutputDevice
    }

    private func applyAutoRunChange() {
        preferences.autoRun = autoRun
        do {
            if autoRun {
                try LoginItemController.register()
            } else {
                try LoginItemController.unregister()
            }
        } catch {
            Log.app.error("autoRun change failed: \(error.localizedDescription)")
            // ロールバック
            autoRun = preferences.autoRun
        }
    }
}
