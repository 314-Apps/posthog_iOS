import Foundation
import PostHogFoundation

/// One session replay recording. The REST shape varies with server-side
/// hydration flags, so every field except `id` decodes defensively.
public struct SessionRecording: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let distinctID: String?
  /// Best display string for the person: their email when the nested `person`
  /// carries one, else the person's first distinct id.
  public let personEmailOrID: String?
  public let startTime: Date?
  public let recordingDuration: Double?
  public let activeSeconds: Double?
  public let clickCount: Int?
  public let consoleErrorCount: Int?
  public let startURL: String?
  public let viewed: Bool
  /// `web` or a mobile SDK's name. Mobile recordings hold wireframes rather
  /// than a DOM, so the player has to convert them before it can draw them.
  public let snapshotSource: String?

  public var isMobileRecording: Bool {
    guard let snapshotSource else { return false }
    return snapshotSource != "web" && snapshotSource != "unknown"
  }

  enum CodingKeys: String, CodingKey {
    case id
    case distinctID = "distinct_id"
    case person
    case startTime = "start_time"
    case recordingDuration = "recording_duration"
    case activeSeconds = "active_seconds"
    case clickCount = "click_count"
    case consoleErrorCount = "console_error_count"
    case startURL = "start_url"
    case viewed
    case snapshotSource = "snapshot_source"
  }

  public init(
    id: String,
    distinctID: String?,
    personEmailOrID: String?,
    startTime: Date?,
    recordingDuration: Double?,
    activeSeconds: Double?,
    clickCount: Int?,
    consoleErrorCount: Int?,
    startURL: String?,
    viewed: Bool,
    snapshotSource: String? = nil
  ) {
    self.id = id
    self.distinctID = distinctID
    self.personEmailOrID = personEmailOrID
    self.startTime = startTime
    self.recordingDuration = recordingDuration
    self.activeSeconds = activeSeconds
    self.clickCount = clickCount
    self.consoleErrorCount = consoleErrorCount
    self.startURL = startURL
    self.viewed = viewed
    self.snapshotSource = snapshotSource
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.distinctID = try? container.decode(String.self, forKey: .distinctID)
    // The API nests a person object; the cache re-encodes the derived display
    // string under the same key, so both shapes decode here.
    let person = try? container.decode(JSONValue.self, forKey: .person)
    if let cached = person?.stringValue {
      self.personEmailOrID = cached
    } else {
      let email = person?["properties"]?["email"]?.stringValue
      let firstDistinctID = person?["distinct_ids"]?.arrayValue?.first?.stringValue
      self.personEmailOrID = email ?? firstDistinctID
    }
    self.startTime = try? container.decode(Date.self, forKey: .startTime)
    self.recordingDuration = try? container.decode(Double.self, forKey: .recordingDuration)
    self.activeSeconds = try? container.decode(Double.self, forKey: .activeSeconds)
    self.clickCount = try? container.decode(Int.self, forKey: .clickCount)
    self.consoleErrorCount = try? container.decode(Int.self, forKey: .consoleErrorCount)
    self.startURL = try? container.decode(String.self, forKey: .startURL)
    self.viewed = (try? container.decode(Bool.self, forKey: .viewed)) ?? false
    self.snapshotSource = try? container.decode(String.self, forKey: .snapshotSource)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(distinctID, forKey: .distinctID)
    try container.encodeIfPresent(personEmailOrID, forKey: .person)
    try container.encodeIfPresent(startTime, forKey: .startTime)
    try container.encodeIfPresent(recordingDuration, forKey: .recordingDuration)
    try container.encodeIfPresent(activeSeconds, forKey: .activeSeconds)
    try container.encodeIfPresent(clickCount, forKey: .clickCount)
    try container.encodeIfPresent(consoleErrorCount, forKey: .consoleErrorCount)
    try container.encodeIfPresent(startURL, forKey: .startURL)
    try container.encode(viewed, forKey: .viewed)
    try container.encodeIfPresent(snapshotSource, forKey: .snapshotSource)
  }

  /// The list-row and header display string.
  public var personDisplay: String {
    personEmailOrID ?? distinctID ?? "Unknown user"
  }
}

/// Progress of a server-side export; `hasContent` means the file is ready.
public struct ExportStatus: Codable, Sendable, Equatable {
  public let id: Int
  public let hasContent: Bool
  public let exception: String?

  enum CodingKeys: String, CodingKey {
    case id
    case hasContent = "has_content"
    case exception
  }

  public init(id: Int, hasContent: Bool, exception: String?) {
    self.id = id
    self.hasContent = hasContent
    self.exception = exception
  }
}

/// POST /exports/ replies with the full asset object; only the id matters here.
private struct RecordingExportCreated: Decodable, Sendable {
  let id: Int
}

extension APIClient {
  public func sessionRecordings(
    projectID: Int,
    dateFrom: String? = nil
  ) async throws -> Paginated<SessionRecording> {
    var query: [URLQueryItem] = []
    if let dateFrom, !dateFrom.isEmpty {
      query.append(URLQueryItem(name: "date_from", value: dateFrom))
    }
    return try await send(.get("/api/projects/\(projectID)/session_recordings/", query: query))
  }

  public func sessionRecording(projectID: Int, sessionID: String) async throws -> SessionRecording {
    try await send(.get("/api/projects/\(projectID)/session_recordings/\(sessionID)/"))
  }

  /// Starts a server-side video render and returns the export id to poll.
  public func createRecordingExport(projectID: Int, sessionID: String) async throws -> Int {
    let payload: JSONValue = [
      "export_format": "video/mp4",
      "export_context": ["session_recording_id": .string(sessionID)],
    ]
    let body = try Self.makeEncoder().encode(payload)
    let created: RecordingExportCreated = try await send(
      .post("/api/projects/\(projectID)/exports/", body: body)
    )
    return created.id
  }

  public func exportStatus(projectID: Int, exportID: Int) async throws -> ExportStatus {
    try await send(.get("/api/projects/\(projectID)/exports/\(exportID)/"))
  }

  /// Path for the rendered file; callers download it with `sendRaw`.
  public func exportContentPath(projectID: Int, exportID: Int) -> String {
    "/api/projects/\(projectID)/exports/\(exportID)/content/"
  }
}
