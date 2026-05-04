import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var serverStatus = "Unknown"
    @State private var availableModels: [String] = []
    @State private var isChecking = false
    @State private var isScanning = false
    @State private var scanResults: [ScanResult] = []

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Server URL", text: $settings.serverURL)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .help(serverStatus)
                }

                SecureField("Auth Token", text: $settings.authToken)

                HStack {
                    Button("Check Connection") { checkHealth() }
                    Button("Scan Network") { startScan() }
                        .disabled(isScanning)
                }

                if isChecking {
                    HStack {
                        ProgressView().scaleEffect(0.5)
                        Text("Checking…").font(.caption).foregroundColor(.secondary)
                    }
                }

                if isScanning {
                    HStack {
                        ProgressView().scaleEffect(0.5)
                        Text("Scanning…").font(.caption).foregroundColor(.secondary)
                    }
                }

                if !scanResults.isEmpty && !isScanning {
                    Picker("Found servers", selection: $settings.serverURL) {
                        ForEach(scanResults) { result in
                            Text(result.display).tag(result.url)
                        }
                    }
                }
            } header: {
                Text("Connection")
            }

            Section("Model") {
                Picker("Model", selection: $settings.selectedModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .onChange(of: settings.selectedModel) { _, newModel in
                    setModel(newModel)
                }

                Button("Refresh Models") { fetchModels() }
            }

            Section("Recording") {
                Picker("Mode", selection: $settings.recordingMode) {
                    Text("Hold to Record").tag("hold")
                    Text("Toggle Recording").tag("toggle")
                }

                KeyboardShortcuts.Recorder("Shortcut", name: .record) { _ in
                    NotificationCenter.default.post(name: .recordShortcutChanged, object: nil)
                }
            }
        }
        .padding()
        .frame(width: 420)
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
            do {
                let health = try await ServerClient().healthCheck()
                await MainActor.run {
                    serverStatus = health.status
                    isChecking = false
                }
            } catch {
                await MainActor.run {
                    serverStatus = error.localizedDescription
                    isChecking = false
                }
            }
        }
    }

    private func fetchModels() {
        Task {
            do {
                let response = try await ServerClient().listModels()
                await MainActor.run {
                    availableModels = response.models
                    settings.selectedModel = response.active
                }
            } catch {
                await MainActor.run { serverStatus = error.localizedDescription }
            }
        }
    }

    private func setModel(_ model: String) {
        Task {
            do {
                let response = try await ServerClient().setActiveModel(model)
                await MainActor.run { serverStatus = "Model: \(response.model)" }
            } catch {
                await MainActor.run { serverStatus = error.localizedDescription }
            }
        }
    }

    private func startScan() {
        isScanning = true
        scanResults = []

        Task {
            let results = await NetworkScanner.scan()
            await MainActor.run {
                scanResults = results
                isScanning = false
                if let first = results.first {
                    settings.serverURL = first.url
                }
            }
        }
    }
}
