import PostHogFoundation

/// Totals mined from the raw stats payload. The endpoint's shape varies by
/// server version, so the walk matches event-name keys anywhere in the object
/// instead of relying on one fixed path.
struct SurveyStatsSummary: Equatable, Sendable {
  var shown: Int?
  var responded: Int?
  var dismissed: Int?

  init(shown: Int? = nil, responded: Int? = nil, dismissed: Int? = nil) {
    self.shown = shown
    self.responded = responded
    self.dismissed = dismissed
  }

  var hasAnyValue: Bool { shown != nil || responded != nil || dismissed != nil }

  static func parse(_ raw: JSONValue) -> SurveyStatsSummary {
    var summary = SurveyStatsSummary()
    collect(raw, into: &summary, depth: 0)
    return summary
  }

  /// The depth cap bounds the walk on adversarially nested payloads.
  private static func collect(_ value: JSONValue, into summary: inout SurveyStatsSummary, depth: Int) {
    guard depth < 6, case .object(let object) = value else { return }
    for (key, entry) in object {
      switch key.lowercased().replacingOccurrences(of: "_", with: " ") {
      case "survey shown":
        summary.shown = summary.shown ?? count(in: entry)
      case "survey sent":
        summary.responded = summary.responded ?? count(in: entry)
      case "survey dismissed":
        summary.dismissed = summary.dismissed ?? count(in: entry)
      default:
        collect(entry, into: &summary, depth: depth + 1)
      }
    }
  }

  private static func count(in value: JSONValue) -> Int? {
    if let number = value.numberValue { return Int(number) }
    for key in ["total_count", "count", "total"] {
      if let number = value[key]?.numberValue { return Int(number) }
    }
    return nil
  }
}
