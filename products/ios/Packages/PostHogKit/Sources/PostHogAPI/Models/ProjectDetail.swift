import Foundation

/// `/api/projects/{id}/` — the fields the app reads beyond the list row.
/// `liveEventsToken` authenticates SSE streams against the livestream service.
public struct ProjectDetail: Codable, Sendable, Equatable, Identifiable {
  public let id: Int
  public let name: String
  public let liveEventsToken: String?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case liveEventsToken = "live_events_token"
  }

  public init(id: Int, name: String, liveEventsToken: String?) {
    self.id = id
    self.name = name
    self.liveEventsToken = liveEventsToken
  }
}

extension APIClient {
  public func projectDetail(projectID: Int) async throws -> ProjectDetail {
    try await send(.get("/api/projects/\(projectID)/"))
  }
}
