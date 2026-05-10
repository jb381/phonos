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
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Connection") {
                ConnectionSettingsSection(
                    settings: settings,
                    viewModel: viewModel,
                    mode: .settings,
                    onCheckConnection: { viewModel.checkHealth() },
                    onScanNetwork: startScan,
                    isScanning: isScanning,
                    scanResults: scanResults
                )
            }

            Divider()

            SettingsSection(title: "Model") {
                ModelSettingsSection(
                    settings: settings,
                    viewModel: viewModel,
                    showsRefresh: true,
                    onRefreshModels: { viewModel.fetchModels() }
                )
            }

            Divider()

            SettingsSection(title: "Recording") {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsRow(title: "Mode") {
                        Picker("", selection: $settings.recordingMode) {
                            Text("Hold to Record").tag("hold")
                            Text("Toggle Recording").tag("toggle")
                        }
                        .labelsHidden()
                        .settingsControlWidth(250)
                    }

                    if !availableInputDevices.isEmpty {
                        SettingsRow(title: "Microphone") {
                            Picker("", selection: $settings.selectedInputDeviceUID) {
                                Text("System Default").tag("")
                                ForEach(availableInputDevices) { device in
                                    Text(device.name).tag(device.id)
                                }
                            }
                            .labelsHidden()
                            .settingsControlWidth(360)
                        }
                    }

                    SettingsRow(title: "Shortcut") {
                        ShortcutRecorderView(name: .record) { _ in
                            NotificationCenter.default.post(name: .recordShortcutChanged, object: nil)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            Divider()

            SettingsSection(title: "App") {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsRow(title: "") {
                        Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                            .onChange(of: settings.launchAtLogin) { _, enabled in
                                guard !isSyncingLaunchAtLogin else { return }
                                updateLaunchAtLogin(enabled)
                            }
                    }

                    SettingsRow(title: "") {
                        Toggle("Save Transcription History", isOn: $settings.historyEnabled)
                            .onChange(of: settings.historyEnabled) { _, enabled in
                                TranscriptHistoryStore.shared.setPersistenceEnabled(enabled)
                            }
                    }

                    SettingsRow(title: "") {
                        Text("Store transcript history locally in a SQLite database on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let error = launchAtLoginError {
                        SettingsRow(title: "") {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SettingsRow(title: "Version") {
                        Text(AppVersion.displayString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 540)
        .frame(height: 620, alignment: .topLeading)
        .onAppear {
            viewModel.fetchModels()
            viewModel.checkHealth()
            refreshInputDevices()
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
