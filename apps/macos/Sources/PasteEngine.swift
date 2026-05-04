import Cocoa

enum PasteError: LocalizedError {
    case accessibilityDenied
    case pasteFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied: return "Accessibility permission required for paste"
        case .pasteFailed: return "Paste operation failed"
        }
    }
}

actor PasteEngine {
    func pasteText(_ text: String) async throws {
        guard AXIsProcessTrusted() else {
            throw PasteError.accessibilityDenied
        }

        let savedPasteboard = NSPasteboard.general.string(forType: .string)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let vKey = CGKeyCode(0x09)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            if let saved = savedPasteboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(saved, forType: .string)
            }
            throw PasteError.pasteFailed
        }

        down.flags = .maskCommand
        up.flags = .maskCommand

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        try? await Task.sleep(nanoseconds: 300_000_000)

        if let saved = savedPasteboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(saved, forType: .string)
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
