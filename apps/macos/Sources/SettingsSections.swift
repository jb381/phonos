import SwiftUI

private let settingsLabelWidth: CGFloat = 112

enum SettingsSectionMode {
    case settings
    case setup
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if title.isEmpty {
                Spacer()
                    .frame(width: settingsLabelWidth)
            } else {
                Text(title)
                    .frame(width: settingsLabelWidth, alignment: .trailing)
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension View {
    func settingsControlWidth(_ width: CGFloat) -> some View {
        frame(width: width, alignment: .leading)
    }
}

struct ConnectionSettingsSection: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var viewModel: ServerSettingsViewModel
    let mode: SettingsSectionMode
    let onCheckConnection: () -> Void
    let onScanNetwork: (() -> Void)?
    let isScanning: Bool
    let scanResults: [ScanResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow(title: "Server URL") {
                TextField("", text: $settings.serverURL)
                    .frame(maxWidth: .infinity)
            }

            SettingsRow(title: "") {
                HStack(spacing: 6) {
                    statusDot
                    statusDescription
                }
            }

            SettingsRow(title: "Auth Token") {
                SecureField("", text: $settings.authToken)
                    .frame(maxWidth: .infinity)
            }

            if let error = settings.authTokenStorageError {
                SettingsRow(title: "") {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsRow(title: "") {
                HStack(spacing: 10) {
                    Button("Check Connection") { onCheckConnection() }
                        .disabled(viewModel.isChecking)

                    if mode == .settings, let onScanNetwork {
                        Button("Scan Network") { onScanNetwork() }
                            .disabled(isScanning)
                    }

                    if viewModel.isChecking {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking\u{2026}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning\u{2026}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if mode == .settings, !scanResults.isEmpty && !isScanning {
                SettingsRow(title: "Found server") {
                    Picker("", selection: $settings.serverURL) {
                        ForEach(scanResults) { result in
                            Text(result.display).tag(result.url)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch connectionState {
        case .connected: return .green
        case .loading: return .orange
        case .error, .unavailable: return .red
        case .notChecked: return .secondary
        }
    }

    private var statusDescription: some View {
        Group {
            if viewModel.isChecking {
                Text("Checking\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if connectionState == .notChecked {
                Text("Not checked yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if connectionState == .connected {
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if connectionState == .loading {
                Text("Loading model")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if connectionState == .error {
                Text(viewModel.serverStatus)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(viewModel.serverStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private enum ConnectionState {
        case connected, loading, error, unavailable, notChecked
    }

    private var connectionState: ConnectionState {
        let status = viewModel.serverStatus.lowercased()
        if status == "ok" { return .connected }
        if status == "loading" { return .loading }
        if status == "unknown" || status.isEmpty { return .notChecked }
        if status.hasPrefix("model:") { return .connected }
        return .error
    }
}

struct ModelSettingsSection: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var viewModel: ServerSettingsViewModel
    let showsRefresh: Bool
    let onRefreshModels: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow(title: "Model") {
                Picker("", selection: $settings.selectedModel) {
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .settingsControlWidth(180)
                .onChange(of: settings.selectedModel) { _, newModel in
                    guard !viewModel.isSyncingModelSelection else { return }
                    viewModel.setModel(newModel)
                }
            }

            SettingsRow(title: "") {
                Text(ModelCatalog.description(for: settings.selectedModel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsRefresh {
                SettingsRow(title: "") {
                    Button("Refresh Models") { onRefreshModels?() }
                }
            }
        }
    }

    private var modelOptions: [String] {
        viewModel.availableModels.isEmpty ? [settings.selectedModel] : viewModel.availableModels
    }
}
