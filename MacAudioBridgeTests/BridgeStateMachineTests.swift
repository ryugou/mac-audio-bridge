import Testing
@testable import MacAudioBridge

struct BridgeStateMachineTests {
    @Test func userToggleOnFromIdle() {
        let next = BridgeStateMachine.transition(from: .idle, on: .userToggledOn)
        #expect(next == .starting)
    }

    @Test func userToggleOnFromStoppedRestart() {
        let next = BridgeStateMachine.transition(from: .stopped(.userToggledOff), on: .userToggledOn)
        #expect(next == .starting)
    }

    @Test func userToggleOffFromRunningStops() {
        let next = BridgeStateMachine.transition(from: .running, on: .userToggledOff)
        #expect(next == .stopped(.userToggledOff))
    }

    @Test func userToggleOffFromStartingStops() {
        let next = BridgeStateMachine.transition(from: .starting, on: .userToggledOff)
        #expect(next == .stopped(.userToggledOff))
    }

    @Test func startSucceededFromStartingRunning() {
        let next = BridgeStateMachine.transition(from: .starting, on: .startSucceeded)
        #expect(next == .running)
    }

    @Test func startFailedFromStartingStops() {
        let next = BridgeStateMachine.transition(
            from: .starting,
            on: .startFailed(reason: .feedbackLoop)
        )
        #expect(next == .stopped(.feedbackLoop))
    }

    @Test func deviceDisconnectedFromRunningStops() {
        let next = BridgeStateMachine.transition(
            from: .running,
            on: .deviceDisconnected(uid: "spk-1")
        )
        #expect(next == .stopped(.deviceDisconnected(uid: "spk-1")))
    }

    @Test func deviceReconnectedFromStoppedDisconnectedRestarts() {
        let next = BridgeStateMachine.transition(
            from: .stopped(.deviceDisconnected(uid: "spk-1")),
            on: .deviceReconnected(uid: "spk-1")
        )
        #expect(next == .starting)
    }

    @Test func deviceReconnectedFromStoppedDisconnectedDifferentUIDIgnored() {
        let next = BridgeStateMachine.transition(
            from: .stopped(.deviceDisconnected(uid: "spk-1")),
            on: .deviceReconnected(uid: "other-uid")
        )
        // 別 UID の再接続は無視（状態維持）
        #expect(next == .stopped(.deviceDisconnected(uid: "spk-1")))
    }

    @Test func feedbackLoopFromRunningStops() {
        let next = BridgeStateMachine.transition(from: .running, on: .feedbackLoopDetected)
        #expect(next == .stopped(.feedbackLoop))
    }

    @Test func userToggleOffFromIdleIgnored() {
        let next = BridgeStateMachine.transition(from: .idle, on: .userToggledOff)
        // idle で OFF を押しても何も起きない
        #expect(next == .idle)
    }
}
