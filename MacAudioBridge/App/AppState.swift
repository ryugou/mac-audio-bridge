import Foundation
import AVFoundation
import Combine
import AppKit
import os

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
    /// SMAppService 操作（ログイン項目登録・解除）の最後のエラーメッセージ。
    /// nil ならエラーなし。メニュー UI で表示してユーザーに知らせる。
    @Published private(set) var lastAutoRunError: String?

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
    /// SMAppService の register/unregister を直列化する専用キュー。
    /// バックグラウンドで実行しつつ、トグル連打時に複数の操作が並行起動して
    /// 完了順序が入れ替わるのを防ぐ。
    private let autoRunQueue = DispatchQueue(label: "com.ryugo.mac-audio-bridge.autoRun")
    private var monitor: DeviceMonitor?
    private nonisolated(unsafe) var debounceWorkItem: DispatchWorkItem?

    // autoRun の didSet 再帰を防ぐための内部フラグ (MainActor 上のみで操作)
    private var isInitializingAutoRun = false
    private var isRollingBackAutoRun = false
    // engineQueue 上でのみ読み書きする「動作中」フラグ。
    // main.sync で MainActor の status を読みに行くと shutdown とのデッドロックが起きるため、
    // engineQueue 内で完結する別フラグを持つ。
    private nonisolated(unsafe) var engineRunningOnEngineQ: Bool = false

    // 起動要求を世代管理して、保留中の permission completion や engineQueue 上の
    // startSync を toggleOff によって invalidate できるようにする。
    // toggleOn / toggleOff のたびに inc し、completion / startSync で照合する。
    // MainActor (toggleOn/toggleOff) と engineQueue (startSync/rebuildSync) で
    // 並行アクセスされるため、OSAllocatedUnfairLock で同期する。
    private let startGenerationLock = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    private nonisolated func bumpStartGeneration() -> UInt64 {
        startGenerationLock.withLock { state in
            state &+= 1
            return state
        }
    }

    private nonisolated func currentStartGeneration() -> UInt64 {
        startGenerationLock.withLock { $0 }
    }

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
        let gen = bumpStartGeneration()
        PermissionHelper.requestMicrophoneAccess { [weak self] auth in
            // PermissionHelper.requestMicrophoneAccess は .authorized / .denied のみ返す
            // 仕様 (.notDetermined は内部で requestAccess を発行して結果に解決される)。
            guard let self, self.currentStartGeneration() == gen else { return }
            switch auth {
            case .authorized:
                self.engineQueue.async {
                    self.startSync(generation: gen)
                }
            case .denied, .notDetermined:
                // .notDetermined は到達しないが defensive に denied 同様に扱う。
                self.status = .stopped(.micPermissionDenied)
            }
        }
    }

    func toggleOff() {
        _ = bumpStartGeneration()
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
        // snapshot は engineQueue 上 (handleMonitorEvent の呼び出し元) で取得し、
        // @Published の差分反映だけを MainActor に逃がす。MainActor 上で
        // HAL 列挙を同期実行しないことでメニューバー UI の詰まりを防ぐ。
        let snap = provider.snapshot()
        Task { @MainActor in self.applySnapshot(snap) }
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
            engine.stop()
            engineRunningOnEngineQ = false
            // startSync と同じ unresolvedReason ロジックを使い、起動時と動作中で
            // 診断粒度を揃える。.systemDefault 由来は "system_default" を UI に
            // 露出させず engineFailed("no system default") に落とす。
            setStatus(.stopped(unresolvedReason(input: input, output: output)))
        }
    }

    nonisolated private func setStatus(_ newStatus: BridgeStatus) {
        Task { @MainActor in self.status = newStatus }
    }

    nonisolated private func resolveCurrentSelection() -> (input: ResolvedDevice?, output: ResolvedDevice?) {
        // 1 回の snapshot で入出力を解決し、HAL の二重列挙を避ける。
        let snap = provider.snapshot()
        return (
            resolve(choice: preferences.inputChoice, defaultDevice: snap.defaultInputDevice, list: snap.connectedInputDevices),
            resolve(choice: preferences.outputChoice, defaultDevice: snap.defaultOutputDevice, list: snap.connectedOutputDevices)
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

    nonisolated private func startSync(generation: UInt64) {
        // permission チェックは toggleOn 経由で MainActor で済んでいる前提。
        // generation がズレていれば toggleOff 等で起動要求が無効化されたので何もしない。
        guard generation == currentStartGeneration() else { return }
        let (input, output) = resolveCurrentSelection()
        guard let inputUID = input?.uid, let outputUID = output?.uid else {
            // 解決失敗の理由を入力 / 出力の choice から特定する:
            // - .specific(uid) なら「選択デバイスが見つからない」(deviceDisconnected)
            // - .systemDefault なら「システムデフォルト未取得」(engineFailed)
            failStart(unresolvedReason(input: input, output: output))
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

    nonisolated private func unresolvedReason(input: ResolvedDevice?, output: ResolvedDevice?) -> StopReason {
        if input == nil, case .specific(let uid) = preferences.inputChoice {
            return .deviceDisconnected(uid: uid)
        }
        if output == nil, case .specific(let uid) = preferences.outputChoice {
            return .deviceDisconnected(uid: uid)
        }
        return .engineFailed(message: "no system default")
    }

    nonisolated private func rebuildSync() {
        // engineQueue 上で実行。動作中のみ再構築（idle のままなら何もしない）。
        // main.sync は使わず、engineQueue ローカルの engineRunningOnEngineQ で判定する。
        guard engineRunningOnEngineQ else { return }
        engine.stop()
        engineRunningOnEngineQ = false
        // 同じ generation のまま startSync を呼ぶ。startSync 中に toggleOff で
        // generation が進めば、startSync 冒頭の guard で abort する。
        startSync(generation: currentStartGeneration())
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
        // init 経由で MainActor 上で 1 度だけ呼ばれる。HAL 列挙は走るがブロッキング
        // 影響は限定的。デバイスイベント由来の更新は handleMonitorEvent から
        // engineQueue で snapshot を取り applySnapshot に流す。
        applySnapshot(provider.snapshot())
    }

    private func applySnapshot(_ snap: DeviceSnapshot) {
        // 変化があったプロパティだけ書き換えて、SwiftUI の不要な再描画を抑える。
        if snap.connectedInputDevices != connectedInputDevices { connectedInputDevices = snap.connectedInputDevices }
        if snap.connectedOutputDevices != connectedOutputDevices { connectedOutputDevices = snap.connectedOutputDevices }
        if snap.defaultInputDevice != defaultInputDevice { defaultInputDevice = snap.defaultInputDevice }
        if snap.defaultOutputDevice != defaultOutputDevice { defaultOutputDevice = snap.defaultOutputDevice }
    }

    private func applyAutoRunChange() {
        // SMAppService の register / unregister は ServiceManagement 経由で
        // 失敗時に数秒オーダーで遅延しうる。MainActor で同期実行するとメニューバー
        // UI がブロックされるため、autoRunQueue (serial) に送り、結果だけ MainActor
        // に戻す。serial 化することでトグル連打時の完了順入れ替わりも防ぐ。
        //
        // rollback 先は autoRunQueue 上で SMAppService の実状態 (isRegistered) を
        // 読んで決める。didSet 時点で `preferences.autoRun` をキャプチャすると、
        // 直前の操作が完了前で preferences が古いままのときに不正な rollback 先に
        // なる (例: 連打で register 成功直後に unregister 失敗、rollback 先が
        // 既に register 後の実状態と矛盾する false に戻ってしまう)。
        let target = autoRun
        autoRunQueue.async { [weak self] in
            guard let self else { return }
            let actualPrevious = LoginItemController.isRegistered
            let result: Result<Void, Error>
            do {
                if target {
                    try LoginItemController.register()
                } else {
                    try LoginItemController.unregister()
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }
            Task { @MainActor in
                switch result {
                case .success:
                    self.preferences.autoRun = target
                    self.lastAutoRunError = nil
                case .failure(let error):
                    Log.app.error("autoRun change failed: \(error.localizedDescription)")
                    self.lastAutoRunError = error.localizedDescription
                    self.preferences.autoRun = actualPrevious
                    self.isRollingBackAutoRun = true
                    self.autoRun = actualPrevious
                    self.isRollingBackAutoRun = false
                }
            }
        }
    }
}
