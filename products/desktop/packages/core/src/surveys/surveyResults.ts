import type {
  Survey,
  SurveyDateRange,
  SurveyResponseRow,
  SurveyStatsResponse,
} from "@posthog/api-client/types";

export type SurveyStatus = "draft" | "running" | "complete";

export type SurveyAction =
  | "launch"
  | "stop"
  | "resume"
  | "archive"
  | "unarchive";

type SurveyDates = Pick<Survey, "start_date" | "end_date">;

/** Matches the backend `status` filter: an end date in the future still counts as running. */
export function surveyStatus(
  survey: SurveyDates,
  now = Date.now(),
): SurveyStatus {
  if (!survey.start_date) return "draft";
  if (survey.end_date && Date.parse(survey.end_date) <= now) return "complete";
  return "running";
}

/** The lifecycle actions the web app offers for a survey in its current state. */
export function surveyActions(
  survey: SurveyDates & Pick<Survey, "archived">,
  now = Date.now(),
): SurveyAction[] {
  // The backend refuses to launch an archived survey, so unarchiving comes first.
  if (survey.archived) return ["unarchive"];
  const status = surveyStatus(survey, now);
  const lifecycle: SurveyAction =
    status === "draft" ? "launch" : status === "running" ? "stop" : "resume";
  return [lifecycle, "archive"];
}

export type SurveyDatePreset = "all" | "7d" | "30d" | "90d";

const PRESET_DAYS: Record<Exclude<SurveyDatePreset, "all">, number> = {
  "7d": 7,
  "30d": 30,
  "90d": 90,
};

export function surveyDateRange(
  preset: SurveyDatePreset,
  now = Date.now(),
): SurveyDateRange {
  if (preset === "all") return {};
  const since = new Date(now - PRESET_DAYS[preset] * 24 * 60 * 60 * 1000);
  return { since: since.toISOString() };
}

export type SurveyQuestionType =
  | "open"
  | "link"
  | "rating"
  | "single_choice"
  | "multiple_choice";

export interface SurveyQuestionDef {
  id: string | null;
  index: number;
  type: SurveyQuestionType;
  text: string;
  description: string | null;
  choices: string[];
  hasOpenChoice: boolean;
  scale: number | null;
  lowerBoundLabel: string | null;
  upperBoundLabel: string | null;
}

