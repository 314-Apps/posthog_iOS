import Foundation
import PostHogFoundation

/// A survey. The API has no status field, so lifecycle derives from the dates:
/// no start is a draft, started without an end is running, ended is complete.
/// `questions` stays raw because editing happens on the web.
public struct Survey: Codable, Sendable, Equatable, Identifiable {
  public enum Lifecycle: Sendable, Equatable {
    case draft
    case running
    case complete
  }

  public let id: String
  public let name: String
  public let description: String?
  public let type: String?
  public let startDate: Date?
  public let endDate: Date?
  public let archived: Bool
  public let questionsRaw: JSONValue?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case description
    case type
    case startDate = "start_date"
    case endDate = "end_date"
    case archived
    case questionsRaw = "questions"
  }

  public init(
    id: String,
    name: String,
    description: String?,
    type: String?,
    startDate: Date?,
    endDate: Date?,
    archived: Bool,
    questionsRaw: JSONValue?
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.type = type
    self.startDate = startDate
    self.endDate = endDate
    self.archived = archived
    self.questionsRaw = questionsRaw
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.name = try container.decode(String.self, forKey: .name)
    self.description = try container.decodeIfPresent(String.self, forKey: .description)
    self.type = try container.decodeIfPresent(String.self, forKey: .type)
    self.startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
    self.endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
    self.archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    self.questionsRaw = try container.decodeIfPresent(JSONValue.self, forKey: .questionsRaw)
  }

  public var lifecycle: Lifecycle {
    if endDate != nil { return .complete }
    if startDate != nil { return .running }
    return .draft
  }

  /// One line per question, falling back to "Question N" when an entry has no
  /// usable `question` string. Non-array `questions` payloads yield no rows.
  public var questionSummaries: [String] {
    guard let entries = questionsRaw?.arrayValue else { return [] }
    return entries.enumerated().map { index, entry in
      if let question = entry["question"]?.stringValue, !question.isEmpty {
        return question
      }
      return "Question \(index + 1)"
    }
  }
}

extension APIClient {
  public func surveys(projectID: Int, limit: Int = 100) async throws -> Paginated<Survey> {
    try await send(
      .get(
        "/api/projects/\(projectID)/surveys/",
        query: [URLQueryItem(name: "limit", value: String(limit))]
      ))
  }

  public func survey(projectID: Int, surveyID: String) async throws -> Survey {
    try await send(.get("/api/projects/\(projectID)/surveys/\(surveyID)/"))
  }

  /// PATCHes only the provided keys so the other date stays untouched:
  /// launching sends `start_date`, stopping sends `end_date`.
  public func updateSurveyDates(
    projectID: Int,
    surveyID: String,
    startDate: Date? = nil,
    endDate: Date? = nil
  ) async throws -> Survey {
    var payload: [String: Date] = [:]
    if let startDate {
      payload["start_date"] = startDate
    }
    if let endDate {
      payload["end_date"] = endDate
    }
    let body = try Self.makeEncoder().encode(payload)
    return try await send(.patch("/api/projects/\(projectID)/surveys/\(surveyID)/", body: body))
  }

  /// Raw stats payload. The shape varies by server version, so callers parse defensively.
  public func surveyStats(projectID: Int, surveyID: String) async throws -> JSONValue {
    try await send(.get("/api/projects/\(projectID)/surveys/\(surveyID)/stats/"))
  }
}
