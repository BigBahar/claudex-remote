import Foundation
import Observation
import Security
import UIKit
import UserNotifications

/// The token lives in the Keychain; the addresses and the PC's name are not secret.
enum Keychain {
    static func set(_ value: String?, for key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.silolabs.claudex", kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        guard let value else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.silolabs.claudex", kSecAttrAccount as String: key, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

struct Env<T: Decodable>: Decodable { var payload: T }

enum Link: Equatable { case unpaired, connecting, live, offline(String) }

@MainActor
@Observable
final class AppModel {
    var link: Link = Keychain.get("token") == nil ? .unpaired : .connecting
    var sessions: [Session] = []
    var transcripts: [String: [Ev]] = [:]
    var hosts: [String] = UserDefaults.standard.stringArray(forKey: "hosts") ?? []
    var port: Int = UserDefaults.standard.integer(forKey: "port") == 0 ? 18932 : UserDefaults.standard.integer(forKey: "port")
    var pcVersion = ""
    var notice: String?
    /// Set by a claudex-remote:// link or the scanner; the pairing screen reads it.
    var pairLink: String?

    private var client: Client?
    private var stream: Task<Void, Never>?
    private var lastStatus: [String: String] = [:]

    var paired: Bool { Keychain.get("token") != nil }

    // MARK: connecting

    func start() {
        guard let token = Keychain.get("token") else { link = .unpaired; return }
        stream?.cancel()
        stream = Task { [weak self] in
            var delay: UInt64 = 1
            while !Task.isCancelled {
                guard let self else { return }
                await self.run(token: token)
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 15)
            }
        }
    }

    func stop() { stream?.cancel(); stream = nil }

    /// Resolves the PC, loads the sessions, then follows the live stream until it drops.
    private func run(token: String) async {
        if case .live = link {} else { link = .connecting }
        guard let base = await Client.find(hosts: hosts, port: port) else { link = .offline("Can't reach your PC. Is Claudex running, and are you on Tailscale or the same Wi-Fi?"); return }
        let c = Client(base: base, token: token)
        client = c
        do {
            sessions = try await c.get("/api/sessions")
            sessions.forEach { lastStatus[$0.id] = $0.status }
            link = .live
            // Reload what is open so nothing missed while offline stays missing.
            for id in transcripts.keys { await loadTranscript(id) }
            try await c.events { [weak self] name, data in
                Task { @MainActor in self?.handle(name, data) }
            }
            link = .offline("The connection dropped. Reconnecting…")
        } catch let f as Failure where f.code == 401 {
            unpair(message: "This phone was removed in Claudex. Pair it again.")
        } catch {
            link = .offline((error as? Failure)?.message ?? error.localizedDescription)
        }
    }

    func reconnect() { start() }

    private func handle(_ name: String, _ data: Data) {
        let dec = JSONDecoder()
        switch name {
        case "session:meta":
            guard let s = (try? dec.decode(Env<Session>.self, from: data))?.payload else { return }
            transition(s)
            if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.append(s) }
        case "session:removed":
            guard let id = (try? dec.decode(Env<String>.self, from: data))?.payload else { return }
            sessions.removeAll { $0.id == id }
            transcripts[id] = nil
        case "session:event":
            guard let p = (try? dec.decode(Env<EventPayload>.self, from: data))?.payload else { return }
            guard var list = transcripts[p.id] else { return } // not open: it loads in full when opened
            if p.index < list.count { list[p.index] = p.ev }
            else if p.index == list.count { list.append(p.ev) }
            else { Task { await loadTranscript(p.id) }; return }
            transcripts[p.id] = list
            // The meta event for a pending approval can lag; keep the count fresh from the transcript itself.
            if p.ev.k == "approval" || p.ev.k == "question", let i = sessions.firstIndex(where: { $0.id == p.id }) {
                sessions[i].pending = list.filter { ($0.k == "approval" || $0.k == "question") && $0.state == "pending" }.count
            }
        default: break
        }
    }

