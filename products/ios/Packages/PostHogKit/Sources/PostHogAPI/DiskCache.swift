import Foundation
import PostHogFoundation

/// Stale-while-revalidate JSON file cache under Caches/ (OS-purgeable — every
/// entry is a discardable snapshot of server truth). Keys are hierarchical
/// (`region/project/resource`) so a project switch or sign-out drops a subtree.
public actor DiskCache {
  public struct Entry<Value: Codable & Sendable>: Codable, Sendable {
    public let storedAt: Date
    public let payload: Value
  }

  public struct Hit<Value: Codable & Sendable>: Sendable {
    public let value: Value
    public let storedAt: Date
    public let isStale: Bool
  }

  private let root: URL
  private let fileManager = FileManager.default

  public init(directoryName: String = "PostHogCache") {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    self.root = caches.appendingPathComponent(directoryName, isDirectory: true)
  }

  /// Test seam: an explicit root directory.
  public init(root: URL) {
    self.root = root
  }

  public func read<Value: Codable & Sendable>(
    _ key: String,
    as type: Value.Type = Value.self,
    staleAfter: TimeInterval
  ) -> Hit<Value>? {
    let url = fileURL(for: key)
    guard let data = try? Data(contentsOf: url),
      let entry = try? JSONDecoder().decode(Entry<Value>.self, from: data)
    else {
      return nil
    }
    let age = Date.now.timeIntervalSince(entry.storedAt)
    return Hit(value: entry.payload, storedAt: entry.storedAt, isStale: age > staleAfter)
  }

  public func write<Value: Codable & Sendable>(_ key: String, value: Value) {
    let url = fileURL(for: key)
    do {
      try fileManager.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try JSONEncoder().encode(Entry(storedAt: .now, payload: value))
      try data.write(to: url, options: .atomic)
    } catch {
      PHLog.cache.error("write failed for \(key, privacy: .public): \(error)")
    }
  }

  /// Removes everything under a key prefix (e.g. one project's cache).
  public func removeSubtree(_ prefix: String) {
    try? fileManager.removeItem(at: directoryURL(for: prefix))
  }

  public func removeAll() {
    try? fileManager.removeItem(at: root)
  }

  private func fileURL(for key: String) -> URL {
    directoryURL(for: key).appendingPathExtension("json")
  }

  private func directoryURL(for key: String) -> URL {
    key.split(separator: "/").reduce(root) { url, component in
      url.appendingPathComponent(sanitize(String(component)), isDirectory: true)
    }
  }

  private func sanitize(_ component: String) -> String {
    component.replacingOccurrences(of: "[^A-Za-z0-9._@-]", with: "_", options: .regularExpression)
  }
}
