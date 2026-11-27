import AppKit
import ApplicationServices

final class ShortcutEngine {
    var rules = BindingRule.starter
    var scrollGap = 0.45
    var onAction: ((ShortcutAction, Bool) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let keyboardSource = CGEventSource(stateID: .hidSystemState)
    private let actionQueue = DispatchQueue(label: "local.spacemouse.window-actions")
    private var captured = Set<MouseInput>()
    private var lastScroll: (input: MouseInput, modifier: Modifier, time: Double)?

    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown,
                                    .leftMouseUp, .rightMouseUp, .otherMouseUp,
                                    .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                    .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<ShortcutEngine>.fromOpaque(context).takeUnretainedValue()
            return engine.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: context),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.tap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        captured.removeAll()
        lastScroll = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            captured.removeAll()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard let input = mouseInput(type, event) else { return false }
        switch type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return captured.remove(input) != nil
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return captured.contains(input)
        default: break
        }

        let modifier = Modifier.matching(event.flags)
        // Keep the shortcut editor usable while the app has focus.
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier, let modifier,
              let rule = rules.first(where: { $0.enabled && $0.input == input && $0.modifier == modifier }) else {
            if type == .scrollWheel { lastScroll = nil }
            return false
        }

        if type == .scrollWheel {
            let previous = lastScroll
            lastScroll = (input, modifier, now)
            if let previous, previous.input == input, previous.modifier == modifier,
               now - previous.time < scrollGap { return true }
        } else {
            captured.insert(input)
        }

        if let key = rule.action.key {
            for down in [true, false] {
                let keyEvent = CGEvent(keyboardEventSource: keyboardSource, virtualKey: key, keyDown: down)
                keyEvent?.flags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
                keyEvent?.post(tap: .cghidEventTap)
            }
            DispatchQueue.main.async { [weak self] in self?.onAction?(rule.action, true) }
        } else if let pid {
            actionQueue.async { [weak self] in
                let success = WindowAction.perform(rule.action, pid: pid)
                DispatchQueue.main.async { self?.onAction?(rule.action, success) }
            }
        }
        return true
    }

    private func mouseInput(_ type: CGEventType, _ event: CGEvent) -> MouseInput? {
        switch type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: return .left
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return .right
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            switch event.getIntegerValueField(.mouseEventButtonNumber) {
            case 2: return .middle
            case 3: return .mouse4
            case 4: return .mouse5
            default: return nil
            }
        case .scrollWheel:
            guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return nil }
            let vertical = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            return vertical == 0 ? nil : (vertical > 0 ? .scrollUp : .scrollDown)
        default: return nil
        }
    }
}

enum WindowAction {
    private static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }

    private static func element(_ app: AXUIElement, _ key: String) -> AXUIElement? {
        guard let value = value(app, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func children(_ element: AXUIElement?) -> [AXUIElement] {
        guard let element else { return [] }
        return (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func child(_ parent: AXUIElement?, named title: String) -> AXUIElement? {
        children(parent).first { (value($0, kAXTitleAttribute) as? String) == title }
    }

    static func perform(_ action: ShortcutAction, pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        if action == .fullScreen {
            guard let window = element(app, kAXFocusedWindowAttribute),
                  let fullScreen = value(window, "AXFullScreen") as? Bool else { return false }
            return AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString,
                                                 fullScreen ? kCFBooleanFalse : kCFBooleanTrue) == .success
        }
        guard let title = action.menuTitle else { return false }
        let window = child(element(app, kAXMenuBarAttribute), named: "Window")
        let resize = child(children(window).first, named: "Move & Resize")
        let menu = children(resize).first
        let item = child(menu, named: title) ?? (title == "Center" ? child(menu, named: "Centre") : nil)
        guard let item else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }
}
