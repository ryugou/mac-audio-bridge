import Testing
import Foundation
@testable import MacAudioBridge

struct PreferencesTests {
    /// テスト用の独立 UserDefaults を返す。
    private func makeStore() -> (UserDefaults, String) {
        let suite = "com.ryugo.mac-audio-bridge.tests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        return (ud, suite)
    }

    @Test func defaultsAreSystemDefaultAndAutoRunFalse() {
        let (ud, _) = makeStore()
        let prefs = Preferences(store: ud)
        #expect(prefs.inputChoice == .systemDefault)
        #expect(prefs.outputChoice == .systemDefault)
        #expect(prefs.autoRun == false)
    }

    @Test func savesAndLoadsSpecificDevice() {
        let (ud, _) = makeStore()
        let prefs = Preferences(store: ud)
        prefs.inputChoice = .specific(uid: "mic-1")
        prefs.outputChoice = .specific(uid: "spk-1")
        prefs.autoRun = true

        // 別インスタンスで読み込み確認
        let prefs2 = Preferences(store: ud)
        #expect(prefs2.inputChoice == .specific(uid: "mic-1"))
        #expect(prefs2.outputChoice == .specific(uid: "spk-1"))
        #expect(prefs2.autoRun == true)
    }

    @Test func ignoresUnknownKeys() {
        let (ud, _) = makeStore()
        ud.set("unexpected", forKey: "some.unrelated.key")
        let prefs = Preferences(store: ud)
        #expect(prefs.inputChoice == .systemDefault)
    }

    @Test func systemDefaultStorageString() {
        let (ud, _) = makeStore()
        let prefs = Preferences(store: ud)
        prefs.inputChoice = .systemDefault
        #expect(ud.string(forKey: "device.input") == "system_default")
    }

    @Test func specificUIDStorageString() {
        let (ud, _) = makeStore()
        let prefs = Preferences(store: ud)
        prefs.inputChoice = .specific(uid: "mic-1")
        #expect(ud.string(forKey: "device.input") == "mic-1")
    }
}
