import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogQueries
import PostHogTestSupport
import Testing

@testable import FeatureSurveys

@MainActor
@Suite struct SurveyDetailModelTests {
  private func makeModel(transport: StubTransport) -> SurveyDetailModel {
    let client = APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
    let cacheRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("feature-surveys-tests-\(UUID().uuidString)", isDirectory: true)
    let context = ProjectContext(region: .us, projectID: 1, client: client, cache: DiskCache(root: cacheRoot))
    return SurveyDetailModel(context: context, surveyID: "survey-1")
  }

  private let draftSurvey = Data(#"{"id": "survey-1", "name": "Onboarding feedback"}"#.utf8)
  private let runningSurvey = Data(
    #"{"id": "survey-1", "name": "Onboarding feedback", "start_date": "2026-08-01T09:00:00Z"}"#.utf8
  )
  private let completeSurvey = Data(
    (#"{"id": "survey-1", "name": "Onboarding feedback", "start_date": "2026-08-01T09:00:00Z", "#
      + #""end_date": "2026-09-01T09:00:00Z"}"#).utf8
  )
  private let statsJunk = Data(#"{"stats": "unavailable"}"#.utf8)
  private let emptyResponses = Data(
    #"{"results":[],"has_more":false,"limit":100,"offset":0}"#.utf8
  )

  @Test func launchPatchesOnlyStartDate() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: draftSurvey),
      .response(status: 200, body: statsJunk),
      .response(status: 200, body: emptyResponses),
      .response(status: 200, body: runningSurvey),
    ])
    let model = makeModel(transport: transport)
    await model.load()
    #expect(model.survey?.lifecycle == .draft)
    #expect(model.stats == .unavailable)

    await model.launch()

    let patch = transport.requests[3]
    #expect(patch.httpMethod == "PATCH")
    #expect(patch.url?.absoluteString == "https://us.posthog.com/api/projects/1/surveys/survey-1/")
    let body = try JSONDecoder().decode(JSONValue.self, from: patch.httpBody ?? Data())
    #expect(body.objectValue?.keys.sorted() == ["start_date"])
    let stamp = try #require(body["start_date"]?.stringValue)
    #expect((try? Date(stamp, strategy: .iso8601)) != nil)
    #expect(model.survey?.lifecycle == .running)
    #expect(model.actionError == nil)
    #expect(!model.isUpdating)
  }

  @Test func stopPatchesOnlyEndDate() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: runningSurvey),
      .response(status: 200, body: statsJunk),
      .response(status: 200, body: emptyResponses),
      .response(status: 200, body: completeSurvey),
    ])
    let model = makeModel(transport: transport)
    await model.load()
    #expect(model.survey?.lifecycle == .running)

    await model.stop()

    let patch = transport.requests[3]
    #expect(patch.httpMethod == "PATCH")
    #expect(patch.url?.absoluteString == "https://us.posthog.com/api/projects/1/surveys/survey-1/")
    let body = try JSONDecoder().decode(JSONValue.self, from: patch.httpBody ?? Data())
    #expect(body.objectValue?.keys.sorted() == ["end_date"])
    #expect(model.survey?.lifecycle == .complete)
    #expect(model.actionError == nil)
  }

  @Test func failedUpdateKeepsSurveyAndShowsError() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: draftSurvey),
      .response(status: 200, body: statsJunk),
      .response(status: 200, body: emptyResponses),
      .response(status: 500, body: Data()),
    ])
    let model = makeModel(transport: transport)
    await model.load()

    await model.launch()

    #expect(model.survey?.lifecycle == .draft)
    #expect(model.actionError == "Couldn't update the survey. Try again.")
    #expect(!model.isUpdating)
  }

  @Test func loadParsesStatsTotals() async throws {
    let statsBody = Data(
      #"{"stats": {"survey shown": {"total_count": 120}, "survey sent": {"total_count": 45}}}"#.utf8
    )
    let transport = StubTransport(script: [
      .response(status: 200, body: runningSurvey),
      .response(status: 200, body: statsBody),
      .response(status: 200, body: emptyResponses),
    ])
    let model = makeModel(transport: transport)
    await model.load()

    #expect(model.stats == .loaded(SurveyFunnel(shown: 120, sent: 45)))
  }

  @Test func loadRequestsPerQuestionStatsAndResponses() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: runningSurvey),
      .response(status: 200, body: statsJunk),
      .response(status: 200, body: emptyResponses),
    ])
    let model = makeModel(transport: transport)
    await model.load()

    let urls = transport.requests.compactMap(\.url?.absoluteString)
    #expect(urls.contains(where: {
      $0.contains("/surveys/survey-1/stats/") && $0.contains("include_per_question_stats=true")
    }))
    #expect(urls.contains(where: { $0.contains("/surveys/survey-1/responses/") }))
  }
}
