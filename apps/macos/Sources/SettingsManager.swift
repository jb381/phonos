import Foundation
import SwiftUI

extension Notification.Name {
    static let recordShortcutChanged = Notification.Name("recordShortcutChanged")
}

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    private static let authTokenAccount = "authToken"

    @AppStorage("serverURL") var serverURL = "http://localhost:8765"
    @AppStorage("recordingMode") var recordingMode = "hold"
    @AppStorage("selectedModel") var selectedModel = "base.en"
    @AppStorage("firstRunCompleted") var firstRunCompleted = false
    @Published var authToken = "" {
        didSet {
            do {
                try KeychainStore.set(authToken, account: Self.authTokenAccount)
                authTokenStorageError = nil
            } catch {
                authTokenStorageError = error.localizedDescription
            }
        }
    }
    @Published private(set) var authTokenStorageError: String?

    private init() {
        do {
            if let storedToken = try KeychainStore.read(account: Self.authTokenAccount) {
                authToken = storedToken
                return
            }

            let defaults = UserDefaults.standard
            if let legacyToken = defaults.string(forKey: "authToken"), !legacyToken.isEmpty {
                authToken = legacyToken
                try KeychainStore.set(legacyToken, account: Self.authTokenAccount)
                defaults.removeObject(forKey: "authToken")
            }
        } catch {
            authTokenStorageError = error.localizedDescription
        }
    }

    var baseURL: String {
        serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
