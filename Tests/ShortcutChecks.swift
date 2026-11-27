import CoreGraphics
import Foundation

@main
struct ShortcutChecks {
    static func main() throws {
        precondition(Modifier.matching(.maskControl) == .control)
        precondition(Modifier.matching(.maskAlternate) == .option)
        precondition(Modifier.matching([.maskControl, .maskAlternate]) == .controlOption)
        precondition(Modifier.matching([]) == nil)

        let rules = BindingRule.starter
        func action(_ modifier: Modifier, _ input: MouseInput) -> ShortcutAction? {
            rules.first { $0.enabled && $0.modifier == modifier && $0.input == input }?.action
        }
        precondition(action(.control, .left) == .tileLeft && action(.control, .right) == .tileRight)
        precondition(action(.option, .left) == .tileTop && action(.option, .right) == .tileBottom)
        precondition(action(.control, .middle) == .fullScreen)
        precondition(action(.control, .scrollUp) == .spaceRight && action(.control, .scrollDown) == .spaceLeft)
        precondition(rules.allSatisfy { rule in !rules.contains(where: rule.conflicts(with:)) })

        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([BindingRule].self, from: data)
        precondition(decoded == rules, "The app must preserve shortcut settings")
        print("Modifier matching, starter shortcuts, and settings round trip passed.")
    }
}
