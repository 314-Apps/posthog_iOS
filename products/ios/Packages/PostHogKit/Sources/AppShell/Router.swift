import Foundation
import Observation
import PostHogAPI
import SwiftUI

public enum AppTab: String, Sendable, CaseIterable {
  case home
  case dashboards
  case flags
  case inbox
  case max
}

/// Screens the app can navigate to. Serializable so deep links and state
/// restoration share one vocabulary.
public enum Route: Hashable, Sendable {
  case dashboard(id: Int)
  case insight(id: Int)
  case flag(id: Int)
  case errorsList
  case errorIssue(id: String)
  case liveEvents
  case replayList
  case replay(sessionID: String)
  case experimentsList
  case experiment(id: Int)
  case surveysList
  case survey(id: String)
  case webAnalytics
  case peopleList
  case person(id: String)
  case sqlRunner
  case activityFeed
  case annotations
  case billing
}

/// One router: the selected tab plus a NavigationStack path per tab.
@MainActor
@Observable
public final class Router {
  public var selectedTab: AppTab = .home
  public var homePath = NavigationPath()
  public var dashboardsPath = NavigationPath()
  public var flagsPath = NavigationPath()
  public var inboxPath = NavigationPath()
  public var maxPath = NavigationPath()

  public init() {}

  public func open(_ route: Route) {
    switch route {
    case .dashboard, .insight:
      selectedTab = .dashboards
      dashboardsPath.append(route)
    case .flag:
      selectedTab = .flags
      flagsPath.append(route)
    default:
      pushOnSelectedTab(route)
    }
  }

  /// Pushes without switching tabs (Home chips, inbox row taps).
  public func pushOnSelectedTab(_ route: Route) {
    switch selectedTab {
    case .home: homePath.append(route)
    case .dashboards: dashboardsPath.append(route)
    case .flags: flagsPath.append(route)
    case .inbox: inboxPath.append(route)
    case .max: maxPath.append(route)
    }
  }

  public func handle(deepLink url: URL, currentProjectID: Int?) -> DeepLink? {
    guard let link = DeepLinkParser.parse(url) else { return nil }
    if let tab = link.tab {
      selectedTab = tab
      return nil
    }
    if let route = link.route, link.projectID == nil || link.projectID == currentProjectID {
      open(route)
      return nil
    }
    // A different project (or a project-less link) needs the shell's help.
    return link
  }
}

public struct DeepLink: Hashable, Sendable {
  public let region: Region?
  public let projectID: Int?
  public let route: Route?
  public var tab: AppTab?

  public init(region: Region?, projectID: Int?, route: Route?, tab: AppTab? = nil) {
    self.region = region
    self.projectID = projectID
    self.route = route
    self.tab = tab
  }
}

/// Pure parser for `posthog-ios://` URLs (and, later, universal links).
/// `posthog-ios://project/123/dashboard/45`, `…/insights/67`, `…/feature_flags/89`.
public enum DeepLinkParser {
  public static func parse(_ url: URL) -> DeepLink? {
    guard url.scheme == "posthog-ios" else { return nil }
    var parts = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
    guard !parts.isEmpty else { return nil }

    var projectID: Int?
    if parts.first == "project", parts.count >= 2, let id = Int(parts[1]) {
      projectID = id
      parts.removeFirst(2)
    }

    guard let head = parts.first else {
      return DeepLink(region: nil, projectID: projectID, route: nil)
    }
    // Tab-level links (Siri shortcuts, widgets): posthog-ios://max etc.
    if parts.count == 1, projectID == nil, let tab = AppTab(rawValue: head) {
      return DeepLink(region: nil, projectID: nil, route: nil, tab: tab)
    }
    let idPart = parts.count >= 2 ? Int(parts[1]) : nil
    let route: Route? =
      switch (head, idPart) {
      case ("dashboard", .some(let id)): .dashboard(id: id)
      case ("insights", .some(let id)): .insight(id: id)
      case ("feature_flags", .some(let id)): .flag(id: id)
      case ("replay", _) where parts.count >= 2: .replay(sessionID: parts[1])
      default: nil
      }
    guard route != nil else { return nil }
    return DeepLink(region: nil, projectID: projectID, route: route)
  }
}
