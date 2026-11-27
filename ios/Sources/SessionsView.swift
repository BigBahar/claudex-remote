import SwiftUI

struct SessionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Updates.self) private var updates
    @State private var newSession = false
    @State private var newKind: SessionKind = .chat
    @State private var settings = false
    @State private var path: [String] = []

    private var groups: [(name: String, items: [Session])] {
        let by = Dictionary(grouping: model.sessions.filter { $0.status != "archived" }, by: \.projectPath)
        return by.map { (name: URL(fileURLWithPath: $0.key).lastPathComponent, items: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { ($0.items.first?.updatedAt ?? 0) > ($1.items.first?.updatedAt ?? 0) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: 12) {
                        Button { newKind = .chat; newSession = true } label: { Label("Chat", systemImage: "bubble.left") }
                            .frame(maxWidth: .infinity)
                        Button { newKind = .duet; newSession = true } label: { Label("Duet", systemImage: "point.3.connected.trianglepath.dotted") }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.link != .live)
                    .listRowBackground(Color.clear)
                }
                if case .offline(let m) = model.link { Banner(text: m, action: ("Retry", model.reconnect)) }
                if model.link == .connecting { HStack { ProgressView(); Text("Connecting to your PC…").foregroundStyle(Theme.muted) }.listRowBackground(Color.clear) }
                if updates.latest != nil {
                    Banner(text: "Version \(updates.latest!.name) is ready.", action: ("Update now", { Task { _ = await updates.install() } }))
                }
                if model.sessions.isEmpty && model.link == .live {
                    Text("No sessions yet. Start one with the pencil, or on your PC.").foregroundStyle(Theme.muted).listRowBackground(Color.clear)
                }
                ForEach(groups, id: \.name) { g in
                    Section {
                        ForEach(g.items) { s in
                            NavigationLink(value: s.id) { SessionRow(s: s) }.listRowBackground(Theme.surface)
                        }
                    } header: {
                        Text(g.name).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).textCase(nil)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Sessions")
            .navigationDestination(for: String.self) { SessionView(id: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") }
                ToolbarItem(placement: .topBarTrailing) { Button { newKind = .project; newSession = true } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("New session").disabled(model.link != .live) }
            }
            .refreshable { model.reconnect(); try? await Task.sleep(nanoseconds: 600_000_000) }
        }
        .sheet(isPresented: $newSession) { NewSessionView(kind: newKind) { id in path.append(id) } }
        .sheet(isPresented: $settings) { SettingsView() }
    }
}

struct Banner: View {
    var text: String
    var action: (String, () -> Void)
    var body: some View {
        HStack {
            Text(text).font(.subheadline).foregroundStyle(Theme.ink)
            Spacer()
            Button(action.0, action: action.1).font(.subheadline.weight(.semibold))
        }
        .padding(12).background(Theme.raised, in: RoundedRectangle(cornerRadius: 12)).listRowBackground(Color.clear)
    }
}

struct StatusDot: View {
    var s: Session
    var body: some View {
        Group {
            if s.needsOK { Circle().fill(Theme.ember) }
            else if s.status == "running" { ProgressView().controlSize(.mini) }
            else if s.status == "error" { Circle().fill(Theme.bad) }
            else if s.unread == true { Circle().fill(Theme.ok) }
            else { Circle().fill(Theme.line) }
        }
        .frame(width: 10, height: 10)
        .accessibilityLabel(s.needsOK ? "Needs your OK" : s.status == "running" ? "Running" : s.status == "error" ? "Failed" : s.unread == true ? "Done, unread" : "Idle")
    }
}

struct SessionRow: View {
    var s: Session
    var body: some View {
        HStack(spacing: 12) {
            StatusDot(s: s)
            VStack(alignment: .leading, spacing: 3) {
                BidiText(text: s.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(2)
                HStack(spacing: 6) {
                    Text(Agent(rawValue: s.agent)?.label ?? s.agent)
                    Text("·")
                    Text(s.needsOK ? "Needs your OK" : s.status == "running" ? "Running" : s.date.formatted(.relative(presentation: .named)))
                        .foregroundStyle(s.needsOK ? Theme.ember : Theme.muted)
                }
                .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
    }
}
