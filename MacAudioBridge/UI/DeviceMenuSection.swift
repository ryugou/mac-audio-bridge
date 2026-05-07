import SwiftUI

struct DeviceMenuSection: View {
    let title: String
    let devices: [Device]
    let defaultDevice: Device?
    let currentChoice: DeviceChoice
    let onSelect: (DeviceChoice) -> Void

    var body: some View {
        Section(header: Text(title)) {
            Button {
                onSelect(.systemDefault)
            } label: {
                HStack {
                    Image(systemName: currentChoice == .systemDefault ? "checkmark" : "")
                        .frame(width: 14)
                    Text("System Default (\(defaultDevice?.name ?? "—"))")
                }
            }

            Divider()

            ForEach(devices) { device in
                Button {
                    onSelect(.specific(uid: device.uid))
                } label: {
                    HStack {
                        Image(systemName: isSelected(device) ? "checkmark" : "")
                            .frame(width: 14)
                        Text(device.name)
                    }
                }
            }
        }
    }

    private func isSelected(_ device: Device) -> Bool {
        if case .specific(let uid) = currentChoice, uid == device.uid {
            return true
        }
        return false
    }
}
