import Foundation
import PostHogFoundation

/// Dashboard list row.
public struct DashboardSummary: Codable, Sendable, Equatable, Identifiable {
  public let id: Int
  public let name: String
  public let description: String?
  public let pinned: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case description
    case pinned
  }
}

/// Dashboard detail: metadata plus tiles. A tile is an insight or a text block.
public struct DashboardDetail: Codable, Sendable, Equatable {
  public let id: Int
  public let name: String
  public let description: String?
  public let pinned: Bool
  public let tiles: [DashboardTile]

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case description
    case pinned
    case tiles
  }
}

public struct DashboardTile: Codable, Sendable, Equatable, Identifiable {
  public let id: Int
  public let insight: TileInsight?
  public let text: TileText?

  enum CodingKeys: String, CodingKey {
    case id
    case insight
    case text
  }
}

/// The insight embedded in a dashboard tile. `query` and `result` stay raw:
/// the query feeds PostHogQueries and the cached result paints instantly.
public struct TileInsight: Codable, Sendable, Equatable, Identifiable {
  public let id: Int
  public let shortID: String
  public let name: String?
  public let derivedName: String?
  public let query: JSONValue?
  public let result: JSONValue?

  enum CodingKeys: String, CodingKey {
    case id
    case shortID = "short_id"
    case name
    case derivedName = "derived_name"
    case query
    case result
  }

  public var displayName: String {
    if let name, !name.isEmpty { return name }
    return derivedName ?? "Untitled insight"
  }
}

public struct TileText: Codable, Sendable, Equatable {
  public let body: String?

  enum CodingKeys: String, CodingKey {
    case body
  }
}

extension APIClient {
  public func dashboards(projectID: Int, limit: Int = 100) async throws -> Paginated<DashboardSummary> {
    try await send(
      .get(
        "/api/projects/\(projectID)/dashboards/",
        query: [URLQueryItem(name: "limit", value: String(limit))]
      )
    )
  }

  public func dashboard(projectID: Int, dashboardID: Int) async throws -> DashboardDetail {
    try await send(.get("/api/projects/\(projectID)/dashboards/\(dashboardID)/"))
  }
}
