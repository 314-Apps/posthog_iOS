import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogTestSupport
import Testing

@testable import FeatureExperiments

private func makeExperiment(
  startDate: Date? = nil,
  endDate: Date? = nil,
  metricsRaw: JSONValue? = nil,
  parametersRaw: JSONValue? = nil
) -> Experiment {
  Experiment(
    id: 1,
    name: "Test",
    startDate: startDate,
    endDate: endDate,
    metricsRaw: metricsRaw,
    parametersRaw: parametersRaw
  )
}

@Suite struct ExperimentTests {
  private let baseURL = URL(string: "https://us.posthog.com")!

  private func makeClient(transport: StubTransport) -> APIClient {
    APIClient(
      baseURL: baseURL,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
  }

  // MARK: Decoding

  @Test func decodesFullPayloadWithStringFlagKey() throws {
    let json = """
      {
        "id": 7,
        "name": "New signup CTA",
        "description": "Tests the shorter form",
        "start_date": "2026-08-01T09:00:00Z",
        "end_date": "2026-08-20T09:00:00.250Z",
        "archived": true,
        "feature_flag_key": "signup-cta",
        "metrics": [{"name": "Conversion", "kind": "ExperimentFunnelsQuery"}],
        "parameters": {"feature_flag_variants": [{"key": "control"}, {"key": "test"}]}
      }
      """
    let experiment = try APIClient.makeDecoder().decode(Experiment.self, from: Data(json.utf8))
    #expect(experiment.id == 7)
    #expect(experiment.name == "New signup CTA")
    #expect(experiment.description == "Tests the shorter form")
    #expect(experiment.startDate != nil)
    #expect(experiment.endDate != nil)
    #expect(experiment.archived)
    #expect(experiment.featureFlagKey == "signup-cta")
    #expect(experiment.variantCount == 2)
    #expect(experiment.lifecycle == .complete)
  }

  @Test func decodesNestedFlagObjectWhenKeyStringIsAbsent() throws {
    let json = """
      {
        "id": 8,
        "name": "Pricing page",
        "feature_flag": {"id": 44, "key": "pricing-page-test", "active": true}
      }
      """
    let experiment = try APIClient.makeDecoder().decode(Experiment.self, from: Data(json.utf8))
    #expect(experiment.featureFlagKey == "pricing-page-test")

    let flagAsID = #"{"id": 9, "name": "Pricing page", "feature_flag": 44}"#
    let fallback = try APIClient.makeDecoder().decode(Experiment.self, from: Data(flagAsID.utf8))
    #expect(fallback.featureFlagKey == nil)
  }

  @Test func missingOptionalFieldsDecodeDefensively() throws {
    let json = #"{"id": 10, "name": "Draft idea"}"#
    let experiment = try APIClient.makeDecoder().decode(Experiment.self, from: Data(json.utf8))
    #expect(experiment.description == nil)
    #expect(experiment.startDate == nil)
    #expect(experiment.endDate == nil)
    #expect(!experiment.archived)
    #expect(experiment.featureFlagKey == nil)
    #expect(experiment.metricsRaw == nil)
    #expect(experiment.variantCount == nil)
    #expect(experiment.lifecycle == .draft)
  }

  // MARK: Derivations

  @Test func derivesLifecycleFromDatePair() {
    let started = Date(timeIntervalSince1970: 1_000)
    let ended = Date(timeIntervalSince1970: 2_000)
    #expect(makeExperiment().lifecycle == .draft)
    #expect(makeExperiment(startDate: started).lifecycle == .running)
    #expect(makeExperiment(startDate: started, endDate: ended).lifecycle == .complete)
    #expect(makeExperiment(endDate: ended).lifecycle == .draft)
  }

  @Test(
    arguments: [
      (nil, nil),
      (JSONValue.object([:]), nil),
      (["feature_flag_variants": ["a", "b", "c"]], 3),
      (["feature_flag_variants": "oops"], nil),
    ] as [(JSONValue?, Int?)])
  func derivesVariantCountDefensively(parameters: JSONValue?, expected: Int?) {
    #expect(makeExperiment(parametersRaw: parameters).variantCount == expected)
  }

  @Test func metricNamesFallBackToKindThenPosition() {
    let metrics: JSONValue = [
      ["name": "Conversion rate"],
      ["name": "", "kind": "ExperimentTrendsQuery"],
      ["order": 3],
      "not an object",
    ]
    let experiment = makeExperiment(metricsRaw: metrics)
    #expect(
      experiment.metricDisplayNames == [
        "Conversion rate", "ExperimentTrendsQuery", "Metric 3", "Metric 4",
      ])
    #expect(makeExperiment().metricDisplayNames.isEmpty)
  }

  // MARK: Endpoints

  @Test func listsExperimentsForProject() async throws {
    let listJSON = """
      {
        "count": 2,
        "next": null,
        "previous": null,
        "results": [
          {"id": 1, "name": "Running one", "start_date": "2026-08-01T09:00:00Z"},
          {"id": 2, "name": "Draft one"}
        ]
      }
      """
    let transport = StubTransport(script: [.response(status: 200, body: Data(listJSON.utf8))])
    let page = try await makeClient(transport: transport).experiments(projectID: 3)
    #expect(
      transport.requests[0].url?.absoluteString
        == "https://us.posthog.com/api/projects/3/experiments/?limit=100")
    #expect(page.results.map(\.id) == [1, 2])
    #expect(page.results.map(\.lifecycle) == [.running, .draft])
  }

  @Test func fetchesOneExperimentWithTrailingSlash() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(#"{"id": 5, "name": "Solo"}"#.utf8))
    ])
    let experiment = try await makeClient(transport: transport).experiment(projectID: 3, experimentID: 5)
    #expect(
      transport.requests[0].url?.absoluteString
        == "https://us.posthog.com/api/projects/3/experiments/5/")
    #expect(experiment.name == "Solo")
  }
}
