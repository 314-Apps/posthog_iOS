import Foundation
import PostHogFoundation
import Testing

@testable import FeatureSurveys

private let statsCases: [(json: String, expected: SurveyStatsSummary)] = [
  (
    json: #"{"stats": {"survey shown": {"total_count": 120}, "survey sent": {"total_count": 45}}}"#,
    expected: SurveyStatsSummary(shown: 120, responded: 45)
  ),
  (
    json: #"{"stats": {"survey dismissed": {"total_count": 30}}, "rates": {"response_rate": 37.5}}"#,
    expected: SurveyStatsSummary(dismissed: 30)
  ),
  (json: #"{"survey shown": 12}"#, expected: SurveyStatsSummary(shown: 12)),
  (json: #"{"survey_shown": {"count": 7}}"#, expected: SurveyStatsSummary(shown: 7)),
  (json: #"{"unrelated": {"deep": {"noise": true}}}"#, expected: SurveyStatsSummary()),
  (json: #"{"survey shown": "many", "survey sent": [4], "survey dismissed": null}"#, expected: SurveyStatsSummary()),
  (json: #"["survey shown", 12]"#, expected: SurveyStatsSummary()),
  (json: #""junk""#, expected: SurveyStatsSummary()),
]

@Suite struct SurveyStatsSummaryTests {
  @Test(arguments: statsCases)
  func parsesDefensively(_ testCase: (json: String, expected: SurveyStatsSummary)) throws {
    let raw = try JSONDecoder().decode(JSONValue.self, from: Data(testCase.json.utf8))
    #expect(SurveyStatsSummary.parse(raw) == testCase.expected)
  }
}
