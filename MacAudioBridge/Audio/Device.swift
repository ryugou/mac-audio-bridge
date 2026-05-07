import Foundation
import CoreAudio

struct Device: Equatable, Identifiable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
}