    /// A session that has just finished, or just needs the person, is worth a banner.
    private func transition(_ s: Session) {
        let before = lastStatus[s.id]
        lastStatus[s.id] = s.status
        guard before != s.status else { return }
        if s.status == "waiting" { banner(s, "Needs your OK") }
        else if before == "running" && s.status == "idle" { banner(s, "Finished") }
    }

    private func banner(_ s: Session, _ text: String) {
        let c = UNMutableNotificationContent()
        c.title = s.title
        c.body = text
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(s.id)-\(text)", content: c, trigger: nil))
    }

    func askNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: pairing

    struct PairTarget { var code: String; var hosts: [String]; var port: Int }

    static func parse(_ s: String) -> PairTarget? {
        guard let u = URLComponents(string: s), u.scheme == "claudex-remote", u.host == "pair" else { return nil }
        let q = Dictionary((u.queryItems ?? []).compactMap { i in i.value.map { (i.name, $0) } }, uniquingKeysWith: { a, _ in a })
        guard let code = q["c"], let hosts = q["h"]?.split(separator: ",").map(String.init), !hosts.isEmpty else { return nil }
        return PairTarget(code: code, hosts: hosts, port: Int(q["p"] ?? "") ?? 18932)
    }

    func pair(_ t: PairTarget) async throws {
        guard let base = await Client.find(hosts: t.hosts, port: t.port) else {
            throw Failure(message: "Can't reach your PC at \(t.hosts.joined(separator: ", ")). Turn Tailscale on, or join the same Wi-Fi.")
        }
        let c = Client(base: base, token: nil)
        let r = try await c.pair(code: t.code, name: UIDevice.current.name)
        Keychain.set(r.token, for: "token")
        hosts = t.hosts; port = t.port
        UserDefaults.standard.set(hosts, forKey: "hosts")
        UserDefaults.standard.set(port, forKey: "port")
        askNotifications()
        start()
    }

    func unpair(message: String? = nil) {
        stop()
        Keychain.set(nil, for: "token")
        sessions = []; transcripts = [:]; client = nil
        link = .unpaired
        notice = message
    }

    // MARK: operations (all of them run on the PC)

    private func need() throws -> Client {
        guard let client else { throw Failure(message: "Not connected to your PC yet.") }
        return client
    }

    func loadTranscript(_ id: String) async {
        guard let c = client, let t: Transcript = try? await c.get("/api/sessions/\(id)/transcript") else { return }
        transcripts[id] = t.events
    }

    func send(_ id: String, _ text: String) async throws { try await need().post("/api/sessions/\(id)/send", TextBody(text: text)) }
    func stop(_ id: String) async throws { try await need().post("/api/sessions/\(id)/interrupt") }
    func setMode(_ id: String, _ m: Mode) async throws { try await need().post("/api/sessions/\(id)/mode", ModeBody(mode: m.rawValue)) }
    func markRead(_ id: String) { Task { try? await client?.post("/api/sessions/\(id)/read") } }

    func answer(_ id: String, event: String, _ value: Encodable) async throws {
        try await need().post("/api/sessions/\(id)/answer", AnswerBody(eventId: event, value: AnyEncodable(value)))
    }

    func create(_ body: NewSessionBody) async throws -> Session {
        let s: Session = try await need().post(body.team == nil ? "/api/sessions" : "/api/cowork", body, as: Session.self)
        if !sessions.contains(where: { $0.id == s.id }) { sessions.insert(s, at: 0) }
        return s
    }

    func models(_ agent: Agent) async -> [ModelInfo] { (try? await client?.get("/api/models?agent=\(agent.rawValue)", as: [ModelInfo].self, timeout: 60)) ?? [] }
    func defaults() async -> Defaults? { try? await client?.get("/api/defaults", as: Defaults.self) }
    func folders() async -> Folders? { try? await client?.get("/api/folders", as: Folders.self) }
    func changes(_ id: String) async -> Changes? { try? await client?.get("/api/sessions/\(id)/changes", as: Changes.self) }
    func diff(_ id: String, _ file: String) async -> String {
        let q = file.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? file
        return ((try? await client?.get("/api/sessions/\(id)/diff?file=\(q)", as: Diff.self))?.diff) ?? "Couldn't load this diff."
    }
}
