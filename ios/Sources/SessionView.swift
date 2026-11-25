import SwiftUI

struct SessionView: View {
    let id: String
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var error: String?
    @State private var changes = false
    @FocusState private var focused: Bool

    private var session: Session? { model.sessions.first { $0.id == id } }
    private var events: [Ev] { model.transcripts[id] ?? [] }
    private var running: Bool { session?.status == "running" || session?.status == "waiting" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(events.enumerated()), id: \.offset) { i, ev in
                            EvView(ev: ev, session: id) { err in error = err }.id(i)
                        }
                        if running { HStack { ProgressView().controlSize(.small); Text("Working…").font(.caption).foregroundStyle(Theme.muted) }.id("busy") }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: events.count) { _, _ in withAnimation { proxy.scrollTo("end") } }
                .onChange(of: events.last?.output) { _, _ in proxy.scrollTo("end") }
                .task { await model.loadTranscript(id); proxy.scrollTo("end") }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.bad).padding(.horizontal, 16).padding(.top, 6).frame(maxWidth: .infinity, alignment: .leading) }
            composer
        }
        .background(Theme.bg)
        .navigationTitle(session?.title ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { changes = true } label: { Label("Changed files", systemImage: "doc.text.magnifyingglass") }
                    if let s = session {
                        Picker("Permissions", selection: Binding(get: { Mode(rawValue: s.mode) ?? .ask }, set: { m in Task { try? await model.setMode(id, m) } })) {
                            ForEach(Mode.allCases) { Text($0.label).tag($0) }
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $changes) { ChangesView(session: id) }
        .onAppear { model.markRead(id) }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(running ? "Add to the running session" : "Reply", text: $text, axis: .vertical)
                .lineLimit(1...6).focused($focused)
                .environment(\.layoutDirection, text.isRTL ? .rightToLeft : .leftToRight)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line))
            if running && text.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { Task { do { try await model.stop(id) } catch { self.error = error.localizedDescription } } } label: {
                    Image(systemName: "stop.fill").font(.body.weight(.bold)).frame(width: 40, height: 40).background(Theme.ink, in: Circle()).foregroundStyle(Theme.bg)
                }.accessibilityLabel("Stop")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.body.weight(.bold)).frame(width: 40, height: 40)
                        .background(text.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.line : Theme.ember, in: Circle()).foregroundStyle(.white)
                }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8).background(Theme.bg)
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        text = ""; error = nil
        Task { do { try await model.send(id, t) } catch { self.error = error.localizedDescription; text = t } }
    }
}

struct EvView: View {
    let ev: Ev
    let session: String
    var onError: (String) -> Void
    @Environment(AppModel.self) private var model
    @State private var open = false
    @State private var picked: [String: Set<String>] = [:]
    @State private var other: [String: String] = [:]

