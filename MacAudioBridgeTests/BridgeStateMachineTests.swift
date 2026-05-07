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

    // 4 状態 × 7 イベントの全 28 ケースを表で網羅。
    // 上の個別テストでカバーされている明示的遷移以外は default で「状態維持」が期待値。
    @Test(arguments: BridgeStateMachineTests.transitionMatrix)
    func transitionMatrix(_ scenario: TransitionScenario) {
        let next = BridgeStateMachine.transition(from: scenario.from, on: scenario.event)
        #expect(next == scenario.expected, "\(scenario.label): expected \(scenario.expected), got \(next)")
    }

    struct TransitionScenario: CustomStringConvertible {
        let from: BridgeStatus
        let event: BridgeEvent
        let expected: BridgeStatus
        let label: String
        var description: String { label }
    }

    static let sampleStop: StopReason = .deviceDisconnected(uid: "spk-1")
    static let sampleEvent: BridgeEvent = .deviceDisconnected(uid: "spk-1")
    static let sampleReconnect: BridgeEvent = .deviceReconnected(uid: "spk-1")
    static let sampleFailure: BridgeEvent = .startFailed(reason: .feedbackLoop)

    static let transitionMatrix: [TransitionScenario] = [
        // idle
        .init(from: .idle, event: .userToggledOn, expected: .starting, label: "idle/userToggledOn"),
        .init(from: .idle, event: .userToggledOff, expected: .idle, label: "idle/userToggledOff"),
        .init(from: .idle, event: .startSucceeded, expected: .idle, label: "idle/startSucceeded"),
        .init(from: .idle, event: sampleFailure, expected: .idle, label: "idle/startFailed"),
        .init(from: .idle, event: sampleEvent, expected: .idle, label: "idle/deviceDisconnected"),
        .init(from: .idle, event: sampleReconnect, expected: .idle, label: "idle/deviceReconnected"),
        .init(from: .idle, event: .feedbackLoopDetected, expected: .idle, label: "idle/feedbackLoopDetected"),

        // starting
        .init(from: .starting, event: .userToggledOn, expected: .starting, label: "starting/userToggledOn"),
        .init(from: .starting, event: .userToggledOff, expected: .stopped(.userToggledOff), label: "starting/userToggledOff"),
        .init(from: .starting, event: .startSucceeded, expected: .running, label: "starting/startSucceeded"),
        .init(from: .starting, event: sampleFailure, expected: .stopped(.feedbackLoop), label: "starting/startFailed"),
        .init(from: .starting, event: sampleEvent, expected: .starting, label: "starting/deviceDisconnected"),
        .init(from: .starting, event: sampleReconnect, expected: .starting, label: "starting/deviceReconnected"),
        .init(from: .starting, event: .feedbackLoopDetected, expected: .stopped(.feedbackLoop), label: "starting/feedbackLoopDetected"),

        // running
        .init(from: .running, event: .userToggledOn, expected: .running, label: "running/userToggledOn"),
        .init(from: .running, event: .userToggledOff, expected: .stopped(.userToggledOff), label: "running/userToggledOff"),
        .init(from: .running, event: .startSucceeded, expected: .running, label: "running/startSucceeded"),
        .init(from: .running, event: sampleFailure, expected: .running, label: "running/startFailed"),
        .init(from: .running, event: sampleEvent, expected: .stopped(sampleStop), label: "running/deviceDisconnected"),
        .init(from: .running, event: sampleReconnect, expected: .running, label: "running/deviceReconnected"),
        .init(from: .running, event: .feedbackLoopDetected, expected: .stopped(.feedbackLoop), label: "running/feedbackLoopDetected"),

        // stopped(.deviceDisconnected("spk-1"))
        .init(from: .stopped(sampleStop), event: .userToggledOn, expected: .starting, label: "stoppedDD/userToggledOn"),
        .init(from: .stopped(sampleStop), event: .userToggledOff, expected: .stopped(sampleStop), label: "stoppedDD/userToggledOff"),
        .init(from: .stopped(sampleStop), event: .startSucceeded, expected: .stopped(sampleStop), label: "stoppedDD/startSucceeded"),
        .init(from: .stopped(sampleStop), event: sampleFailure, expected: .stopped(sampleStop), label: "stoppedDD/startFailed"),
        .init(from: .stopped(sampleStop), event: sampleEvent, expected: .stopped(sampleStop), label: "stoppedDD/deviceDisconnected"),
        .init(from: .stopped(sampleStop), event: sampleReconnect, expected: .starting, label: "stoppedDD/deviceReconnectedSameUID"),
        .init(from: .stopped(sampleStop), event: .feedbackLoopDetected, expected: .stopped(sampleStop), label: "stoppedDD/feedbackLoopDetected"),
    ]
}
