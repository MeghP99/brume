import AppKit
import SwiftUI

@main
struct SpaceMouseApp: App {
    @StateObject private var store = ShortcutStore()

    var body: some Scene {
        Window("SpaceMouse", id: "dashboard") {
            Dashboard(store: store)
                .frame(minWidth: 920, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1020, height: 720)
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

private enum Page: String, CaseIterable {
    case shortcuts = "Shortcuts", settings = "Settings"
    var icon: String { self == .shortcuts ? "square.grid.2x2" : "slider.horizontal.3" }
}

struct Dashboard: View {
    @ObservedObject var store: ShortcutStore
    @State private var page: Page = .shortcuts
    @State private var draft: BindingRule?
    @State private var selectedID: UUID?
    @State private var restoreConfirmation = false
    @Environment(\.scenePhase) private var phase

    private let violet = Color(red: 0.70, green: 0.62, blue: 1.0)
    private let teal = Color(red: 0.35, green: 0.92, blue: 0.88)

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 192)
                .padding(.leading, 15)
                .padding(.top, 44)
                .padding(.bottom, 15)
            VStack(alignment: .leading, spacing: 20) {
                header
                if let message = store.message {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                        Text(message).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: .rect(cornerRadius: 13))
                }
                switch page {
                case .shortcuts: shortcuts
                case .settings: settings
                }
            }
            .padding(.horizontal, 27)
            .padding(.top, 29)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background { backdrop }
        .tint(violet)
        .sheet(item: $draft) { rule in
            ShortcutEditor(rule: rule, store: store) { saved in selectedID = saved.id }
        }
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
            LinearGradient(colors: [Color(red: 0.045, green: 0.055, blue: 0.15),
                                    Color(red: 0.075, green: 0.09, blue: 0.20),
                                    Color(red: 0.03, green: 0.06, blue: 0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.31, green: 0.17, blue: 0.72).opacity(0.78), .clear],
                           center: .init(x: 0.22, y: -0.12), startRadius: 25, endRadius: 560)
            RadialGradient(colors: [Color(red: 0.12, green: 0.48, blue: 0.67).opacity(0.54), .clear],
                           center: .init(x: 0.90, y: 0.93), startRadius: 0, endRadius: 540)
            Ellipse()
                .strokeBorder(.white.opacity(0.12), lineWidth: 72)
                .frame(width: 680, height: 345)
                .rotationEffect(.degrees(-32))
                .blur(radius: 48)
                .offset(x: 370, y: 200)
        }
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 10) {
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        LinearGradient(colors: [Color(red: 0.69, green: 0.51, blue: 1),
                                                Color(red: 0.26, green: 0.27, blue: 0.89)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 11)
                    )
                    .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.38)) }
                Text("SpaceMouse").font(.system(size: 16, weight: .semibold))
            }
            .padding(.top, 18)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Page.allCases, id: \.self) { option in
                    Button { page = option } label: {
                        Label(option.rawValue, systemImage: option.icon)
                            .font(.system(size: 13, weight: page == option ? .semibold : .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 11)
                            .contentShape(.rect)
                            .background(page == option ? Color.white.opacity(0.16) : .clear,
                                        in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == option ? .isSelected : [])
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle().fill(store.running ? .green : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                    Text(store.running ? "Shortcuts active" : "Shortcuts paused").font(.system(size: 12, weight: .semibold))
                }
                Text(store.running ? "Available from any other app." : "Start shortcuts to use this setup.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: 15)
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 13)
        .glassPanel(radius: 22)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(page.rawValue).font(.system(size: 34, weight: .semibold, design: .default)).tracking(-1.2)
                Text(page == .shortcuts ? "Map mouse gestures to windows and Spaces." : "Set scroll timing and manage Accessibility access.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                if store.running { store.pause() } else { store.start() }
            } label: {
                Label(store.running ? "Pause shortcuts" : "Start shortcuts",
                      systemImage: store.running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.glassProminent)
            .tint(violet)
            .controlSize(.large)
        }
    }

    private var shortcuts: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Bindings").font(.headline)
                    Spacer()
                    Button {
                        draft = BindingRule(modifier: .control, input: .mouse4, action: .missionControl)
                    } label: {
                        Label("Add shortcut", systemImage: "plus")
                    }
                    .buttonStyle(.glassProminent)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.rules) { rule in
                            bindingRow(rule)
                            if rule.id != store.rules.last?.id { Divider().overlay(.white.opacity(0.04)).padding(.leading, 57) }
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 15))
                .glassPanel(radius: 15)
                Text("\(store.rules.filter(\.enabled).count) enabled")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 17) {
                let selected = store.rules.first(where: { $0.id == selectedID }) ?? store.rules.element(at: 5) ?? store.rules.first
                preview(selected)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tile vertically", systemImage: "option")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Hold Option and left-click for the top half, or right-click for the bottom half.")
                        .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPanel(radius: 16)
            }
            .frame(width: 232)
        }
    }

    private func bindingRow(_ rule: BindingRule) -> some View {
        HStack(spacing: 10) {
            Button {
                selectedID = rule.id
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: rule.action.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(rule.enabled ? violet : Color.secondary)
                        .frame(width: 33, height: 33)
                        .background(violet.opacity(rule.enabled ? 0.11 : 0.04), in: .rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rule.action.title).font(.system(size: 13, weight: .semibold))
                        Text("\(rule.modifier.title) · \(rule.input.title)")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(rule.action.title), \(rule.modifier.title), \(rule.input.title)")

            Toggle(isOn: Binding(get: { rule.enabled }, set: { enabled in
                var edited = rule
                edited.enabled = enabled
                store.save(edited)
            })) { Text("Enable \(rule.action.title)") }
            .labelsHidden().toggleStyle(.switch).controlSize(.mini)

            Button {
                selectedID = rule.id
                draft = rule
            } label: {
                Image(systemName: "ellipsis").frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Edit \(rule.action.title)")
            .accessibilityLabel("Edit \(rule.action.title)")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(selectedID == rule.id ? violet.opacity(0.08) : .clear)
    }

    private func preview(_ rule: BindingRule?) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Layout preview").font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(LinearGradient(colors: [violet.opacity(0.61), Color(red: 0.17, green: 0.36, blue: 0.74),
                                                  teal.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                WindowDiagram(action: rule?.action ?? .tileTop)
                    .padding(20)
            }
.frame(height: 144)
            .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.23)) }
            .accessibilityHidden(true)
            Text(rule?.action.title ?? "Add a shortcut").font(.system(size: 16, weight: .semibold))
            if let rule {
                Text("\(rule.modifier.title) · \(rule.input.title)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: 19)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 17) {
                timingSlider("Scroll pause", value: $store.scrollGap, range: 0.15 ... 0.9,
                             detail: "Pause before another scroll in the same direction moves a Space.")
            }
            .padding(18)
            .glassPanel(radius: 18)

            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Accessibility").font(.headline)
                    Text(store.trusted ? "SpaceMouse has access." : "Required to detect mouse shortcuts and move windows.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }.buttonStyle(.glass)
            }
            .padding(18)
            .glassPanel(radius: 18)

            Button("Restore starter shortcuts") { restoreConfirmation = true }
                .buttonStyle(.glass)
            Spacer()
        }
    }

    private func timingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(Int(value.wrappedValue * 1000)) ms").monospacedDigit().foregroundStyle(.secondary)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: range, step: 0.05) { Text(title) }
                .labelsHidden()
        }
    }
}

