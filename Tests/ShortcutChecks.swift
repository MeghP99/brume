import AppKit
import CoreGraphics

@main
struct ShortcutChecks {
    private static let target = ProcessInfo.processInfo.processIdentifier + 1

    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    private static func mouse(_ type: CGEventType, button: CGMouseButton, flags: CGEventFlags,
                              number: Int64? = nil) -> CGEvent {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero,
                            mouseButton: button)!
        event.flags = flags
        if let number { event.setIntegerValueField(.mouseEventButtonNumber, value: number) }
        return event
    }

    private static func scroll(_ delta: Int32, flags: CGEventFlags = .maskControl,
                               units: CGScrollEventUnit = .line, horizontal: Int32 = 0) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2,
                            wheel1: delta, wheel2: horizontal, wheel3: 0)!
        event.flags = flags
        return event
    }

    private static func clickChecks() throws {
        let engine = ShortcutEngine()
        let clicks: [(String, CGEventFlags, CGEventType, CGEventType, CGEventType, CGMouseButton, ShortcutAction)] = [
            ("Control + left-click", .maskControl, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .left, .tileLeft),
            ("Control + right-click", .maskControl, .rightMouseDown, .rightMouseUp, .rightMouseDragged, .right, .tileRight),
            ("Control + middle-click", .maskControl, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .center, .fullScreen),
            ("Option + left-click", .maskAlternate, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .left, .tileTop),
            ("Option + right-click", .maskAlternate, .rightMouseDown, .rightMouseUp, .rightMouseDragged, .right, .tileBottom),
            ("Option + middle-click", .maskAlternate, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .center, .fill),
            ("Control + Option + middle-click", [.maskControl, .maskAlternate], .otherMouseDown, .otherMouseUp,
             .otherMouseDragged, .center, .fill)
        ]
        for (label, flags, down, up, drag, button, action) in clicks {
            let ordinary = mouse(down, button: button, flags: [])
            try check(engine.route(down, ordinary, target: target, at: 1) == .pass, "\(label): unmodified click was captured")
            let trigger = mouse(down, button: button, flags: flags)
            try check(engine.route(down, trigger, target: nil, at: 1) == .pass, "\(label): no active window target")
            try check(engine.route(down, trigger, target: ProcessInfo.processInfo.processIdentifier, at: 1) == .pass,
                      "\(label): SpaceMouse's editor must receive clicks")
            for attempt in 1...2 {
                try check(engine.route(down, trigger, target: target, at: 2) == .run(action, target: target),
                          "\(label): wrong action on attempt \(attempt)")
                let dragging = mouse(drag, button: button, flags: flags)
                try check(engine.route(drag, dragging, target: target, at: 2.1) == .swallow,
                          "\(label): drag leaked after the shortcut")
                let release = mouse(up, button: button, flags: [])
                try check(engine.route(up, release, target: target, at: 2.2) == .swallow,
                          "\(label): matching release leaked after modifier release")
                try check(engine.route(up, release, target: target, at: 2.3) == .pass,
                          "\(label): unrelated release was captured")
            }
            print("PASS \(label) → \(action.title)")
        }
    }

    private static func checkKeyEvents(_ engine: ShortcutEngine, action: ShortcutAction, expectedKey: Int64) throws {
        guard let key = action.key else { throw Failure(description: "Missing key for \(action.title)") }
        let events = engine.keyEvents(for: key)
        try check(events.map(\.type) == [.keyDown, .keyUp], "\(action.title): expected key-down and key-up")
        for event in events {
            try check(event.getIntegerValueField(.keyboardEventKeycode) == expectedKey, "\(action.title): wrong key")
            try check(event.flags == [.maskControl, .maskSecondaryFn, .maskNumericPad],
                      "\(action.title): wrong flags for macOS arrow shortcut")
        }
    }

    private static func scrollChecks() throws {
        let engine = ShortcutEngine()
        let up = scroll(1)
        let down = scroll(-1)
        try check(engine.route(.scrollWheel, up, target: target, at: 5) == .run(.spaceRight, target: target),
                  "Control + scroll up must move right")
        try check(engine.route(.scrollWheel, up, target: target, at: 5.1) == .swallow, "Wheel burst repeated")
        try check(engine.route(.scrollWheel, down, target: target, at: 5.2) == .run(.spaceLeft, target: target),
                  "Control + scroll down must move left immediately after reversing direction")
        try check(engine.route(.scrollWheel, down, target: target, at: 5.3) == .swallow, "Downward burst repeated")
        try check(engine.route(.scrollWheel, down, target: target, at: 5.8) == .run(.spaceLeft, target: target),
                  "New wheel burst did not start")
        for unmatched in [scroll(1, flags: []), scroll(1, flags: .maskAlternate),
                          scroll(0, horizontal: 1), scroll(10, units: .pixel)] {
            try check(engine.route(.scrollWheel, unmatched, target: target, at: 6) == .pass, "Unbound scroll was captured")
        }
        try checkKeyEvents(engine, action: .spaceRight, expectedKey: 124)
        try checkKeyEvents(engine, action: .spaceLeft, expectedKey: 123)
        print("PASS Control + scroll up/down → next/previous Space, including wheel-burst handling")
    }

    private static func configurableChecks() throws {
        let engine = ShortcutEngine()
        let alternate = scroll(1, flags: [.maskControl, .maskAlternate])
        try check(engine.route(.scrollWheel, alternate, target: target, at: 1) == .pass, "Disabled Mission Control fired")
        guard let index = engine.rules.firstIndex(where: { $0.action == .missionControl }) else {
            throw Failure(description: "Missing optional Mission Control binding")
        }
        engine.rules[index].enabled = true
        try check(engine.route(.scrollWheel, alternate, target: target, at: 2) == .run(.missionControl, target: target),
                  "Enabled Mission Control didn't fire")
        try checkKeyEvents(engine, action: .missionControl, expectedKey: 126)
        try checkKeyEvents(engine, action: .appWindows, expectedKey: 125)

        // Exercise the configurable side-button inputs through the same mouse event parser.
        for (number, input, action) in [(Int64(3), MouseInput.mouse4, ShortcutAction.spaceRight),
                                        (Int64(4), .mouse5, .spaceLeft)] {
            let event = mouse(.otherMouseDown, button: .center, flags: .maskControl, number: number)
            try check(engine.route(.otherMouseDown, event, target: target, at: 3) == .pass, "Disabled side button fired")
            engine.rules = [.init(modifier: .control, input: input, action: action)]
            try check(engine.route(.otherMouseDown, event, target: target, at: 4) == .run(action, target: target),
                      "Side button dispatched the wrong action")
        }

        let nativeTitles: [(ShortcutAction, String)] = [
            (.tileLeft, "Left"), (.tileRight, "Right"), (.tileTop, "Top"), (.tileBottom, "Bottom"),
            (.center, "Center"), (.fill, "Fill"), (.restore, "Return to Previous Size")
        ]
        for (action, title) in nativeTitles {
            let event = mouse(.leftMouseDown, button: .left, flags: .maskAlternate)
            engine.rules = [.init(modifier: .option, input: .left, action: action)]
            try check(engine.route(.leftMouseDown, event, target: target, at: 5) == .run(action, target: target),
                      "Custom binding for \(action.title) dispatched the wrong action")
            try check(action.menuTitle == title, "\(action.title): wrong macOS menu command")
        }

        let rules = BindingRule.starter
        try check(rules.allSatisfy { rule in !rules.contains(where: rule.conflicts(with:)) }, "Conflicting starter bindings")
        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([BindingRule].self, from: data)
        try check(decoded == rules, "The app must preserve shortcut settings")
        print("PASS Optional gestures, native command names, configurable actions, and settings round trip")
    }

    private static func conflictChecks() throws {
        let previous = BindingRule(modifier: .option, input: .middle, action: .center)
        let unrelated = BindingRule(modifier: .control, input: .middle, action: .fullScreen)
        let replacement = BindingRule(modifier: .option, input: .middle, action: .missionControl)
        let rules = [previous, unrelated]
        try check(replacement.conflicts(with: previous), "Existing enabled shortcut did not report a conflict")
        try check(BindingRule.applying(replacement, to: rules, replacingConflicts: false) == nil,
                  "The existing shortcut must survive until replacement is confirmed")
        try check(BindingRule.applying(replacement, to: rules, replacingConflicts: true) == [unrelated, replacement],
                  "Explicit replacement must remove only the conflicted shortcut")
        var disabled = replacement
        disabled.enabled = false
        try check(BindingRule.applying(disabled, to: rules, replacingConflicts: false) == rules + [disabled],
                  "Disabled shortcuts may share a gesture")
        let enabled = BindingRule.applying(replacement, to: rules + [disabled], replacingConflicts: true)
        try check(enabled == [unrelated, replacement], "Enabling a conflicting shortcut must replace the enabled owner")
        try check(BindingRule.migratingOptionMiddleClick(in: [unrelated]) == [unrelated, .optionMiddleFill],
                  "Existing settings must gain the new default")
        try check(BindingRule.migratingOptionMiddleClick(in: [unrelated, replacement]) == [unrelated, replacement],
                  "Updating the defaults must preserve the user's custom gesture")
        try check(BindingRule.migratingOptionMiddleClick(in: [unrelated, disabled]) == [unrelated, disabled],
                  "Updating the defaults must preserve a disabled custom gesture")
        var upgraded = previous
        upgraded.action = .fill
        try check(BindingRule.migratingOptionMiddleClick(in: rules) == [upgraded, unrelated],
                  "Existing Option + middle-click Center must become Fill without changing its ID")
        let customizedFillGesture = BindingRule(modifier: .controlOption, input: .middle, action: .restore, enabled: false)
        try check(BindingRule.addingDefault(.fillDefault, to: rules) == rules + [.fillDefault],
                  "Existing settings must gain Fill when its gesture is free")
        try check(BindingRule.addingDefault(.fillDefault, to: rules + [customizedFillGesture]) == rules + [customizedFillGesture],
                  "The Fill migration must preserve existing user bindings")
        print("PASS Conflict detection, explicit replacement, and migration of existing shortcuts")
    }

    static func main() throws {
        try clickChecks()
        try scrollChecks()
        try configurableChecks()
        try conflictChecks()
    }
}
