import Foundation

/// A PostHog instance the app can talk to.
public enum Region: String, Sendable, Codable, CaseIterable, Identifiable {
  case us
  case eu
  /// Local `hogli start` stack; surfaced only in Debug builds.
  case dev

  public var id: String { rawValue }

  public var apiBaseURL: URL {
    switch self {
    case .us: URL(string: "https://us.posthog.com")!
    case .eu: URL(string: "https://eu.posthog.com")!
    case .dev: URL(string: "http://localhost:8010")!
    }
  }

  public var livestreamBaseURL: URL {
    switch self {
    case .us: URL(string: "https://live.us.posthog.com")!
    case .eu: URL(string: "https://live.eu.posthog.com")!
    case .dev: URL(string: "http://localhost:8666")!
    }
  }

  public var displayName: String {
    switch self {
    case .us: "US Cloud"
    case .eu: "EU Cloud"
    case .dev: "Local dev"
    }
  }

  public var hostDescription: String {
    switch self {
    case .us: "us.posthog.com"
    case .eu: "eu.posthog.com"
    case .dev: "localhost:8010"
    }
  }
}
