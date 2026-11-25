import Foundation

struct Session: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var agent: String
    var model: String
    var effort: String
    var mode: String
    var cwd: String
    var repo: String?
    var branch: String?
    var createdAt: Double
    var updatedAt: Double
    var status: String
    var unread: Bool?
    var pending: Int?

    /// Sessions are grouped by the project folder the person picked.
    var project: String { URL(fileURLWithPath: repo ?? cwd).lastPathComponent }
    var projectPath: String { repo ?? cwd }
    var date: Date { Date(timeIntervalSince1970: updatedAt / 1000) }
    var needsOK: Bool { status == "waiting" || (pending ?? 0) > 0 }
}

struct Question: Codable, Hashable {
    var question: String
    var header: String?
    var multiSelect: Bool?
    var options: [Option]
    struct Option: Codable, Hashable { var label: String; var description: String? }
}

struct FilePatch: Codable, Hashable { var path: String; var kind: String; var diff: String? }
struct PlanItem: Codable, Hashable { var content: String; var status: String }

/// One entry of a transcript. The PC sends many shapes; this holds the union of their fields.
struct Ev: Decodable, Identifiable, Hashable {
    var k: String
    var eid: String?
    var text: String?
    var name: String?
    var status: String?
    var output: String?
    var command: String?
    var title: String?
    var detail: String?
    var state: String?
    var questions: [Question]?
    var answers: [String: String]?
    var files: [FilePatch]?
    var items: [PlanItem]?
    var input: JSON?
    var ms: Double?
    var exitCode: Int?

    var id: String { eid ?? "\(k)-\(text?.hashValue ?? 0)-\(ms ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case k, text, name, status, output, command, title, detail, state, questions, answers, files, items, input, ms, exitCode
        case eid = "id"
    }
}

/// Anything JSON, for a tool's input, which differs per tool.
enum JSON: Decodable, Hashable {
    case string(String), number(Double), bool(Bool), array([JSON]), object([String: JSON]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSON].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSON].self) { self = .object(v) }
        else { self = .null }
    }
    /// A short line for the row: the first useful string inside it.
    var summary: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        case .bool(let b): return String(b)
        case .null: return ""
        case .array(let a): return a.map(\.summary).joined(separator: ", ")
        case .object(let o):
            for key in ["command", "file_path", "path", "pattern", "url", "query", "description"] { if let v = o[key], !v.summary.isEmpty { return v.summary } }
            return o.keys.sorted().prefix(3).joined(separator: ", ")
        }
    }
}

struct Transcript: Decodable { var total: Int; var from: Int; var events: [Ev] }
struct EventPayload: Decodable { var id: String; var index: Int; var ev: Ev }
struct ModelInfo: Decodable, Hashable, Identifiable {
    var id: String
    var label: String
    var efforts: [String]
    var defaultEffort: String
    var isDefault: Bool?
    var resolves: String?
}
struct Defaults: Decodable { var agent: String; var mode: String; var claudeModel: String; var codexModel: String; var localModel: String }
struct Folders: Decodable { var folders: [String]; var `default`: String }
struct Changes: Decodable {
    var repo: Bool
    var branch: String?
    var files: [File]?
    struct File: Decodable, Hashable, Identifiable {
        var path: String; var status: String; var staged: Bool; var added: Int; var removed: Int
        var id: String { path }
    }
}
struct Diff: Decodable { var diff: String }

enum Agent: String, CaseIterable, Identifiable {
    case claude, codex, local
    var id: String { rawValue }
    var label: String { self == .claude ? "Claude" : self == .codex ? "Codex" : "Local" }
}

enum Mode: String, CaseIterable, Identifiable {
    case ask, edits, plan, auto, full
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ask: return "Ask first"
        case .edits: return "Accept edits"
        case .plan: return "Plan"
        case .auto: return "Auto"
        case .full: return "Full access"
        }
    }
}