private struct WindowDiagram: View {
    let action: ShortcutAction
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let frame = tile(width: w, height: h)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9).fill(.black.opacity(0.2))
                RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.50))
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white.opacity(0.34))
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.76)) }
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                Image(systemName: action.symbol)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
    }

    private func tile(width w: Double, height h: Double) -> CGRect {
        switch action {
        case .tileLeft: CGRect(x: 6, y: 6, width: w / 2 - 9, height: h - 12)
        case .tileRight: CGRect(x: w / 2 + 3, y: 6, width: w / 2 - 9, height: h - 12)
        case .tileTop: CGRect(x: 6, y: 6, width: w - 12, height: h / 2 - 9)
        case .tileBottom: CGRect(x: 6, y: h / 2 + 3, width: w - 12, height: h / 2 - 9)
        case .fullScreen, .fill: CGRect(x: 6, y: 6, width: w - 12, height: h - 12)
        default: CGRect(x: w * 0.17, y: h * 0.15, width: w * 0.66, height: h * 0.70)
        }
    }
}

private struct ShortcutEditor: View {
    @State var rule: BindingRule
    @ObservedObject var store: ShortcutStore
    let onSave: (BindingRule) -> Void
    @Environment(\.dismiss) private var dismiss

    private var existing: Bool { store.rules.contains { $0.id == rule.id } }
    private var conflict: Bool { store.rules.contains { rule.conflicts(with: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text(existing ? "Edit shortcut" : "Add shortcut").font(.title2.weight(.semibold))
            Form {
                Picker("Modifier", selection: $rule.modifier) {
                    ForEach(Modifier.allCases) { Text($0.title).tag($0) }
                }
                Picker("Mouse input", selection: $rule.input) {
                    ForEach(MouseInput.allCases) { Text($0.title).tag($0) }
                }
                Picker("Action", selection: $rule.action) {
                    ForEach(ShortcutAction.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Enabled", isOn: $rule.enabled)
            }
            if conflict {
                Label("That combination is already enabled.", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.red)
            }
            HStack {
                if existing {
                    Button("Delete", role: .destructive) { store.delete(rule); dismiss() }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.save(rule)
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(conflict)
            }
        }
        .padding(23)
        .frame(width: 440)
    }
}

private extension Array {
    func element(at index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
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
