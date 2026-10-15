import { Text } from "@components/text";
import type {
  ResultBar,
  SurveyQuestionResult,
} from "@posthog/core/surveys/surveyResults";
import { formatDistanceToNow } from "date-fns";
import { useState } from "react";
import { Pressable, View } from "react-native";

const OPEN_TEXT_STEP = 10;

const TYPE_LABELS: Record<SurveyQuestionResult["question"]["type"], string> = {
  open: "Open text",
  link: "Link",
  rating: "Rating",
  single_choice: "Single choice",
  multiple_choice: "Multiple choice",
};

const percent = (share: number) => `${Math.round(share * 100)}%`;

function HorizontalBar({ bar }: { bar: ResultBar }) {
  return (
    <View className="gap-1">
      <View className="flex-row items-baseline justify-between gap-3">
        <Text className="shrink text-[14px] text-gray-12">{bar.label}</Text>
        <Text className="text-[12px] text-gray-10">
          {bar.count} · {percent(bar.share)}
        </Text>
      </View>
      <View className="h-2 overflow-hidden rounded-full bg-gray-3">
        <View
          className="h-full rounded-full bg-accent-9"
          style={{ width: `${Math.max(bar.share * 100, bar.count ? 2 : 0)}%` }}
        />
      </View>
    </View>
  );
}

function RatingColumns({ bars }: { bars: ResultBar[] }) {
  const max = Math.max(...bars.map((b) => b.count), 1);
  return (
    <View className="flex-row items-end gap-1" style={{ height: 120 }}>
      {bars.map((bar) => (
        <View key={bar.label} className="flex-1 items-center gap-1">
          <Text className="text-[10px] text-gray-10">
            {bar.count ? percent(bar.share) : ""}
          </Text>
          <View
            className="w-full rounded-t-md bg-accent-9"
            style={{ height: Math.max((bar.count / max) * 80, 2) }}
          />
          <Text className="text-[11px] text-gray-11">{bar.label}</Text>
        </View>
      ))}
    </View>
  );
}

function NpsSummary({
  nps,
  total,
}: {
  nps: NonNullable<Extract<SurveyQuestionResult, { kind: "rating" }>["nps"]>;
  total: number;
}) {
  const segments = [
    { label: "Promoters", count: nps.promoters, color: "bg-status-success" },
    { label: "Passives", count: nps.passives, color: "bg-status-warning" },
    { label: "Detractors", count: nps.detractors, color: "bg-status-error" },
  ];
  return (
    <View className="gap-2 rounded-lg bg-gray-2 p-3">
      <View className="flex-row items-baseline gap-2">
        <Text className="font-semibold text-[24px] text-gray-12">
          {nps.score}
        </Text>
        <Text className="text-[12px] text-gray-10">NPS</Text>
      </View>
      <View className="h-2 flex-row overflow-hidden rounded-full bg-gray-3">
        {segments.map((s) =>
          s.count ? (
            <View
              key={s.label}
              className={`h-full ${s.color}`}
              style={{ width: `${(s.count / total) * 100}%` }}
            />
          ) : null,
        )}
      </View>
      <View className="flex-row flex-wrap gap-x-4 gap-y-1">
        {segments.map((s) => (
          <View key={s.label} className="flex-row items-center gap-1.5">
            <View className={`h-2 w-2 rounded-full ${s.color}`} />
            <Text className="text-[12px] text-gray-11">
              {s.label} {s.count} ({percent(s.count / total)})
            </Text>
          </View>
        ))}
      </View>
    </View>
  );
}

function OpenTextAnswers({
  result,
}: {
  result: Extract<SurveyQuestionResult, { kind: "open" }>;
}) {
  const [visible, setVisible] = useState(OPEN_TEXT_STEP);
  if (result.answers.length === 0) {
    return <EmptyResult />;
  }
  const remaining = result.answers.length - visible;
  return (
    <View className="gap-2">
      {result.answers.slice(0, visible).map((answer) => (
        <View
          key={answer.responseUuid}
          className="gap-1 rounded-lg bg-gray-2 px-3 py-2"
        >
          <Text className="text-[14px] text-gray-12 leading-snug">
            {answer.text}
          </Text>
          <Text className="text-[11px] text-gray-10" numberOfLines={1}>
            {answer.distinctId} ·{" "}
            {formatDistanceToNow(new Date(answer.submittedAt), {
              addSuffix: true,
            })}
          </Text>
        </View>
      ))}
      {remaining > 0 ? (
        <Pressable
          onPress={() => setVisible((v) => v + OPEN_TEXT_STEP)}
          className="items-center rounded-lg border border-gray-5 py-2 active:bg-gray-2"
        >
          <Text className="font-medium text-[13px] text-gray-12">
            Show {Math.min(remaining, OPEN_TEXT_STEP)} more
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

function EmptyResult() {
  return (
    <Text className="text-[13px] text-gray-10">
      No answers in this date range yet.
    </Text>
  );
}

function ResultBody({ result }: { result: SurveyQuestionResult }) {
  switch (result.kind) {
    case "rating":
      if (result.total === 0) return <EmptyResult />;
      return (
        <View className="gap-3">
          {result.nps ? (
            <NpsSummary nps={result.nps} total={result.total} />
          ) : null}
          <RatingColumns bars={result.bars} />
          {result.question.lowerBoundLabel ||
          result.question.upperBoundLabel ? (
            <View className="flex-row justify-between">
              <Text className="text-[11px] text-gray-10">
                {result.question.lowerBoundLabel ?? ""}
              </Text>
              <Text className="text-[11px] text-gray-10">
                {result.question.upperBoundLabel ?? ""}
              </Text>
            </View>
          ) : null}
          {result.average !== null ? (
            <Text className="text-[12px] text-gray-10">
              Average {result.average.toFixed(1)}
            </Text>
          ) : null}
        </View>
      );
    case "choice":
      if (result.total === 0) return <EmptyResult />;
      return (
        <View className="gap-3">
          {result.bars.map((bar) => (
            <HorizontalBar key={bar.label} bar={bar} />
          ))}
        </View>
      );
    case "open":
      return <OpenTextAnswers result={result} />;
    case "link":
      return (
        <Text className="text-[13px] text-gray-10">
          {result.total} {result.total === 1 ? "person" : "people"} clicked the
          link.
        </Text>
      );
  }
}

function sampleNote(result: SurveyQuestionResult): string | null {
  if ((result.kind === "choice" || result.kind === "open") && result.sampled) {
    return "Counted from the latest responses. Load more responses for a full count.";
  }
  return null;
}

export function QuestionResultCard({
  result,
}: {
  result: SurveyQuestionResult;
}) {
  const note = sampleNote(result);
  return (
    <View className="gap-3 rounded-xl border border-gray-5 bg-card p-4">
      <View className="gap-1">
        <Text className="text-[11px] text-gray-10 uppercase">
          Question {result.question.index + 1} ·{" "}
          {TYPE_LABELS[result.question.type]}
        </Text>
        <Text className="font-semibold text-[16px] text-gray-12 leading-snug">
          {result.question.text || "Untitled question"}
        </Text>
        <Text className="text-[12px] text-gray-10">
          {result.total} {result.total === 1 ? "answer" : "answers"}
        </Text>
      </View>
      <ResultBody result={result} />
      {note ? <Text className="text-[11px] text-gray-9">{note}</Text> : null}
    </View>
  );
}
