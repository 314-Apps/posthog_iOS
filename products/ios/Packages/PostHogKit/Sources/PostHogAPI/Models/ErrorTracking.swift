import Foundation
import PostHogFoundation

/// An error tracking issue (one group of related exceptions). The REST shape
/// is still settling server-side, so every field except `id` decodes
/// defensively — a missing or unexpected value must never fail the screen.
public struct ErrorTrackingIssue: Codable, Sendable, Equatable, Identifiable {
  public enum Status: String, Codable, Sendable {
    case active
    case resolved
    case suppressed
    case archived
    /// Decode fallback for statuses this client does not model — never sent back.
    case unknown

    public init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      let raw = (try? container.decode(String.self)) ?? ""
      self = Status(rawValue: raw) ?? .unknown
    }
  }

  public let id: String
  public let name: String?
  public let description: String?
  public let status: Status
  public let firstSeen: Date?
  /// Kept raw: assignees can be users or roles and the app does not model them yet.
  public let assignee: JSONValue?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case description
    case status
    case firstSeen = "first_seen"
    case assignee
  }

  public init(
    id: String,
    name: String?,
    description: String?,
    status: Status,
    firstSeen: Date?,
    assignee: JSONValue?
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.status = status
    self.firstSeen = firstSeen
    self.assignee = assignee
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.name = try? container.decode(String.self, forKey: .name)
    self.description = try? container.decode(String.self, forKey: .description)
    self.status = (try? container.decode(Status.self, forKey: .status)) ?? .unknown
    self.firstSeen = try? container.decode(Date.self, forKey: .firstSeen)
    let rawAssignee = try? container.decode(JSONValue.self, forKey: .assignee)
    self.assignee = rawAssignee?.isNull == true ? nil : rawAssignee
  }
}

extension APIClient {
  public func errorTrackingIssue(projectID: Int, issueID: String) async throws -> ErrorTrackingIssue {
    try await send(.get("/api/projects/\(projectID)/error_tracking/issues/\(issueID)/"))
  }

  /// Triage via PATCH. Pass a concrete status — `.unknown` is a decode
  /// fallback, not an API value.
  public func updateErrorTrackingIssue(
    projectID: Int,
    issueID: String,
    status: ErrorTrackingIssue.Status
  ) async throws -> ErrorTrackingIssue {
    let body = try Self.makeEncoder().encode(["status": status.rawValue])
    return try await send(.patch("/api/projects/\(projectID)/error_tracking/issues/\(issueID)/", body: body))
  }
}
