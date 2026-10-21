import Foundation
import Testing

@testable import PostHogAPI

@Suite struct DiskCacheTests {
  private func makeCache() -> DiskCache {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("DiskCacheTests-\(UUID().uuidString)", isDirectory: true)
    return DiskCache(root: root)
  }

  @Test func roundTripsAndReportsFreshness() async {
    let cache = makeCache()
    await cache.write("us/123/dashboards", value: ["a", "b"])
    let hit = await cache.read("us/123/dashboards", as: [String].self, staleAfter: 60)
    #expect(hit?.value == ["a", "b"])
    #expect(hit?.isStale == false)
    let staleHit = await cache.read("us/123/dashboards", as: [String].self, staleAfter: -1)
    #expect(staleHit?.isStale == true)
  }

  @Test func missReturnsNil() async {
    let cache = makeCache()
    let hit = await cache.read("us/123/nothing", as: [String].self, staleAfter: 60)
    #expect(hit == nil)
  }

  @Test func removeSubtreeDropsOnlyThatPrefix() async {
    let cache = makeCache()
    await cache.write("us/123/dashboards", value: ["a"])
    await cache.write("us/456/dashboards", value: ["b"])
    await cache.removeSubtree("us/123")
    let removed = await cache.read("us/123/dashboards", as: [String].self, staleAfter: 60)
    let kept = await cache.read("us/456/dashboards", as: [String].self, staleAfter: 60)
    #expect(removed == nil)
    #expect(kept?.value == ["b"])
  }

  @Test func corruptEntryReadsAsMiss() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("DiskCacheTests-\(UUID().uuidString)", isDirectory: true)
    let cache = DiskCache(root: root)
    await cache.write("k", value: 1)
    let file = root.appendingPathComponent("k.json")
    try Data("not json".utf8).write(to: file)
    let hit = await cache.read("k", as: Int.self, staleAfter: 60)
    #expect(hit == nil)
  }
}
