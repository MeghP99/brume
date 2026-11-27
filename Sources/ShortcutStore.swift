import AppKit
import Combine

final class ShortcutStore: ObservableObject {
    @Published private(set) var rules: [BindingRule]
    @Published private(set) var running = false
    @Published private(set) var legacyActive = false
    @Published private(set) var trusted = ShortcutEngine.trusted
    @Published var message: String?
    @Published private(set) var paused = false
    @Published var scrollGap: Double {
        didSet { defaults.set(scrollGap, forKey: "scrollGap"); engine.scrollGap = scrollGap }
    }

    private let engine = ShortcutEngine()
    private let defaults = UserDefaults.standard
    private let legacy = LegacyAgent()
    private var restoreLegacy: Bool {
        get { defaults.bool(forKey: "restoreLegacyAgent") }
        set { defaults.set(newValue, forKey: "restoreLegacyAgent") }
    }
    private var observer: NSObjectProtocol?

    init() {
        let saved = defaults.data(forKey: "bindings")
            .flatMap { try? JSONDecoder().decode([BindingRule].self, from: $0) }
        let presetVersion = defaults.integer(forKey: "bindingPresetVersion")
        if let saved, presetVersion < 3 {
            var migrated = saved
            if presetVersion < 2 {
                migrated = BindingRule.addingDefault(.fillDefault, to: migrated)
            }
            migrated = BindingRule.migratingOptionMiddleClick(in: migrated)
            rules = migrated
            if let data = try? JSONEncoder().encode(migrated) { defaults.set(data, forKey: "bindings") }
        } else {
            rules = saved ?? BindingRule.starter
        }
        defaults.set(3, forKey: "bindingPresetVersion")
        scrollGap = defaults.object(forKey: "scrollGap") as? Double ?? 0.45
        paused = defaults.bool(forKey: "shortcutsPaused")
        engine.rules = rules
        engine.scrollGap = scrollGap
        engine.onAction = { [weak self] action, success in
            self?.message = success ? nil : "The active window couldn’t perform “\(action.title)”."
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.deactivate() }
    }

    func refreshPermission() {
        trusted = ShortcutEngine.trusted
        if paused || !trusted {
            let lostAccess = running && !trusted
            if running || restoreLegacy { deactivate() }
            legacyActive = legacy.isRunning
            if lostAccess { message = "Accessibility access was removed." }
            return
        }
        guard !running else { return }

        legacyActive = legacy.isRunning
        guard engine.start() else {
            message = "macOS couldn’t start the shortcut listener. Check Accessibility access."
            return
        }
        if legacyActive {
            guard legacy.stop() else {
                engine.stop()
                message = "The previous SpaceMouse script couldn’t be paused."
                return
            }
            restoreLegacy = true
            legacyActive = false
        }
        running = true
        message = nil
    }

    func requestAccess() {
        refreshPermission()
        if !trusted { ShortcutEngine.requestPermission() }
    }

    func resume() {
        paused = false
        defaults.set(false, forKey: "shortcutsPaused")
        requestAccess()
    }

    func pause() {
        paused = true
        defaults.set(true, forKey: "shortcutsPaused")
        deactivate()
    }

    private func deactivate() {
        engine.stop()
        running = false
        if restoreLegacy {
            if legacy.start() {
                restoreLegacy = false
                legacyActive = true
            } else {
                message = "The previous SpaceMouse script couldn’t be resumed."
            }
        }
    }

    func conflict(for rule: BindingRule) -> BindingRule? {
        rules.first(where: rule.conflicts(with:))
    }

    func save(_ rule: BindingRule, replacingConflicts: Bool = false) {
        guard let updated = BindingRule.applying(rule, to: rules, replacingConflicts: replacingConflicts) else {
            message = "Another enabled shortcut uses that combination."
            return
        }
        update(updated)
    }

    func delete(_ rule: BindingRule) { update(rules.filter { $0.id != rule.id }) }
    func restoreStarter() { update(BindingRule.starter) }

    private func update(_ rules: [BindingRule]) {
        self.rules = rules
        engine.rules = rules
        if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: "bindings") }
        message = nil
    }
}

private struct LegacyAgent {
    let domain = "gui/\(getuid())"
    var service: String { "\(domain)/local.spacemouse" }

    var isRunning: Bool { launchctl(["print", service]) }

    func stop() -> Bool { launchctl(["bootout", service]) }

    func start() -> Bool {
        if isRunning { return true }
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/local.spacemouse.plist").path
        return launchctl(["bootstrap", domain, path])
    }

    private func launchctl(_ arguments: [String]) -> Bool {
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        command.arguments = arguments
        command.standardOutput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice
        guard (try? command.run()) != nil else { return false }
        command.waitUntilExit()
        return command.terminationStatus == 0
    }
}
