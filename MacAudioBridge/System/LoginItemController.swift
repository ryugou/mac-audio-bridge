import Foundation
import ServiceManagement

enum LoginItemError: Error, LocalizedError {
    case registrationFailed(underlying: Error)
    case unregistrationFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let e): return "ログイン項目の登録に失敗: \(e.localizedDescription)"
        case .unregistrationFailed(let e): return "ログイン項目の解除に失敗: \(e.localizedDescription)"
        }
    }
}

enum LoginItemController {
    /// 現在ログイン項目に登録されているか。
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 登録（ログイン時自動起動を有効化）。
    static func register() throws {
        do {
            try SMAppService.mainApp.register()
            Log.app.info("LoginItem registered")
        } catch {
            Log.app.error("LoginItem register failed: \(error.localizedDescription)")
            throw LoginItemError.registrationFailed(underlying: error)
        }
    }

    /// 解除（ログイン時自動起動を無効化）。
    static func unregister() throws {
        do {
            try SMAppService.mainApp.unregister()
            Log.app.info("LoginItem unregistered")
        } catch {
            Log.app.error("LoginItem unregister failed: \(error.localizedDescription)")
            throw LoginItemError.unregistrationFailed(underlying: error)
        }
    }
}
