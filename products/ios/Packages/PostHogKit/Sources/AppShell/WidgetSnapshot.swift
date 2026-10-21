import Foundation
import PostHogFoundation
import WidgetKit

/// The pulse snapshot the app hands to its widgets via the App Group.
/// Widgets render only this cached data: no tokens, no network in extensions.
public struct WidgetSnapshot: Codable, Sendable {
  public let projectName: String
  public let value: Double
  public let deltaFraction: Double?
  public let updatedAt: Date

  public init(projectName: String, value: Double, deltaFraction: Double?, updatedAt: Date) {
    self.projectName = projectName
    self.value = value
    self.deltaFraction = deltaFraction
    self.updatedAt = updatedAt
  }
}

public enum WidgetSnapshotStore {
  public static let appGroupID = "group.com.posthog.ios"

  static var fileURL: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
      .appendingPathComponent("pulse-snapshot.json")
  }

  /// No-ops when the App Group is unavailable (entitlement not provisioned).
  public static func write(_ snapshot: WidgetSnapshot) {
    guard let fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
    try? data.write(to: fileURL, options: .atomic)
    WidgetCenter.shared.reloadAllTimelines()
  }

  public static func read() -> WidgetSnapshot? {
    guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
  }

  public static func clear() {
    guard let fileURL else { return }
    try? FileManager.default.removeItem(at: fileURL)
    WidgetCenter.shared.reloadAllTimelines()
  }
}
