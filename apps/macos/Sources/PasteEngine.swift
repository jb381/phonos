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

        let savedItems = await MainActor.run {
            let pasteboard = NSPasteboard.general
            let savedItems = snapshotPasteboardItems(pasteboard.pasteboardItems)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return savedItems
        }

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
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let restoredItems = savedItems.map { itemData in
                let item = NSPasteboardItem()
                for (type, data) in itemData {
                    item.setData(data, forType: type)
                }
                return item
            }
            if !restoredItems.isEmpty {
                pasteboard.writeObjects(restoredItems)
            }
        }
    }

    func copyToClipboard(_ text: String) async {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private nonisolated func snapshotPasteboardItems(_ items: [NSPasteboardItem]?) -> [[NSPasteboard.PasteboardType: Data]] {
        items?.compactMap { item in
            var itemData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                }
            }
            return itemData.isEmpty ? nil : itemData
        } ?? []
    }
}
