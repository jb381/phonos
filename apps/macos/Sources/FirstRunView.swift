import AVFoundation
import Cocoa
import SwiftUI

struct FirstRunView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    @State private var serverStatus = "Not checked"
    @State private var isCheckingServer = false
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
                    Text(serverStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Connection") { checkServer() }
                        .disabled(isCheckingServer)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    settings.firstRunCompleted = true
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460, height: 430)
        .onAppear {
            refreshPermissions()
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(serverStatus.lowercased() == "ok" ? Color.green : Color.secondary)
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

    private func checkServer() {
        isCheckingServer = true
        Task {
            do {
                let health = try await ServerClient().healthCheck()
                await MainActor.run {
                    serverStatus = health.status
                    isCheckingServer = false
                }
            } catch {
                await MainActor.run {
                    serverStatus = error.localizedDescription
                    isCheckingServer = false
                }
            }
        }
    }
}
