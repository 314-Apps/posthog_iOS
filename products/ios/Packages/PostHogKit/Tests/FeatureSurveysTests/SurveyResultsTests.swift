import Foundation
import PostHogAPI
import PostHogFoundation
import Testing

@testable import FeatureSurveys

private let past = "2026-05-01T00:00:00Z"
private let now = Date(timeIntervalSince1970: 1_780_315_200)  // 2026-06-01T12:00:00Z

private func statsJSON(_ perQuestion: String) -> JSONValue {
  let raw = """
    {"survey_id":"s1","start_date":"\(past)","end_date":null,"stats":{},"rates":{},"per_question_stats":\(perQuestion)}
    """
  return try! JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
}

private func row(
  uuid: String,
  answers: [(id: String, type: String, answer: JSONValue)]
) -> SurveyResponseRow {
  SurveyResponseRow(
    uuid: uuid,
    distinctID: "user-\(uuid)",
    sessionID: nil,
    submittedAt: past,
    answers: answers.enumerated().map { index, answer in
      SurveyResponseAnswer(
        questionID: answer.id,
        questionIndex: index,
        questionText: "",
        questionType: answer.type,
        answer: answer.answer
      )
    }
  )
}

@Suite struct SurveyResultsTests {
  @Test func surveyActionsMatchLifecycle() {
    let draft = Survey(
      id: "1", name: "A", description: nil, type: nil,
      startDate: nil, endDate: nil, archived: false, questionsRaw: nil
    )
    #expect(surveyActions(for: draft, now: now) == [.launch, .archive])

    let running = Survey(
      id: "1", name: "A", description: nil, type: nil,
      startDate: Date(timeIntervalSince1970: 1_777_622_400), endDate: nil,
      archived: false, questionsRaw: nil
    )
    #expect(surveyActions(for: running, now: now) == [.stop, .archive])

    let complete = Survey(
      id: "1", name: "A", description: nil, type: nil,
      startDate: Date(timeIntervalSince1970: 1_777_622_400),
      endDate: Date(timeIntervalSince1970: 1_777_622_400),
      archived: false, questionsRaw: nil
    )
    #expect(surveyActions(for: complete, now: now) == [.resume, .archive])

    let archived = Survey(
      id: "1", name: "A", description: nil, type: nil,
      startDate: nil, endDate: nil, archived: true, questionsRaw: nil
    )
    #expect(surveyActions(for: archived, now: now) == [.unarchive])
  }

  @Test func summarizeReadsFunnelCountsAndRates() {
    let raw: JSONValue = [
      "stats": [
        "survey shown": ["total_count": 200, "unique_persons": 150],
        "survey sent": ["total_count": 40, "unique_persons": 30],
      ],
      "rates": ["response_rate": 20, "unique_users_response_rate": 20],
    ]
    let funnel = summarizeSurveyStats(raw)
    #expect(funnel.shown == 200)
    #expect(funnel.uniqueShown == 150)
    #expect(funnel.sent == 40)
    #expect(funnel.dismissed == 0)
    #expect(funnel.responseRate == 20)
  }

  @Test func ratingFillsScaleAndScoresNPS() {
    let questions = parseSurveyQuestions([
      ["id": "q1", "type": "rating", "question": "Recommend us?", "scale": 10],
    ])
    let results = buildSurveyQuestionResults(
      questions: questions,
      stats: statsJSON(
        #"[{"question_id":"q1","distribution":{"10":5,"9":1,"8":2,"3":2},"average":7.9}]"#
      ),
      responses: [],
      responsesComplete: true
    )
    guard case .rating(_, let total, let bars, _, let nps) = results[0] else {
      Issue.record("expected rating")
      return
    }
    #expect(bars.map(\.label) == (0...10).map(String.init))
    #expect(total == 10)
    #expect(nps == NpsBreakdown(score: 40, promoters: 6, passives: 2, detractors: 2))
  }

  @Test func smallerRatingScaleStartsAtOneWithoutNPS() {
    let questions = parseSurveyQuestions([
      ["id": "q1", "type": "rating", "question": "Rate", "scale": 5],
    ])
    let results = buildSurveyQuestionResults(
      questions: questions,
      stats: statsJSON(#"[{"question_id":"q1","distribution":{"5":1}}]"#),
      responses: [],
      responsesComplete: true
    )
    guard case .rating(_, _, let bars, _, let nps) = results[0] else {
      Issue.record("expected rating")
      return
    }
    #expect(bars.map(\.label) == ["1", "2", "3", "4", "5"])
    #expect(nps == nil)
  }

  @Test func singleChoiceCreditsRedactedOtherBucket() {
    let questions = parseSurveyQuestions([
      [
        "id": "q1",
        "type": "single_choice",
        "question": "Pick",
        "choices": ["Red", "Blue", "Other"],
        "hasOpenChoice": true,
      ],
    ])
    let results = buildSurveyQuestionResults(
      questions: questions,
      stats: statsJSON(
        #"[{"question_id":"q1","distribution":{"Red":3,"<other>":2}}]"#
      ),
      responses: [],
      responsesComplete: true
    )
    guard case .choice(_, _, let bars, _) = results[0] else {
      Issue.record("expected choice")
      return
    }
    #expect(bars == [
      ResultBar(label: "Red", count: 3, share: 0.6),
      ResultBar(label: "Other", count: 2, share: 0.4),
      ResultBar(label: "Blue", count: 0, share: 0),
    ])
  }

  @Test func multipleChoiceCountsFromResponses() {
    let questions = parseSurveyQuestions([
      [
        "id": "q1",
        "type": "multiple_choice",
        "question": "Which?",
        "choices": ["A", "B"],
      ],
    ])
    let results = buildSurveyQuestionResults(
      questions: questions,
      stats: statsJSON("[]"),
      responses: [
        row(uuid: "1", answers: [("q1", "multiple_choice", ["A", "B"])]),
        row(uuid: "2", answers: [("q1", "multiple_choice", ["A"])]),
      ],
      responsesComplete: false
    )
    guard case .choice(_, let total, let bars, let sampled) = results[0] else {
      Issue.record("expected choice")
      return
    }
    #expect(total == 2)
    #expect(sampled)
    #expect(bars == [
      ResultBar(label: "A", count: 2, share: 1),
      ResultBar(label: "B", count: 1, share: 0.5),
    ])
  }

  @Test func openTextUsesServerTotal() {
    let questions = parseSurveyQuestions([
      ["id": "q1", "type": "open", "question": "Thoughts?"],
    ])
    let results = buildSurveyQuestionResults(
      questions: questions,
      stats: statsJSON(#"[{"question_id":"q1","response_count":42}]"#),
      responses: [
        row(uuid: "1", answers: [("q1", "open", "  Love it ")]),
        row(uuid: "2", answers: [("q1", "open", "")]),
      ],
      responsesComplete: false
    )
    guard case .open(_, let total, let answers, _) = results[0] else {
      Issue.record("expected open")
      return
    }
    #expect(total == 42)
    #expect(answers.map(\.text) == ["Love it"])
  }
}
