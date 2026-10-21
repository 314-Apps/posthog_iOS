import Foundation

/// `/api/users/@me/` — the signed-in user plus their organizations.
public struct User: Decodable, Sendable, Equatable, Identifiable {
  public let id: Int
  public let uuid: String
  public let email: String
  public let firstName: String
  public let organizations: [OrganizationSummary]
  public let currentOrganizationID: String?
  public let currentTeamID: Int?
  /// The current organization's projects, as this route already returns them.
  public let currentOrganizationProjects: [Project]

  enum CodingKeys: String, CodingKey {
    case id
    case uuid
    case email
    case firstName = "first_name"
    case organizations
    case organization
    case team
  }

  enum NestedIDKeys: String, CodingKey {
    case id
    case projects
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(Int.self, forKey: .id)
    self.uuid = try container.decode(String.self, forKey: .uuid)
    self.email = try container.decode(String.self, forKey: .email)
    self.firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
    self.organizations =
      try container.decodeIfPresent([OrganizationSummary].self, forKey: .organizations) ?? []
    let organization = try? container.nestedContainer(keyedBy: NestedIDKeys.self, forKey: .organization)
    self.currentOrganizationID = try organization?.decodeIfPresent(String.self, forKey: .id)
    // This route already returns the projects the person can see, and unlike
    // the organization-nested list it accepts a project-scoped key.
    let nestedProjects = try? organization?.decodeIfPresent([Project].self, forKey: .projects)
    self.currentOrganizationProjects = nestedProjects.flatMap { $0 } ?? []
    let team = try? container.nestedContainer(keyedBy: NestedIDKeys.self, forKey: .team)
    self.currentTeamID = try team?.decodeIfPresent(Int.self, forKey: .id)
  }

  public init(
    id: Int,
    uuid: String,
    email: String,
    firstName: String,
    organizations: [OrganizationSummary],
    currentOrganizationID: String?,
    currentTeamID: Int?,
    currentOrganizationProjects: [Project] = []
  ) {
    self.id = id
    self.uuid = uuid
    self.email = email
    self.firstName = firstName
    self.organizations = organizations
    self.currentOrganizationID = currentOrganizationID
    self.currentTeamID = currentTeamID
    self.currentOrganizationProjects = currentOrganizationProjects
  }
}

public struct OrganizationSummary: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

/// One project (team) row.
public struct Project: Codable, Sendable, Equatable, Identifiable {
  public let id: Int
  public let name: String
  public let organizationID: String?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case organizationID = "organization"
  }

  public init(id: Int, name: String, organizationID: String?) {
    self.id = id
    self.name = name
    self.organizationID = organizationID
  }
}

extension APIClient {
  public func me() async throws -> User {
    try await send(.get("/api/users/@me/"))
  }

  public func organizationProjects(organizationID: String) async throws -> Paginated<Project> {
    try await send(.get("/api/organizations/\(organizationID)/projects/"))
  }
}
