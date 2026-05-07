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
    private var tapCallbackCount: Int = 0
    private var lastTapLogTime: Date = .distantPast

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

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let mixerInFormat = engine.mainMixerNode.inputFormat(forBus: 0)
        let mixerOutFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        Log.engine.info("inputNode outputFormat: sr=\(inputFormat.sampleRate, privacy: .public) ch=\(inputFormat.channelCount, privacy: .public) interleaved=\(inputFormat.isInterleaved, privacy: .public) standard=\(inputFormat.isStandard, privacy: .public) commonFmt=\(inputFormat.commonFormat.rawValue, privacy: .public)")
        Log.engine.info("outputNode outputFormat: sr=\(outputFormat.sampleRate, privacy: .public) ch=\(outputFormat.channelCount, privacy: .public) interleaved=\(outputFormat.isInterleaved, privacy: .public) standard=\(outputFormat.isStandard, privacy: .public) commonFmt=\(outputFormat.commonFormat.rawValue, privacy: .public)")
        Log.engine.info("mainMixer inputFormat[0]: sr=\(mixerInFormat.sampleRate, privacy: .public) ch=\(mixerInFormat.channelCount, privacy: .public)")
        Log.engine.info("mainMixer outputFormat[0]: sr=\(mixerOutFormat.sampleRate, privacy: .public) ch=\(mixerOutFormat.channelCount, privacy: .public)")

        // pass-thru 実装：tap + AVAudioPlayerNode 中継方式
        // tap も player 接続も outputFormat (48kHz 2ch) に統一して、
        // AVAudioEngine 内蔵のコンバータで input format → output format 変換させる。
        // mainMixer をバイパスして player → outputNode 直接接続することで、
        // mainMixer のデフォルト 44.1kHz とのミスマッチも回避する。
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.outputNode, format: outputFormat)

        Log.engine.info("attached nodes count=\(engine.attachedNodes.count, privacy: .public)")
        Log.engine.info("player connected to outputNode with format sr=\(outputFormat.sampleRate, privacy: .public) ch=\(outputFormat.channelCount, privacy: .public)")

        tapCallbackCount = 0
        lastTapLogTime = .distantPast
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: outputFormat) { [weak self, weak player] buffer, _ in
            guard let self else { return }
            self.tapCallbackCount += 1
            let count = self.tapCallbackCount
            let now = Date()
            // 最初の 3 回 + 1 秒に 1 回ログ
            if count <= 3 || now.timeIntervalSince(self.lastTapLogTime) > 1.0 {
                self.lastTapLogTime = now
                let frames = buffer.frameLength
                var peak: Float = 0
                if let ch0 = buffer.floatChannelData?[0] {
                    for i in 0..<Int(frames) {
                        let v = abs(ch0[i])
                        if v > peak { peak = v }
                    }
                }
                Log.engine.info("tap #\(count, privacy: .public) frames=\(frames, privacy: .public) ch=\(buffer.format.channelCount, privacy: .public) peak=\(peak, privacy: .public)")
            }
            player?.scheduleBuffer(buffer, completionHandler: nil)
        }

        do {
            try engine.start()
        } catch {
            Log.engine.error("engine.start() threw: \(error.localizedDescription, privacy: .public) | \(String(describing: error), privacy: .public)")
            throw error
        }
        player.play()
        self.engine = engine
        self.player = player
        Log.engine.info("engine.isRunning=\(engine.isRunning, privacy: .public) player.isPlaying=\(player.isPlaying, privacy: .public)")

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

extension Notification.Name {
    static let audioBridgeShouldRebuild = Notification.Name("com.ryugo.mac-audio-bridge.shouldRebuild")
}
