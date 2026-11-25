import SwiftUI

struct ChangesView: View {
    let session: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var changes: Changes?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView().listRowBackground(Color.clear) }
                else if changes?.repo != true { Text("This folder isn't a git repository, so there is nothing to compare.").foregroundStyle(Theme.muted).listRowBackground(Color.clear) }
                else if changes?.files?.isEmpty ?? true { Text("No changes.").foregroundStyle(Theme.muted).listRowBackground(Color.clear) }
                ForEach(changes?.files ?? []) { f in
                    NavigationLink { FileDiff(session: session, file: f.path) } label: {
                        HStack {
                            Text(f.path).font(.footnote.monospaced()).lineLimit(1).truncationMode(.head)
                            Spacer()
                            Text("+\(f.added)").foregroundStyle(Theme.ok); Text("−\(f.removed)").foregroundStyle(Theme.bad)
                        }.font(.caption)
                    }.listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle(changes?.branch.map { "Changes on \($0)" } ?? "Changes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { changes = await model.changes(session); loading = false }
        }
    }
}

struct FileDiff: View {
    let session: String
    let file: String
    @Environment(AppModel.self) private var model
    @State private var diff: String?
    var body: some View {
        ScrollView { if let diff { DiffText(diff: diff).padding(12) } else { ProgressView().padding(40) } }
            .background(Theme.bg).navigationTitle(URL(fileURLWithPath: file).lastPathComponent).navigationBarTitleDisplayMode(.inline)
            .task { diff = await model.diff(session, file) }
    }
}
