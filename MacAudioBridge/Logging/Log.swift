import Foundation
import OSLog

enum Log {
    private static let subsystem = "com.ryugo.mac-audio-bridge"

    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let deviceMonitor = Logger(subsystem: subsystem, category: "device-monitor")
    static let aggregate = Logger(subsystem: subsystem, category: "aggregate")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let app = Logger(subsystem: subsystem, category: "app")
}
