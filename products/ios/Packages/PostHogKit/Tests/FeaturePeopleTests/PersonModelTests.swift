import Foundation
import PostHogAPI
import PostHogFoundation
import Testing

@testable import FeaturePeople

@Suite struct PersonModelTests {
  @Test func decodesIntegerAndStringIDs() throws {
    let decoder = APIClient.makeDecoder()
    let full = #"""
      {"id": 42, "uuid": "0192-abc", "distinct_ids": ["d-1", "d-2"],
      "properties": {"email": "ana@example.com"}, "created_at": "2026-08-30T10:00:00Z"}
      """#
    let person = try decoder.decode(Person.self, from: Data(full.utf8))
    #expect(person.id == "42")
    #expect(person.uuid == "0192-abc")
    #expect(person.distinctIDs == ["d-1", "d-2"])
    #expect(person.propertiesRaw?["email"]?.stringValue == "ana@example.com")
    #expect(person.createdAt != nil)

    let sparse = try decoder.decode(Person.self, from: Data(#"{"id": "person-9"}"#.utf8))
    #expect(sparse.id == "person-9")
    #expect(sparse.uuid == nil)
    #expect(sparse.distinctIDs == [])
    #expect(sparse.propertiesRaw == nil)
    #expect(sparse.createdAt == nil)
  }

  @Test func decodesEmptyProperties() throws {
    let json = #"{"id": 7, "distinct_ids": ["d-7"], "properties": {}}"#
    let person = try APIClient.makeDecoder().decode(Person.self, from: Data(json.utf8))
    #expect(person.propertiesRaw == .object([:]))
    #expect(person.displayName == "d-7")
  }

  struct DisplayNameCase: Sendable {
    let properties: JSONValue
    let distinctIDs: [String]
    let expected: String
  }

  @Test(arguments: [
    DisplayNameCase(
      properties: .object(["email": "ana@example.com", "name": "Ana"]),
      distinctIDs: ["d-1"],
      expected: "ana@example.com"
    ),
    DisplayNameCase(properties: .object(["name": "Ana"]), distinctIDs: ["d-1"], expected: "Ana"),
    DisplayNameCase(
      properties: .object(["email": "", "name": "Ana"]),
      distinctIDs: ["d-1"],
      expected: "Ana"
    ),
    DisplayNameCase(properties: .object([:]), distinctIDs: ["d-1"], expected: "d-1"),
    DisplayNameCase(properties: .null, distinctIDs: [], expected: "Anonymous user"),
  ])
  func displayNamePrecedence(_ testCase: DisplayNameCase) {
    let person = Person(
      id: "1",
      uuid: nil,
      distinctIDs: testCase.distinctIDs,
      propertiesRaw: testCase.properties,
      createdAt: nil
    )
    #expect(person.displayName == testCase.expected)
  }
}
