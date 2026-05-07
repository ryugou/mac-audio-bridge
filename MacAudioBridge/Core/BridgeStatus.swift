import Foundation

enum BridgeStatus: Equatable {
    case idle
    case starting
    case running
    case stopped(StopReason)
}
