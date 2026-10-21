import Foundation
import PostHogAPI
import Testing

@Suite struct ErrorTrackingIssueTests {
  @Test func decodesAFullIssue() throws {
    let json = """
      {
        "id": "0198f9a1-0000-7000-8000-1234567890ab",
        "name": "TypeError",
        "description": "undefined is not a function",
        "status": "resolved",
        "first_seen": "2026-08-30T10:00:00.500000Z",
        "assignee": {"type": "user", "id": 7}
      }
      """
    let issue = try APIClient.makeDecoder().decode(ErrorTrackingIssue.self, from: Data(json.utf8))
    #expect(issue.id == "0198f9a1-0000-7000-8000-1234567890ab")
    #expect(issue.name == "TypeError")
    #expect(issue.description == "undefined is not a function")
    #expect(issue.status == .resolved)
    #expect(issue.firstSeen != nil)
    #expect(issue.assignee?["type"]?.stringValue == "user")
  }

  @Test func unknownStatusAndMissingFieldsDecodeDefensively() throws {
    let json = #"{"id": "abc", "status": "escalated", "assignee": null, "first_seen": "not a date"}"#
    let issue = try APIClient.makeDecoder().decode(ErrorTrackingIssue.self, from: Data(json.utf8))
    #expect(issue.status == .unknown)
    #expect(issue.name == nil)
    #expect(issue.description == nil)
    #expect(issue.firstSeen == nil)
    #expect(issue.assignee == nil)
  }
}
