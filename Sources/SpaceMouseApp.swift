import AppKit
import SwiftUI

private let secondaryInk = Color(red: 0.19, green: 0.24, blue: 0.30)

@main
struct SpaceMouseApp: App {
    @StateObject private var store = ShortcutStore()

    var body: some Scene {
        Window("SpaceMouse", id: "dashboard") {
            Dashboard(store: store)
                .frame(minWidth: 490, minHeight: 320)
                .preferredColorScheme(.light)
                .containerBackground(.clear, for: .window)
        }
        .defaultSize(width: 548, height: 506)
        .restorationBehavior(.disabled)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("SpaceMouse", systemImage: "computermouse") {
            MenuBarControls(store: store)
        }
    }
}

private struct MenuBarControls: View {
    @ObservedObject var store: ShortcutStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open SpaceMouse") { showWindow() }
        if store.running {
            Button("Pause shortcuts") { store.pause() }
        } else if store.paused {
            Button("Resume shortcuts") { store.resume() }
        } else if !store.trusted {
            Button("Enable Accessibility") { showWindow(); store.requestAccess() }
        }
        Divider()
        Button("Quit SpaceMouse") { NSApp.terminate(nil) }
    }

    private func showWindow() {
        openWindow(id: "dashboard")
        NSApp.activate()
    }
}

private enum ShortcutGroup: String, CaseIterable, Identifiable {
    case windows = "Windows", spaces = "Spaces", system = "System"
    var id: Self { self }

    init(action: ShortcutAction) {
        switch action {
        case .spaceRight, .spaceLeft: self = .spaces
        case .missionControl, .appWindows: self = .system
        default: self = .windows
        }
    }
}

struct Dashboard: View {
    @ObservedObject var store: ShortcutStore
    @State private var draft: BindingRule?
    @State private var showingSettings = false
    @State private var restoreConfirmation = false
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var phase

    private let accent = Color(red: 0.16, green: 0.39, blue: 0.59)
    private var showingPanel: Bool { draft != nil || showingSettings }

