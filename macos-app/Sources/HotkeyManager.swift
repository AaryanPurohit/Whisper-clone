import Cocoa

// Top-level C-compatible callback required for CGEventTap
private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.processEvent(type: type, event: event)
}

class HotkeyManager {
    static let shared = HotkeyManager()

    var onToggle: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Double-press detection state
    private var lastPressTime: TimeInterval = 0
    private var modifierWasDown = false
    private let doublePressInterval: TimeInterval = 0.5

    private init() {}

    // MARK: - Public

    func start() {
        requestAccessibilityIfNeeded()
        install()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyChanged),
            name: .hotkeyChanged,
            object: nil
        )
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Private

    @objc private func hotkeyChanged() {
        // Reset double-press state when hotkey changes
        lastPressTime = 0
        modifierWasDown = false
    }

    private func install() {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[HotkeyManager] Failed to create event tap — grant Accessibility access in System Settings.")
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = src
    }

    private func requestAccessibilityIfNeeded() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Event handling

    fileprivate func processEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let hotkey = PreferencesManager.shared.hotkey

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event: event, hotkey: hotkey)
        default:
            return Unmanaged.passRetained(event)
        }
    }

    // Modifier keys (Control, Option, Shift) fire flagsChanged events
    private func handleFlagsChanged(event: CGEvent, hotkey: HotkeyOption) -> Unmanaged<CGEvent>? {
        let flag = hotkey.cgFlag
        let isDown = event.flags.contains(flag)

        if isDown && !modifierWasDown {
            // Key pressed
            modifierWasDown = true
            let now = Date().timeIntervalSince1970
            if now - lastPressTime < doublePressInterval {
                lastPressTime = 0
                modifierWasDown = false
                DispatchQueue.main.async { self.onToggle?() }
            } else {
                lastPressTime = now
            }
        } else if !isDown && modifierWasDown {
            modifierWasDown = false
        }

        return Unmanaged.passRetained(event)
    }

    // Fn key fires keyDown events
}

// MARK: - HotkeyOption helpers

private extension HotkeyOption {
    var cgFlag: CGEventFlags {
        switch self {
        case .control: return .maskControl
        case .option:  return .maskAlternate
        case .shift:   return .maskShift
        }
    }
}
