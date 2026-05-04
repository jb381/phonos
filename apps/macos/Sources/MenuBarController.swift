import Cocoa
import SwiftUI

final class MenuBarController: NSObject, HotkeyManagerDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let recorder = AudioRecorder()
    private let paster = PasteEngine()
    private var hotkeyManager: HotkeyManager?
    private let settings = SettingsManager.shared

    override init() {
        super.init()
        setupMenuBar()
        setupHotkey()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Phonos")
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let statusItem = NSMenuItem(title: "Server: checking...", action: nil, keyEquivalent: "")
        menu.addItem(statusItem)

        menu.addItem(.separator())

        let recordItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "r")
        recordItem.target = self
        menu.addItem(recordItem)

        let pasteItem = NSMenuItem(title: "Paste Last Transcript", action: #selector(pasteLast), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = [.command, .shift]
        pasteItem.target = self
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu

        // Update status asynchronously
        Task {
            await updateConnectionStatus(statusItem)
        }
    }

    private func updateConnectionStatus(_ item: NSMenuItem) async {
        do {
            let health = try await ServerClient().healthCheck()
            await MainActor.run {
                item.title = "Server: \(health.model) (\(health.device))"
            }
        } catch {
            await MainActor.run {
                item.title = "Server: offline"
            }
        }
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager = HotkeyManager()
        hotkeyManager?.delegate = self
        if !(hotkeyManager?.start() ?? false) {
            showAccessibilityAlert()
        }
    }

    func hotkeyDidPress() {
        if settings.recordingMode == "toggle" {
            Task { await toggleRecordingViaHotkey() }
        } else {
            Task { await startRecordingViaHotkey() }
        }
    }

    func hotkeyDidRelease() {
        if settings.recordingMode == "hold" {
            Task { await stopAndTranscribe() }
        }
    }

    // MARK: - Recording

    private var lastTranscript = ""
    private var isRecording = false

    @objc private func toggleRecording() {
        Task { await toggleRecordingViaHotkey() }
    }

    private func toggleRecordingViaHotkey() async {
        if isRecording {
            await stopAndTranscribe()
        } else {
            await startRecordingViaHotkey()
        }
    }

    private func startRecordingViaHotkey() async {
        guard !isRecording else { return }
        do {
            _ = try await recorder.startRecording()
            isRecording = true
            await updateRecordingUI(true)
        } catch {
            showError(error)
        }
    }

    private func stopAndTranscribe() async {
        guard isRecording else { return }
        await recorder.stopRecording()
        isRecording = false
        await updateRecordingUI(false)

        guard let fileURL = await recorder.getOutputURL() else { return }

        do {
            let result = try await ServerClient().transcribe(fileURL: fileURL)
            lastTranscript = result.text

            try? await Task.sleep(nanoseconds: 100_000_000)

            do {
                try await paster.pasteText(result.text)
            } catch {
                await paster.copyToClipboard(result.text)
                await showTranscript(result.text)
            }
        } catch {
            showError(error)
        }
    }

    @objc private func pasteLast() {
        Task {
            if lastTranscript.isEmpty {
                NSSound.beep()
                return
            }
            do {
                try await paster.pasteText(lastTranscript)
            } catch {
                await paster.copyToClipboard(lastTranscript)
            }
        }
    }

    // MARK: - UI Helpers

    @MainActor
    private func updateRecordingUI(_ recording: Bool) {
        if recording {
            statusItem?.button?.image = NSImage(
                systemSymbolName: "mic.circle.fill",
                accessibilityDescription: "Recording"
            )
        } else {
            statusItem?.button?.image = NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: "Phonos"
            )
        }

        if let menu = statusItem?.menu {
            for item in menu.items where item.action == #selector(toggleRecording) {
                item.title = recording ? "Stop Recording" : "Start Recording"
            }
        }
    }

    @MainActor
    private func showTranscript(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Transcription"
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showError(_ error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func showAccessibilityAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Required"
            alert.informativeText = "Phonos needs Accessibility permission for global hotkey and paste. Grant it in System Settings → Privacy & Security → Accessibility."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {}

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quitApp() {
        hotkeyManager?.stop()
        NSApplication.shared.terminate(nil)
    }
}
