import SwiftUI
import UserNotifications

/// Lets a banner show even while the app is open.
final class Banners: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}

@main
struct ClaudexRemoteApp: App {
    private let banners = Banners()
    @State private var model = AppModel()
    @State private var updates = Updates()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Root()
                .environment(model)
                .environment(updates)
                .tint(Theme.ember)
                .task {
                    UNUserNotificationCenter.current().delegate = banners
                    // Open straight onto a pairing link in the launch arguments (used for simulator checks).
                    if let i = CommandLine.arguments.firstIndex(of: "-claudexPairURL"), i + 1 < CommandLine.arguments.count { model.pairLink = CommandLine.arguments[i + 1] }
                    model.start()
                    await updates.check(force: true)
                }
                .onOpenURL { model.pairLink = $0.absoluteString }
                .onChange(of: phase) { _, p in
                    if p == .active { model.start(); Task { await updates.check() } }
                }
        }
    }
}

struct Root: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if model.link == .unpaired { PairView() } else { SessionsView() }
        }
    }
}
