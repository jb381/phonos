import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var serverStatus = "Unknown"
    @State private var availableModels: [String] = []
    @State private var isChecking = false

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $settings.serverURL)
                    .onChange(of: settings.serverURL) { _ in checkHealth() }

                SecureField("Auth Token", text: $settings.authToken)

                HStack {
                    Text("Status:")
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(serverStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if isChecking {
                    ProgressView().scaleEffect(0.5)
                }

                Button("Check Connection") { checkHealth() }
            }

            Section("Model") {
                Picker("Model", selection: $settings.selectedModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .onChange(of: settings.selectedModel) { newModel in
                    setModel(newModel)
                }

                Button("Refresh Models") { fetchModels() }
            }

            Section("Recording") {
                Picker("Mode", selection: $settings.recordingMode) {
                    Text("Hold to Record").tag("hold")
                    Text("Toggle Recording").tag("toggle")
                }
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            fetchModels()
            checkHealth()
        }
    }

    private var statusColor: Color {
        switch serverStatus.lowercased() {
        case "ok": return .green
        case "loading": return .yellow
        default: return .red
        }
    }

    private func checkHealth() {
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let health = try await ServerClient().healthCheck()
                await MainActor.run { serverStatus = health.status }
            } catch {
                await MainActor.run { serverStatus = error.localizedDescription }
            }
        }
    }

    private func fetchModels() {
        Task {
            do {
                let response = try await ServerClient().listModels()
                await MainActor.run { availableModels = response.models }
            } catch {}
        }
    }

    private func setModel(_ model: String) {
        Task {
            do {
                _ = try await ServerClient().setActiveModel(model)
            } catch {}
        }
    }
}
