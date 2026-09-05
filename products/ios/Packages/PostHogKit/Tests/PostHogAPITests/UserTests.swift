import Foundation
import Testing

@testable import PostHogAPI

@Suite struct UserTests {
  /// `@me` carries the current organization's projects. Reading them here is
  /// what lets a project-scoped key populate the switcher at all, because the
  /// organization-nested project list refuses such a key with a 403.
  @Test func readsTheProjectsRidingAlongOnTheCurrentOrganization() throws {
    let body = Data(
      #"""
      {"id": 1, "uuid": "0198c4a1-0000-4000-8000-000000000001", "email": "ada@example.com",
       "first_name": "Ada",
       "organizations": [{"id": "org-1", "name": "Hogflix"}],
       "organization": {"id": "org-1", "projects": [
         {"id": 11, "name": "Hogflix web", "organization": "org-1"},
         {"id": 12, "name": "Hogflix mobile", "organization": "org-1"}]},
       "team": {"id": 11}}
      """#.utf8
    )
    let user = try JSONDecoder().decode(User.self, from: body)

    #expect(user.currentOrganizationID == "org-1")
    #expect(user.currentOrganizationProjects.map(\.id) == [11, 12])
    #expect(user.currentOrganizationProjects.map(\.name) == ["Hogflix web", "Hogflix mobile"])
    #expect(user.currentOrganizationProjects.first?.organizationID == "org-1")
  }

  /// Older or trimmed payloads omit the nested list, and that must decode to an
  /// empty list rather than failing the whole sign-in.
  @Test(
    arguments: [
      #"{"id": 1, "uuid": "u", "email": "a@example.com", "organization": {"id": "org-1"}}"#,
      #"{"id": 1, "uuid": "u", "email": "a@example.com", "organization": {"id": "org-1", "projects": null}}"#,
      #"{"id": 1, "uuid": "u", "email": "a@example.com"}"#,
    ]
  )
  func aMissingProjectListDecodesToEmpty(_ json: String) throws {
    let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))
    #expect(user.currentOrganizationProjects.isEmpty)
  }
}
