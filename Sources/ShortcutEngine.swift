import AppKit
import ApplicationServices

enum EventRouting: Equatable {
    case pass
    case swallow
    case run(ShortcutAction, target: pid_t)
}

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
            lastScroll = nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        switch route(type, event, target: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                     at: ProcessInfo.processInfo.systemUptime) {
        case .pass: return false
        case .swallow: return true
        case let .run(action, target):
            if let key = action.key {
                let events = keyEvents(for: key)
                for event in events { event.post(tap: .cghidEventTap) }
                DispatchQueue.main.async { [weak self] in self?.onAction?(action, events.count == 2) }
            } else {
                actionQueue.async { [weak self] in
                    let success = WindowAction.perform(action, pid: target)
                    DispatchQueue.main.async { self?.onAction?(action, success) }
                }
            }
            return true
        }
    }

    func route(_ type: CGEventType, _ event: CGEvent, target: @autoclosure () -> pid_t?, at now: Double) -> EventRouting {
        guard let input = mouseInput(type, event) else { return .pass }
        switch type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return captured.remove(input) == nil ? .pass : .swallow
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return captured.contains(input) ? .swallow : .pass
        default: break
        }

        // The editor receives normal mouse input while Brume has focus.
        guard let modifier = Modifier.matching(event.flags),
              let rule = rules.first(where: { $0.enabled && $0.input == input && $0.modifier == modifier }),
              let target = target(), target != ProcessInfo.processInfo.processIdentifier else {
            if type == .scrollWheel { lastScroll = nil }
            return .pass
        }

        if type == .scrollWheel {
            let previous = lastScroll
            lastScroll = (input, modifier, now)
            if let previous, previous.input == input, previous.modifier == modifier,
               now - previous.time < scrollGap { return .swallow }
        } else {
            captured.insert(input)
        }
        return .run(rule.action, target: target)
    }

    func keyEvents(for key: CGKeyCode) -> [CGEvent] {
        [true, false].compactMap { down in
            let event = CGEvent(keyboardEventSource: keyboardSource, virtualKey: key, keyDown: down)
            event?.flags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
            return event
        }
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
        guard let item = menuItem(action, in: app) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    static func menuItem(_ action: ShortcutAction, in app: AXUIElement) -> AXUIElement? {
        guard let title = action.menuTitle else { return nil }
        let window = child(element(app, kAXMenuBarAttribute), named: "Window")
        let windowMenu = children(window).first
        let resize = child(windowMenu, named: "Move & Resize")
        let resizeMenu = children(resize).first
        return child(windowMenu, named: title) ?? child(resizeMenu, named: title)
            ?? (title == "Center" ? child(windowMenu, named: "Centre") ?? child(resizeMenu, named: "Centre") : nil)
    }
}
