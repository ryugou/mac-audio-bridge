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
    static func image(for status: BridgeStatus) -> some View {
        let name = systemImageName(for: status)
        let img = Image(systemName: name)
        switch status {
        case .stopped(.feedbackLoop): return AnyView(img.foregroundStyle(.yellow))
        case .stopped(.deviceDisconnected),
             .stopped(.micPermissionDenied),
             .stopped(.engineFailed): return AnyView(img.foregroundStyle(.red))
        case .idle, .stopped(.userToggledOff): return AnyView(img.foregroundStyle(.secondary))
        default: return AnyView(img)
        }
    }
}
