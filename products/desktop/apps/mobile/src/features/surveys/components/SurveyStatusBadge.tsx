import { Text } from "@components/text";
import type { SurveyStatus } from "@posthog/core/surveys/surveyResults";
import { View } from "react-native";

const STATUS_STYLE: Record<
  SurveyStatus | "archived",
  { label: string; container: string; text: string }
> = {
  running: {
    label: "Running",
    container: "bg-status-success/15",
    text: "text-status-success",
  },
  draft: { label: "Draft", container: "bg-gray-3", text: "text-gray-11" },
  complete: {
    label: "Complete",
    container: "bg-status-info/15",
    text: "text-status-info",
  },
  archived: { label: "Archived", container: "bg-gray-3", text: "text-gray-10" },
};

export function SurveyStatusBadge({
  status,
  archived,
}: {
  status: SurveyStatus;
  archived?: boolean;
}) {
  const style = STATUS_STYLE[archived ? "archived" : status];
  return (
    <View className={`rounded-full px-2 py-0.5 ${style.container}`}>
      <Text className={`font-medium text-[11px] ${style.text}`}>
        {style.label}
      </Text>
    </View>
  );
}
