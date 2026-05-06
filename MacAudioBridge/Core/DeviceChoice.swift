import Foundation

enum DeviceChoice: Equatable, Codable {
    case systemDefault
    case specific(uid: String)

    /// UserDefaults 保存用文字列。"system_default" or UID。
    var storageString: String {
        switch self {
        case .systemDefault: return "system_default"
        case .specific(let uid): return uid
        }
    }

    /// UserDefaults 保存文字列から復元。
    init(storageString: String) {
        if storageString == "system_default" {
            self = .systemDefault
        } else {
            self = .specific(uid: storageString)
        }
    }
}
