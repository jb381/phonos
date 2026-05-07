import AVFoundation
import Cocoa
import SwiftUI

struct FirstRunView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var viewModel = ServerSettingsViewModel()
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set Up Phonos")
                    .font(.title2.weight(.semibold))
                Text("Connect the server and grant the permissions needed for dictation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                checklistRow(
                    title: "Microphone",
                    detail: microphoneGranted ? "Ready" : "Required for recording audio",
                    isComplete: microphoneGranted
                ) {
                    Button("Grant") { requestMicrophone() }
                        .disabled(microphoneGranted)
                }

                checklistRow(
                    title: "Accessibility",
                    detail: accessibilityGranted ? "Ready" : "Required for automatic paste",
                    isComplete: accessibilityGranted
                ) {
                    Button("Open Settings") { openAccessibilitySettings() }
                }

                Divider()

                TextField("Server URL", text: $settings.serverURL)
                SecureField("Auth Token", text: $settings.authToken)

                if let error = settings.authTokenStorageError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    statusDot
                    Text(viewModel.serverStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Connection") { viewModel.checkHealth() }
                        .disabled(viewModel.isChecking)
                }

                if !viewModel.availableModels.isEmpty {
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
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    finishSetup()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460, height: 500)
        .onAppear {
            refreshPermissions()
            viewModel.fetchModels()
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(viewModel.serverStatus.lowercased() == "ok" ? Color.green : Color.secondary)
            .frame(width: 8, height: 8)
    }

    private func checklistRow<Content: View>(
        title: String,
        detail: String,
        isComplete: Bool,
        @ViewBuilder action: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            action()
        }
    }

    private func refreshPermissions() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in
                refreshPermissions()
            }
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
        refreshPermissions()
    }

    private func finishSetup() {
        let missingMic = !microphoneGranted
        let missingServer = viewModel.serverStatus.lowercased() != "ok"
        if missingMic || missingServer {
            let alert = NSAlert()
            alert.messageText = "Setup Incomplete"
            var issues: [String] = []
            if missingMic { issues.append("microphone permission not granted") }
            if missingServer { issues.append("server connection not verified") }
            alert.informativeText = "You are missing: \(issues.joined(separator: " and ")). Continue anyway?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                settings.firstRunCompleted = true
                onDone()
            }
        } else {
            settings.firstRunCompleted = true
            onDone()
        }
    }
}
