import AppKit
import SwiftUI

@main
struct SpaceMouseApp: App {
    @StateObject private var store = ShortcutStore()

    var body: some Scene {
        Window("SpaceMouse", id: "dashboard") {
            Dashboard(store: store)
                .frame(minWidth: 490, minHeight: 310)
                .preferredColorScheme(.dark)
                .containerBackground(.clear, for: .window)
        }
        .defaultSize(width: 520, height: 450)
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
        Button(store.running ? "Pause shortcuts" : "Set up shortcuts") {
            if store.running { store.pause() } else { showWindow() }
        }
        Divider()
        Button("Quit SpaceMouse") { NSApp.terminate(nil) }
    }

    private func showWindow() {
        openWindow(id: "dashboard")
        NSApp.activate()
    }
}

struct Dashboard: View {
    @ObservedObject var store: ShortcutStore
    @State private var draft: BindingRule?
    @State private var showingSettings = false
    @State private var restoreConfirmation = false
    @Environment(\.scenePhase) private var phase

    private let accent = Color(red: 0.55, green: 0.73, blue: 0.85)
    private let actionWidth: CGFloat = 143
    private var showingPanel: Bool { draft != nil || showingSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let message = store.message {
                Label(message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: .rect(cornerRadius: 8))
            }
            bindings
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .disabled(showingPanel)
        .accessibilityHidden(showingPanel)
        .blur(radius: showingPanel ? 5 : 0)
        .background { backdrop }
        .overlay {
            if showingPanel {
                Rectangle().fill(.black.opacity(0.20)).ignoresSafeArea()
                if let draft {
                    ShortcutEditor(rule: draft, store: store) { self.draft = nil }
                        .id(draft.id)
                } else {
                    settings
                }
            }
        }
        .tint(accent)
        .alert("Use SpaceMouse for shortcuts?", isPresented: $store.confirmTakeover) {
            Button("Cancel", role: .cancel) {}
            Button("Switch to SpaceMouse") { store.takeOver() }
        } message: {
            Text("Your previous script will pause while SpaceMouse is active. It will resume when you pause shortcuts or quit the app.")
        }
        .confirmationDialog("Replace your shortcuts with the starter set?", isPresented: $restoreConfirmation) {
            Button("Restore starter shortcuts", role: .destructive) { store.restoreStarter() }
        }
        .onAppear { store.refreshPermission() }
        .onChange(of: phase) { _, value in if value == .active { store.refreshPermission() } }
    }

    private var backdrop: some View {
        ZStack {
            DesktopGlass()
            LinearGradient(colors: [.black.opacity(0.49), .black.opacity(0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.72, green: 0.87, blue: 1).opacity(0.22), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(red: 0.32, green: 0.60, blue: 0.86).opacity(0.16), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 480)
            FrostDust()
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 24, height: 24)
                .glassPanel(radius: 7)
                .accessibilityHidden(true)
            Text("SpaceMouse").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 5) {
                Circle().fill(store.running ? .green : store.legacyActive ? accent : .secondary.opacity(0.65))
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text(store.running ? "Active" : store.legacyActive ? "Previous script active" : "Paused")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)

            Spacer(minLength: 0)
            Button {
                if store.running { store.pause() } else { store.start() }
            } label: {
                Label(store.running ? "Pause" : "Start",
                      systemImage: store.running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.glass)
            .help(store.running ? "Pause shortcuts" : "Start shortcuts")
            .accessibilityLabel(store.running ? "Pause shortcuts" : "Start shortcuts")

            Button {
                draft = BindingRule(modifier: .control, input: .mouse4, action: .missionControl)
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
            .help("Add shortcut")
            .accessibilityLabel("Add shortcut")
            .keyboardShortcut("n", modifiers: .command)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.glass)
            .help("Settings")
            .accessibilityLabel("Settings")
            .keyboardShortcut(",", modifiers: .command)
        }
        .controlSize(.small)
        .padding(.horizontal, 3)
    }

    private var bindings: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text("Action").frame(width: actionWidth, alignment: .leading)
                Text("Gesture").frame(maxWidth: .infinity, alignment: .leading)
                Text("On").frame(width: 34)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 23)
            .accessibilityHidden(true)

            Divider()
            if store.rules.isEmpty {
                Text("No shortcuts yet. Click Add to create one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.rules) { rule in
                            bindingRow(rule)
                            if rule.id != store.rules.last?.id { Divider().padding(.leading, 37) }
                        }
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .glassPanel(radius: 12)
    }

    private func bindingRow(_ rule: BindingRule) -> some View {
        HStack(spacing: 9) {
            Button { draft = rule } label: {
                HStack(spacing: 9) {
                    HStack(spacing: 7) {
                        Image(systemName: rule.action.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(rule.enabled ? accent : Color.secondary)
                            .frame(width: 20, height: 20)
                            .background(accent.opacity(rule.enabled ? 0.12 : 0.05), in: .rect(cornerRadius: 5))
                        Text(rule.action.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(width: actionWidth, alignment: .leading)

                    Text("\(rule.modifier.title) + \(rule.input.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 27)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Edit \(rule.action.title)")
            .accessibilityLabel("Edit \(rule.action.title), \(rule.modifier.title), \(rule.input.title)")

            if !rule.enabled, let owner = store.rules.first(where: { $0.enabled && rule.sharesGesture(with: $0) }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
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
            .frame(width: 34)
        }
        .padding(.horizontal, 10)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Scroll pause").font(.callout.weight(.medium))
                    Spacer()
                    Text("\(Int(store.scrollGap * 1000)) ms").monospacedDigit().foregroundStyle(.secondary)
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
        .padding(16)
        .frame(width: 355)
        .glassPanel(radius: 16)
        .shadow(color: .black.opacity(0.30), radius: 18, y: 8)
        .accessibilityAddTraits(.isModal)
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
                    Text("Modifier").foregroundStyle(.secondary)
                    Picker("Modifier", selection: $rule.modifier) {
                        ForEach(Modifier.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Mouse input").foregroundStyle(.secondary)
                    Picker("Mouse input", selection: $rule.input) {
                        ForEach(MouseInput.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Action").foregroundStyle(.secondary)
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
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
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
        .glassPanel(radius: 17)
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
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.34), .white.opacity(0.06), .white.opacity(0.15)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
        }
    }
}

private struct FrostDust: View {
    var body: some View {
        Canvas { context, size in
            let ice = Color(red: 0.83, green: 0.93, blue: 1)
            for index in 0..<50 {
                let x = CGFloat((index * 73 + 31) % 997) / 997
                let y = CGFloat((index * 97 + 17) % 659) / 659
                let diameter: CGFloat = index.isMultiple(of: 9) ? 2.4 : 1.4
                let brightness = 0.08 + Double(index % 5) * 0.025
                let flake = CGRect(x: x * size.width, y: y * size.height, width: diameter, height: diameter)
                context.fill(Path(ellipseIn: flake), with: .color(ice.opacity(brightness)))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DesktopGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> GlassBackdrop {
        let view = GlassBackdrop()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.58
        return view
    }

    func updateNSView(_ view: GlassBackdrop, context: Context) {
        view.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.58
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
