import Foundation
import Observation
import UIKit

/// Updates from inside the app, as far as iOS lets an app go without the App Store.
/// Silo Store (Uri's SideStore source) lists the newest build; the app checks it on open and whenever it comes
/// back to the front, shows when a newer build is waiting, and "Update now" hands the IPA to SideStore
/// (sidestore://install), which re-signs and installs it in place, keeping the app's data. iOS does not let
/// an app install itself; this is the shortest way round that it allows.
@MainActor
@Observable
final class Updates {
    struct Latest: Equatable { var build: Int; var name: String; var ipa: URL }

    static let feed = URL(string: "https://bigbahar.github.io/silo-store/source.json")!
    static let bundle = "com.silolabs.claudex"

    var latest: Latest?
    var checked: Date?
    var message = ""
    var checking = false

    static var current: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0 }
    static var currentName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    func check(force: Bool = false) async {
        if !force, let c = checked, Date().timeIntervalSince(c) < 1800 { return }
        checking = true
        defer { checking = false }
        do {
            var r = URLRequest(url: Self.feed, timeoutInterval: 15)
            r.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, resp) = try await URLSession.shared.data(for: r)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let apps = root["apps"] as? [[String: Any]],
                  let app = apps.first(where: { $0["bundleIdentifier"] as? String == Self.bundle })
            else { message = "Claudex isn't in Silo Store yet."; checked = Date(); return }
            // AltStore sources list releases newest first under "versions"; older ones put the fields on the app.
            let v = (app["versions"] as? [[String: Any]])?.first ?? app
            let name = v["version"] as? String ?? ""
            let build = Int(v["buildVersion"] as? String ?? "") ?? Int(name.split(separator: ".").last ?? "") ?? 0
            if let s = v["downloadURL"] as? String, let url = URL(string: s), build > Self.current {
                latest = Latest(build: build, name: name, ipa: url)
            } else { latest = nil }
            message = ""
            checked = Date()
        } catch {
            message = "Couldn't check for updates."
        }
    }

    /// Opens the installer the phone has. False if it has neither.
    func install() async -> Bool {
        guard let latest else { return false }
        let link = latest.ipa.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        for scheme in ["sidestore", "altstore"] {
            if let url = URL(string: "\(scheme)://install?url=\(link)"), UIApplication.shared.canOpenURL(url) {
                return await UIApplication.shared.open(url)
            }
        }
        message = "Open Silo Store to install the update; it wasn't found on this iPhone."
        return false
    }
}
