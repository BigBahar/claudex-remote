import Foundation

struct Failure: LocalizedError {
    var message: String
    var code: Int?
    var errorDescription: String? { message }
}

/// Talks to the Claudex app on the PC. Every call but hello and pair carries the device token.
final class Client {
    let base: URL
    let token: String?
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    init(base: URL, token: String?) { self.base = base; self.token = token }

    private func request(_ path: String, method: String = "GET", body: Encodable? = nil, timeout: TimeInterval = 30) -> URLRequest {
        var r = URLRequest(url: URL(string: path, relativeTo: base)!.absoluteURL, timeoutInterval: timeout)
        r.httpMethod = method
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONEncoder().encode(AnyEncodable(body))
        }
        return r
    }

    @discardableResult
    private func send(_ r: URLRequest) async throws -> Data {
        let data: Data, resp: URLResponse
        do { (data, resp) = try await Self.session.data(for: r) }
        catch { throw Failure(message: "Can't reach your PC. Is Claudex running, with Phone remote on?") }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 { return data }
        let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        throw Failure(message: msg ?? "The PC answered \(code)", code: code)
    }

    func get<T: Decodable>(_ path: String, as _: T.Type = T.self, timeout: TimeInterval = 30) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await send(request(path, timeout: timeout)))
    }

    func post(_ path: String, _ body: Encodable = [String: String]()) async throws {
        try await send(request(path, method: "POST", body: body))
    }

    func post<T: Decodable>(_ path: String, _ body: Encodable, as _: T.Type) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await send(request(path, method: "POST", body: body)))
    }

    /// Live events from the PC. Ends when the connection drops; the caller reconnects.
    func events(_ onEvent: @escaping (String, Data) -> Void) async throws {
        var r = request("/api/events", timeout: 24 * 3600)
        r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 24 * 3600
        let (bytes, resp) = try await URLSession(configuration: cfg).bytes(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure(message: "Not paired", code: (resp as? HTTPURLResponse)?.statusCode)
        }
        var name = ""
        // The PC sends "event:" then "data:" back to back, so a data line completes the pair.
        for try await line in bytes.lines {
            if line.hasPrefix("event: ") { name = String(line.dropFirst(7)) }
            else if line.hasPrefix("data: ") { onEvent(name, Data(line.dropFirst(6).utf8)) }
        }
    }

    /// The first address that answers is the one to use; the QR carries Tailscale and LAN addresses.
    static func find(hosts: [String], port: Int) async -> URL? {
        await withTaskGroup(of: URL?.self) { group in
            for h in hosts {
                group.addTask {
                    guard let url = URL(string: "http://\(h):\(port)") else { return nil }
                    let c = Client(base: url, token: nil)
                    let hello = try? await c.send(c.request("/api/hello", timeout: 3))
                    return hello == nil ? nil : url
                }
            }
            for await found in group { if let found { group.cancelAll(); return found } }
            return nil
        }
    }

    struct PairReply: Decodable { var token: String; var deviceId: String }
    func pair(code: String, name: String) async throws -> PairReply {
        try await post("/api/pair", ["code": code, "name": name], as: PairReply.self)
    }
}

struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ v: Encodable) { value = v }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

struct NewSessionBody: Encodable {
    var agent: String, model: String, effort: String, mode: String, folder: String, worktree: Bool, prompt: String
}
struct TextBody: Encodable { var text: String }
struct ModeBody: Encodable { var mode: String }
struct AnswerBody: Encodable { var eventId: String; var value: AnyEncodable }
