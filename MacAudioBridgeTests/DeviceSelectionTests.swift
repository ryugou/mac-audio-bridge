import Testing
@testable import MacAudioBridge

struct DeviceSelectionTests {
    let mic = ResolvedDevice(uid: "mic-1", name: "USB Mic", isConnected: true)
    let speaker = ResolvedDevice(uid: "spk-1", name: "AirPods", isConnected: true)
    let unplugged = ResolvedDevice(uid: "ghost", name: "Ghost", isConnected: false)

    @Test func systemDefaultReturnsSystemDefault() {
        let result = DeviceSelection.resolve(
            choice: .systemDefault,
            systemDefault: mic,
            connectedDevices: [mic, speaker]
        )
        #expect(result == mic)
    }

    @Test func systemDefaultReturnsNilWhenNoDefault() {
        let result = DeviceSelection.resolve(
            choice: .systemDefault,
            systemDefault: nil,
            connectedDevices: [mic]
        )
        #expect(result == nil)
    }

    @Test func specificReturnsConnectedDevice() {
        let result = DeviceSelection.resolve(
            choice: .specific(uid: "mic-1"),
            systemDefault: speaker,
            connectedDevices: [mic, speaker]
        )
        #expect(result == mic)
    }

    @Test func specificReturnsNilWhenNotConnected() {
        let result = DeviceSelection.resolve(
            choice: .specific(uid: "ghost"),
            systemDefault: mic,
            connectedDevices: [mic, speaker]
        )
        #expect(result == nil)
    }

    @Test func specificReturnsDeviceEvenIfMarkedDisconnected() {
        // connectedDevices に含まれていれば isConnected=false でも返す
        // （isConnected フラグは UI 表示用、解決の判定は配列存在で行う）
        let result = DeviceSelection.resolve(
            choice: .specific(uid: "ghost"),
            systemDefault: nil,
            connectedDevices: [unplugged]
        )
        #expect(result == unplugged)
    }
}
