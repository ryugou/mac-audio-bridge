import Foundation
import AVFoundation
import CoreAudio

/// 単一の入出力ペアの pass-thru を担うエンジン。
/// engineQueue 上で start / stop / restart を直列実行する前提（並行性モデル §7.6 参照）。
/// 将来マルチブリッジ拡張時はこのクラスを複数インスタンス化する。
final class AudioBridgeEngine {
    private let aggregateManager = AggregateDeviceManager()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var aggregateDeviceID: AudioDeviceID?
    private var configChangeObserver: NSObjectProtocol?

    /// 起動。事前に inputUID と outputUID は呼び出し側で解決済みであること。
    /// 同一 UID（feedback loop）の場合は呼び出し側で弾くこと。
    /// AVAudioEngine は毎回新規インスタンスを作る（再利用しない、§8.5）。
    func start(inputUID: String, outputUID: String) throws {
        try stopInternal(destroyAggregate: true)

        let aggID = try aggregateManager.create(inputUID: inputUID, outputUID: outputUID)
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

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: outputFormat) { [weak player] buffer, _ in
            player?.scheduleBuffer(buffer, completionHandler: nil)
        }

        try engine.start()
        player.play()
        self.engine = engine
        self.player = player

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

