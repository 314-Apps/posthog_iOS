import Foundation
import PostHogFoundation

/// A person the SDKs identified. `propertiesRaw` stays raw — person properties
/// are unmodeled key/value pairs rendered as-is.
public struct Person: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let uuid: String?
  public let distinctIDs: [String]
  public let propertiesRaw: JSONValue?
  public let createdAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case uuid
    case distinctIDs = "distinct_ids"
    case propertiesRaw = "properties"
    case createdAt = "created_at"
  }

  public init(
    id: String,
    uuid: String?,
    distinctIDs: [String],
    propertiesRaw: JSONValue?,
    createdAt: Date?
  ) {
    self.id = id
    self.uuid = uuid
    self.distinctIDs = distinctIDs
    self.propertiesRaw = propertiesRaw
    self.createdAt = createdAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // The API serves a numeric id today; accept a string too so a backend
    // change cannot break decoding.
    if let numeric = try? container.decode(Int.self, forKey: .id) {
      self.id = String(numeric)
    } else {
      self.id = try container.decode(String.self, forKey: .id)
    }
    self.uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
    self.distinctIDs = try container.decodeIfPresent([String].self, forKey: .distinctIDs) ?? []
    self.propertiesRaw = try container.decodeIfPresent(JSONValue.self, forKey: .propertiesRaw)
    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
  }

  /// The list-row and header title: email, then name, then a distinct id.
  public var displayName: String {
    if let email = propertiesRaw?["email"]?.stringValue, !email.isEmpty {
      return email
    }
    if let name = propertiesRaw?["name"]?.stringValue, !name.isEmpty {
      return name
    }
    if let distinctID = distinctIDs.first, !distinctID.isEmpty {
      return distinctID
    }
    return "Anonymous user"
  }
}

/// A cohort summary as the list endpoint serves it.
public struct Cohort: Codable, Sendable, Equatable, Identifiable {
  public let id: Int
  public let name: String
  public let count: Int?
  public let isStatic: Bool
  public let createdAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case count
    case isStatic = "is_static"
    case createdAt = "created_at"
  }

  public init(id: Int, name: String, count: Int?, isStatic: Bool, createdAt: Date?) {
    self.id = id
    self.name = name
    self.count = count
    self.isStatic = isStatic
    self.createdAt = createdAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(Int.self, forKey: .id)
    self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    self.count = try container.decodeIfPresent(Int.self, forKey: .count)
    self.isStatic = try container.decodeIfPresent(Bool.self, forKey: .isStatic) ?? false
    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
  }
}

extension APIClient {
  public func persons(projectID: Int, search: String? = nil) async throws -> Paginated<Person> {
    var query: [URLQueryItem] = []
    if let search, !search.isEmpty {
      query.append(URLQueryItem(name: "search", value: search))
    }
    return try await send(.get("/api/projects/\(projectID)/persons/", query: query))
  }

  public func person(projectID: Int, personID: String) async throws -> Person {
    try await send(.get("/api/projects/\(projectID)/persons/\(personID)/"))
  }

  public func cohorts(projectID: Int) async throws -> Paginated<Cohort> {
    try await send(.get("/api/projects/\(projectID)/cohorts/"))
  }
}
