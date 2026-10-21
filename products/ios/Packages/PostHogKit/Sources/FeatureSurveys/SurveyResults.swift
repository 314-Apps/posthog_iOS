import Foundation
import PostHogAPI
import PostHogFoundation

/// Date preset matching the Expo survey detail chips.
public enum SurveyDatePreset: String, CaseIterable, Sendable, Equatable, Identifiable {
  case all
  case last7Days = "7d"
  case last30Days = "30d"
  case last90Days = "90d"

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .all: "All time"
    case .last7Days: "Last 7 days"
    case .last30Days: "Last 30 days"
    case .last90Days: "Last 90 days"
    }
  }

  /// ISO-8601 `since` for API calls; nil means all-time.
  public func since(now: Date = .now) -> String? {
    let days: Int?
    switch self {
    case .all: days = nil
    case .last7Days: days = 7
    case .last30Days: days = 30
    case .last90Days: days = 90
    }
    guard let days else { return nil }
    let start = now.addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
    return ISO8601DateFormatter().string(from: start)
  }
}

public enum SurveyQuestionType: String, Sendable, Equatable {
  case open
  case link
  case rating
  case singleChoice = "single_choice"
  case multipleChoice = "multiple_choice"
}

public struct SurveyQuestionDef: Sendable, Equatable, Identifiable {
  public var id: String { stableID }
  public let stableID: String
  public let questionID: String?
  public let index: Int
  public let type: SurveyQuestionType
  public let text: String
  public let description: String?
  public let choices: [String]
  public let hasOpenChoice: Bool
  public let scale: Int?
  public let lowerBoundLabel: String?
  public let upperBoundLabel: String?
}

public struct SurveyFunnel: Sendable, Equatable {
  public var shown: Int
  public var uniqueShown: Int
  public var sent: Int
  public var uniqueSent: Int
  public var dismissed: Int
  public var uniqueDismissed: Int
  public var responseRate: Double
  public var uniqueResponseRate: Double
  public var dismissalRate: Double

  public init(
    shown: Int = 0,
    uniqueShown: Int = 0,
    sent: Int = 0,
    uniqueSent: Int = 0,
    dismissed: Int = 0,
    uniqueDismissed: Int = 0,
    responseRate: Double = 0,
    uniqueResponseRate: Double = 0,
    dismissalRate: Double = 0
  ) {
    self.shown = shown
    self.uniqueShown = uniqueShown
    self.sent = sent
    self.uniqueSent = uniqueSent
    self.dismissed = dismissed
    self.uniqueDismissed = uniqueDismissed
    self.responseRate = responseRate
    self.uniqueResponseRate = uniqueResponseRate
    self.dismissalRate = dismissalRate
  }

  public var hasAnyValue: Bool {
    shown > 0 || sent > 0 || dismissed > 0 || responseRate > 0
  }
}

public struct ResultBar: Sendable, Equatable, Identifiable {
  public var id: String { label }
  public let label: String
  public let count: Int
  public let share: Double
}

public struct NpsBreakdown: Sendable, Equatable {
  public let score: Int
  public let promoters: Int
  public let passives: Int
  public let detractors: Int
}

public struct OpenTextAnswer: Sendable, Equatable, Identifiable {
  public var id: String { responseUUID }
  public let responseUUID: String
  public let distinctID: String
  public let submittedAt: String
  public let text: String
}

public enum SurveyQuestionResult: Sendable, Equatable, Identifiable {
  case rating(question: SurveyQuestionDef, total: Int, bars: [ResultBar], average: Double?, nps: NpsBreakdown?)
  case choice(question: SurveyQuestionDef, total: Int, bars: [ResultBar], sampled: Bool)
  case open(question: SurveyQuestionDef, total: Int, answers: [OpenTextAnswer], sampled: Bool)
  case link(question: SurveyQuestionDef, total: Int)

  public var id: String { question.stableID }

  public var question: SurveyQuestionDef {
    switch self {
    case .rating(let question, _, _, _, _),
      .choice(let question, _, _, _),
      .open(let question, _, _, _),
      .link(let question, _):
      return question
    }
  }

  public var total: Int {
    switch self {
    case .rating(_, let total, _, _, _),
      .choice(_, let total, _, _),
      .open(_, let total, _, _),
      .link(_, let total):
      return total
    }
  }
}

public enum SurveyAction: Sendable, Equatable {
  case launch
  case stop
  case resume
  case archive
  case unarchive
}

/// Lifecycle actions the web app offers for a survey in its current state.
public func surveyActions(for survey: Survey, now: Date = .now) -> [SurveyAction] {
  if survey.archived { return [.unarchive] }
  let lifecycle: SurveyAction =
    switch survey.lifecycle(at: now) {
    case .draft: .launch
    case .running: .stop
    case .complete: .resume
    }
  return [lifecycle, .archive]
}

