import AVFoundation
import AppKit

enum MicrophoneAuthorization {
    case authorized
    case denied
    case notDetermined
}

enum PermissionHelper {
    static var microphoneStatus: MicrophoneAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    /// マイク権限をユーザーに要求し、結果を completion で返す。
    /// completion は **常に MainActor 上** で呼ばれる（型で保証）。
    /// 呼び出し側はスレッドを意識せず @MainActor の状態更新が書ける。
    static func requestMicrophoneAccess(completion: @escaping @MainActor (MicrophoneAuthorization) -> Void) {
        let deliver: (MicrophoneAuthorization) -> Void = { auth in
            Task { @MainActor in completion(auth) }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            deliver(.authorized)
        case .denied, .restricted:
            deliver(.denied)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                deliver(granted ? .authorized : .denied)
            }
        @unknown default:
            deliver(.denied)
        }
    }

    /// 「システム設定 > プライバシー > マイク」を開く。
    static func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
