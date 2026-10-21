import Foundation
import PostHogFoundation
import Testing

@testable import FeatureSurveys

private let statsCases: [(json: String, expected: SurveyFunnel)] = [
  (
    json: #"{"stats": {"survey shown": {"total_count": 120}, "survey sent": {"total_count": 45}}}"#,
    expected: SurveyFunnel(shown: 120, sent: 45)
  ),
  (
    json: #"{"stats": {"survey dismissed": {"total_count": 30}}, "rates": {"response_rate": 37.5}}"#,
    expected: SurveyFunnel(dismissed: 30, responseRate: 37.5)
  ),
  (json: #"{"survey shown": 12}"#, expected: SurveyFunnel(shown: 12)),
  (json: #"{"survey_shown": {"count": 7}}"#, expected: SurveyFunnel(shown: 7)),
  (json: #"{"unrelated": {"deep": {"noise": true}}}"#, expected: SurveyFunnel()),
  (json: #"{"survey shown": "many", "survey sent": [4], "survey dismissed": null}"#, expected: SurveyFunnel()),
  (json: #"["survey shown", 12]"#, expected: SurveyFunnel()),
  (json: #""junk""#, expected: SurveyFunnel()),
]

@Suite struct SurveyStatsSummaryTests {
  @Test(arguments: statsCases)
  func parsesDefensively(_ testCase: (json: String, expected: SurveyFunnel)) throws {
    let raw = try JSONDecoder().decode(JSONValue.self, from: Data(testCase.json.utf8))
    #expect(SurveyFunnel.parse(raw) == testCase.expected)
  }
}