public func parseSurveyQuestions(_ raw: JSONValue?) -> [SurveyQuestionDef] {
  guard let entries = raw?.arrayValue else { return [] }
  let allowed = Set(SurveyQuestionType.allCases.map(\.rawValue))
  return entries.enumerated().compactMap { index, entry in
    guard let typeRaw = entry["type"]?.stringValue, allowed.contains(typeRaw),
      let type = SurveyQuestionType(rawValue: typeRaw)
    else { return nil }
    let choices =
      entry["choices"]?.arrayValue?.compactMap(\.stringValue) ?? []
    let questionID = nonEmpty(entry["id"]?.stringValue)
    return SurveyQuestionDef(
      stableID: questionID ?? "index-\(index)",
      questionID: questionID,
      index: index,
      type: type,
      text: entry["question"]?.stringValue ?? "",
      description: nonEmpty(entry["description"]?.stringValue),
      choices: choices,
      hasOpenChoice: entry["hasOpenChoice"]?.boolValue == true,
      scale: entry["scale"]?.intValue,
      lowerBoundLabel: nonEmpty(entry["lowerBoundLabel"]?.stringValue),
      upperBoundLabel: nonEmpty(entry["upperBoundLabel"]?.stringValue)
    )
  }
}

extension SurveyQuestionType: CaseIterable {}

public func summarizeSurveyStats(_ raw: JSONValue) -> SurveyFunnel {
  let byEvent = raw["stats"]?.objectValue ?? [:]
  let rates = raw["rates"]
  return SurveyFunnel(
    shown: numberAt(byEvent["survey shown"], key: "total_count"),
    uniqueShown: numberAt(byEvent["survey shown"], key: "unique_persons"),
    sent: numberAt(byEvent["survey sent"], key: "total_count"),
    uniqueSent: numberAt(byEvent["survey sent"], key: "unique_persons"),
    dismissed: numberAt(byEvent["survey dismissed"], key: "total_count"),
    uniqueDismissed: numberAt(byEvent["survey dismissed"], key: "unique_persons"),
    responseRate: doubleAt(rates, key: "response_rate"),
    uniqueResponseRate: doubleAt(rates, key: "unique_users_response_rate"),
    dismissalRate: doubleAt(rates, key: "dismissal_rate")
  )
}

public func buildSurveyQuestionResults(
  questions: [SurveyQuestionDef],
  stats: JSONValue?,
  responses: [SurveyResponseRow],
  responsesComplete: Bool
) -> [SurveyQuestionResult] {
  let perQuestion = parsePerQuestionStats(stats?["per_question_stats"])
  return questions.map { question in
    let stat = findStat(perQuestion, question: question)
    switch question.type {
    case .rating:
      return ratingResult(question: question, stat: stat)
    case .singleChoice:
      return singleChoiceResult(question: question, stat: stat)
    case .multipleChoice:
      return multipleChoiceResult(
        question: question,
        responses: responses,
        responsesComplete: responsesComplete
      )
    case .open:
      return openResult(
        question: question,
        stat: stat,
        responses: responses,
        responsesComplete: responsesComplete
      )
    case .link:
      return .link(question: question, total: stat?.responseCount ?? 0)
    }
  }
}

// MARK: - Internals

private struct PerQuestionStat {
  let questionID: String?
  let questionIndex: Int?
  let responseCount: Int
  let distribution: [String: Int]
  let average: Double?
}

private let otherBucket = "<other>"

private func nonEmpty(_ value: String?) -> String? {
  guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    return nil
  }
  return value
}

private func numberAt(_ record: JSONValue?, key: String) -> Int {
  Int(doubleAt(record, key: key))
}

private func doubleAt(_ record: JSONValue?, key: String) -> Double {
  guard let record else { return 0 }
  if let n = record[key]?.numberValue, n.isFinite { return n }
  if let n = record.numberValue, n.isFinite { return n }
  return 0
}

private func parsePerQuestionStats(_ raw: JSONValue?) -> [PerQuestionStat] {
  guard let entries = raw?.arrayValue else { return [] }
  return entries.compactMap { entry in
    guard entry.objectValue != nil else { return nil }
    var distribution: [String: Int] = [:]
    if let dist = entry["distribution"]?.objectValue {
      for (key, value) in dist {
        if let n = value.numberValue, n.isFinite {
          distribution[key] = Int(n)
        }
      }
    }
    let averageNumber = entry["average"]?.numberValue
    let average =
      averageNumber.flatMap { $0.isFinite ? $0 : nil }
    return PerQuestionStat(
      questionID: nonEmpty(entry["question_id"]?.stringValue),
      questionIndex: entry["question_index"]?.intValue,
      responseCount: numberAt(entry, key: "response_count"),
      distribution: distribution,
      average: average
    )
  }
}

