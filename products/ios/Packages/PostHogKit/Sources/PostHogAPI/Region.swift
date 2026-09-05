import Foundation

/// A PostHog instance the app can talk to.
public enum Region: Sendable, Equatable, Hashable, Identifiable {
  case us
  case eu
  /// Local `hogli start` stack; surfaced only in Debug builds.
  case dev
  /// A customer-run instance, reached with a personal API key.
  case selfHosted(host: URL)

  /// The picker's fixed options; self-hosted enters through its own flow.
  public static let cloudOptions: [Region] = [.us, .eu]

  /// Maps a typed instance URL back onto a known region, so signing into cloud
  /// with an API key keeps its livestream host and cache namespace instead of
  /// being treated as a stranger.
  public static func forHost(_ url: URL) -> Region {
    switch url.host()?.lowercased() {
    case "us.posthog.com", "app.posthog.com": .us
    case "eu.posthog.com": .eu
    case "localhost", "127.0.0.1": .dev
    default: .selfHosted(host: url)
    }
  }

  public var id: String { storageKey }

  /// Stable key for caches and storage namespacing.
  public var storageKey: String {
    switch self {
    case .us: "us"
    case .eu: "eu"
    case .dev: "dev"
    case .selfHosted(let host): "custom-\(host.host() ?? "instance")"
    }
  }

  public var apiBaseURL: URL {
    switch self {
    case .us: URL(string: "https://us.posthog.com")!
    case .eu: URL(string: "https://eu.posthog.com")!
    case .dev: URL(string: "http://localhost:8010")!
    case .selfHosted(let host): host
    }
  }

  public var livestreamBaseURL: URL? {
    switch self {
    case .us: URL(string: "https://live.us.posthog.com")
    case .eu: URL(string: "https://live.eu.posthog.com")
    case .dev: URL(string: "http://localhost:8666")
    case .selfHosted: nil
    }
  }

  public var displayName: String {
    switch self {
    case .us: "US Cloud"
    case .eu: "EU Cloud"
    case .dev: "Local dev"
    case .selfHosted(let host): host.host() ?? "Self-hosted"
    }
  }

  public var hostDescription: String {
    switch self {
    case .us: "us.posthog.com"
    case .eu: "eu.posthog.com"
    case .dev: "localhost:8010"
    case .selfHosted(let host): host.host() ?? host.absoluteString
    }
  }
}

extension Region: Codable {
  // Stored sessions predate self-hosted support and carry a bare string
  // ("us"/"eu"/"dev"); newer custom entries carry {"custom": "<url>"}.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let plain = try? container.decode(String.self) {
      switch plain {
      case "us": self = .us
      case "eu": self = .eu
      case "dev": self = .dev
      default:
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Unknown region \(plain)"
        )
      }
      return
    }
    let object = try container.decode([String: String].self)
    guard let raw = object["custom"], let url = URL(string: raw) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unknown region payload"
      )
    }
    self = .selfHosted(host: url)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .us: try container.encode("us")
    case .eu: try container.encode("eu")
    case .dev: try container.encode("dev")
    case .selfHosted(let host): try container.encode(["custom": host.absoluteString])
    }
  }
}
