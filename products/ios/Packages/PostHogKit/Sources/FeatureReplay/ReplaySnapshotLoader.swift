import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogQueries

/// Why a recording cannot be played, in the terms the person needs.
public enum ReplayLoadFailure: Error, Equatable, Sendable {
  case noAccess
  case noData
  case deleted(at: Date?)
  case tooBusy
  case other(String)

  init(_ error: APIError) {
    guard case .server(let status, _, _, _) = error else {
      self = .other(String(describing: error))
      return
    }
    switch status {
    case 401, 403: self = .noAccess
    case 404: self = .noData
    case 410: self = .deleted(at: nil)
    case 429, 503: self = .tooBusy
    default: self = .other("status \(status)")
    }
  }
}

/// Turns one recording into an ordered list of fetchable blocks.
///
/// The API serves blocks in ranges, and caps how many one request may ask for,
/// so this groups them into chunks that stay under the cap. The player asks for
/// chunk `i`, never for a block, which keeps paging entirely on this side.
public actor ReplaySnapshotLoader {
  /// The server rejects a range wider than 20 blocks for a personal API key,
  /// which is the smaller of the two limits it applies. Requesting 20 at a time
  /// stays inside it whichever credential the person signed in with.
  public static let blocksPerChunk = 20

  /// One fetchable unit, already resolved to the request it needs.
  public enum Chunk: Equatable, Sendable {
    case blocks(start: Int, end: Int)
    case archive(blobKey: String)
  }

  private let context: ProjectContext
  private let sessionID: String
  private var chunks: [Chunk] = []
  private var didPlan = false

  public init(context: ProjectContext, sessionID: String) {
    self.context = context
    self.sessionID = sessionID
  }

  /// Reads the source listing and returns how many chunks the player should ask
  /// for. Throws rather than returning zero when the recording cannot be read,
  /// so the caller can say why.
  public func plan() async throws -> Int {
    if didPlan { return chunks.count }
    let sources: RecordingSnapshotSources
    do {
      sources = try await context.client.recordingSnapshotSources(
        projectID: context.projectID,
        sessionID: sessionID
      )
    } catch let error as APIError {
      throw ReplayLoadFailure(error)
    }
    chunks = Self.plan(for: sources.sources)
    didPlan = true
    if chunks.isEmpty { throw ReplayLoadFailure.noData }
    return chunks.count
  }

  public static func plan(for sources: [RecordingSnapshotSource]) -> [Chunk] {
    // Long-term storage answers with the whole recording at one key, so it is
    // one chunk and the block ranges do not apply.
    let archive = sources.first { $0.source == .blobV2LTS }
    if let key = archive?.blobKey, !key.isEmpty {
      return [.archive(blobKey: key)]
    }

    let indices =
      sources
      .filter { $0.source == .blobV2 }
      .compactMap { $0.blobKey.flatMap(Int.init) }
      .sorted()
    guard let first = indices.first, let last = indices.last else { return [] }

    var chunks: [Chunk] = []
    var start = first
    while start <= last {
      let end = min(start + blocksPerChunk - 1, last)
      chunks.append(.blocks(start: start, end: end))
      start = end + 1
    }
    return chunks
  }

  /// The bytes of one chunk, exactly as the API sent them.
  public func chunk(at index: Int) async throws -> Data {
    guard chunks.indices.contains(index) else { throw ReplayLoadFailure.noData }
    do {
      switch chunks[index] {
      case .blocks(let start, let end):
        return try await context.client.recordingSnapshotBlocks(
          projectID: context.projectID,
          sessionID: sessionID,
          startBlobKey: start,
          endBlobKey: end
        )
      case .archive(let blobKey):
        return try await context.client.recordingSnapshotArchive(
          projectID: context.projectID,
          sessionID: sessionID,
          blobKey: blobKey
        )
      }
    } catch let error as APIError {
      PHLog.api.error("snapshot chunk \(index) failed: \(error)")
      throw ReplayLoadFailure(error)
    }
  }
}
