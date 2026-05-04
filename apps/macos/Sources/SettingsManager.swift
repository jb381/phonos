import Foundation
import SwiftUI

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @AppStorage("serverURL") var serverURL = "http://localhost:8765"
    @AppStorage("authToken") var authToken = ""
    @AppStorage("recordingMode") var recordingMode = "hold"
    @AppStorage("selectedModel") var selectedModel = "base.en"
    @AppStorage("hotkeyFallback") var hotkeyFallback = "control"

    var baseURL: String {
        serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
