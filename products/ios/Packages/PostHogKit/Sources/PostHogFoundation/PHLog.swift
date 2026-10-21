import OSLog

/// Central logger factory. One subsystem for the whole app, one category per area.
public enum PHLog {
  public static let subsystem = "com.posthog.ios"

  public static func logger(category: String) -> Logger {
    Logger(subsystem: subsystem, category: category)
  }

  public static let api = logger(category: "api")
  public static let auth = logger(category: "auth")
  public static let cache = logger(category: "cache")
  public static let sse = logger(category: "sse")
  public static let ui = logger(category: "ui")
}
