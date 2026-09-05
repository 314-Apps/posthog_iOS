import Foundation
import PostHogAPI

/// Where a tapped inbox row navigates. The shell owns the actual routing.
public enum InboxDestination: Hashable, Sendable {
  case insight(id: Int)
  case flag(id: Int)
  case errorIssue(id: String)
  case web(path: String)
}

extension InboxDestination {
  /// The web activity page is the fallback for rows without a resolvable
  /// native resource, so a tap never dead-ends.
  static func forEvent(_ event: NotificationEvent) -> InboxDestination {
    if event.type == .issueAssigned, let id = event.resourceID {
      return .errorIssue(id: id)
    }
    switch event.resourceType {
    case "insight":
      if let raw = event.resourceID, let id = Int(raw) {
        return .insight(id: id)
      }
    case "feature_flag", "flag":
      if let raw = event.resourceID, let id = Int(raw) {
        return .flag(id: id)
      }
    default:
      break
    }
    return .web(path: "/activity")
  }
}