private func findStat(
  _ stats: [PerQuestionStat],
  question: SurveyQuestionDef
) -> PerQuestionStat? {
  if let questionID = question.questionID,
    let byID = stats.first(where: { $0.questionID == questionID })
  {
    return byID
  }
  return stats.first(where: { $0.questionIndex == question.index })
}

private func answersFor(
  _ responses: [SurveyResponseRow],
  question: SurveyQuestionDef
) -> [(row: SurveyResponseRow, answer: JSONValue?)] {
  responses.compactMap { row in
    let match = row.answers.first { answer in
      if let questionID = question.questionID {
        return answer.questionID == questionID
      }
      return answer.questionIndex == question.index
    }
    return match.map { (row, $0.answer) }
  }
}

private func share(_ count: Int, total: Int) -> Double {
  total > 0 ? Double(count) / Double(total) : 0
}

private func ratingValues(scale: Int) -> [Int] {
  let start = scale == 10 ? 0 : 1
  return Array(start...scale)
}

private func ratingResult(question: SurveyQuestionDef, stat: PerQuestionStat?) -> SurveyQuestionResult {
  let distribution = stat?.distribution ?? [:]
  let scale = question.scale ?? 5
  let total = distribution.values.reduce(0, +)
  let bars = ratingValues(scale: scale).map { value in
    let count = distribution[String(value)] ?? 0
    return ResultBar(label: String(value), count: count, share: share(count, total: total))
  }

  var nps: NpsBreakdown?
  if scale == 10, total > 0 {
    var promoters = 0
    var passives = 0
    var detractors = 0
    for (value, count) in distribution {
      let score = Int(value) ?? -1
      if score >= 9 {
        promoters += count
      } else if score >= 7 {
        passives += count
      } else if score >= 0 {
        detractors += count
      }
    }
    nps = NpsBreakdown(
      score: Int(round(Double(promoters - detractors) / Double(total) * 100)),
      promoters: promoters,
      passives: passives,
      detractors: detractors
    )
  }

  return .rating(
    question: question,
    total: total,
    bars: bars,
    average: stat?.average,
    nps: nps
  )
}

private func singleChoiceResult(
  question: SurveyQuestionDef,
  stat: PerQuestionStat?
) -> SurveyQuestionResult {
  var counts = Dictionary(uniqueKeysWithValues: question.choices.map { ($0, 0) })
  for (label, count) in stat?.distribution ?? [:] {
    let key: String
    if label == otherBucket {
      key =
        question.hasOpenChoice && !question.choices.isEmpty
        ? question.choices[question.choices.count - 1]
        : "Other"
    } else {
      key = label
    }
    counts[key, default: 0] += count
  }
  let total = counts.values.reduce(0, +)
  return .choice(
    question: question,
    total: total,
    bars: sortBars(counts, total: total),
    sampled: false
  )
}

private func multipleChoiceResult(
  question: SurveyQuestionDef,
  responses: [SurveyResponseRow],
  responsesComplete: Bool
) -> SurveyQuestionResult {
  var counts = Dictionary(uniqueKeysWithValues: question.choices.map { ($0, 0) })
  let openLabel =
    question.hasOpenChoice && !question.choices.isEmpty
    ? question.choices[question.choices.count - 1]
    : "Other"
  var total = 0
  for (_, answer) in answersFor(responses, question: question) {
    let picks: [String]
    if let array = answer?.arrayValue {
      picks = array.compactMap(\.stringValue).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    } else if let string = answer?.stringValue, !string.trimmingCharacters(in: .whitespaces).isEmpty {
      picks = [string]
    } else {
      picks = []
    }
    guard !picks.isEmpty else { continue }
    total += 1
    for pick in Set(picks) {
      let key = counts.keys.contains(pick) ? pick : openLabel
      counts[key, default: 0] += 1
    }
  }
  return .choice(
    question: question,
    total: total,
    bars: sortBars(counts, total: total),
    sampled: !responsesComplete
  )
}

private func sortBars(_ counts: [String: Int], total: Int) -> [ResultBar] {
  counts.map { ResultBar(label: $0.key, count: $0.value, share: share($0.value, total: total)) }
    .sorted { $0.count > $1.count }
}

private func openResult(
  question: SurveyQuestionDef,
  stat: PerQuestionStat?,
  responses: [SurveyResponseRow],
  responsesComplete: Bool
) -> SurveyQuestionResult {
  let answers = answersFor(responses, question: question).compactMap { row, answer -> OpenTextAnswer? in
    guard let text = answer?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
    else { return nil }
    return OpenTextAnswer(
      responseUUID: row.uuid,
      distinctID: row.distinctID,
      submittedAt: row.submittedAt,
      text: text
    )
  }
  return .open(
    question: question,
    total: stat?.responseCount ?? answers.count,
    answers: answers,
    sampled: !responsesComplete
  )
}
