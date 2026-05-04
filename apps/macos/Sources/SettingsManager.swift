import Foundation
import SwiftUI

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
}

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @AppStorage("serverURL") var serverURL = "http://localhost:8765"
    @AppStorage("authToken") var authToken = ""
    @AppStorage("recordingMode") var recordingMode = "hold"
    @AppStorage("selectedModel") var selectedModel = "base.en"
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode = 0x3B

    var baseURL: String {
        serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static let keyNames: [Int: String] = [
        0x3B: "Control (left)",
        0x3F: "Fn / Globe",
        0x3E: "Control (right)",
        0x3A: "Option (left)",
        0x3D: "Option (right)",
        0x37: "Command (left)",
        0x36: "Command (right)",
        0x38: "Shift (left)",
        0x3C: "Shift (right)",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]

    static func keyName(for code: Int) -> String {
        keyNames[code] ?? "Key \(code)"
    }
}
