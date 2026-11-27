import CoreGraphics
import Foundation

enum MouseInput: String, Codable, CaseIterable, Identifiable {
    case left, right, middle, mouse4, mouse5, scrollUp, scrollDown
    var id: Self { self }
    var title: String {
        switch self {
        case .left: "Left-click"
        case .right: "Right-click"
        case .middle: "Middle-click"
        case .mouse4: "Mouse 4"
        case .mouse5: "Mouse 5"
        case .scrollUp: "Scroll up"
        case .scrollDown: "Scroll down"
        }
    }
    var symbol: String {
        switch self {
        case .scrollUp: "arrow.up"
        case .scrollDown: "arrow.down"
        default: "computermouse"
        }
    }
}

enum Modifier: String, Codable, CaseIterable, Identifiable {
    case control, option, command, shift, controlOption, controlShift, fn
    var id: Self { self }
    var title: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .command: "Command"
        case .shift: "Shift"
        case .controlOption: "Control + Option"
        case .controlShift: "Control + Shift"
        case .fn: "Fn"
        }
    }
    var flags: CGEventFlags {
        switch self {
        case .control: .maskControl
        case .option: .maskAlternate
        case .command: .maskCommand
        case .shift: .maskShift
        case .controlOption: [.maskControl, .maskAlternate]
        case .controlShift: [.maskControl, .maskShift]
        case .fn: .maskSecondaryFn
        }
    }
    static let mask: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift, .maskSecondaryFn]

    static func matching(_ flags: CGEventFlags) -> Self? {
        let flags = flags.intersection(mask)
        return allCases.first { $0.flags == flags }
    }
}

enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
    case spaceRight, spaceLeft, tileLeft, tileRight, tileTop, tileBottom, fullScreen
    case missionControl, appWindows, center, fill, restore

    var id: Self { self }
    var title: String {
        switch self {
        case .spaceRight: "Next Space"
        case .spaceLeft: "Previous Space"
        case .tileLeft: "Tile left"
        case .tileRight: "Tile right"
        case .tileTop: "Tile top"
        case .tileBottom: "Tile bottom"
        case .fullScreen: "Toggle full screen"
        case .missionControl: "Mission Control"
        case .appWindows: "Show app windows"
        case .center: "Center window"
        case .fill: "Fill desktop"
        case .restore: "Restore window size"
        }
    }
    var symbol: String {
        switch self {
        case .spaceRight: "arrow.right"
        case .spaceLeft: "arrow.left"
        case .tileLeft: "rectangle.lefthalf.inset.filled"
        case .tileRight: "rectangle.righthalf.inset.filled"
        case .tileTop: "rectangle.tophalf.inset.filled"
        case .tileBottom: "rectangle.bottomhalf.inset.filled"
        case .fullScreen: "arrow.up.left.and.arrow.down.right"
        case .missionControl: "rectangle.3.group"
        case .appWindows: "rectangle.on.rectangle"
        case .center: "rectangle.center.inset.filled"
        case .fill: "rectangle.inset.filled"
        case .restore: "arrow.uturn.backward"
        }
    }
    var key: CGKeyCode? {
        switch self {
        case .spaceRight: 124
        case .spaceLeft: 123
        case .missionControl: 126
        case .appWindows: 125
        default: nil
        }
    }
    var menuTitle: String? {
        switch self {
        case .tileLeft: "Left"
        case .tileRight: "Right"
        case .tileTop: "Top"
        case .tileBottom: "Bottom"
        case .center: "Center"
        case .fill: "Fill"
        case .restore: "Return to Previous Size"
        default: nil
        }
    }
}

struct BindingRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var modifier: Modifier
    var input: MouseInput
    var action: ShortcutAction
    var enabled = true

    func conflicts(with other: Self) -> Bool {
        enabled && other.enabled && sharesGesture(with: other)
    }

    func sharesGesture(with other: Self) -> Bool {
        id != other.id && input == other.input && modifier == other.modifier
    }

    static let centerDefault = Self(modifier: .option, input: .middle, action: .center)
    static let fillDefault = Self(modifier: .controlOption, input: .middle, action: .fill)

    static func addingDefault(_ rule: Self, to rules: [Self]) -> [Self] {
        guard !rules.contains(where: { $0.modifier == rule.modifier && $0.input == rule.input }) else {
            return rules
        }
        return rules + [rule]
    }

    static func applying(_ rule: Self, to rules: [Self], replacingConflicts: Bool) -> [Self]? {
        guard replacingConflicts || !rules.contains(where: rule.conflicts(with:)) else { return nil }
        var updated = rules.filter { !rule.conflicts(with: $0) }
        if let index = updated.firstIndex(where: { $0.id == rule.id }) {
            updated[index] = rule
        } else {
            updated.append(rule)
        }
        return updated
    }

    static let starter: [Self] = [
        .init(modifier: .control, input: .scrollUp, action: .spaceRight),
        .init(modifier: .control, input: .scrollDown, action: .spaceLeft),
        .init(modifier: .control, input: .left, action: .tileLeft),
        .init(modifier: .control, input: .right, action: .tileRight),
        .init(modifier: .control, input: .middle, action: .fullScreen),
        .init(modifier: .option, input: .left, action: .tileTop),
        .init(modifier: .option, input: .right, action: .tileBottom),
        centerDefault,
        fillDefault,
        .init(modifier: .controlOption, input: .scrollUp, action: .missionControl, enabled: false),
        .init(modifier: .control, input: .mouse4, action: .spaceRight, enabled: false),
        .init(modifier: .control, input: .mouse5, action: .spaceLeft, enabled: false)
    ]
}
