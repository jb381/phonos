import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var serverStatus = "Unknown"
    @State private var availableModels: [String] = []
    @State private var isChecking = false
    @State private var isScanning = false
    @State private var scanResults: [ScanResult] = []
    @State private var isRecordingHotkey = false
    @State private var hotkeyDisplay = SettingsManager.keyName(for: Int(SettingsManager.shared.hotkeyKeyCode))

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

                HStack {
                    Text("Hotkey")
                    Spacer()
                    if isRecordingHotkey {
                        Text("Press a key…")
                            .foregroundColor(.accentColor)
                    } else {
                        Text(hotkeyDisplay)
                            .foregroundColor(.secondary)
                    }
                    Button(isRecordingHotkey ? "Cancel" : "Record") {
                        isRecordingHotkey.toggle()
                    }
                }
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear {
            fetchModels()
            checkHealth()
        }
        .background(KeyCaptureView(isActive: $isRecordingHotkey) { keyCode in
            settings.hotkeyKeyCode = Int(keyCode)
            hotkeyDisplay = SettingsManager.keyName(for: Int(keyCode))
            isRecordingHotkey = false
            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
        })
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

// MARK: - Key Capture

struct KeyCaptureView: NSViewRepresentable {
    @Binding var isActive: Bool
    let onCapture: (Int64) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        if isActive {
            context.coordinator.startCapturing(nsView)
        } else {
            context.coordinator.stopCapturing()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isActive: $isActive, onCapture: onCapture)
    }

    final class Coordinator {
        @Binding var isActive: Bool
        let onCapture: (Int64) -> Void
        private var monitor: Any?

        init(isActive: Binding<Bool>, onCapture: @escaping (Int64) -> Void) {
            self._isActive = isActive
            self.onCapture = onCapture
        }

        func startCapturing(_ view: KeyCaptureNSView) {
            stopCapturing()
            view.window?.makeFirstResponder(view)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self else { return event }
                let code = Int64(event.keyCode)
                // Only capture on keyDown, or flagsChanged with non-zero keyCode (modifier press)
                if event.type == .keyDown || (event.type == .flagsChanged && code != 0) {
                    DispatchQueue.main.async {
                        self.onCapture(code)
                        self.isActive = false
                    }
                    return nil
                }
                return nil
            }
        }

        func stopCapturing() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

final class KeyCaptureNSView: NSView {
    weak var coordinator: KeyCaptureView.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        // Add a subtle visual indicator (focus ring)
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return true
    }

    override func resignFirstResponder() -> Bool {
        layer?.borderWidth = 0
        return true
    }
}
