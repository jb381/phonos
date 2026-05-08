import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var viewModel = ServerSettingsViewModel()
    @State private var isScanning = false
    @State private var scanResults: [ScanResult] = []
    @State private var isSyncingLaunchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var availableInputDevices: [AudioDevice] = []

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Server URL", text: $settings.serverURL)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }

                if !viewModel.serverStatus.isEmpty && viewModel.serverStatus.lowercased() != "ok" && !viewModel.serverStatus.lowercased().hasPrefix("model:") {
                    Text(viewModel.serverStatus)
                        .font(.caption)
                        .foregroundColor(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecureField("Auth Token", text: $settings.authToken)

                if let error = settings.authTokenStorageError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Button("Check Connection") { viewModel.checkHealth() }
                    Button("Scan Network") { startScan() }
                        .disabled(isScanning)
                }

                if viewModel.isChecking {
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
                    ForEach(viewModel.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .onChange(of: settings.selectedModel) { _, newModel in
                    guard !viewModel.isSyncingModelSelection else { return }
                    viewModel.setModel(newModel)
                }

                Text(ModelCatalog.description(for: settings.selectedModel))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Refresh Models") { viewModel.fetchModels() }
            }

            Section("Recording") {
                Picker("Mode", selection: $settings.recordingMode) {
                    Text("Hold to Record").tag("hold")
                    Text("Toggle Recording").tag("toggle")
                }

                if !availableInputDevices.isEmpty {
                    Picker("Microphone", selection: $settings.selectedInputDeviceUID) {
                        Text("System Default").tag("")
                        ForEach(availableInputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                }

                HStack {
                    Text("Shortcut")
                    ShortcutRecorderView(name: .record) { _ in
                        NotificationCenter.default.post(name: .recordShortcutChanged, object: nil)
                    }
                }
            }

            Section("App") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in
                        guard !isSyncingLaunchAtLogin else { return }
                        updateLaunchAtLogin(enabled)
                    }

                if let error = launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear {
            viewModel.fetchModels()
            viewModel.checkHealth()
            refreshInputDevices()
        }
    }

    private var statusColor: Color {
        switch viewModel.serverStatus.lowercased() {
        case "ok": return .green
        case "loading": return .yellow
        default: return .red
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
            }
        }
    }

    private func refreshInputDevices() {
        availableInputDevices = AudioDeviceManager.availableInputDevices()
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            isSyncingLaunchAtLogin = true
            settings.launchAtLogin = !enabled
            isSyncingLaunchAtLogin = false
        }
    }
}
