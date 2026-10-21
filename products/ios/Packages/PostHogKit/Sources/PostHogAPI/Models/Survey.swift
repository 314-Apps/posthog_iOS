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

  /// Matches the backend status filter: an end date in the future still counts as running.
  public func lifecycle(at now: Date = .now) -> Lifecycle {
    guard startDate != nil else { return .draft }
    if let endDate, endDate <= now { return .complete }
    return .running
  }

  public var lifecycle: Lifecycle { lifecycle(at: .now) }

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
    try await updateSurvey(
      projectID: projectID,
      surveyID: surveyID,
      startDate: startDate,
      endDate: endDate
    )
  }
}
