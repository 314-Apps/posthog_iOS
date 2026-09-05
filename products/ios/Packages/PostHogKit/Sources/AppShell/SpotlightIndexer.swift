import CoreSpotlight
import Foundation
import PostHogAPI
import PostHogFoundation

/// Feeds dashboards and flags into Spotlight; tapping a result routes natively.
/// Indexing is best-effort and refreshed on each Home load.
public enum SpotlightIndexer {
  static let domain = "com.posthog.ios.search"

  public static func index(dashboards: [DashboardSummary], flags: [FeatureFlag], projectID: Int) {
    var items: [CSSearchableItem] = []
    for dashboard in dashboards {
      let attributes = CSSearchableItemAttributeSet(contentType: .content)
      attributes.title = dashboard.name
      attributes.contentDescription = "PostHog dashboard"
      items.append(
        CSSearchableItem(
          uniqueIdentifier: "dashboard/\(projectID)/\(dashboard.id)",
          domainIdentifier: domain,
          attributeSet: attributes
        )
      )
    }
    for flag in flags {
      let attributes = CSSearchableItemAttributeSet(contentType: .content)
      attributes.title = flag.key
      attributes.contentDescription = "PostHog feature flag"
      items.append(
        CSSearchableItem(
          uniqueIdentifier: "flag/\(projectID)/\(flag.id)",
          domainIdentifier: domain,
          attributeSet: attributes
        )
      )
    }
    CSSearchableIndex.default().indexSearchableItems(items) { error in
      if let error {
        PHLog.ui.error("spotlight indexing failed: \(error)")
      }
    }
  }

  public static func clear() {
    CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
  }

  /// Parses a tapped result back into a route, when it targets this project.
  public static func route(for identifier: String, currentProjectID: Int) -> Route? {
    let parts = identifier.split(separator: "/").map(String.init)
    guard parts.count == 3, let projectID = Int(parts[1]), projectID == currentProjectID,
      let id = Int(parts[2])
    else { return nil }
    switch parts[0] {
    case "dashboard": return .dashboard(id: id)
    case "flag": return .flag(id: id)
    default: return nil
    }
  }
}
