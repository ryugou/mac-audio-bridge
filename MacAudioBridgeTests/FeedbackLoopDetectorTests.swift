import Testing
@testable import MacAudioBridge

struct FeedbackLoopDetectorTests {
    @Test func sameUIDIsLoop() {
        #expect(FeedbackLoopDetector.isLoop(inputUID: "dev-1", outputUID: "dev-1") == true)
    }

    @Test func differentUIDIsNotLoop() {
        #expect(FeedbackLoopDetector.isLoop(inputUID: "in-1", outputUID: "out-1") == false)
    }

    @Test func nilInputIsNotLoop() {
        #expect(FeedbackLoopDetector.isLoop(inputUID: nil, outputUID: "out-1") == false)
    }

    @Test func nilOutputIsNotLoop() {
        #expect(FeedbackLoopDetector.isLoop(inputUID: "in-1", outputUID: nil) == false)
    }

    @Test func bothNilIsNotLoop() {
        #expect(FeedbackLoopDetector.isLoop(inputUID: nil, outputUID: nil) == false)
    }
}
