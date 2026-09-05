import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogQueries
import PostHogTestSupport
import Testing

@testable import FeatureInsights

private let alertResponse = Data(
  """
  {
    "id": "alert-1",
    "name": "Signups too low",
    "enabled": true,
    "insight": {"id": 42, "short_id": "abc123"},
    "state": "NOT_FIRING",
    "calculation_interval": "daily",
    "threshold": {"configuration": {"type": "absolute", "bounds": {"lower": 10}}}
  }
  """.utf8)

private func makeContext(transport: StubTransport) -> ProjectContext {
  let client = APIClient(
    baseURL: URL(string: "https://us.posthog.com")!,
    transport: transport,
    tokens: StubTokens(),
    clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
  )
  let cacheRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("alert-tests-\(UUID().uuidString)", isDirectory: true)
  return ProjectContext(region: .us, projectID: 1, client: client, cache: DiskCache(root: cacheRoot))
}

private func existingAlert() -> InsightAlert {
  InsightAlert(
    id: "alert-1",
    name: "Signups too low",
    enabled: true,
    insightID: 42,
    state: "NOT_FIRING",
    calculationInterval: "daily",
    lowerThreshold: 10,
    upperThreshold: nil,
    thresholdRaw: nil
  )
}

private let boundsMessage = "Bounds must be numbers. Enter a number or leave the field empty."
private let orderMessage = "The lower bound is above the upper bound. Adjust the values so lower stays below upper."

@MainActor
@Suite struct AlertEditorModelTests {
  struct ValidationCase: Sendable {
    let lower: String
    let upper: String
    let expected: String?
  }

  @Test(arguments: [
    ValidationCase(lower: "", upper: "", expected: nil),
    ValidationCase(lower: "5", upper: "", expected: nil),
    ValidationCase(lower: "", upper: "12.5", expected: nil),
    ValidationCase(lower: "5", upper: "10", expected: nil),
    ValidationCase(lower: "-3.5", upper: "2", expected: nil),
    ValidationCase(lower: "5", upper: "5", expected: nil),
    ValidationCase(lower: " 7 ", upper: "9", expected: nil),
    ValidationCase(lower: "abc", upper: "", expected: boundsMessage),
    ValidationCase(lower: "", upper: "1e", expected: boundsMessage),
    ValidationCase(lower: "10", upper: "5", expected: orderMessage),
  ])
  func validationTable(_ testCase: ValidationCase) {
    let model = AlertEditorModel(context: makeContext(transport: StubTransport(script: [])), insightID: 42)
    model.lowerText = testCase.lower
    model.upperText = testCase.upper
    #expect(model.validationMessage == testCase.expected)
  }

  @Test func invalidBoundsBlockSaveWithoutARequest() async {
    let transport = StubTransport(script: [])
    let model = AlertEditorModel(context: makeContext(transport: transport), insightID: 42)
    model.lowerText = "abc"
    let saved = await model.save()
    #expect(!saved)
    #expect(model.errorMessage == boundsMessage)
    #expect(transport.callCount == 0)
  }

  @Test func createPostsToAlertsCollection() async throws {
    let transport = StubTransport(script: [.response(status: 201, body: alertResponse)])
    let model = AlertEditorModel(context: makeContext(transport: transport), insightID: 42)
    model.name = "Signups too low"
    model.lowerText = "10"
    let saved = await model.save()
    #expect(saved)
    #expect(model.errorMessage == nil)
    #expect(!model.isSaving)
    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path() == "/api/projects/1/alerts/")
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
    #expect(body["insight"] == 42)
    #expect(body["name"] == "Signups too low")
  }

  @Test func updatePatchesTheAlert() async throws {
    let transport = StubTransport(script: [.response(status: 200, body: alertResponse)])
    let model = AlertEditorModel(
      context: makeContext(transport: transport),
      insightID: 42,
      alert: existingAlert()
    )
    model.upperText = "100"
    let saved = await model.save()
    #expect(saved)
    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "PATCH")
    #expect(request.url?.path() == "/api/projects/1/alerts/alert-1/")
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
    #expect(body["threshold"]?["configuration"]?["bounds"]?["upper"] == 100)
  }

  @Test func deleteRemovesTheAlert() async throws {
    let transport = StubTransport(script: [.response(status: 204, body: Data())])
    let model = AlertEditorModel(
      context: makeContext(transport: transport),
      insightID: 42,
      alert: existingAlert()
    )
    let deleted = await model.delete()
    #expect(deleted)
    #expect(!model.isDeleting)
    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "DELETE")
    #expect(request.url?.path() == "/api/projects/1/alerts/alert-1/")
  }

  @Test func serverFailureSetsErrorAndKeepsSheetOpen() async {
    let body = Data(#"{"type":"validation_error","code":"invalid_input","detail":"bad"}"#.utf8)
    let transport = StubTransport(script: [.response(status: 400, body: body)])
    let model = AlertEditorModel(context: makeContext(transport: transport), insightID: 42)
    let saved = await model.save()
    #expect(!saved)
    #expect(model.errorMessage == "Couldn't save the alert. Check the values and try again.")
    #expect(!model.isSaving)
  }

  @Test func saveInFlightRejectsASecondSubmission() async {
    let transport = StubTransport(script: [
      .slowResponse(status: 201, body: alertResponse, delay: 0.1)
    ])
    let model = AlertEditorModel(context: makeContext(transport: transport), insightID: 42)
    async let first = model.save()
    var spins = 0
    while transport.callCount == 0, spins < 100_000 {
      spins += 1
      await Task.yield()
    }
    #expect(model.isSaving)
    let second = await model.save()
    #expect(!second)
    #expect(await first)
    #expect(transport.callCount == 1)
  }
}

@MainActor
@Suite struct InsightAlertsModelTests {
  @Test func loadKeepsOnlyThisInsightsAlerts() async throws {
    let list = Data(
      """
      {
        "count": 2,
        "next": null,
        "previous": null,
        "results": [
          {"id": "a1", "name": "Mine", "enabled": true, "insight": {"id": 42}},
          {"id": "a2", "name": "Other", "enabled": true, "insight": 7}
        ]
      }
      """.utf8)
    let transport = StubTransport(script: [.response(status: 200, body: list)])
    let model = InsightAlertsModel(context: makeContext(transport: transport), insightID: 42)
    await model.load()
    #expect(model.alerts.map(\.id) == ["a1"])
    let url = try #require(transport.requests.first?.url)
    #expect(url.query == "insight_id=42")
  }
}
