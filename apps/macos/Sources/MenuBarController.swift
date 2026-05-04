import Cocoa
import SwiftUI

@MainActor
final class MenuBarController: NSObject, HotkeyManagerDelegate {
    private var statusItem: NSStatusItem?
    private let recorder = AudioRecorder()
    private let paster = PasteEngine()
    private var hotkeyManager: HotkeyManager?
    private let settings = SettingsManager.shared
    private let history = TranscriptHistoryStore.shared
    private let recentMenu = NSMenu()
    private var lastPasteTargetBundleID: String?

    override init() {
        super.init()
        startTrackingPasteTarget()
        setupMenuBar()
        setupHotkey()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func startTrackingPasteTarget() {
        updatePasteTarget(from: NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func activeApplicationChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        updatePasteTarget(from: app)
    }

    private func updatePasteTarget(from app: NSRunningApplication?) {
        guard let bundleIdentifier = app?.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier,
              bundleIdentifier != "com.apple.systemuiserver"
        else { return }

        lastPasteTargetBundleID = bundleIdentifier
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Phonos")
        }
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "Server: checking...", action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        let recordItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "r")
        recordItem.target = self
        menu.addItem(recordItem)

        let pasteItem = NSMenuItem(title: "Paste Last Transcript", action: #selector(pasteLast), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = [.command, .shift]
        pasteItem.target = self
        menu.addItem(pasteItem)

        let historyItem = NSMenuItem(title: "History...", action: #selector(openHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let recentItem = NSMenuItem(title: "Recent Transcripts", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)
        refreshRecentMenu()

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

        Task {
            await updateConnectionStatus(statusMenuItem)
        }
    }

    @MainActor
    private func updateConnectionStatus(_ item: NSMenuItem) async {
        do {
            let health = try await ServerClient().healthCheck()
            item.title = "Server: \(health.model) (\(health.device))"
        } catch {
            item.title = "Server: offline"
        }
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        startHotkey()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeySettingChanged),
            name: .hotkeyChanged,
            object: nil
        )
    }

    @objc private func hotkeySettingChanged() {
        hotkeyManager?.stop()
        startHotkey()
    }

    private func startHotkey() {
        hotkeyManager = HotkeyManager(targetKeyCode: CGKeyCode(settings.hotkeyKeyCode))
        hotkeyManager?.delegate = self
        if hotkeyManager?.start() ?? false {
        } else if !AXIsProcessTrusted(),
                  !UserDefaults.standard.bool(forKey: "accessibility_alert_shown") {
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
            updateRecordingUI(true)
        } catch {
            showError(error)
        }
    }

    private func stopAndTranscribe() async {
        guard isRecording else { return }
        await recorder.stopRecording()
        isRecording = false
        updateRecordingUI(false)

        guard let fileURL = await recorder.getOutputURL() else { return }
        let pasteTargetBundleID = lastPasteTargetBundleID

        do {
            let result = try await ServerClient().transcribe(fileURL: fileURL)
            lastTranscript = result.text
            await MainActor.run {
                history.add(result.text)
                refreshRecentMenu()
            }

            guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            try? await Task.sleep(nanoseconds: 100_000_000)
            reactivatePasteTarget(bundleIdentifier: pasteTargetBundleID)
            try? await Task.sleep(nanoseconds: 150_000_000)

            do {
                try await paster.pasteText(result.text)
            } catch PasteError.accessibilityDenied {
                await paster.copyToClipboard(result.text)
                showAccessibilityAlert()
            } catch {
                await paster.copyToClipboard(result.text)
            }
        } catch {
            showError(error)
        }
    }

    private func reactivatePasteTarget(bundleIdentifier: String?) {
        guard let bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier })
        else { return }

        app.activate(options: [])
    }

    @objc private func pasteLast() {
        Task {
            if lastTranscript.isEmpty {
                NSSound.beep()
                return
            }
            do {
                try await paster.pasteText(lastTranscript)
            } catch PasteError.accessibilityDenied {
                await paster.copyToClipboard(lastTranscript)
                showAccessibilityAlert()
            } catch {
                await paster.copyToClipboard(lastTranscript)
            }
        }
    }

    // MARK: - UI Helpers

    @MainActor
    private func updateRecordingUI(_ recording: Bool) {
        statusItem?.button?.image = NSImage(
            systemSymbolName: recording ? "mic.circle.fill" : "mic.fill",
            accessibilityDescription: "Phonos"
        )

        if let menu = statusItem?.menu {
            for item in menu.items where item.action == #selector(toggleRecording) {
                item.title = recording ? "Stop Recording" : "Start Recording"
            }
        }
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
            UserDefaults.standard.set(true, forKey: "accessibility_alert_shown")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    // MARK: - Actions

    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?

    @MainActor
    private func refreshRecentMenu() {
        recentMenu.removeAllItems()

        if history.entries.isEmpty {
            let item = NSMenuItem(title: "No transcripts yet", action: nil, keyEquivalent: "")
            item.isEnabled = false
            recentMenu.addItem(item)
            return
        }

        for entry in history.entries.prefix(5) {
            let title = entry.text.replacingOccurrences(of: "\n", with: " ")
            let item = NSMenuItem(title: String(title.prefix(70)), action: #selector(copyTranscriptFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.text
            recentMenu.addItem(item)
        }
    }

    @objc private func copyTranscriptFromMenu(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func openHistory() {
        if let window = historyWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Phonos History"
        window.center()
        window.contentView = NSHostingView(rootView: TranscriptHistoryView(store: history))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyWindow = window
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Phonos Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func quitApp() {
        hotkeyManager?.stop()
        NSApplication.shared.terminate(nil)
    }
}
