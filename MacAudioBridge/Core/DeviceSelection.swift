import Foundation

enum DeviceSelection {
    /// DeviceChoice と現在のシステムデフォルト・接続中デバイス一覧から ResolvedDevice を解決する。
    /// - .systemDefault: systemDefault をそのまま返す（nil なら nil）
    /// - .specific(uid): connectedDevices から uid 一致を探して返す（無ければ nil）
    static func resolve(
        choice: DeviceChoice,
        systemDefault: ResolvedDevice?,
        connectedDevices: [ResolvedDevice]
    ) -> ResolvedDevice? {
        switch choice {
        case .systemDefault:
            return systemDefault
        case .specific(let uid):
            return connectedDevices.first(where: { $0.uid == uid })
        }
    }
}
