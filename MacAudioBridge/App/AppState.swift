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
        didSet {
            // 再帰防止: init 中の代入や rollback の再代入で didSet が再発火するのを抑止する。
            guard !isInitializingAutoRun, !isRollingBackAutoRun else { return }
            applyAutoRunChange()
        }
    }

    // MARK: - Dependencies
    //
    // engineQueue 経由で参照する依存・ステートは nonisolated(unsafe) で MainActor 隔離から外す。
    // engineQueue は serial DispatchQueue なので、その上で操作する限り race-free。
    // Swift の strict concurrency check では静的に判別できないため、unsafe を明示する。
    private nonisolated(unsafe) let preferences: Preferences
    private nonisolated(unsafe) let provider: DeviceProvider
    private nonisolated(unsafe) let engine: AudioBridgeEngine
    private let engineQueue = DispatchQueue(
        label: "com.ryugo.mac-audio-bridge.engine",
        qos: .userInitiated
    )
    private var monitor: DeviceMonitor?
    private nonisolated(unsafe) var debounceWorkItem: DispatchWorkItem?

    // autoRun の didSet 再帰を防ぐための内部フラグ (MainActor 上のみで操作)
    private var isInitializingAutoRun = false
    private var isRollingBackAutoRun = false
    // engineQueue 上でのみ読み書きする「動作中」フラグ。
    // main.sync で MainActor の status を読みに行くと shutdown とのデッドロックが起きるため、
    // engineQueue 内で完結する別フラグを持つ。
    private nonisolated(unsafe) var engineRunningOnEngineQ: Bool = false

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

        // init 中は SMAppService を呼ばない (テスト環境でも安全)
        isInitializingAutoRun = true
        self.autoRun = preferences.autoRun
        isInitializingAutoRun = false

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

        if preferences.autoRun {
            toggleOn()
        }
    }

    func shutdown() {
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
            guard let self else { return }
            self.engine.stop()
            self.engineRunningOnEngineQ = false
            self.setStatus(.stopped(.userToggledOff))
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

    nonisolated private func handleMonitorEvent(_ event: DeviceMonitor.Event) {
        Task { @MainActor in self.refreshDeviceLists() }
        switch event {
        case .deviceListChanged:
            // 自分の AggregateDevice の create/destroy でも発火するため、
            // 無条件に再構築すると自己ループになる。選択中のデバイスが消えた時のみ stop。
            checkSelectedDeviceStillConnected()
        case .defaultInputChanged:
            rebuildIfFollowingDefault(preferences.inputChoice)
        case .defaultOutputChanged:
            rebuildIfFollowingDefault(preferences.outputChoice)
        }
    }

    nonisolated private func rebuildIfFollowingDefault(_ choice: DeviceChoice) {
        if choice == .systemDefault, engineRunningOnEngineQ {
            scheduleRebuildOnEngineQueue()
        }
    }

    nonisolated private func checkSelectedDeviceStillConnected() {
        guard engineRunningOnEngineQ else { return }
        let (input, output) = resolveCurrentSelection()
        if input == nil || output == nil {
            let lostUID = input == nil
                ? preferences.inputChoice.storageString
                : preferences.outputChoice.storageString
            engine.stop()
            engineRunningOnEngineQ = false
            setStatus(.stopped(.deviceDisconnected(uid: lostUID)))
        }
    }

    nonisolated private func setStatus(_ newStatus: BridgeStatus) {
        Task { @MainActor in self.status = newStatus }
    }

    nonisolated private func resolveCurrentSelection() -> (input: ResolvedDevice?, output: ResolvedDevice?) {
        (
            resolve(choice: preferences.inputChoice, defaultDevice: provider.defaultInputDevice, list: provider.connectedInputDevices),
            resolve(choice: preferences.outputChoice, defaultDevice: provider.defaultOutputDevice, list: provider.connectedOutputDevices)
        )
    }

    private func scheduleRebuild() {
        engineQueue.async { [weak self] in
            self?.scheduleRebuildOnEngineQueue()
        }
    }

    nonisolated private func scheduleRebuildOnEngineQueue() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildSync()
        }
        debounceWorkItem = work
        engineQueue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    nonisolated private func startSync() {
        // permission チェックは toggleOn 経由で MainActor で済んでいる前提。
        let (input, output) = resolveCurrentSelection()
        guard let inputUID = input?.uid, let outputUID = output?.uid else {
            failStart(.engineFailed(message: "no system default"))
            return
        }
        if FeedbackLoopDetector.isLoop(inputUID: inputUID, outputUID: outputUID) {
            failStart(.feedbackLoop)
            return
        }
        do {
            try engine.start(inputUID: inputUID, outputUID: outputUID)
            engineRunningOnEngineQ = true
            setStatus(.running)
        } catch {
            Log.engine.error("start failed: \(error.localizedDescription)")
            failStart(.engineFailed(message: error.localizedDescription))
        }
    }

    nonisolated private func failStart(_ reason: StopReason) {
        engineRunningOnEngineQ = false
        setStatus(.stopped(reason))
    }

    nonisolated private func rebuildSync() {
        // engineQueue 上で実行。動作中のみ再構築（idle のままなら何もしない）。
        // main.sync は使わず、engineQueue ローカルの engineRunningOnEngineQ で判定する。
        guard engineRunningOnEngineQ else { return }
        engine.stop()
        engineRunningOnEngineQ = false
        startSync()
    }

    nonisolated private func resolve(choice: DeviceChoice, defaultDevice: Device?, list: [Device]) -> ResolvedDevice? {
        let resolvedDefault = defaultDevice.map { provider.resolvedDevice(for: $0) }
        let resolvedList = list.map { provider.resolvedDevice(for: $0) }
        return DeviceSelection.resolve(
            choice: choice,
            systemDefault: resolvedDefault,
            connectedDevices: resolvedList
        )
    }

    private func refreshDeviceLists() {
        // 変化があったプロパティだけ書き換えて、SwiftUI の不要な再描画を抑える。
        let newInputs = provider.connectedInputDevices
        if newInputs != connectedInputDevices { connectedInputDevices = newInputs }
        let newOutputs = provider.connectedOutputDevices
        if newOutputs != connectedOutputDevices { connectedOutputDevices = newOutputs }
        let newDefaultIn = provider.defaultInputDevice
        if newDefaultIn != defaultInputDevice { defaultInputDevice = newDefaultIn }
        let newDefaultOut = provider.defaultOutputDevice
        if newDefaultOut != defaultOutputDevice { defaultOutputDevice = newDefaultOut }
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
            // ロールバック (didSet の再発火を抑止する)
            isRollingBackAutoRun = true
            autoRun = preferences.autoRun
            isRollingBackAutoRun = false
        }
    }
}
