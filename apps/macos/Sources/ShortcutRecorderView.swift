import AppKit
import KeyboardShortcuts
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let onChange: (KeyboardShortcuts.Shortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(name: name)
        button.onChange = onChange
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        nsView.shortcutName = name
        nsView.onChange = onChange
        nsView.refreshTitle()
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcutName: KeyboardShortcuts.Name {
        didSet { refreshTitle() }
    }

    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?
    private var eventMonitor: Any?

    init(name: KeyboardShortcuts.Name) {
        self.shortcutName = name
        super.init(frame: NSRect(x: 0, y: 0, width: 130, height: 24))
        title = ""
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 130, height: 24)
    }

    func refreshTitle() {
        title = KeyboardShortcuts.getShortcut(for: shortcutName).map(String.init(describing:)) ?? "Record Shortcut"
    }

    @objc private func startRecording() {
        guard eventMonitor == nil else { return }
        title = "Press Shortcut"
        window?.makeFirstResponder(self)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        defer { stopRecording() }

        if event.keyCode == 53 {
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            KeyboardShortcuts.setShortcut(nil, for: shortcutName)
            onChange?(nil)
            return
        }

        guard let shortcut = KeyboardShortcuts.Shortcut(event: event),
              !shortcut.modifiers.intersection([.command, .option, .control, .shift]).isEmpty
        else {
            NSSound.beep()
            return
        }

        KeyboardShortcuts.setShortcut(shortcut, for: shortcutName)
        onChange?(shortcut)
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        refreshTitle()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