    var body: some View {
        switch ev.k {
        case "user":
            BidiText(text: ev.text ?? "").foregroundStyle(Theme.ink).padding(12)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16)).frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 40)
        case "text":
            BidiText(text: ev.text ?? "", markdown: true).foregroundStyle(Theme.ink)
        case "thinking":
            DisclosureGroup("Thinking", isExpanded: $open) { BidiText(text: ev.text ?? "").font(.footnote).foregroundStyle(Theme.muted) }
                .font(.footnote).foregroundStyle(Theme.muted)
        case "tool":
            card {
                HStack(spacing: 8) {
                    Image(systemName: ev.status == "error" ? "exclamationmark.triangle" : "wrench.and.screwdriver").foregroundStyle(ev.status == "error" ? Theme.bad : Theme.muted)
                    Text(ev.name ?? "Tool").font(.footnote.weight(.semibold))
                    Text(ev.input?.summary ?? "").font(.footnote.monospaced()).lineLimit(1).foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                    if ev.status == "running" { ProgressView().controlSize(.mini) }
                }
                if let o = ev.output, !o.isEmpty {
                    Button(open ? "Hide output" : "Show output") { open.toggle() }.font(.caption)
                    if open { Mono(text: o) }
                }
            }
        case "command":
            card {
                Text("$ " + (ev.command ?? "")).font(.footnote.monospaced().weight(.semibold)).foregroundStyle(Theme.ink)
                if let o = ev.output, !o.isEmpty { Mono(text: String(o.suffix(open ? 6000 : 400))); Button(open ? "Less" : "More") { open.toggle() }.font(.caption) }
                if ev.status == "running" { ProgressView().controlSize(.mini) }
                else if let c = ev.exitCode, c != 0 { Text("Exited with \(c)").font(.caption).foregroundStyle(Theme.bad) }
            }
        case "patch":
            card {
                Label("Edited \(ev.files?.count ?? 0) file\(ev.files?.count == 1 ? "" : "s")", systemImage: "doc.badge.gearshape").font(.footnote.weight(.semibold))
                ForEach(ev.files ?? [], id: \.self) { f in
                    DisclosureGroup { if let d = f.diff { DiffText(diff: d) } } label: { Text(f.path).font(.footnote.monospaced()) }.font(.footnote)
                }
            }
        case "plan":
            card {
                Label("Plan", systemImage: "checklist").font(.footnote.weight(.semibold))
                ForEach(ev.items ?? [], id: \.self) { it in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: it.status == "completed" ? "checkmark.circle.fill" : it.status == "in_progress" ? "circle.dotted" : "circle").foregroundStyle(it.status == "completed" ? Theme.ok : Theme.muted)
                        BidiText(text: it.content).font(.footnote)
                    }
                }
            }
        case "approval": approval
        case "question": question
        case "error":
            Label(ev.text ?? "Error", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.bad)
        case "turn":
            if ev.state == "end", let ms = ev.ms { Text("Done in \(Int(ms / 1000)) s").font(.caption2).foregroundStyle(Theme.muted).frame(maxWidth: .infinity) }
        default: EmptyView()
        }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8, content: c).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    private func reply(_ value: Encodable) {
        guard let eid = ev.eid else { return }
        Task { do { try await model.answer(session, event: eid, value) } catch { onError(error.localizedDescription) } }
    }

    private var approval: some View {
        card {
            Label(ev.title ?? "Needs your OK", systemImage: "hand.raised").font(.subheadline.weight(.semibold)).foregroundStyle(ev.state == "pending" ? Theme.ember : Theme.ink)
            if let d = ev.detail, !d.isEmpty { Mono(text: d) }
            if ev.state == "pending" {
                HStack {
                    Button("Allow") { reply("allow") }.buttonStyle(.borderedProminent)
                    Button("Always, this session") { reply("allow-session") }.buttonStyle(.bordered)
                    Button("Don't") { reply("deny") }.buttonStyle(.bordered).tint(Theme.bad)
                }.font(.footnote).controlSize(.small)
            } else {
                Text(ev.state == "denied" ? "Not allowed" : "Allowed").font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private var question: some View {
        card {
            ForEach(ev.questions ?? [], id: \.self) { q in
                VStack(alignment: .leading, spacing: 8) {
                    BidiText(text: q.question).font(.subheadline.weight(.semibold))
                    if ev.state == "answered" { Text(ev.answers?[q.question] ?? "").font(.subheadline).foregroundStyle(Theme.ember) }
                    else {
                        ForEach(q.options, id: \.self) { o in
                            let on = picked[q.question]?.contains(o.label) == true
                            Button {
                                var set = picked[q.question] ?? []
                                if q.multiSelect == true { if on { set.remove(o.label) } else { set.insert(o.label) } } else { set = [o.label] }
                                picked[q.question] = set
                                if ev.questions?.count == 1 && q.multiSelect != true { submit() }
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.ember : Theme.muted)
                                    VStack(alignment: .leading) {
                                        BidiText(text: o.label).font(.subheadline).foregroundStyle(Theme.ink)
                                        if let d = o.description { BidiText(text: d).font(.caption).foregroundStyle(Theme.muted) }
                                    }
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                        TextField("Or type your own answer", text: Binding(get: { other[q.question] ?? "" }, set: { other[q.question] = $0 }))
                            .padding(10).background(Theme.raised, in: RoundedRectangle(cornerRadius: 10)).font(.subheadline)
                    }
                }
            }
            if ev.state != "answered" { Button("Send answers") { submit() }.buttonStyle(.borderedProminent).controlSize(.small) }
        }
    }

    private func submit() {
        var answers: [String: String] = [:]
        for q in ev.questions ?? [] {
            let typed = other[q.question]?.trimmingCharacters(in: .whitespaces) ?? ""
            answers[q.question] = typed.isEmpty ? q.options.map(\.label).filter { picked[q.question]?.contains($0) == true }.joined(separator: ", ") : typed
        }
        reply(answers)
    }
}

struct Mono: View {
    var text: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text).font(.caption.monospaced()).foregroundStyle(Theme.ink).textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
        }
        .padding(8).background(Theme.raised, in: RoundedRectangle(cornerRadius: 8)).environment(\.layoutDirection, .leftToRight)
    }
}

struct DiffText: View {
    var diff: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, l in
                    let s = String(l)
                    Text(s.isEmpty ? " " : s).font(.caption2.monospaced())
                        .foregroundStyle(s.hasPrefix("+") && !s.hasPrefix("+++") ? Theme.ok : s.hasPrefix("-") && !s.hasPrefix("---") ? Theme.bad : s.hasPrefix("@@") ? Theme.ember : Theme.ink)
                }
            }.textSelection(.enabled)
        }
        .padding(8).background(Theme.raised, in: RoundedRectangle(cornerRadius: 8)).environment(\.layoutDirection, .leftToRight)
    }
}
