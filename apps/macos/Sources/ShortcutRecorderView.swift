import AppKit
import Carbon.HIToolbox
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
        title = KeyboardShortcuts.getShortcut(for: shortcutName).map(Self.displayString(for:)) ?? "Record Shortcut"
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

    private static func displayString(for shortcut: KeyboardShortcuts.Shortcut) -> String {
        var value = ""
        let modifiers = shortcut.modifiers

        if modifiers.contains(.control) {
            value += "^"
        }
        if modifiers.contains(.option) {
            value += "Option-"
        }
        if modifiers.contains(.shift) {
            value += "Shift-"
        }
        if modifiers.contains(.command) {
            value += "Command-"
        }

        return value + keyDisplayName(for: shortcut.carbonKeyCode)
    }

    private static func keyDisplayName(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Escape"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_LeftArrow: return "Left"
        case kVK_RightArrow: return "Right"
        case kVK_UpArrow: return "Up"
        case kVK_DownArrow: return "Down"
        case kVK_F1...kVK_F20: return functionKeyDisplayName(for: keyCode)
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        default: return "Key \(keyCode)"
        }
    }

    private static func functionKeyDisplayName(for keyCode: Int) -> String {
        let functionKeys: [Int: String] = [
            kVK_F1: "F1",
            kVK_F2: "F2",
            kVK_F3: "F3",
            kVK_F4: "F4",
            kVK_F5: "F5",
            kVK_F6: "F6",
            kVK_F7: "F7",
            kVK_F8: "F8",
            kVK_F9: "F9",
            kVK_F10: "F10",
            kVK_F11: "F11",
            kVK_F12: "F12",
            kVK_F13: "F13",
            kVK_F14: "F14",
            kVK_F15: "F15",
            kVK_F16: "F16",
            kVK_F17: "F17",
            kVK_F18: "F18",
            kVK_F19: "F19",
            kVK_F20: "F20"
        ]
        return functionKeys[keyCode] ?? "Key \(keyCode)"
    }
}
