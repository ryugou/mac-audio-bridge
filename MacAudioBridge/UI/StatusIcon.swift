import SwiftUI

enum StatusIcon {
    static func systemImageName(for status: BridgeStatus) -> String {
        switch status {
        case .running: return "speaker.wave.2"
        case .idle, .stopped(.userToggledOff): return "speaker.slash"
        case .stopped(.feedbackLoop): return "exclamationmark.triangle.fill"
        case .stopped(.deviceDisconnected),
             .stopped(.micPermissionDenied),
             .stopped(.engineFailed):
            return "exclamationmark.triangle.fill"
        case .starting: return "speaker.wave.2"
        }
    }

    /// メニューバーアイコン用の色付き SwiftUI Image。
    @ViewBuilder
    static func image(for status: BridgeStatus) -> some View {
        let img = Image(systemName: systemImageName(for: status))
        switch status {
        case .stopped(.feedbackLoop):
            img.foregroundStyle(.yellow)
        case .stopped(.deviceDisconnected),
             .stopped(.micPermissionDenied),
             .stopped(.engineFailed):
            img.foregroundStyle(.red)
        case .idle, .stopped(.userToggledOff):
            img.foregroundStyle(.secondary)
        default:
            img
        }
    }
}
