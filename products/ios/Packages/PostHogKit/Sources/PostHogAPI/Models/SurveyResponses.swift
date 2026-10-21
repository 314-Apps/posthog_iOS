import Foundation
import PostHogFoundation

/// One answer on a survey response row.
public struct SurveyResponseAnswer: Codable, Sendable, Equatable {
  public let questionID: String?
  public let questionIndex: Int?
  public let questionText: String?
  public let questionType: String?
  public let answer: JSONValue?

  enum CodingKeys: String, CodingKey {
    case questionID = "question_id"
    case questionIndex = "question_index"
    case questionText = "question_text"
    case questionType = "question_type"
    case answer
  }

  public init(
    questionID: String?,
    questionIndex: Int?,
    questionText: String?,
    questionType: String?,
    answer: JSONValue?
  ) {
    self.questionID = questionID
    self.questionIndex = questionIndex
    self.questionText = questionText
    self.questionType = questionType
    self.answer = answer
  }
}

/// One submitted survey response, newest-first from the list endpoint.
public struct SurveyResponseRow: Codable, Sendable, Equatable, Identifiable {
  public var id: String { uuid }
  public let uuid: String
  public let distinctID: String
  public let sessionID: String?
  public let submittedAt: String
  public let answers: [SurveyResponseAnswer]

  enum CodingKeys: String, CodingKey {
    case uuid
    case distinctID = "distinct_id"
    case sessionID = "session_id"
    case submittedAt = "submitted_at"
    case answers
  }

  public init(
    uuid: String,
    distinctID: String,
    sessionID: String?,
    submittedAt: String,
    answers: [SurveyResponseAnswer]
  ) {
    self.uuid = uuid
    self.distinctID = distinctID
    self.sessionID = sessionID
    self.submittedAt = submittedAt
    self.answers = answers
  }
}

/// Page of individual responses from `surveys/{id}/responses/`.
public struct SurveyResponsesPage: Codable, Sendable, Equatable {
  public let results: [SurveyResponseRow]
  public let hasMore: Bool
  public let limit: Int
  public let offset: Int

  enum CodingKeys: String, CodingKey {
    case results
    case hasMore = "has_more"
    case limit
    case offset
  }

  public init(results: [SurveyResponseRow], hasMore: Bool, limit: Int, offset: Int) {
    self.results = results
    self.hasMore = hasMore
    self.limit = limit
    self.offset = offset
  }
}

extension APIClient {
  /// Funnel counts, rates, and per-question distributions.
  /// Pass `since` (ISO-8601) for a date floor; omit for all-time.
  public func surveyStats(
    projectID: Int,
    surveyID: String,
    since: String? = nil
  ) async throws -> JSONValue {
    var query: [URLQueryItem] = [
      URLQueryItem(name: "include_per_question_stats", value: "true")
    ]
    if let since {
      query.append(URLQueryItem(name: "date_from", value: since))
    }
    return try await send(
      .get("/api/projects/\(projectID)/surveys/\(surveyID)/stats/", query: query)
    )
  }

  /// Individual responses, newest first.
  public func listSurveyResponses(
    projectID: Int,
    surveyID: String,
    since: String? = nil,
    limit: Int = 100,
    offset: Int = 0
  ) async throws -> SurveyResponsesPage {
    var query: [URLQueryItem] = [
      URLQueryItem(name: "limit", value: String(limit)),
      URLQueryItem(name: "offset", value: String(offset)),
    ]
    if let since {
      query.append(URLQueryItem(name: "since", value: since))
    }
    return try await send(
      .get("/api/projects/\(projectID)/surveys/\(surveyID)/responses/", query: query)
    )
  }

  /// PATCHes only the provided keys. Use `clearEndDate` to resume a stopped survey.
  public func updateSurvey(
    projectID: Int,
    surveyID: String,
    archived: Bool? = nil,
    clearEndDate: Bool = false,
    startDate: Date? = nil,
    endDate: Date? = nil
  ) async throws -> Survey {
    var payload: [String: JSONValue] = [:]
    if let archived {
      payload["archived"] = .bool(archived)
    }
    if clearEndDate {
      payload["end_date"] = .null
    }
    if let startDate {
      payload["start_date"] = .string(Self.iso8601String(startDate))
    }
    if let endDate {
      payload["end_date"] = .string(Self.iso8601String(endDate))
    }
    let body = try Self.makeEncoder().encode(payload)
    return try await send(.patch("/api/projects/\(projectID)/surveys/\(surveyID)/", body: body))
  }

  private static func iso8601String(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }
}
