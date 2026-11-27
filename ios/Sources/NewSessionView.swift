import SwiftUI

struct NewSessionView: View {
    var opened: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var agent: Agent = .claude
    @State private var mode: Mode = .auto
    @State private var models: [ModelInfo] = []
    @State private var model_: String = ""
    @State private var effort = ""
    @State private var folders: [String] = []
    @State private var folder = ""
    @State private var chat = false
    @State private var cowork = false
    @State private var planner: Agent = .local
    @State private var builder: Agent = .codex
    @State private var reviewer: Agent = .claude
    @State private var worktree = false
    @State private var prompt = ""
    @State private var defaults: Defaults?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    Toggle("Chat without a project", isOn: $chat)
                    if !chat {
                        Picker("Folder", selection: $folder) { ForEach(folders, id: \.self) { Text(URL(fileURLWithPath: $0).lastPathComponent).tag($0) } }
                        Toggle("In a new git worktree", isOn: $worktree)
                    }
                }
                Section("Agent") {
                    Toggle("Work together", isOn: $cowork)
                    if cowork {
                        Picker("Plans", selection: $planner) { ForEach(Agent.allCases) { Text($0.label).tag($0) } }
                        Picker("Builds", selection: $builder) { ForEach(Agent.allCases) { Text($0.label).tag($0) } }
                        Picker("Reviews", selection: $reviewer) { ForEach(Agent.allCases) { Text($0.label).tag($0) } }
                    }
                    Picker("Agent", selection: $agent) { ForEach(Agent.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    if !models.isEmpty { Picker("Model", selection: $model_) { ForEach(models) { Text($0.label).tag($0.id) } } }
                    if let m = models.first(where: { $0.id == model_ }), !m.efforts.isEmpty {
                        Picker("Effort", selection: $effort) { ForEach(m.efforts, id: \.self) { Text($0.capitalized).tag($0) } }
                    }
                    Picker("Permissions", selection: $mode) { ForEach(Mode.allCases) { Text($0.label).tag($0) } }
                }
                Section("Task") {
                    TextField("Describe a task", text: $prompt, axis: .vertical).lineLimit(3...10)
                        .environment(\.layoutDirection, prompt.isRTL ? .rightToLeft : .leftToRight)
                }
                if let error { Text(error).foregroundStyle(Theme.bad).font(.footnote) }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("New session").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Start") { start() }.disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!chat && folder.isEmpty)) }
                }
            }
            .task {
                defaults = await model.defaults()
                if let f = await model.folders() { folders = f.folders; folder = f.default }
                if let d = defaults { agent = Agent(rawValue: d.agent) ?? .claude; mode = Mode(rawValue: d.mode) ?? .auto }
                await loadModels()
            }
            .onChange(of: agent) { _, _ in Task { await loadModels() } }
        }
    }

    private func loadModels() async {
        models = await model.models(agent)
        let want = agent == .claude ? defaults?.claudeModel : agent == .codex ? defaults?.codexModel : defaults?.localModel
        let pick = models.first(where: { $0.id == want || $0.resolves == want }) ?? models.first(where: { $0.isDefault == true }) ?? models.first
        model_ = pick?.id ?? want ?? ""
        effort = pick?.defaultEffort ?? ""
    }

    private func start() {
        busy = true; error = nil
        func member(_ agent: Agent) -> TeamMember {
            let selected = agent == .claude ? defaults?.claudeModel : agent == .codex ? defaults?.codexModel : defaults?.localModel
            return TeamMember(agent: agent.rawValue, model: selected ?? "")
        }
        let team = cowork ? ["plan": member(planner), "build": member(builder), "review": member(reviewer)] : nil
        let body = NewSessionBody(agent: agent.rawValue, model: model_, effort: effort, mode: mode.rawValue, folder: chat ? "" : folder, worktree: !chat && !cowork && worktree, prompt: prompt, team: team)
        Task {
            do {
                let s = try await model.create(body)
                dismiss()
                opened(s.id)
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

