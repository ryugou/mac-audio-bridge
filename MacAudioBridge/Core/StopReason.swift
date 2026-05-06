import Foundation

enum StopReason: Equatable {
    case userToggledOff
    case deviceDisconnected(uid: String)
    case feedbackLoop
    case micPermissionDenied
    case engineFailed(message: String)
}
