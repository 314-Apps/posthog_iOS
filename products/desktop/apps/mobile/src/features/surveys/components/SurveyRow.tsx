import { Text } from "@components/text";
import type { Survey } from "@posthog/api-client/types";
import { surveyStatus } from "@posthog/core/surveys/surveyResults";
import { formatDistanceToNow } from "date-fns";
import { CaretRight } from "phosphor-react-native";
import { memo } from "react";
import { Pressable, View } from "react-native";
import { useThemeColors } from "@/lib/theme";
import { SurveyStatusBadge } from "./SurveyStatusBadge";

const TYPE_LABELS: Record<string, string> = {
  popover: "Popover",
  widget: "Widget",
  api: "API",
  external_survey: "Hosted",
};

interface SurveyRowProps {
  survey: Survey;
  responseCount: number | undefined;
  onPress: (survey: Survey) => void;
}

export const SurveyRow = memo(function SurveyRow({
  survey,
  responseCount,
  onPress,
}: SurveyRowProps) {
  const themeColors = useThemeColors();
  const meta = [
    TYPE_LABELS[survey.type] ?? survey.type,
    responseCount === undefined
      ? null
      : `${responseCount} ${responseCount === 1 ? "response" : "responses"}`,
    `Created ${formatDistanceToNow(new Date(survey.created_at), { addSuffix: true })}`,
  ].filter(Boolean);

  return (
    <Pressable
      onPress={() => onPress(survey)}
      className="flex-row items-center gap-3 border-gray-4 border-b px-4 py-3 active:bg-gray-2"
    >
      <View className="min-w-0 flex-1 gap-1">
        <View className="flex-row items-center gap-2">
          <Text
            className="shrink font-medium text-[15px] text-gray-12"
            numberOfLines={1}
          >
            {survey.name}
          </Text>
          <SurveyStatusBadge
            status={surveyStatus(survey)}
            archived={survey.archived}
          />
        </View>
        <Text className="text-[12px] text-gray-10" numberOfLines={1}>
          {meta.join(" · ")}
        </Text>
      </View>
      <CaretRight size={14} color={themeColors.gray[9]} />
    </Pressable>
  );
});
