import Foundation

enum FeedbackLoopDetector {
    /// 入力 UID と出力 UID が同じならフィードバックループ。
    /// 片方が nil なら判定不可（false 扱い）。
    static func isLoop(inputUID: String?, outputUID: String?) -> Bool {
        guard let inputUID, let outputUID else { return false }
        return inputUID == outputUID
    }
}
