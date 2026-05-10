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
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("historyEnabled") var historyEnabled = true
    @AppStorage("keychainMigrationCompleted") var keychainMigrationCompleted = false
    @AppStorage("selectedInputDeviceUID") var selectedInputDeviceUID = ""
    @Published var authToken = "" {
        didSet {
            debouncedKeychainWrite()
        }
    }
    @Published private(set) var authTokenStorageError: String?
    private var keychainWriteWorkItem: DispatchWorkItem?

    private func debouncedKeychainWrite() {
        keychainWriteWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                try KeychainStore.set(self.authToken, account: Self.authTokenAccount)
                self.authTokenStorageError = nil
            } catch {
                self.authTokenStorageError = error.localizedDescription
            }
        }
        keychainWriteWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private init() {
        do {
            let defaults = UserDefaults.standard

            // If we already have a Keychain token, use it and clean up any stale legacy data.
            if let storedToken = try KeychainStore.read(account: Self.authTokenAccount) {
                authToken = storedToken
                if defaults.object(forKey: "authToken") != nil {
                    defaults.removeObject(forKey: "authToken")
                }
                keychainMigrationCompleted = true
                return
            }

            // No Keychain token yet — attempt migration from UserDefaults.
            if let legacyToken = defaults.string(forKey: "authToken"), !legacyToken.isEmpty {
                authToken = legacyToken
                try KeychainStore.set(legacyToken, account: Self.authTokenAccount)
                // Mark migration complete before deleting the legacy value so a crash
                // between write and delete will not re-trigger a lost-token scenario.
                keychainMigrationCompleted = true
                defaults.removeObject(forKey: "authToken")
                return
            }

            // Startup audit: if migration was previously marked complete but the legacy
            // token was never deleted (e.g. crash during first migration), clean it up.
            if keychainMigrationCompleted && defaults.object(forKey: "authToken") != nil {
                defaults.removeObject(forKey: "authToken")
            }
        } catch {
            authTokenStorageError = error.localizedDescription
        }
    }

    var baseURL: String {
        var url = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !url.lowercased().hasPrefix("http://") && !url.lowercased().hasPrefix("https://") {
            url = "http://" + url
        }
        return url
    }
}
