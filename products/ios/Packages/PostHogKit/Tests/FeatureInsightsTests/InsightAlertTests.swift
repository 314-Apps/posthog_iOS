import Foundation
import PostHogAPI
import PostHogFoundation
import Testing

@Suite struct InsightAlertTests {
  @Test func decodesIntInsightAndNestedThreshold() throws {
    let json = Data(
      """
      {
        "id": "alert-1",
        "name": "Signups too low",
        "enabled": true,
        "insight": 42,
        "state": "NOT_FIRING",
        "calculation_interval": "daily",
        "threshold": {"configuration": {"type": "absolute", "bounds": {"lower": 10, "upper": 100.5}}}
      }
      """.utf8)
    let alert = try APIClient.makeDecoder().decode(InsightAlert.self, from: json)
    #expect(alert.id == "alert-1")
    #expect(alert.name == "Signups too low")
    #expect(alert.enabled)
    #expect(alert.insightID == 42)
    #expect(alert.state == "NOT_FIRING")
    #expect(alert.calculationInterval == "daily")
    #expect(alert.lowerThreshold == 10)
    #expect(alert.upperThreshold == 100.5)

    let reEncoded = try JSONEncoder().encode(alert)
    let roundTripped = try APIClient.makeDecoder().decode(InsightAlert.self, from: reEncoded)
    #expect(roundTripped == alert)
  }

  @Test func decodesObjectInsight() throws {
    let json = Data(
      """
      {
        "id": "alert-2",
        "name": "Errors spiking",
        "enabled": true,
        "insight": {"id": 7, "short_id": "xyz789", "name": "Error count"},
        "state": "FIRING"
      }
      """.utf8)
    let alert = try APIClient.makeDecoder().decode(InsightAlert.self, from: json)
    #expect(alert.insightID == 7)
    #expect(alert.state == "FIRING")
    #expect(alert.lowerThreshold == nil)
    #expect(alert.upperThreshold == nil)
  }

  @Test func toleratesMissingOptionalFields() throws {
    let alert = try APIClient.makeDecoder().decode(InsightAlert.self, from: Data(#"{"id": "alert-3"}"#.utf8))
    #expect(alert.name == "")
    #expect(!alert.enabled)
    #expect(alert.insightID == nil)
    #expect(alert.state == nil)
    #expect(alert.calculationInterval == nil)
    #expect(alert.lowerThreshold == nil)
    #expect(alert.upperThreshold == nil)
    #expect(alert.thresholdRaw == nil)
  }

  @Test func keepsRawThresholdEvenWithoutBounds() throws {
    let json = Data(
      """
      {
        "id": "alert-4",
        "name": "Odd threshold",
        "enabled": false,
        "insight": 42,
        "threshold": {"configuration": {"type": "percentage", "custom_field": "kept"}}
      }
      """.utf8)
    let alert = try APIClient.makeDecoder().decode(InsightAlert.self, from: json)
    #expect(alert.lowerThreshold == nil)
    #expect(alert.upperThreshold == nil)
    let expected: JSONValue = [
      "configuration": ["type": "percentage", "custom_field": "kept"]
    ]
    #expect(alert.thresholdRaw == expected)
  }

  @Test func payloadContainsExpectedStructure() throws {
    let data = InsightAlert.payload(
      name: "Signups too low",
      enabled: true,
      insightID: 42,
      calculationInterval: "weekly",
      lower: 10,
      upper: 100
    )
    let payload = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(payload["name"] == "Signups too low")
    #expect(payload["enabled"] == true)
    #expect(payload["insight"] == 42)
    #expect(payload["calculation_interval"] == "weekly")
    #expect(payload["threshold"]?["configuration"]?["type"] == "absolute")
    #expect(payload["threshold"]?["configuration"]?["bounds"]?["lower"] == 10)
    #expect(payload["threshold"]?["configuration"]?["bounds"]?["upper"] == 100)
    #expect(payload["subscribed_users"] == .array([]))
    #expect(payload["config"]?["type"] == "TrendsAlertConfig")
    #expect(payload["config"]?["series_index"] == 0)
  }

  struct BoundsCase: Sendable {
    let lower: Double?
    let upper: Double?
    let keys: [String]
  }

  @Test(arguments: [
    BoundsCase(lower: 10, upper: nil, keys: ["lower"]),
    BoundsCase(lower: nil, upper: 5.5, keys: ["upper"]),
    BoundsCase(lower: nil, upper: nil, keys: []),
  ])
  func payloadOmitsNilBounds(_ testCase: BoundsCase) throws {
    let data = InsightAlert.payload(
      name: "Bounds",
      enabled: true,
      insightID: 1,
      calculationInterval: "daily",
      lower: testCase.lower,
      upper: testCase.upper
    )
    let payload = try JSONDecoder().decode(JSONValue.self, from: data)
    let bounds = try #require(payload["threshold"]?["configuration"]?["bounds"]?.objectValue)
    #expect(Set(bounds.keys) == Set(testCase.keys))
    #expect(bounds["lower"]?.numberValue == testCase.lower)
    #expect(bounds["upper"]?.numberValue == testCase.upper)
  }
}
