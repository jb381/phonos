import Cocoa
import Carbon

enum HotkeyMode {
    case hold
    case toggle
}

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyDidPress()
    func hotkeyDidRelease()
}

final class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    private let targetKeyCode: CGKeyCode

    var mode: HotkeyMode = .hold

    init(targetKeyCode: CGKeyCode = 0x3B) {
        self.targetKeyCode = targetKeyCode
    }

    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { (_, type, event, refcon) in
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
            return manager.handleEvent(type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = eventTap else { return false }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(targetKeyCode) else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            if !isKeyDown {
                isKeyDown = true
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidPress()
                }
                if mode == .hold {
                    return nil
                }
            }
        case .keyUp:
            isKeyDown = false
            if mode == .hold {
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidRelease()
                }
            }
            return nil
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }
}
