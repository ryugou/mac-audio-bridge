import Foundation

final class Preferences {
    private let store: UserDefaults

    private enum Keys {
        static let inputDevice = "device.input"
        static let outputDevice = "device.output"
        static let autoRun = "app.autoRun"
    }

    init(store: UserDefaults = .standard) {
        self.store = store
    }

    var inputChoice: DeviceChoice {
        get {
            // 永続化表現の文字列リテラルは DeviceChoice 側に集約。
            // store にエントリが無ければ .systemDefault を返す。
            store.string(forKey: Keys.inputDevice).map(DeviceChoice.init(storageString:)) ?? .systemDefault
        }
        set {
            store.set(newValue.storageString, forKey: Keys.inputDevice)
        }
    }

    var outputChoice: DeviceChoice {
        get {
            store.string(forKey: Keys.outputDevice).map(DeviceChoice.init(storageString:)) ?? .systemDefault
        }
        set {
            store.set(newValue.storageString, forKey: Keys.outputDevice)
        }
    }

    var autoRun: Bool {
        get { store.bool(forKey: Keys.autoRun) }
        set { store.set(newValue, forKey: Keys.autoRun) }
    }
}
