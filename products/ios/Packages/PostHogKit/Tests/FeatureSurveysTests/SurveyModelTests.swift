import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogTestSupport
import Testing

private let listFixture = """
  {
    "count": 2,
    "next": null,
    "previous": null,
    "results": [
      {
        "id": "0198a2c4-0001-4f00-8000-000000000001",
        "name": "Onboarding feedback",
        "description": "Asked after the first insight is saved",
        "type": "popover",
        "start_date": "2026-08-01T09:00:00Z",
        "end_date": null,
        "archived": false,
        "questions": [
          {"type": "open", "question": "How was setup?"},
          {"type": "rating", "scale": 5}
        ]
      },
      {
        "id": "0198a2c4-0002-4f00-8000-000000000002",
        "name": "Bare survey"
      }
    ]
  }
  """

struct LifecycleCase: Sendable {
  let start: Date?
  let end: Date?
  let expected: Survey.Lifecycle
}

private let lifecycleCases: [LifecycleCase] = [
  LifecycleCase(start: nil, end: nil, expected: .draft),
  LifecycleCase(start: Date(timeIntervalSince1970: 100), end: nil, expected: .running),
  LifecycleCase(
    start: Date(timeIntervalSince1970: 100),
    end: Date(timeIntervalSince1970: 200),
    expected: .complete
  ),
  // No start date is always a draft, even if an end date is present.
  LifecycleCase(start: nil, end: Date(timeIntervalSince1970: 200), expected: .draft),
]

@Suite struct SurveyModelTests {
  private func makeClient(transport: StubTransport) -> APIClient {
    APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
  }

  private func makeSurvey(
    startDate: Date? = nil,
    endDate: Date? = nil,
    questionsRaw: JSONValue? = nil
  ) -> Survey {
    Survey(
      id: "survey-1",
      name: "Onboarding feedback",
      description: nil,
      type: nil,
      startDate: startDate,
      endDate: endDate,
      archived: false,
      questionsRaw: questionsRaw
    )
  }

  @Test func decodesFullAndMinimalSurveys() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(listFixture.utf8))
    ])
    let client = makeClient(transport: transport)
    let page = try await client.surveys(projectID: 1)

    #expect(
      transport.requests[0].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/surveys/?limit=100")
    #expect(page.results.count == 2)

    let full = page.results[0]
    #expect(full.name == "Onboarding feedback")
    #expect(full.description == "Asked after the first insight is saved")
    #expect(full.type == "popover")
    #expect(full.startDate != nil)
    #expect(full.endDate == nil)
    #expect(!full.archived)
    #expect(full.lifecycle == .running)
    #expect(full.questionSummaries == ["How was setup?", "Question 2"])

    let minimal = page.results[1]
    #expect(minimal.name == "Bare survey")
    #expect(minimal.description == nil)
    #expect(minimal.type == nil)
    #expect(minimal.startDate == nil)
    #expect(minimal.endDate == nil)
    #expect(!minimal.archived)
    #expect(minimal.questionsRaw == nil)
    #expect(minimal.lifecycle == .draft)
    #expect(minimal.questionSummaries.isEmpty)
  }

  @Test(arguments: lifecycleCases)
  func lifecycleFollowsDates(_ testCase: LifecycleCase) {
    let survey = makeSurvey(startDate: testCase.start, endDate: testCase.end)
    #expect(survey.lifecycle == testCase.expected)
  }

  @Test func questionSummariesTolerateJunkEntries() {
    let junkEntries = makeSurvey(questionsRaw: [
      ["question": "Rate us"],
      ["question": 4],
      "junk",
      ["question": ""],
    ])
    #expect(junkEntries.questionSummaries == ["Rate us", "Question 2", "Question 3", "Question 4"])

    let nonArray = makeSurvey(questionsRaw: ["question": "Rate us"])
    #expect(nonArray.questionSummaries.isEmpty)
  }
}
