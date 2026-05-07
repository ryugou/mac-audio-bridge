import Foundation

enum BridgeEvent: Equatable {
    case userToggledOn
    case userToggledOff
    case startSucceeded
    case startFailed(reason: StopReason)
    case deviceDisconnected(uid: String)
    case deviceReconnected(uid: String)
    case feedbackLoopDetected
}

enum BridgeStateMachine {
    /// 現在状態とイベントから次状態を返す純関数。
    /// 副作用を持たない。AppState 側で副作用（実エンジン操作）を起こす。
    static func transition(from current: BridgeStatus, on event: BridgeEvent) -> BridgeStatus {
        switch (current, event) {
        // ON トグル: idle / stopped から starting へ
        case (.idle, .userToggledOn),
             (.stopped, .userToggledOn):
            return .starting

        // OFF トグル: starting / running から stopped(.userToggledOff)
        case (.starting, .userToggledOff),
             (.running, .userToggledOff):
            return .stopped(.userToggledOff)

        // 起動成功
        case (.starting, .startSucceeded):
            return .running

        // 起動失敗
        case (.starting, .startFailed(let reason)):
            return .stopped(reason)

        // 動作中の切断
        case (.running, .deviceDisconnected(let uid)):
            return .stopped(.deviceDisconnected(uid: uid))

        // 切断状態からの再接続（同じ UID のときだけ再起動）
        case (.stopped(.deviceDisconnected(let stoppedUID)), .deviceReconnected(let uid)):
            return stoppedUID == uid ? .starting : current

        // フィードバックループ検知（動作中・起動中とも停止）
        case (.running, .feedbackLoopDetected),
             (.starting, .feedbackLoopDetected):
            return .stopped(.feedbackLoop)

        // それ以外は状態維持
        default:
            return current
        }
    }
}
