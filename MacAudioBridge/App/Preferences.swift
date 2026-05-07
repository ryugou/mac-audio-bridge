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
            DeviceChoice(storageString: store.string(forKey: Keys.inputDevice) ?? "system_default")
        }
        set {
            store.set(newValue.storageString, forKey: Keys.inputDevice)
        }
    }

    var outputChoice: DeviceChoice {
        get {
            DeviceChoice(storageString: store.string(forKey: Keys.outputDevice) ?? "system_default")
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
