import Foundation
import AVFoundation
import CoreAudio

/// 単一の入出力ペアの pass-thru を担うエンジン。
/// engineQueue 上で start / stop / restart を直列実行する前提（並行性モデル §7.6 参照）。
/// 将来マルチブリッジ拡張時はこのクラスを複数インスタンス化する。
final class AudioBridgeEngine {
    private let aggregateManager = AggregateDeviceManager()
    private var engine: AVAudioEngine?
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

        // pass-thru 不変条件 (§8.7):
        // I1: ゲイン 1.0
        // I2: input → mainMixer の 1 本のみ、エフェクト無し
        // I4: format=nil で AVAudioEngine の自動マッチに任せる
        engine.mainMixerNode.outputVolume = 1.0
        engine.connect(engine.inputNode, to: engine.mainMixerNode, format: nil)

        // engine.outputNode は AVAudioEngine が暗黙に mainMixerNode と接続するため明示しない (I3)

        try engine.start()
        self.engine = engine

        // configurationChangeNotification を購読（フル再構築のトリガー、§6.2 #12）
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { _ in
            Log.engine.info("AVAudioEngineConfigurationChange received")
            // ここでは通知を投げるだけ。再構築は AppState 側が engineQueue 上で行う。
            NotificationCenter.default.post(name: .audioBridgeShouldRebuild, object: nil)
        }

        Log.engine.info("engine started input=\(inputUID) output=\(outputUID)")
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

extension Notification.Name {
    static let audioBridgeShouldRebuild = Notification.Name("com.ryugo.mac-audio-bridge.shouldRebuild")
}
