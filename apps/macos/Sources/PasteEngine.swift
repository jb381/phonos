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

        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try? await Task.sleep(nanoseconds: 300_000_000)

        let source = CGEventSource(stateID: .hidSystemState)
        let vKey = CGKeyCode(0x09)

        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            throw PasteError.pasteFailed
        }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        vDown.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 50_000_000)
        vUp.post(tap: .cghidEventTap)

        // Restore previous clipboard contents after a short delay.
        try? await Task.sleep(nanoseconds: 300_000_000)
        pasteboard.clearContents()
        if let savedItems = savedItems, !savedItems.isEmpty {
            pasteboard.writeObjects(savedItems)
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