    private var matches: [BindingRule] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.rules }
        return store.rules.filter { rule in
            [rule.action.title, rule.modifier.title, rule.input.title]
                .joined(separator: " ")
                .localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let message = store.message {
                Label(message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.45), in: .rect(cornerRadius: 8))
            }
            bindings
            status
        }
        .padding(.horizontal, 15)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .disabled(showingPanel)
        .accessibilityHidden(showingPanel)
        .blur(radius: showingPanel ? 2 : 0)
        .background { backdrop }
        .overlay {
            if showingPanel {
                Rectangle().fill(.white.opacity(0.06)).ignoresSafeArea()
                if let draft {
                    ShortcutEditor(rule: draft, store: store) { self.draft = nil }
                        .id(draft.id)
                } else {
                    settings
                }
            }
        }
        .tint(accent)
        .confirmationDialog("Replace your shortcuts with the starter set?", isPresented: $restoreConfirmation) {
            Button("Restore starter shortcuts", role: .destructive) { store.restoreStarter() }
        }
        .onAppear { store.refreshPermission() }
        .onChange(of: phase) { _, value in if value == .active { store.refreshPermission() } }
    }

    private var backdrop: some View {
        ZStack {
            DesktopGlass()
            Color.white.opacity(0.18)
            LinearGradient(colors: [Color(red: 0.75, green: 0.87, blue: 0.98).opacity(0.10), .clear, .white.opacity(0.03)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 31, height: 31)
                .background(accent.opacity(0.13), in: .rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.24)) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("SpaceMouse").font(.system(size: 17, weight: .semibold)).tracking(-0.25)
                Text("Shortcuts").font(.system(size: 10, weight: .medium)).foregroundStyle(secondaryInk)
            }

            Spacer(minLength: 4)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(secondaryInk).accessibilityHidden(true)
                TextField("Find a shortcut", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel("Find a shortcut")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(secondaryInk)
                        .accessibilityLabel("Clear search")
                }
            }
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .frame(width: 143, height: 28)
            .background(.white.opacity(0.23), in: .rect(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.black.opacity(0.12)) }
            .onKeyPress(.escape) {
                guard searchFocused else { return .ignored }
                search = ""
                searchFocused = false
                return .handled
            }

            Button {
                draft = BindingRule(modifier: .control, input: .mouse4, action: .missionControl)
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
            .help("Add shortcut")
            .accessibilityLabel("Add shortcut")
            .keyboardShortcut("n", modifiers: .command)

            Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.glass)
                .help("Settings")
                .accessibilityLabel("Settings")
                .keyboardShortcut(",", modifiers: .command)
        }
        .controlSize(.small)
    }

    private var bindings: some View {
        let rules = matches
        return Group {
            if rules.isEmpty {
                ContentUnavailableView(
                    store.rules.isEmpty ? "No shortcuts" : "No matches",
                    systemImage: store.rules.isEmpty ? "computermouse" : "magnifyingglass",
                    description: Text(store.rules.isEmpty ? "Use Add to create a shortcut." : "Try a different action or mouse input.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(ShortcutGroup.allCases) { group in
                            let items = rules.filter { ShortcutGroup(action: $0.action) == group }
                            if !items.isEmpty {
                                section(group, items)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 10))
        .background(.white.opacity(0.29), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.53))
                .allowsHitTesting(false)
        }
    }

    private func section(_ group: ShortcutGroup, _ items: [BindingRule]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(secondaryInk)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(items) { rule in
                bindingRow(rule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bindingRow(_ rule: BindingRule) -> some View {
        HStack(spacing: 9) {
            BindingRow(rule: rule, accent: accent) { draft = rule }

            if !rule.enabled, let owner = store.rules.first(where: { $0.enabled && rule.sharesGesture(with: $0) }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("This gesture is in use by \(owner.action.title)")
                    .accessibilityLabel("Gesture in use by \(owner.action.title)")
            }

            Toggle(isOn: Binding(get: { rule.enabled }, set: { enabled in
                var edited = rule
                edited.enabled = enabled
                if store.conflict(for: edited) != nil {
                    draft = edited
                } else {
                    store.save(edited)
                }
            })) { Text("Enable \(rule.action.title)") }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .frame(width: 32)
        }
        .padding(.horizontal, 8)
    }

    private var status: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.running ? Color.green : store.legacyActive ? accent : Color.secondary)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(store.running ? "Shortcuts active" : store.legacyActive ? "Previous script active" : store.paused ? "Paused" : "Shortcuts inactive")
                .foregroundStyle(secondaryInk)
            Spacer()
            if !store.trusted {
                Button("Enable Accessibility") { store.requestAccess() }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
            } else {
                Text("\(store.rules.filter(\.enabled).count) enabled")
                    .monospacedDigit()
                    .foregroundStyle(secondaryInk)
            }
        }
        .font(.caption)
        .padding(.horizontal, 2)
        .frame(minHeight: 17)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Settings").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Scroll pause").font(.callout.weight(.medium))
                    Spacer()
                    Text("\(Int(store.scrollGap * 1000)) ms").monospacedDigit().foregroundStyle(secondaryInk)
                }
                Slider(value: $store.scrollGap, in: 0.15 ... 0.9, step: 0.05) { Text("Scroll pause") }
                    .labelsHidden()
            }
            Divider()
            HStack {
                Text(store.trusted ? "Accessibility enabled" : "Accessibility required").font(.callout)
                Spacer()
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }.buttonStyle(.glass)
            }
            HStack {
                Button("Restore starter shortcuts") { restoreConfirmation = true }
                    .buttonStyle(.glass)
                Spacer()
                Button("Done") { showingSettings = false }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .controlSize(.small)
        .padding(17)
        .frame(width: 355)
        .glassPanel(radius: 14)
        .shadow(color: .black.opacity(0.40), radius: 18, y: 8)
        .accessibilityAddTraits(.isModal)
    }
}

private struct BindingRow: View {
    let rule: BindingRule
    let accent: Color
    let edit: () -> Void
    @State private var hovering = false

