import Foundation

struct NotifyPayload: Codable, Equatable {
    static let maxPayloadBytes = 1_048_576

    let sessionUUID: String
    let cwd: String
    let title: String
    let summary: String
    let fullMessage: String
    let timestamp: Double
    // Optional git context enriched by the Stop hook; absent for non-git dirs
    // and for payloads produced before this feature. Backward compatible.
    let repoRoot: String?
    let branch: String?

    enum CodingKeys: String, CodingKey {
        case sessionUUID = "session_uuid"
        case cwd, title, summary
        case fullMessage = "full_message"
        case timestamp
        case repoRoot = "repo_root"
        case branch
    }

    var projectName: String { (cwd as NSString).lastPathComponent }

    static func decode(_ data: Data) -> NotifyPayload? {
        guard data.count <= maxPayloadBytes else { return nil }
        guard let p = try? JSONDecoder().decode(NotifyPayload.self, from: data) else { return nil }
        guard !p.sessionUUID.isEmpty, !p.cwd.isEmpty else { return nil }
        return p
    }
}
