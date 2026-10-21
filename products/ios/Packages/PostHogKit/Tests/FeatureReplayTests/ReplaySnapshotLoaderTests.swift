import Foundation
import PostHogAPI
import Testing

@testable import FeatureReplay

private func blocks(_ count: Int) -> [RecordingSnapshotSource] {
  (0..<count).map {
    RecordingSnapshotSource(source: .blobV2, blobKey: String($0), startTimestamp: Date())
  }
}

@Suite struct ReplaySnapshotLoaderTests {
  /// The API refuses a range wider than 20 blocks for a personal API key, so
  /// the chunking is a server rule this side must not drift from.
  @Test(
    arguments: [
      (1, [ReplaySnapshotLoader.Chunk.blocks(start: 0, end: 0)]),
      (20, [.blocks(start: 0, end: 19)]),
      (21, [.blocks(start: 0, end: 19), .blocks(start: 20, end: 20)]),
      (45, [.blocks(start: 0, end: 19), .blocks(start: 20, end: 39), .blocks(start: 40, end: 44)]),
    ] as [(Int, [ReplaySnapshotLoader.Chunk])]
  )
  func blocksAreGroupedUnderTheServerLimit(_ count: Int, _ expected: [ReplaySnapshotLoader.Chunk]) {
    #expect(ReplaySnapshotLoader.plan(for: blocks(count)) == expected)
  }

  @Test func everyChunkStaysWithinTheLimit() {
    for chunk in ReplaySnapshotLoader.plan(for: blocks(137)) {
      guard case .blocks(let start, let end) = chunk else {
        Issue.record("expected block ranges")
        continue
      }
      #expect(end - start < ReplaySnapshotLoader.blocksPerChunk)
    }
  }

  /// Long-term storage answers with the whole recording under one key, and that
  /// key has to ride through exactly as given or the request 404s.
  @Test func longTermStorageBecomesOneChunkKeyedByItsPath() {
    let sources = [
      RecordingSnapshotSource(
        source: .blobV2LTS,
        blobKey: "session_recordings_lts/team_id/1/session_id/abc/data",
        startTimestamp: nil,
        endTimestamp: nil
      )
    ]
    #expect(
      ReplaySnapshotLoader.plan(for: sources)
        == [.archive(blobKey: "session_recordings_lts/team_id/1/session_id/abc/data")]
    )
  }

  @Test func blocksAreOrderedEvenWhenTheListingIsNot() {
    let shuffled = [4, 0, 2, 1, 3].map {
      RecordingSnapshotSource(source: .blobV2, blobKey: String($0))
    }
    #expect(ReplaySnapshotLoader.plan(for: shuffled) == [.blocks(start: 0, end: 4)])
  }

  @Test(
    arguments: [
      [],
      [RecordingSnapshotSource(source: .unknown("blob_v3"), blobKey: "0")],
      [RecordingSnapshotSource(source: .blobV2, blobKey: nil)],
      [RecordingSnapshotSource(source: .blobV2LTS, blobKey: "")],
    ] as [[RecordingSnapshotSource]]
  )
  func nothingPlayableYieldsNoChunks(_ sources: [RecordingSnapshotSource]) {
    #expect(ReplaySnapshotLoader.plan(for: sources).isEmpty)
  }

  @Test(
    arguments: zip(
      [401, 403, 404, 410, 429, 503, 500],
      [
        ReplayLoadFailure.noAccess, .noAccess, .noData, .deleted(at: nil), .tooBusy, .tooBusy,
        .other("status 500"),
      ]
    )
  )
  func serverStatusMapsToWhatThePersonIsTold(_ status: Int, _ expected: ReplayLoadFailure) {
    #expect(ReplayLoadFailure(APIError.server(status: status, code: nil, detail: nil, attr: nil)) == expected)
  }
}
