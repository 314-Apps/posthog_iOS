import Foundation
import Testing

@testable import PostHogFoundation

@Suite struct JSONValueTests {
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  @Test func decodesEveryShape() throws {
    let raw = #"{"a": 1, "b": "two", "c": [true, null, 3.5], "d": {"nested": -7}}"#
    let value = try decoder.decode(JSONValue.self, from: Data(raw.utf8))
    #expect(value["a"]?.intValue == 1)
    #expect(value["b"]?.stringValue == "two")
    #expect(value["c"]?[0]?.boolValue == true)
    #expect(value["c"]?[1]?.isNull == true)
    #expect(value["c"]?[2]?.numberValue == 3.5)
    #expect(value["d"]?["nested"]?.intValue == -7)
  }

  @Test func roundTripPreservesSemantics() throws {
    let raw = #"{"kind":"TrendsQuery","series":[{"event":null,"math":"dau"}],"n":42,"f":1.25}"#
    let decoded = try decoder.decode(JSONValue.self, from: Data(raw.utf8))
    let reencoded = try encoder.encode(decoded)
    let redecoded = try decoder.decode(JSONValue.self, from: reencoded)
    #expect(decoded == redecoded)
  }

  @Test func wholeNumbersEncodeWithoutFraction() throws {
    let data = try encoder.encode(JSONValue.number(42))
    #expect(String(bytes: data, encoding: .utf8) == "42")
  }

  @Test func literalsBuildValues() {
    let value: JSONValue = ["kind": "HogQLQuery", "limit": 100, "flag": true, "none": nil]
    #expect(value["kind"] == .string("HogQLQuery"))
    #expect(value["limit"] == .number(100))
    #expect(value["flag"] == .bool(true))
    #expect(value["none"] == .null)
  }
}
