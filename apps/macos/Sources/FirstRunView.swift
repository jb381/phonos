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

            SettingsSection(title: "Permissions") {
                VStack(alignment: .leading, spacing: 12) {
                    permissionRow(
                        title: "Microphone",
                        detail: microphoneGranted ? "Ready" : "Required for recording audio",
                        isComplete: microphoneGranted
                    ) {
                        if !microphoneGranted {
                            Button("Grant") { requestMicrophone() }
                        }
                    }

                    permissionRow(
                        title: "Accessibility",
                        detail: accessibilityGranted ? "Ready" : "Required for automatic paste",
                        isComplete: accessibilityGranted
                    ) {
                        if accessibilityGranted {
                            Button("Recheck") { refreshPermissions() }
                        } else {
                            HStack(spacing: 8) {
                                Button("Open Settings") { openAccessibilitySettings() }
                                Button("Recheck") { refreshPermissions() }
                            }
                        }
                    }
                }
            }

            Divider()

            SettingsSection(title: "Server") {
                ConnectionSettingsSection(
                    settings: settings,
                    viewModel: viewModel,
                    mode: .setup,
                    onCheckConnection: { viewModel.checkHealth() },
                    onScanNetwork: nil,
                    isScanning: false,
                    scanResults: []
                )
            }

            if !viewModel.availableModels.isEmpty {
                Divider()

                SettingsSection(title: "Model") {
                    ModelSettingsSection(
                        settings: settings,
                        viewModel: viewModel,
                        showsRefresh: false,
                        onRefreshModels: nil
                    )
                }
            }

            if isSetupIncomplete {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("You can finish now, but dictation may fail until the remaining items are fixed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Done") {
                    finishSetup()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .frame(minHeight: 560)
        .onAppear {
            refreshPermissions()
            viewModel.fetchModels()
            viewModel.checkHealth()
        }
    }

    private var isSetupIncomplete: Bool {
        !microphoneGranted || !accessibilityGranted || viewModel.serverStatus.lowercased() != "ok"
    }

    private func permissionRow<Content: View>(
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
        let missingAccessibility = !accessibilityGranted
        let missingServer = viewModel.serverStatus.lowercased() != "ok"
        if missingMic || missingAccessibility || missingServer {
            let alert = NSAlert()
            alert.messageText = "Setup Incomplete"
            var issues: [String] = []
            if missingMic { issues.append("microphone permission not granted") }
            if missingAccessibility { issues.append("Accessibility permission not granted") }
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
