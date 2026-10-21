import PostHogFoundation

/// Legacy name for funnel totals. Prefer `summarizeSurveyStats` / `SurveyFunnel`.
typealias SurveyStatsSummary = SurveyFunnel

extension SurveyFunnel {
  /// Defensive walk used when the typed funnel keys are missing — matches older
  /// server payloads that nest event names anywhere in the object.
  static func parse(_ raw: JSONValue) -> SurveyFunnel {
    let funnel = summarizeSurveyStats(raw)
    if funnel.hasAnyValue { return funnel }
    var legacy = SurveyFunnel()
    collect(raw, into: &legacy, depth: 0)
    return legacy
  }

  private static func collect(_ value: JSONValue, into summary: inout SurveyFunnel, depth: Int) {
    guard depth < 6, case .object(let object) = value else { return }
    for (key, entry) in object {
      switch key.lowercased().replacingOccurrences(of: "_", with: " ") {
      case "survey shown":
        if summary.shown == 0 { summary.shown = count(in: entry) ?? 0 }
      case "survey sent":
        if summary.sent == 0 { summary.sent = count(in: entry) ?? 0 }
      case "survey dismissed":
        if summary.dismissed == 0 { summary.dismissed = count(in: entry) ?? 0 }
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
