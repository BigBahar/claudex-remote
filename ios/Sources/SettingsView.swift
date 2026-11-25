import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Updates.self) private var updates
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("This PC") {
                    row("Status", { switch model.link { case .live: return "Connected"; case .connecting: return "Connecting…"; case .offline: return "Offline"; case .unpaired: return "Not paired" } }())
                    row("Address", model.hosts.first ?? "—")
                    Button("Unpair this phone", role: .destructive) { confirm = true }
                }
                Section("Updates") {
                    row("Claudex Remote", "\(Updates.currentName) (build \(Updates.current))")
                    if let l = updates.latest {
                        row("Waiting", "Version \(l.name)")
                        Button("Update now") { Task { _ = await updates.install() } }
                    } else {
                        row("Status", updates.checking ? "Checking…" : updates.checked == nil ? "Not checked yet" : "Up to date")
                    }
                    if !updates.message.isEmpty { Text(updates.message).font(.footnote).foregroundStyle(Theme.muted) }
                    Button("Check now") { Task { await updates.check(force: true) } }.disabled(updates.checking)
                }
                Section { Text("Banners appear while Claudex Remote is open or has just been in the background. iOS doesn't allow a sideloaded app to be woken by the PC.").font(.footnote).foregroundStyle(Theme.muted) }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Unpair this phone?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Unpair", role: .destructive) { model.unpair(); dismiss() }
            } message: { Text("You can pair again from Claudex on your PC.") }
        }
    }

    private func row(_ k: String, _ v: String) -> some View { HStack { Text(k); Spacer(); Text(v).foregroundStyle(Theme.muted) } }
}
