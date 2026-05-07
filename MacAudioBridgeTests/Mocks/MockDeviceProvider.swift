import Foundation
@testable import MacAudioBridge

final class MockDeviceProvider: DeviceProvider {
    var connectedInputDevices: [Device]
    var connectedOutputDevices: [Device]
    var defaultInputDevice: Device?
    var defaultOutputDevice: Device?

    init(
        connectedInput: [Device] = [],
        connectedOutput: [Device] = [],
        defaultInput: Device? = nil,
        defaultOutput: Device? = nil
    ) {
        self.connectedInputDevices = connectedInput
        self.connectedOutputDevices = connectedOutput
        self.defaultInputDevice = defaultInput
        self.defaultOutputDevice = defaultOutput
    }
}
