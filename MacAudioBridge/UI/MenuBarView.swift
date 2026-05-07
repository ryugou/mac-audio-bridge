import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        // ON/OFF トグル
        Button(action: toggleAction) {
            Text(toggleLabel)
        }

        Divider()

        // 状態表示
        Text(statusText).disabled(true)

        Divider()

        // Input
        DeviceMenuSection(
            title: "Input Device",
            devices: state.connectedInputDevices,
            defaultDevice: state.defaultInputDevice,
            currentChoice: state.inputChoice,
            onSelect: state.setInputChoice
        )

        Divider()

        // Output
        DeviceMenuSection(
            title: "Output Device",
            devices: state.connectedOutputDevices,
            defaultDevice: state.defaultOutputDevice,
            currentChoice: state.outputChoice,
            onSelect: state.setOutputChoice
        )

        Divider()

        // Settings
        Toggle("ログイン時に自動起動 + 自動 Run", isOn: $state.autoRun)

        // 権限拒否時の補助
        if case .stopped(.micPermissionDenied) = state.status {
            Button("システム設定 > マイクを開く") {
                PermissionHelper.openMicrophoneSettings()
            }
        }

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
    }

    private var toggleLabel: String {
        switch state.status {
        case .running, .starting: return "OFF にする"
        default: return "ON にする"
        }
    }

    private func toggleAction() {
        switch state.status {
        case .running, .starting: state.toggleOff()
        default: state.toggleOn()
        }
    }

    private var statusText: String {
        switch state.status {
        case .idle: return "状態: 停止中"
        case .starting: return "状態: 起動中…"
        case .running:
            let inputName = state.connectedInputDevices.first(where: { isCurrentInput($0) })?.name
                ?? state.defaultInputDevice?.name ?? "—"
            let outputName = state.connectedOutputDevices.first(where: { isCurrentOutput($0) })?.name
                ?? state.defaultOutputDevice?.name ?? "—"
            return "状態: 動作中 (\(inputName) → \(outputName))"
        case .stopped(.userToggledOff): return "状態: 停止中"
        case .stopped(.feedbackLoop): return "状態: ⚠ 入出力が同一デバイスです"
        case .stopped(.deviceDisconnected(let uid)):
            return "状態: ⚠ 選択デバイス未接続: \(uid)"
        case .stopped(.micPermissionDenied):
            return "状態: ✕ マイク権限が拒否されています"
        case .stopped(.engineFailed(let msg)):
            return "状態: ✕ \(msg)"
        }
    }

    private func isCurrentInput(_ device: Device) -> Bool {
        if case .specific(let uid) = state.inputChoice { return uid == device.uid }
        return device.uid == state.defaultInputDevice?.uid
    }

    private func isCurrentOutput(_ device: Device) -> Bool {
        if case .specific(let uid) = state.outputChoice { return uid == device.uid }
        return device.uid == state.defaultOutputDevice?.uid
    }
}
