import Foundation
import PostHogAPI
import PostHogTestSupport
import Testing

@Suite struct SessionRecordingTests {
  @Test func decodesAFullRecordingWithNestedPerson() throws {
    let json = """
      {
        "id": "0199-session-1",
        "distinct_id": "device-42",
        "person": {
          "distinct_ids": ["device-42"],
          "properties": {"email": "casey@example.com"}
        },
        "start_time": "2026-08-30T10:00:00.500000Z",
        "recording_duration": 272.4,
        "active_seconds": 120.0,
        "click_count": 12,
        "console_error_count": 3,
        "start_url": "https://example.com/app",
        "viewed": true
      }
      """
    let recording = try APIClient.makeDecoder().decode(SessionRecording.self, from: Data(json.utf8))
    #expect(recording.id == "0199-session-1")
    #expect(recording.distinctID == "device-42")
    #expect(recording.personEmailOrID == "casey@example.com")
    #expect(recording.startTime != nil)
    #expect(recording.recordingDuration == 272.4)
    #expect(recording.activeSeconds == 120.0)
    #expect(recording.clickCount == 12)
    #expect(recording.consoleErrorCount == 3)
    #expect(recording.startURL == "https://example.com/app")
    #expect(recording.viewed)
  }

  @Test func personWithoutEmailFallsBackToFirstDistinctID() throws {
    let json = """
      {
        "id": "s2",
        "person": {"distinct_ids": ["anon-7", "anon-8"], "properties": {}}
      }
      """
    let recording = try APIClient.makeDecoder().decode(SessionRecording.self, from: Data(json.utf8))
    #expect(recording.personEmailOrID == "anon-7")
  }

  @Test func missingFieldsDecodeDefensively() throws {
    let json = #"{"id": "s3", "start_time": "not a date", "person": null}"#
    let recording = try APIClient.makeDecoder().decode(SessionRecording.self, from: Data(json.utf8))
    #expect(recording.distinctID == nil)
    #expect(recording.personEmailOrID == nil)
    #expect(recording.startTime == nil)
    #expect(recording.recordingDuration == nil)
    #expect(recording.clickCount == nil)
    #expect(recording.consoleErrorCount == nil)
    #expect(recording.startURL == nil)
    #expect(!recording.viewed)
    #expect(recording.personDisplay == "Unknown user")
  }

  @Test func listRequestCarriesDateFrom() async throws {
    let page = Data(#"{"count": 0, "next": null, "previous": null, "results": []}"#.utf8)
    let transport = StubTransport(script: [.response(status: 200, body: page)])
    let client = APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
    _ = try await client.sessionRecordings(projectID: 1, dateFrom: "-24h")

    let url = try #require(transport.requests.first?.url)
    #expect(url.path() == "/api/projects/1/session_recordings/")
    #expect(url.query() == "date_from=-24h")
  }
}
