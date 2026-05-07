import Foundation
import AVFoundation
import CoreAudio
import os

/// 単一の入出力ペアの pass-thru を担うエンジン。
/// engineQueue 上で start / stop / restart を直列実行する前提（並行性モデル §7.6 参照）。
/// 将来マルチブリッジ拡張時はこのクラスを複数インスタンス化する。
final class AudioBridgeEngine {
    /// pass-thru tap → AVAudioPlayerNode 中継のキュー深さ警告閾値（バッファ数）。
    /// installTap の bufferSize=4096 / 48 kHz で 1 buffer ≈ 85 ms。
    /// 閾値 8 個 ≈ 680 ms 相当を超えると警告ログを出して backpressure 異常を可視化する。
    private static let pendingBufferWarnThreshold = 8

    private let aggregateManager = AggregateDeviceManager()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var aggregateDeviceID: AudioDeviceID?
    private var configChangeObserver: NSObjectProtocol?
    /// AVAudioPlayerNode に schedule 済みで未再生のバッファ数。
    /// tap callback で +1、scheduleBuffer の completionHandler で -1。
    /// real-time thread からも触られるため atomic 更新。
    private let pendingBuffers = OSAllocatedUnfairLock<Int>(initialState: 0)
    /// 直近の警告ログ時刻。1 秒に 1 回までに間引く。
    private var lastBackpressureWarn = Date.distantPast

    /// 起動。事前に inputUID と outputUID は呼び出し側で解決済みであること。
    /// 同一 UID（feedback loop）の場合は呼び出し側で弾くこと。
    /// AVAudioEngine は毎回新規インスタンスを作る（再利用しない、§8.5）。
    /// 途中で throw した場合、作成済みの AggregateDevice を defer で確実に破棄する
    /// (例外安全)。
    func start(inputUID: String, outputUID: String) throws {
        try stopInternal(destroyAggregate: true)

        let aggID = try aggregateManager.create(inputUID: inputUID, outputUID: outputUID)
        var startCompleted = false
        defer {
            if !startCompleted {
                try? aggregateManager.destroy(aggID)
                self.aggregateDeviceID = nil
                self.engine = nil
                self.player = nil
                if let observer = self.configChangeObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.configChangeObserver = nil
                }
            }
        }
        self.aggregateDeviceID = aggID

        let engine = AVAudioEngine()
        try engine.inputNode.auAudioUnit.setDeviceID(aggID)
        try engine.outputNode.auAudioUnit.setDeviceID(aggID)

        let outputFormat = engine.outputNode.outputFormat(forBus: 0)

        // pass-thru 実装：tap + AVAudioPlayerNode 中継方式
        // tap も player 接続も outputFormat に統一して、
        // AVAudioEngine 内蔵コンバータで input → output format 変換させる。
        // mainMixer をバイパスして player → outputNode 直接接続することで
        // mainMixer のデフォルトサンプルレートとのミスマッチも回避する。
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.outputNode, format: outputFormat)

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: outputFormat) { [weak self, weak player] buffer, _ in
            guard let self, let player else { return }
            // backpressure 観測: schedule 前後で pending count を増減し、
            // 閾値を超えていたら 1 秒に 1 回まで warn ログを出す。
            // 出力 rate < 入力 rate やシステム全体のスタビング時に検知できる。
            let depth = self.pendingBuffers.withLock { state in
                state += 1
                return state
            }
            if depth > Self.pendingBufferWarnThreshold {
                let now = Date()
                if now.timeIntervalSince(self.lastBackpressureWarn) > 1.0 {
                    self.lastBackpressureWarn = now
                    Log.engine.error("tap backpressure: pending buffers=\(depth, privacy: .public) (threshold=\(Self.pendingBufferWarnThreshold, privacy: .public))")
                }
            }
            player.scheduleBuffer(buffer) { [weak self] in
                self?.pendingBuffers.withLock { state in state -= 1 }
            }
        }

        try engine.start()
        player.play()
        self.engine = engine
        self.player = player
        startCompleted = true

        // configurationChangeNotification は AVAudioEngine 起動直後にも通常発火するため、
        // 自動再構築のトリガーにすると無限ループになる。ログのみ出して無視する。
        // 実デバイス変更は DeviceMonitor (kAudioHardwarePropertyDevices) が別途検知するので
        // 検知漏れにならない。
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { _ in
            Log.engine.info("AVAudioEngineConfigurationChange received (ignored)")
        }

        Log.engine.info("engine started input=\(inputUID, privacy: .public) output=\(outputUID, privacy: .public)")
    }

    /// 停止。AggregateDevice も破棄する。
    func stop() {
        try? stopInternal(destroyAggregate: true)
    }

    private func stopInternal(destroyAggregate: Bool) throws {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        if let engine = engine {
            engine.inputNode.removeTap(onBus: 0)
        }
        player?.stop()
        player = nil
        engine?.stop()
        engine = nil
        pendingBuffers.withLock { $0 = 0 }

        if destroyAggregate, let aggID = aggregateDeviceID {
            try? aggregateManager.destroy(aggID)
            aggregateDeviceID = nil
        }
    }

    /// 起動時に呼ぶ：前回の残骸 AggregateDevice を掃除する。
    func cleanupOrphans() {
        aggregateManager.cleanupOrphans()
    }
}

