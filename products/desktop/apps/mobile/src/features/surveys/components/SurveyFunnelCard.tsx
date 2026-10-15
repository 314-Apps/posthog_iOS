import { Text } from "@components/text";
import type { SurveyFunnel } from "@posthog/core/surveys/surveyResults";
import { View } from "react-native";

function Metric({
  label,
  value,
  detail,
}: {
  label: string;
  value: string;
  detail?: string;
}) {
  return (
    <View className="min-w-[45%] flex-1 gap-0.5 rounded-lg bg-gray-2 px-3 py-2.5">
      <Text className="text-[12px] text-gray-10">{label}</Text>
      <Text className="font-semibold text-[20px] text-gray-12">{value}</Text>
      {detail ? (
        <Text className="text-[11px] text-gray-10">{detail}</Text>
      ) : null}
    </View>
  );
}

const formatCount = (n: number) => n.toLocaleString();
const formatRate = (rate: number) => `${Math.round(rate * 10) / 10}%`;

export function SurveyFunnelCard({ funnel }: { funnel: SurveyFunnel }) {
  return (
    <View className="gap-2 rounded-xl border border-gray-5 bg-card p-3">
      <View className="flex-row flex-wrap gap-2">
        <Metric
          label="Shown"
          value={formatCount(funnel.shown)}
          detail={`${formatCount(funnel.uniqueShown)} unique people`}
        />
        <Metric
          label="Responses"
          value={formatCount(funnel.sent)}
          detail={`${formatCount(funnel.uniqueSent)} unique people`}
        />
        <Metric
          label="Response rate"
          value={funnel.shown > 0 ? formatRate(funnel.responseRate) : "–"}
          detail={
            funnel.shown > 0
              ? `${formatRate(funnel.uniqueResponseRate)} of unique people`
              : "Not shown yet"
          }
        />
        <Metric
          label="Dismissed"
          value={formatCount(funnel.dismissed)}
          detail={
            funnel.shown > 0
              ? `${formatRate(funnel.dismissalRate)} of views`
              : undefined
          }
        />
      </View>
    </View>
  );
}
