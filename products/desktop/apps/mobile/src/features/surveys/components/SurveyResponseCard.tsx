import { Text } from "@components/text";
import type { SurveyResponseRow } from "@posthog/api-client/types";
import { format } from "date-fns";
import { memo } from "react";
import { View } from "react-native";

function answerText(answer: SurveyResponseRow["answers"][number]["answer"]) {
  if (Array.isArray(answer)) return answer.join(", ");
  return answer ?? "";
}

function deviceSummary(extra: Record<string, unknown>): string | null {
  const parts = [extra.browser, extra.os, extra.geoip_country_name].filter(
    (part): part is string => typeof part === "string" && part !== "",
  );
  return parts.length ? parts.join(" · ") : null;
}

export const SurveyResponseCard = memo(function SurveyResponseCard({
  response,
}: {
  response: SurveyResponseRow;
}) {
  const device = deviceSummary(response.extra);
  return (
    <View className="gap-3 rounded-xl border border-gray-5 bg-card p-4">
      <View className="gap-0.5">
        <Text
          className="font-medium text-[13px] text-gray-12"
          numberOfLines={1}
        >
          {response.distinct_id}
        </Text>
        <Text className="text-[11px] text-gray-10" numberOfLines={1}>
          {format(new Date(response.submitted_at), "MMM d, yyyy 'at' h:mm a")}
          {device ? ` · ${device}` : ""}
        </Text>
      </View>
      {response.answers.map((answer) => (
        <View key={answer.question_id} className="gap-0.5">
          <Text className="text-[12px] text-gray-10">
            {answer.question_text || `Question ${answer.question_index + 1}`}
          </Text>
          <Text className="text-[14px] text-gray-12 leading-snug">
            {answerText(answer.answer)}
          </Text>
        </View>
      ))}
    </View>
  );
});
