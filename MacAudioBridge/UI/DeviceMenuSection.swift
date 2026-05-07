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
                checkmarkRow(
                    isSelected: currentChoice == .systemDefault,
                    text: "System Default (\(defaultDevice?.name ?? "—"))"
                )
            }

            Divider()

            ForEach(devices) { device in
                Button {
                    onSelect(.specific(uid: device.uid))
                } label: {
                    checkmarkRow(isSelected: isSelected(device), text: device.name)
                }
            }
        }
    }

    /// MenuBarExtra(.menu) の menu item では `Image.opacity(0)` での非表示が
    /// system rendering に伝わらず、すべての行にチェックマークが描画される
    /// 不具合があるため、`if` で Image 自体を出し分ける。
    @ViewBuilder
    private func checkmarkRow(isSelected: Bool, text: String) -> some View {
        HStack {
            if isSelected {
                Image(systemName: "checkmark").frame(width: 14)
            } else {
                Spacer().frame(width: 14)
            }
            Text(text)
        }
    }

    private func isSelected(_ device: Device) -> Bool {
        if case .specific(let uid) = currentChoice, uid == device.uid {
            return true
        }
        return false
    }
}