const QUESTION_TYPES = new Set<string>([
  "open",
  "link",
  "rating",
  "single_choice",
  "multiple_choice",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

export function parseSurveyQuestions(questions: unknown): SurveyQuestionDef[] {
  if (!Array.isArray(questions)) return [];
  return questions.flatMap((raw, index) => {
    if (!isRecord(raw) || typeof raw.type !== "string") return [];
    if (!QUESTION_TYPES.has(raw.type)) return [];
    const choices = Array.isArray(raw.choices)
      ? raw.choices.filter((c): c is string => typeof c === "string")
      : [];
    return [
      {
        id: stringOrNull(raw.id),
        index,
        type: raw.type as SurveyQuestionType,
        text: typeof raw.question === "string" ? raw.question : "",
        description: stringOrNull(raw.description),
        choices,
        hasOpenChoice: raw.hasOpenChoice === true,
        scale: typeof raw.scale === "number" ? raw.scale : null,
        lowerBoundLabel: stringOrNull(raw.lowerBoundLabel),
        upperBoundLabel: stringOrNull(raw.upperBoundLabel),
      },
    ];
  });
}

export interface SurveyFunnel {
  shown: number;
  uniqueShown: number;
  sent: number;
  uniqueSent: number;
  dismissed: number;
  uniqueDismissed: number;
  /** Percentages from 0 to 100, as the backend reports them. */
  responseRate: number;
  uniqueResponseRate: number;
  dismissalRate: number;
}

function numberAt(record: unknown, key: string): number {
  if (!isRecord(record)) return 0;
  const value = Number(record[key]);
  return Number.isFinite(value) ? value : 0;
}

export function summarizeSurveyStats(stats: SurveyStatsResponse): SurveyFunnel {
  const byEvent = isRecord(stats.stats) ? stats.stats : {};
  const shown = byEvent["survey shown"];
  const sent = byEvent["survey sent"];
  const dismissed = byEvent["survey dismissed"];
  return {
    shown: numberAt(shown, "total_count"),
    uniqueShown: numberAt(shown, "unique_persons"),
    sent: numberAt(sent, "total_count"),
    uniqueSent: numberAt(sent, "unique_persons"),
    dismissed: numberAt(dismissed, "total_count"),
    uniqueDismissed: numberAt(dismissed, "unique_persons"),
    responseRate: numberAt(stats.rates, "response_rate"),
    uniqueResponseRate: numberAt(stats.rates, "unique_users_response_rate"),
    dismissalRate: numberAt(stats.rates, "dismissal_rate"),
  };
}

export interface ResultBar {
  label: string;
  count: number;
  /** Fraction from 0 to 1 of the question's respondents. */
  share: number;
}

export interface NpsBreakdown {
  /** From -100 to 100. */
  score: number;
  promoters: number;
  passives: number;
  detractors: number;
}

export interface OpenTextAnswer {
  responseUuid: string;
  distinctId: string;
  submittedAt: string;
  text: string;
}

interface ResultBase {
  question: SurveyQuestionDef;
  /** Respondents who answered this question. */
  total: number;
}

export type SurveyQuestionResult =
  | (ResultBase & {
      kind: "rating";
      bars: ResultBar[];
      average: number | null;
      nps: NpsBreakdown | null;
    })
  | (ResultBase & {
      kind: "choice";
      bars: ResultBar[];
      /** True when counted from the loaded responses rather than the full range. */
      sampled: boolean;
    })
  | (ResultBase & {
      kind: "open";
      answers: OpenTextAnswer[];
      sampled: boolean;
    })
  | (ResultBase & { kind: "link" });

interface PerQuestionStat {
  questionId: string | null;
  questionIndex: number | null;
  responseCount: number;
  distribution: Record<string, number>;
  average: number | null;
}

const OTHER_BUCKET = "<other>";

function parsePerQuestionStats(raw: unknown): PerQuestionStat[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(isRecord).map((entry) => {
    const distribution: Record<string, number> = {};
    if (isRecord(entry.distribution)) {
      for (const [key, value] of Object.entries(entry.distribution)) {
        const n = Number(value);
        if (Number.isFinite(n)) distribution[key] = n;
      }
    }
    const average = Number(entry.average);
    return {
      questionId: stringOrNull(entry.question_id),
      questionIndex:
        typeof entry.question_index === "number" ? entry.question_index : null,
      responseCount: numberAt(entry, "response_count"),
      distribution,
      average:
        entry.average === null || !Number.isFinite(average) ? null : average,
    };
  });
}

function findStat(
  stats: PerQuestionStat[],
  question: SurveyQuestionDef,
): PerQuestionStat | undefined {
  if (question.id) {
    const byId = stats.find((s) => s.questionId === question.id);
    if (byId) return byId;
  }
  return stats.find((s) => s.questionIndex === question.index);
}

function answersFor(
  responses: SurveyResponseRow[],
  question: SurveyQuestionDef,
): Array<{ row: SurveyResponseRow; answer: unknown }> {
  return responses.flatMap((row) => {
    const match = row.answers.find((a) =>
      question.id
        ? a.question_id === question.id
        : a.question_index === question.index,
    );
    return match ? [{ row, answer: match.answer }] : [];
  });
}

function share(count: number, total: number): number {
  return total > 0 ? count / total : 0;
}

/** Rating scales of 10 run 0–10 (NPS); the smaller scales run 1–N. */
function ratingValues(scale: number): number[] {
  const start = scale === 10 ? 0 : 1;
  return Array.from({ length: scale - start + 1 }, (_, i) => start + i);
}

function ratingResult(
  question: SurveyQuestionDef,
  stat: PerQuestionStat | undefined,
): SurveyQuestionResult {
  const distribution = stat?.distribution ?? {};
  const scale = question.scale ?? 5;
  const total = Object.values(distribution).reduce((sum, n) => sum + n, 0);
  const bars = ratingValues(scale).map((value) => {
    const count = distribution[String(value)] ?? 0;
    return { label: String(value), count, share: share(count, total) };
  });

  let nps: NpsBreakdown | null = null;
  if (scale === 10 && total > 0) {
    let promoters = 0;
    let passives = 0;
    let detractors = 0;
    for (const [value, count] of Object.entries(distribution)) {
      const score = Number(value);
      if (score >= 9) promoters += count;
      else if (score >= 7) passives += count;
      else if (score >= 0) detractors += count;
    }
    nps = {
      score: Math.round(((promoters - detractors) / total) * 100),
      promoters,
      passives,
      detractors,
    };
  }

  return {
    kind: "rating",
    question,
    total,
    bars,
    average: stat?.average ?? null,
    nps,
  };
}

function singleChoiceResult(
  question: SurveyQuestionDef,
  stat: PerQuestionStat | undefined,
): SurveyQuestionResult {
  const counts = new Map<string, number>(
    question.choices.map((choice) => [choice, 0]),
  );
  for (const [label, count] of Object.entries(stat?.distribution ?? {})) {
    // Free-text "other" answers arrive redacted; credit them to the open choice
    // label, which the survey author places last.
    const key =
      label === OTHER_BUCKET
        ? question.hasOpenChoice && question.choices.length > 0
          ? question.choices[question.choices.length - 1]
          : "Other"
        : label;
    counts.set(key, (counts.get(key) ?? 0) + count);
  }
  const total = [...counts.values()].reduce((sum, n) => sum + n, 0);
  return {
    kind: "choice",
    question,
    total,
    bars: sortBars(counts, total),
    sampled: false,
  };
}

function multipleChoiceResult(
  question: SurveyQuestionDef,
  responses: SurveyResponseRow[],
  responsesComplete: boolean,
): SurveyQuestionResult {
  const counts = new Map<string, number>(
    question.choices.map((choice) => [choice, 0]),
  );
  const openLabel =
    question.hasOpenChoice && question.choices.length > 0
      ? question.choices[question.choices.length - 1]
      : "Other";
  let total = 0;
  for (const { answer } of answersFor(responses, question)) {
    const picks = (Array.isArray(answer) ? answer : [answer]).filter(
      (pick): pick is string => typeof pick === "string" && pick.trim() !== "",
    );
    if (picks.length === 0) continue;
    total += 1;
    for (const pick of new Set(picks)) {
      const key = counts.has(pick) ? pick : openLabel;
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  }
  return {
    kind: "choice",
    question,
    total,
    bars: sortBars(counts, total),
    sampled: !responsesComplete,
  };
}

function sortBars(counts: Map<string, number>, total: number): ResultBar[] {
  return [...counts.entries()]
    .map(([label, count]) => ({ label, count, share: share(count, total) }))
    .sort((a, b) => b.count - a.count);
}

function openResult(
  question: SurveyQuestionDef,
  stat: PerQuestionStat | undefined,
  responses: SurveyResponseRow[],
  responsesComplete: boolean,
): SurveyQuestionResult {
  const answers = answersFor(responses, question).flatMap(({ row, answer }) => {
    const text = typeof answer === "string" ? answer.trim() : "";
    return text
      ? [
          {
            responseUuid: row.uuid,
            distinctId: row.distinct_id,
            submittedAt: row.submitted_at,
            text,
          },
        ]
      : [];
  });
  return {
    kind: "open",
    question,
    total: stat?.responseCount ?? answers.length,
    answers,
    sampled: !responsesComplete,
  };
}

/**
 * One result per question. Rating and single-choice results come from the
 * server-side distributions, which cover the whole date range. Open text and
 * multiple choice come from the loaded response rows, because the stats
 * endpoint does not return them; `sampled` says whether those rows are only
 * the newest page.
 */
export function buildSurveyQuestionResults(input: {
  questions: SurveyQuestionDef[];
  stats: SurveyStatsResponse | null | undefined;
  responses: SurveyResponseRow[];
  responsesComplete: boolean;
}): SurveyQuestionResult[] {
  const perQuestion = parsePerQuestionStats(input.stats?.per_question_stats);
  return input.questions.map((question) => {
    const stat = findStat(perQuestion, question);
    switch (question.type) {
      case "rating":
        return ratingResult(question, stat);
      case "single_choice":
        return singleChoiceResult(question, stat);
      case "multiple_choice":
        return multipleChoiceResult(
          question,
          input.responses,
          input.responsesComplete,
        );
      case "open":
        return openResult(
          question,
          stat,
          input.responses,
          input.responsesComplete,
        );
      case "link":
        return { kind: "link", question, total: stat?.responseCount ?? 0 };
      default:
        return question.type satisfies never;
    }
  });
}