    private var modifierKeys: [String] {
        switch rule.modifier {
        case .control: ["⌃"]
        case .option: ["⌥"]
        case .command: ["⌘"]
        case .shift: ["⇧"]
        case .controlOption: ["⌃", "⌥"]
        case .controlShift: ["⌃", "⇧"]
        case .fn: ["Fn"]
        }
    }

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 8) {
                Image(systemName: rule.action.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(rule.enabled ? accent : Color.secondary)
                    .frame(width: 21)
                Text(rule.action.title)
                    .font(.system(size: 12, weight: rule.enabled ? .medium : .regular))
                    .foregroundStyle(rule.enabled ? Color.primary : secondaryInk)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    ForEach(modifierKeys, id: \.self) { key in
                        Text(key)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(rule.enabled ? .primary : .secondary)
                            .frame(minWidth: 17, minHeight: 16)
                            .background(.white.opacity(0.35), in: .rect(cornerRadius: 4))
                            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.10)) }
                    }
                    Text(rule.input.title)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryInk)
                        .padding(.leading, 2)
                }
                .frame(width: 139, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(secondaryInk)
                    .opacity(hovering ? 1 : 0)
                    .frame(width: 9)
            }
            .padding(.horizontal, 2)
            .frame(height: 26)
            .contentShape(.rect)
            .background(hovering ? accent.opacity(0.09) : .clear, in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Edit \(rule.action.title)")
        .accessibilityLabel("Edit \(rule.action.title), \(rule.modifier.title), \(rule.input.title)")
    }
}

private struct ShortcutEditor: View {
    @State var rule: BindingRule
    @ObservedObject var store: ShortcutStore
    let onDismiss: () -> Void

    private var existing: Bool { store.rules.contains { $0.id == rule.id } }
    private var conflict: BindingRule? { store.conflict(for: rule) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existing ? "Edit shortcut" : "Add shortcut").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Modifier").foregroundStyle(secondaryInk)
                    Picker("Modifier", selection: $rule.modifier) {
                        ForEach(Modifier.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Mouse input").foregroundStyle(secondaryInk)
                    Picker("Mouse input", selection: $rule.input) {
                        ForEach(MouseInput.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Action").foregroundStyle(secondaryInk)
                    Picker("Action", selection: $rule.action) {
                        ForEach(ShortcutAction.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                    Toggle("Enabled", isOn: $rule.enabled).toggleStyle(.switch)
                }
            }
            .pickerStyle(.menu)
            if let conflict {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shortcut already in use").font(.callout.weight(.semibold))
                        Text("Replacing it removes “\(conflict.action.title)” from your bindings.")
                            .font(.caption).foregroundStyle(secondaryInk)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.08), in: .rect(cornerRadius: 9))
            }
            HStack {
                if existing {
                    Button("Delete", role: .destructive) { store.delete(rule); onDismiss() }
                }
                Spacer()
                Button("Cancel", role: .cancel) { onDismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button(conflict == nil ? "Save" : "Replace shortcut") {
                    store.save(rule, replacingConflicts: conflict != nil)
                    onDismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
        .padding(17)
        .frame(width: 365)
        .glassPanel(radius: 14)
        .shadow(color: .black.opacity(0.30), radius: 22, y: 10)
        .accessibilityAddTraits(.isModal)
    }
}

private extension View {
    func glassPanel(radius: CGFloat) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: [.white.opacity(0.11), .white.opacity(0.035)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .glassEffect(.clear, in: .rect(cornerRadius: radius))
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.92), .white.opacity(0.38), .white.opacity(0.65)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
        }
    }
}

private struct DesktopGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> GlassBackdrop {
        let view = GlassBackdrop()
        view.material = .windowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.23
        return view
    }

    func updateNSView(_ view: GlassBackdrop, context: Context) {
        view.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.23
    }

    final class GlassBackdrop: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isOpaque = false
            window?.backgroundColor = .clear
            window?.titlebarAppearsTransparent = true
        }
    }
}
