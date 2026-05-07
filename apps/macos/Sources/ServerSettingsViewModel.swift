import Foundation
import SwiftUI

@MainActor
final class ServerSettingsViewModel: ObservableObject {
    @Published var serverStatus = "Unknown"
    @Published var availableModels: [String] = []
    @Published var isChecking = false
    @Published var isSyncingModelSelection = false

    func checkHealth() {
        isChecking = true
        Task {
            do {
                let health = try await ServerClient().healthCheck()
                await MainActor.run {
                    self.serverStatus = health.status
                    self.isChecking = false
                }
            } catch {
                await MainActor.run {
                    self.serverStatus = error.localizedDescription
                    self.isChecking = false
                }
            }
        }
    }

    func fetchModels() {
        Task {
            do {
                let response = try await ServerClient().listModels()
                await MainActor.run {
                    self.availableModels = response.models
                    self.isSyncingModelSelection = true
                    SettingsManager.shared.selectedModel = response.active
                    self.isSyncingModelSelection = false
                }
            } catch {
                await MainActor.run {
                    self.serverStatus = error.localizedDescription
                }
            }
        }
    }

    func setModel(_ model: String) {
        if ModelCatalog.isLargeCPUModel(model) {
            serverStatus = "\(model) may be slow on CPU"
        }
        Task {
            do {
                let response = try await ServerClient().setActiveModel(model)
                await MainActor.run {
                    self.serverStatus = "Model: \(response.model)"
                }
            } catch {
                await MainActor.run {
                    self.serverStatus = error.localizedDescription
                }
            }
        }
    }
}
