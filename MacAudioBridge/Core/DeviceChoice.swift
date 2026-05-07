import Foundation

enum DeviceChoice: Equatable, Codable {
    case systemDefault
    case specific(uid: String)

    /// `.systemDefault` の永続化表現。実 UID と衝突しないよう snake_case を採用。
    private static let systemDefaultStorageKey = "system_default"

    /// UserDefaults 保存用文字列。`systemDefaultStorageKey` or UID。
    var storageString: String {
        switch self {
        case .systemDefault: return Self.systemDefaultStorageKey
        case .specific(let uid): return uid
        }
    }

    /// UserDefaults 保存文字列から復元。
    init(storageString: String) {
        if storageString == Self.systemDefaultStorageKey {
            self = .systemDefault
        } else {
            self = .specific(uid: storageString)
        }
    }
}
