import Foundation

/// One inbox notification. The backend serializer is young, so decoding is
/// defensive: absent keys fall back to defaults and unknown enum strings map
/// to `.unknown` instead of failing the whole page.
public struct NotificationEvent: Codable, Sendable, Equatable, Identifiable {
  public enum EventType: String, Codable, Sendable, CaseIterable {
    case commentMention = "comment_mention"
    case alertFiring = "alert_firing"
    case approvalRequested = "approval_requested"
    case approvalResolved = "approval_resolved"
    case pipelineFailure = "pipeline_failure"
    case issueAssigned = "issue_assigned"
    case unknown

    public init(from decoder: Decoder) throws {
      let raw = try decoder.singleValueContainer().decode(String.self)
      self = EventType(rawValue: raw) ?? .unknown
    }
  }

  public enum Priority: String, Codable, Sendable {
    case normal
    case critical
    case unknown

    public init(from decoder: Decoder) throws {
      let raw = try decoder.singleValueContainer().decode(String.self)
      self = Priority(rawValue: raw) ?? .unknown
    }
  }

  public let id: String
  public let type: EventType
  public let title: String
  public let body: String?
  public let priority: Priority
  public let createdAt: Date
  /// Mutable so list rows can flip optimistically before the API confirms.
  public var isRead: Bool
  public let resourceType: String?
  public let resourceID: String?

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case title
    case body
    case priority
    case createdAt = "created_at"
    case isRead = "is_read"
    case resourceType = "resource_type"
    case resourceID = "resource_id"
  }

  public init(
    id: String,
    type: EventType,
    title: String,
    body: String? = nil,
    priority: Priority = .normal,
    createdAt: Date,
    isRead: Bool = false,
    resourceType: String? = nil,
    resourceID: String? = nil
  ) {
    self.id = id
    self.type = type
    self.title = title
    self.body = body
    self.priority = priority
    self.createdAt = createdAt
    self.isRead = isRead
    self.resourceType = resourceType
    self.resourceID = resourceID
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.type = try container.decodeIfPresent(EventType.self, forKey: .type) ?? .unknown
    self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    self.body = try container.decodeIfPresent(String.self, forKey: .body)
    self.priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .normal
    // Missing timestamps sort deterministically into the oldest bucket.
    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
    self.isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
    self.resourceType = try container.decodeIfPresent(String.self, forKey: .resourceType)
    self.resourceID = try container.decodeIfPresent(String.self, forKey: .resourceID)
  }
}

/// Body of `unread_count/`: `{"count": N}`.
private struct UnreadCountBody: Decodable, Sendable {
  let count: Int
}

extension APIClient {
  public func notifications(projectID: Int) async throws -> Paginated<NotificationEvent> {
    try await send(.get("/api/projects/\(projectID)/notifications/"))
  }

  public func notificationUnreadCount(projectID: Int) async throws -> Int {
    let body: UnreadCountBody = try await send(
      .get("/api/projects/\(projectID)/notifications/unread_count/"))
    return body.count
  }

  public func markNotificationRead(projectID: Int, notificationID: String) async throws {
    try await sendRaw(.post("/api/projects/\(projectID)/notifications/\(notificationID)/mark_read/"))
  }

  public func markNotificationUnread(projectID: Int, notificationID: String) async throws {
    try await sendRaw(.post("/api/projects/\(projectID)/notifications/\(notificationID)/mark_unread/"))
  }

  public func markAllNotificationsRead(projectID: Int) async throws {
    try await sendRaw(.post("/api/projects/\(projectID)/notifications/mark_all_read/"))
  }
}
