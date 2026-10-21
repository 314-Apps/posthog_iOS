import Foundation

/// What the third tab slot shows. The slot's identity (paths, deep links)
/// stays fixed; only its root content re-pins. Defaults to Flags.
public enum PinnableTab: String, CaseIterable, Identifiable, Sendable {
  case flags
  case errors
  case replay
  case web

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .flags: "Flags"
    case .errors: "Errors"
    case .replay: "Replay"
    case .web: "Web"
    }
  }

  public var systemImage: String {
    switch self {
    case .flags: "flag"
    case .errors: "ant"
    case .replay: "play.rectangle"
    case .web: "globe"
    }
  }
}
