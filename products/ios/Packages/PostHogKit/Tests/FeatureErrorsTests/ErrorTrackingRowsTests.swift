import Foundation
import PostHogFoundation
import Testing

@testable import FeatureErrors

@Suite struct ErrorTrackingRowsTests {
  private func body(_ json: String) -> JSONValue {
    (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .null
  }

  @Test func parsesTopLevelAndAggregationsShapes() {
    let fixture = """
      {"results": [
        {
          "id": "issue-1",
          "name": "RangeError",
          "description": "Maximum call stack size exceeded",
          "status": "active",
          "occurrences": 128,
          "sessions": 61,
          "users": 22,
          "first_seen": "2026-08-20T09:15:00.123000Z",
          "last_seen": "2026-09-03T18:00:00Z",
          "volume": [0, 2, 5, 9]
        },
        {
          "id": "issue-2",
          "description": "Lost connection",
          "status": "escalated",
          "aggregations": {"occurrences": 40, "sessions": 8, "users": 5, "volume": [1, 1, 0]}
        }
      ]}
      """
    let rows = ErrorTrackingRows.parse(body(fixture))
    #expect(rows.count == 2)
    #expect(rows[0].id == "issue-1")
    #expect(rows[0].name == "RangeError")
    #expect(rows[0].status == .active)
    #expect(rows[0].occurrences == 128)
    #expect(rows[0].sessions == 61)
    #expect(rows[0].users == 22)
    #expect(rows[0].volume == [0, 2, 5, 9])
    #expect(rows[0].firstSeen != nil)
    #expect(rows[0].lastSeen != nil)
    #expect(rows[1].name == nil)
    #expect(rows[1].displayTitle == "Lost connection")
    #expect(rows[1].displaySubtitle == nil)
    #expect(rows[1].status == .unknown)
    #expect(rows[1].occurrences == 40)
    #expect(rows[1].sessions == 8)
    #expect(rows[1].users == 5)
    #expect(rows[1].volume == [1, 1, 0])
    #expect(rows[1].firstSeen == nil)
    #expect(rows[1].lastSeen == nil)
  }

  @Test func missingFieldsDefaultAndRowsWithoutAnIDDrop() {
    let fixture = """
      {"results": [{"name": "no id"}, "junk", 4, {"id": "kept", "first_seen": "not a date"}]}
      """
    let rows = ErrorTrackingRows.parse(body(fixture))
    #expect(rows.map(\.id) == ["kept"])
    #expect(rows[0].name == nil)
    #expect(rows[0].displayTitle == "Untitled issue")
    #expect(rows[0].occurrences == 0)
    #expect(rows[0].sessions == 0)
    #expect(rows[0].users == 0)
    #expect(rows[0].firstSeen == nil)
    #expect(rows[0].volume.isEmpty)
  }

  @Test func bodiesWithoutResultsParseEmpty() {
    #expect(ErrorTrackingRows.parse(body(#"{"error": "boom"}"#)).isEmpty)
    #expect(ErrorTrackingRows.parse(body(#"{"results": "nope"}"#)).isEmpty)
    #expect(ErrorTrackingRows.parse(.null).isEmpty)
  }
}
