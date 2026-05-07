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
                    // 未選択時は opacity(0) で領域を残しつつ非表示。
                    // 空文字 SF Symbol を渡すと SF Symbols の解決失敗ログが出るため避ける。
                    Image(systemName: "checkmark")
                        .frame(width: 14)
                        .opacity(currentChoice == .systemDefault ? 1 : 0)
                    Text("System Default (\(defaultDevice?.name ?? "—"))")
                }
            }

            Divider()

            ForEach(devices) { device in
                Button {
                    onSelect(.specific(uid: device.uid))
                } label: {
                    HStack {
                        Image(systemName: "checkmark")
                            .frame(width: 14)
                            .opacity(isSelected(device) ? 1 : 0)
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
