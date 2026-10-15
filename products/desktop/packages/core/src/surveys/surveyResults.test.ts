import type {
  SurveyResponseRow,
  SurveyStatsResponse,
} from "@posthog/api-client/types";
import { describe, expect, it } from "vitest";
import {
  buildSurveyQuestionResults,
  parseSurveyQuestions,
  type SurveyQuestionResult,
  summarizeSurveyStats,
  surveyActions,
  surveyStatus,
} from "./surveyResults";

const NOW = Date.parse("2026-06-01T12:00:00Z");
const PAST = "2026-05-01T00:00:00Z";
const FUTURE = "2026-07-01T00:00:00Z";

function stats(perQuestion: unknown[]): SurveyStatsResponse {
  return {
    survey_id: "s1",
    start_date: PAST,
    end_date: null,
    stats: {},
    rates: {},
    per_question_stats: perQuestion,
  };
}

function row(
  uuid: string,
  answers: Array<{ id: string; type: string; answer: string | string[] }>,
): SurveyResponseRow {
  return {
    uuid,
    distinct_id: `user-${uuid}`,
    session_id: null,
    submitted_at: PAST,
    answers: answers.map((a, i) => ({
      question_id: a.id,
      question_index: i,
      question_text: "",
      question_type: a.type,
      answer: a.answer,
    })),
    extra: {},
  };
}

function only<K extends SurveyQuestionResult["kind"]>(
  results: SurveyQuestionResult[],
  kind: K,
): Extract<SurveyQuestionResult, { kind: K }> {
  expect(results).toHaveLength(1);
  expect(results[0].kind).toBe(kind);
  return results[0] as Extract<SurveyQuestionResult, { kind: K }>;
}

describe("surveyStatus and surveyActions", () => {
  it.each([
    [{ start_date: null, end_date: null }, "draft", ["launch", "archive"]],
    [{ start_date: PAST, end_date: null }, "running", ["stop", "archive"]],
    [{ start_date: PAST, end_date: FUTURE }, "running", ["stop", "archive"]],
    [{ start_date: PAST, end_date: PAST }, "complete", ["resume", "archive"]],
  ])("treats %o as %s", (dates, status, actions) => {
    expect(surveyStatus(dates, NOW)).toBe(status);
    expect(surveyActions({ ...dates, archived: false }, NOW)).toEqual(actions);
  });

  it("only offers unarchive for an archived survey", () => {
    expect(
      surveyActions({ start_date: null, end_date: null, archived: true }, NOW),
    ).toEqual(["unarchive"]);
  });
});

describe("summarizeSurveyStats", () => {
  it("reads funnel counts and rates and defaults missing events to zero", () => {
    const funnel = summarizeSurveyStats({
      ...stats([]),
      stats: {
        "survey shown": { total_count: 200, unique_persons: 150 },
        "survey sent": { total_count: 40, unique_persons: 30 },
      },
      rates: { response_rate: 20, unique_users_response_rate: 20 },
    });
    expect(funnel).toMatchObject({
      shown: 200,
      uniqueShown: 150,
      sent: 40,
      dismissed: 0,
      responseRate: 20,
    });
  });
});

describe("buildSurveyQuestionResults", () => {
  it("fills every rating value and scores NPS on a 0-10 scale", () => {
    const questions = parseSurveyQuestions([
      { id: "q1", type: "rating", question: "Recommend us?", scale: 10 },
    ]);
    const result = only(
      buildSurveyQuestionResults({
        questions,
        stats: stats([
          {
            question_id: "q1",
            distribution: { "10": 5, "9": 1, "8": 2, "3": 2 },
            average: 7.9,
          },
        ]),
        responses: [],
        responsesComplete: true,
      }),
      "rating",
    );
    expect(result.bars.map((b) => b.label)).toEqual(
      Array.from({ length: 11 }, (_, i) => String(i)),
    );
    expect(result.total).toBe(10);
    expect(result.nps).toEqual({
      score: 40,
      promoters: 6,
      passives: 2,
      detractors: 2,
    });
  });

  it("starts smaller rating scales at 1 and skips NPS", () => {
    const [result] = buildSurveyQuestionResults({
      questions: parseSurveyQuestions([
        { id: "q1", type: "rating", question: "Rate", scale: 5 },
      ]),
      stats: stats([{ question_id: "q1", distribution: { "5": 1 } }]),
      responses: [],
      responsesComplete: true,
    });
    expect(result.kind === "rating" && result.bars.map((b) => b.label)).toEqual(
      ["1", "2", "3", "4", "5"],
    );
    expect(result.kind === "rating" && result.nps).toBeNull();
  });

  it("keeps unpicked choices and credits redacted free text to the open choice", () => {
    const result = only(
      buildSurveyQuestionResults({
        questions: parseSurveyQuestions([
          {
            id: "q1",
            type: "single_choice",
            question: "Pick",
            choices: ["Red", "Blue", "Other"],
            hasOpenChoice: true,
          },
        ]),
        stats: stats([
          { question_id: "q1", distribution: { Red: 3, "<other>": 2 } },
        ]),
        responses: [],
        responsesComplete: true,
      }),
      "choice",
    );
    expect(result.bars).toEqual([
      { label: "Red", count: 3, share: 0.6 },
      { label: "Other", count: 2, share: 0.4 },
      { label: "Blue", count: 0, share: 0 },
    ]);
  });

  it("counts multiple choice from responses, as a share of respondents", () => {
    const result = only(
      buildSurveyQuestionResults({
        questions: parseSurveyQuestions([
          {
            id: "q1",
            type: "multiple_choice",
            question: "Which?",
            choices: ["A", "B"],
          },
        ]),
        stats: stats([]),
        responses: [
          row("1", [{ id: "q1", type: "multiple_choice", answer: ["A", "B"] }]),
          row("2", [{ id: "q1", type: "multiple_choice", answer: ["A"] }]),
        ],
        responsesComplete: false,
      }),
      "choice",
    );
    expect(result.total).toBe(2);
    expect(result.sampled).toBe(true);
    expect(result.bars).toEqual([
      { label: "A", count: 2, share: 1 },
      { label: "B", count: 1, share: 0.5 },
    ]);
  });

  it("lists open text answers and takes the total from the server count", () => {
    const result = only(
      buildSurveyQuestionResults({
        questions: parseSurveyQuestions([
          { id: "q1", type: "open", question: "Thoughts?" },
        ]),
        stats: stats([{ question_id: "q1", response_count: 42 }]),
        responses: [
          row("1", [{ id: "q1", type: "open", answer: "  Love it " }]),
          row("2", [{ id: "q1", type: "open", answer: "" }]),
        ],
        responsesComplete: false,
      }),
      "open",
    );
    expect(result.total).toBe(42);
    expect(result.answers.map((a) => a.text)).toEqual(["Love it"]);
  });
});
