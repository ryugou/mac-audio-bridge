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
    /// 既に決定済みの場合は即座に現状を返す。
    static func requestMicrophoneAccess(completion: @escaping (MicrophoneAuthorization) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(.authorized)
        case .denied, .restricted:
            completion(.denied)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted ? .authorized : .denied)
                }
            }
        @unknown default:
            completion(.denied)
        }
    }

    /// 「システム設定 > プライバシー > マイク」を開く。
    static func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
