import Foundation

/// One saved Max conversation. Decoding is defensive: only `id` is required,
/// and a malformed timestamp decodes as nil instead of failing the page.
public struct Conversation: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let title: String?
  public let status: String?
  public let createdAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case status
    case createdAt = "created_at"
  }

  public init(id: String, title: String? = nil, status: String? = nil, createdAt: Date? = nil) {
    self.id = id
    self.title = title
    self.status = status
    self.createdAt = createdAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.title = try container.decodeIfPresent(String.self, forKey: .title)
    self.status = try container.decodeIfPresent(String.self, forKey: .status)
    self.createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil
  }
}

extension APIClient {
  public func conversations(projectID: Int) async throws -> Paginated<Conversation> {
    try await send(.get("/api/projects/\(projectID)/conversations/"))
  }

  public func deleteConversation(projectID: Int, conversationID: String) async throws {
    try await sendRaw(.delete("/api/projects/\(projectID)/conversations/\(conversationID)/"))
  }
}
