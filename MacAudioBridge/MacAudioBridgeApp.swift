import SwiftUI
import AppKit

@main
struct MacAudioBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: delegate.state)
        } label: {
            StatusIcon.image(for: delegate.state.status)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let state: AppState

    override init() {
        self.state = AppState()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 多重起動防止 (§5.1 step 2)
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            Log.app.info("Another instance is running; activating it and terminating self")
            others.first?.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }

        state.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdown()
    }
}
