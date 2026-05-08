import Cocoa
import SwiftUI

enum WorkflowStatus: String, CaseIterable {
    case idle = "Idle"
    case recording = "Recording"
    case transcribing = "Transcribing"
    case pasting = "Pasting"
    case pasted = "Pasted"
    case copiedToClipboard = "Copied to Clipboard"
    case error = "Error"

    var isBusy: Bool {
        switch self {
        case .recording, .transcribing, .pasting:
            return true
        default:
            return false
        }
    }

    var userFacingTitle: String {
        switch self {
        case .idle: return "Ready"
        case .recording: return "Recording\u{2026}"
        case .transcribing: return "Transcribing\u{2026}"
        case .pasting: return "Pasting\u{2026}"
        case .pasted: return "Pasted"
        case .copiedToClipboard: return "Copied to Clipboard"
        case .error: return "Error"
        }
    }

    var isSuccess: Bool {
        self == .pasted || self == .copiedToClipboard
    }
}

@MainActor
final class MenuBarController: NSObject, NSWindowDelegate, HotkeyManagerDelegate, RecordingSessionDelegate {
    private var statusItem: NSStatusItem?
    private let session = RecordingSession()
    private var hotkeyManager: HotkeyManager?
    private let settings = SettingsManager.shared
    private let history = TranscriptHistoryStore.shared
    private let recentMenu = NSMenu()
    private let workflowStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let lastErrorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var lastPasteTargetBundleID: String?
    private var isProcessing = false

    private var recordItem: NSMenuItem!
    private var pasteItem: NSMenuItem!
    private var historyItem: NSMenuItem!

    private var successResetTimer: DispatchSourceTimer?
    private var lastStatusForReset: WorkflowStatus?

    override init() {
        super.init()
        Task { await session.setDelegate(self) }
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
        successResetTimer?.cancel()
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
            button.image = menuBarImage(named: "PhonosMenuBarIdleTemplate", description: "Idle")
        }
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        workflowStatusItem.isEnabled = false
        workflowStatusItem.isHidden = true
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

        historyItem = NSMenuItem(title: "History\u{2026}", action: #selector(openHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let recentItem = NSMenuItem(title: "Recent Transcripts", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)
        refreshRecentMenu()

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = menuSymbol(["gearshape", "gear"], description: "Settings")
        menu.addItem(settingsItem)

        let setupItem = NSMenuItem(title: setupMenuItemTitle, action: #selector(openSetup), keyEquivalent: "")
        setupItem.target = self
        setupItem.image = menuSymbol(["checklist", "checkmark.circle"], description: "Setup Assistant")
        menu.addItem(setupItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private var setupMenuItemTitle: String {
        settings.firstRunCompleted ? "Setup Assistant\u{2026}" : "Setup\u{2026}"
    }

    private func menuBarImage(named name: String, description: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "terminal", accessibilityDescription: description)
        }
        image.accessibilityDescription = description
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private func menuSymbol(_ names: [String], description: String) -> NSImage? {
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: description) {
                image.isTemplate = true
                return image
            }
        }
        return nil
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
            Task { await session.toggleRecording(pasteTargetBundleID: lastPasteTargetBundleID) }
        } else {
            Task { await session.start() }
        }
    }

    func hotkeyDidRelease() {
        if settings.recordingMode == "hold" {
            Task { await session.stop(pasteTargetBundleID: lastPasteTargetBundleID) }
        }
    }

    // MARK: - Recording

    private var lastTranscript = ""
    private var isRecording = false

    @objc private func toggleRecording() {
        Task { await session.toggleRecording(pasteTargetBundleID: lastPasteTargetBundleID) }
    }

    private func toggleRecordingViaHotkey() async {
        await session.toggleRecording(pasteTargetBundleID: lastPasteTargetBundleID)
    }

    private func startRecordingViaHotkey() async {
        await session.start()
    }

    private func stopAndTranscribe() async {
        await session.stop(pasteTargetBundleID: lastPasteTargetBundleID)
    }

    @objc private func pasteLast() {
        Task {
            if lastTranscript.isEmpty {
                NSSound.beep()
                return
            }
            await session.pasteLastTranscript(lastTranscript)
        }
    }

    // MARK: - RecordingSessionDelegate

    func recordingSession(_ session: RecordingSession, didUpdate status: WorkflowStatus) {
        updateWorkflowStatus(status)
        if status == .recording {
            isRecording = true
            updateRecordingUI(true)
        } else if status != .transcribing && status != .pasting {
            isRecording = false
            updateRecordingUI(false)
        }
    }

    func recordingSession(_ session: RecordingSession, didReceive transcript: String) {
        lastTranscript = transcript
        history.add(transcript)
        refreshRecentMenu()
    }

    func recordingSession(_ session: RecordingSession, didFailWith error: Error) {
        if case PasteError.accessibilityDenied = error {
            showAccessibilityAlert()
            return
        }
        let message = error.localizedDescription
        if message.contains("Timed out") {
            showLastError("Timed out. Try a smaller model (Settings \u{2192} Model) or increase server timeout.")
        } else {
            showLastError(message)
        }
        showError(error)
    }

    // MARK: - UI Helpers

    @MainActor
    private func updateRecordingUI(_ recording: Bool) {
        let button = statusItem?.button
        if recording {
            button?.image = menuBarImage(named: "PhonosMenuBarRecordingTemplate", description: "Recording")
            button?.wantsLayer = true
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.3
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            button?.layer?.add(pulse, forKey: "pulse")
        } else {
            button?.image = menuBarImage(named: "PhonosMenuBarIdleTemplate", description: "Idle")
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
    private func updateWorkflowStatus(_ status: WorkflowStatus) {
        workflowStatusItem.title = status.userFacingTitle
        workflowStatusItem.isHidden = status == .idle

        let busy = status.isBusy
        if busy != isProcessing {
            isProcessing = busy
            setActionsEnabled(!busy)
        }

        if status.isSuccess {
            cancelSuccessReset()
            lastStatusForReset = status
            scheduleSuccessReset(status)
        }

        if !status.isSuccess {
            cancelSuccessReset()
            lastStatusForReset = nil
        }

        if status == .idle || status.isSuccess {
            hideLastError()
        }
    }

    private func scheduleSuccessReset(_ status: WorkflowStatus) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 3)
        timer.setEventHandler { [weak self] in
            guard let self, self.lastStatusForReset == status else { return }
            self.lastStatusForReset = nil
            self.updateWorkflowStatus(.idle)
        }
        timer.resume()
        successResetTimer = timer
    }

    private func cancelSuccessReset() {
        successResetTimer?.cancel()
        successResetTimer = nil
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
            alert.informativeText = "Phonos needs Accessibility permission for paste automation. Grant it in System Settings \u{2192} Privacy & Security \u{2192} Accessibility."
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
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
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
