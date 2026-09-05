import Foundation

/// Where one part of a recording's data lives. The API answers with these
/// first, then serves the data itself one range at a time.
public struct RecordingSnapshotSource: Decodable, Sendable, Equatable {
  public let source: SnapshotSourceKind
  public let blobKey: String?
  public let startTimestamp: Date?
  public let endTimestamp: Date?

  enum CodingKeys: String, CodingKey {
    case source
    case blobKey = "blob_key"
    case startTimestamp = "start_timestamp"
    case endTimestamp = "end_timestamp"
  }

  public init(
    source: SnapshotSourceKind,
    blobKey: String?,
    startTimestamp: Date? = nil,
    endTimestamp: Date? = nil
  ) {
    self.source = source
    self.blobKey = blobKey
    self.startTimestamp = startTimestamp
    self.endTimestamp = endTimestamp
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.source = SnapshotSourceKind(
      rawValue: try container.decodeIfPresent(String.self, forKey: .source) ?? ""
    )
    self.blobKey = try container.decodeIfPresent(String.self, forKey: .blobKey)
    // Long-term storage names one whole recording and carries no timestamps.
    self.startTimestamp = try? container.decodeIfPresent(Date.self, forKey: .startTimestamp)
    self.endTimestamp = try? container.decodeIfPresent(Date.self, forKey: .endTimestamp)
  }
}

/// A new storage backend must not break playback, so an unrecognized name
/// rides through instead of failing the decode.
public enum SnapshotSourceKind: Sendable, Equatable {
  case blobV2
  case blobV2LTS
  case unknown(String)

  public init(rawValue: String) {
    switch rawValue {
    case "blob_v2": self = .blobV2
    case "blob_v2_lts": self = .blobV2LTS
    default: self = .unknown(rawValue)
    }
  }
}

public struct RecordingSnapshotSources: Decodable, Sendable, Equatable {
  public let sources: [RecordingSnapshotSource]

  public init(sources: [RecordingSnapshotSource]) {
    self.sources = sources
  }
}

/// The body the API sends when a recording has been deleted for good.
public struct RecordingDeletedDetail: Decodable, Sendable, Equatable {
  public let deletedAt: Date?

  enum CodingKeys: String, CodingKey {
    case deletedAt = "deleted_at"
  }

  public init(deletedAt: Date?) {
    self.deletedAt = deletedAt
  }
}

extension APIClient {
  public func recordingSnapshotSources(
    projectID: Int,
    sessionID: String
  ) async throws -> RecordingSnapshotSources {
    try await send(.get("/api/projects/\(projectID)/session_recordings/\(sessionID)/snapshots/"))
  }

  /// One inclusive range of blocks, as JSONL. The body is not JSON, so it comes
  /// back as bytes and is handed to the player untouched.
  public func recordingSnapshotBlocks(
    projectID: Int,
    sessionID: String,
    startBlobKey: Int,
    endBlobKey: Int
  ) async throws -> Data {
    try await sendRaw(
      .get(
        "/api/projects/\(projectID)/session_recordings/\(sessionID)/snapshots/",
        query: [
          URLQueryItem(name: "source", value: "blob_v2"),
          URLQueryItem(name: "start_blob_key", value: String(startBlobKey)),
          URLQueryItem(name: "end_blob_key", value: String(endBlobKey)),
        ]
      )
    )
  }

  /// The whole recording in one object, for recordings moved to long-term
  /// storage. The key must be the exact one the source listing gave.
  public func recordingSnapshotArchive(
    projectID: Int,
    sessionID: String,
    blobKey: String
  ) async throws -> Data {
    try await sendRaw(
      .get(
        "/api/projects/\(projectID)/session_recordings/\(sessionID)/snapshots/",
        query: [
          URLQueryItem(name: "source", value: "blob_v2_lts"),
          URLQueryItem(name: "blob_key", value: blobKey),
        ]
      )
    )
  }
}
