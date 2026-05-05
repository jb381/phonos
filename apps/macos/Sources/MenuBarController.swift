import Cocoa
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSWindowDelegate, HotkeyManagerDelegate {
    private var statusItem: NSStatusItem?
    private let recorder = AudioRecorder()
    private let paster = PasteEngine()
    private var hotkeyManager: HotkeyManager?
    private let settings = SettingsManager.shared
    private let history = TranscriptHistoryStore.shared
    private let recentMenu = NSMenu()
    private let workflowStatusItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
    private let lastErrorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var lastPasteTargetBundleID: String?
    private var isProcessing = false

    private var recordItem: NSMenuItem!
    private var pasteItem: NSMenuItem!
    private var historyItem: NSMenuItem!

    override init() {
        super.init()
        startTrackingPasteTarget()
        setupMenuBar()
        setupHotkey()
        if !settings.firstRunCompleted {
            DispatchQueue.main.async { [weak self] in
                self?.openSetup()
            }
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
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
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Idle")
            button.image?.isTemplate = true
        }
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        workflowStatusItem.isEnabled = false
        menu.addItem(workflowStatusItem)

        lastErrorItem.isEnabled = false
        lastErrorItem.isHidden = true
        menu.addItem(lastErrorItem)

        menu.addItem(.separator())

        recordItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "r")
        recordItem.target = self
        menu.addItem(recordItem)

        pasteItem = NSMenuItem(title: "Paste Last Transcript", action: #selector(pasteLast), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = [.command, .shift]
        pasteItem.target = self
        menu.addItem(pasteItem)

        historyItem = NSMenuItem(title: "History...", action: #selector(openHistory), keyEquivalent: "h")
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

        let setupItem = NSMenuItem(title: "Setup...", action: #selector(openSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        startHotkey()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(recordShortcutChanged),
            name: .recordShortcutChanged,
            object: nil
        )
    }

    @objc private func recordShortcutChanged() {
        hotkeyManager?.stop()
        startHotkey()
    }

    private func startHotkey() {
        hotkeyManager = HotkeyManager()
        hotkeyManager?.delegate = self
        _ = hotkeyManager?.start()
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
            updateWorkflowStatus("Recording")
        } catch {
            updateWorkflowStatus("Error")
            showError(error)
        }
    }

    private func stopAndTranscribe() async {
        guard isRecording else { return }

        let recordedURL = await recorder.getOutputURL()
        defer {
            if let url = recordedURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        do {
            try await recorder.stopRecording()
        } catch {
            isRecording = false
            updateRecordingUI(false)
            updateWorkflowStatus("Error")
            showError(error)
            return
        }
        isRecording = false
        updateRecordingUI(false)
        updateWorkflowStatus("Transcribing")

        guard let captureURL = recordedURL else {
            updateWorkflowStatus("Idle")
            return
        }
        let pasteTargetBundleID = lastPasteTargetBundleID

        do {
            let result = try await ServerClient().transcribe(fileURL: captureURL)
            lastTranscript = result.text
            await MainActor.run {
                history.add(result.text)
                refreshRecentMenu()
            }

            guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                updateWorkflowStatus("Idle")
                return
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
            reactivatePasteTarget(bundleIdentifier: pasteTargetBundleID)
            try? await Task.sleep(nanoseconds: 150_000_000)

            do {
                updateWorkflowStatus("Pasting")
                try await paster.pasteText(result.text)
                updateWorkflowStatus("Pasted")
            } catch PasteError.accessibilityDenied {
                await paster.copyToClipboard(result.text)
                updateWorkflowStatus("Copied to Clipboard")
                showAccessibilityAlert()
            } catch {
                await paster.copyToClipboard(result.text)
                updateWorkflowStatus("Copied to Clipboard")
            }
        } catch {
            updateWorkflowStatus("Error")
            let message = error.localizedDescription
            if message.contains("Timed out") {
                showLastError("Timed out. Try a smaller model (Settings → Model) or increase server timeout.")
            } else {
                showLastError(message)
            }
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
                updateWorkflowStatus("Pasted")
            } catch PasteError.accessibilityDenied {
                await paster.copyToClipboard(lastTranscript)
                updateWorkflowStatus("Copied to Clipboard")
                showAccessibilityAlert()
            } catch {
                await paster.copyToClipboard(lastTranscript)
                updateWorkflowStatus("Copied to Clipboard")
            }
        }
    }

    // MARK: - UI Helpers

    @MainActor
    private func updateRecordingUI(_ recording: Bool) {
        let button = statusItem?.button
        if recording {
            button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            button?.image?.isTemplate = true
            button?.wantsLayer = true
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.3
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            button?.layer?.add(pulse, forKey: "pulse")
        } else {
            button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Idle")
            button?.image?.isTemplate = true
            button?.layer?.removeAnimation(forKey: "pulse")
            button?.layer?.opacity = 1.0
        }

        if let menu = statusItem?.menu {
            for item in menu.items where item.action == #selector(toggleRecording) {
                item.title = recording ? "Stop Recording" : "Start Recording"
            }
        }
    }

    private func showError(_ error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            showLastError(message)
        }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @MainActor
    private func updateWorkflowStatus(_ status: String) {
        workflowStatusItem.title = "Status: \(status)"
        let busy = (status == "Recording" || status == "Transcribing" || status == "Pasting")
        if busy != isProcessing {
            isProcessing = busy
            setActionsEnabled(!busy)
        }
        if status == "Idle" || status == "Pasted" || status == "Copied to Clipboard" {
            hideLastError()
        }
    }

    @MainActor
    private func setActionsEnabled(_ enabled: Bool) {
        recordItem?.isEnabled = enabled
        pasteItem?.isEnabled = enabled
        historyItem?.isEnabled = enabled
    }

    @MainActor
    private func showLastError(_ message: String) {
        lastErrorItem.title = "Last Error: \(message)"
        lastErrorItem.isHidden = false
    }

    @MainActor
    private func hideLastError() {
        lastErrorItem.title = ""
        lastErrorItem.isHidden = true
    }

    private func showAccessibilityAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Required"
            alert.informativeText = "Phonos needs Accessibility permission for paste automation. Grant it in System Settings → Privacy & Security → Accessibility."
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
    private var setupWindow: NSWindow?

    private func showUtilityWindow(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreAccessoryPolicyIfNeeded() {
        guard settingsWindow?.isVisible != true,
              historyWindow?.isVisible != true,
              setupWindow?.isVisible != true
        else { return }

        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
        } else if notification.object as? NSWindow === historyWindow {
            historyWindow = nil
        } else if notification.object as? NSWindow === setupWindow {
            setupWindow = nil
        }

        restoreAccessoryPolicyIfNeeded()
    }

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
            showUtilityWindow(window)
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
        window.delegate = self
        showUtilityWindow(window)
        historyWindow = window
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            showUtilityWindow(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Phonos Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.delegate = self
        showUtilityWindow(window)
        settingsWindow = window
    }

    @objc private func openSetup() {
        if let window = setupWindow {
            showUtilityWindow(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Phonos Setup"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: FirstRunView { [weak window] in
            window?.close()
        })
        showUtilityWindow(window)
        setupWindow = window
    }

    @objc private func quitApp() {
        hotkeyManager?.stop()
        NSApplication.shared.terminate(nil)
    }
}
