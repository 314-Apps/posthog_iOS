import { Text } from "@components/text";
import type { Survey, SurveyResponseRow } from "@posthog/api-client/types";
import {
  buildSurveyQuestionResults,
  parseSurveyQuestions,
  type SurveyAction,
  type SurveyDatePreset,
  type SurveyFunnel,
  type SurveyQuestionResult,
  summarizeSurveyStats,
  surveyActions,
  surveyDateRange,
  surveyStatus,
} from "@posthog/core/surveys/surveyResults";
import { format } from "date-fns";
import { useLocalSearchParams } from "expo-router";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Pressable,
  RefreshControl,
  ScrollView,
  View,
} from "react-native";
import { ChipRow } from "@/features/surveys/components/ChipRow";
import {
  FloatingSurveyHeader,
  SURVEY_HEADER_HEIGHT,
} from "@/features/surveys/components/FloatingSurveyHeader";
import { QuestionResultCard } from "@/features/surveys/components/QuestionResultCard";
import { SurveyFunnelCard } from "@/features/surveys/components/SurveyFunnelCard";
import { SurveyResponseCard } from "@/features/surveys/components/SurveyResponseCard";
import { SurveyStatusBadge } from "@/features/surveys/components/SurveyStatusBadge";
import {
  useSurvey,
  useSurveyAction,
  useSurveyResponses,
  useSurveyStats,
} from "@/features/surveys/hooks";
import { useScreenInsets } from "@/hooks/useScreenInsets";
import { ANALYTICS_EVENTS, useAnalytics } from "@/lib/analytics";
import { useThemeColors } from "@/lib/theme";

type Tab = "results" | "responses";

const TABS: ReadonlyArray<{ value: Tab; label: string }> = [
  { value: "results", label: "Results" },
  { value: "responses", label: "Responses" },
];

const DATE_PRESETS: ReadonlyArray<{ value: SurveyDatePreset; label: string }> =
  [
    { value: "all", label: "All time" },
    { value: "7d", label: "Last 7 days" },
    { value: "30d", label: "Last 30 days" },
    { value: "90d", label: "Last 90 days" },
  ];

const ACTION_COPY: Record<
  SurveyAction,
  { label: string; confirm: string | null; destructive: boolean }
> = {
  launch: {
    label: "Launch",
    confirm: "The survey starts showing to the people it targets.",
    destructive: false,
  },
  stop: {
    label: "Stop",
    confirm: "The survey stops showing to people. You can resume it later.",
    destructive: true,
  },
  resume: {
    label: "Resume",
    confirm: "The survey starts showing to people again.",
    destructive: false,
  },
  archive: {
    label: "Archive",
    confirm: "The survey moves to the archived list. Its responses are kept.",
    destructive: true,
  },
  unarchive: { label: "Unarchive", confirm: null, destructive: false },
};

const TYPE_LABELS: Record<string, string> = {
  popover: "Popover survey",
  widget: "Widget survey",
  api: "API survey",
  external_survey: "Hosted survey",
};

function formatDay(iso: string): string {
  return format(new Date(iso), "MMM d, yyyy");
}

function scheduleLine(survey: Survey): string {
  const parts = [TYPE_LABELS[survey.type] ?? survey.type];
  if (survey.start_date) parts.push(`Started ${formatDay(survey.start_date)}`);
  if (survey.end_date) {
    const ended = Date.parse(survey.end_date) <= Date.now();
    parts.push(`${ended ? "Ended" : "Ends"} ${formatDay(survey.end_date)}`);
  }
  if (!survey.start_date) parts.push(`Created ${formatDay(survey.created_at)}`);
  return parts.join(" · ");
}

export default function SurveyDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const surveyId = id ?? "";
  const themeColors = useThemeColors();
  const { insets, bottom } = useScreenInsets();
  const analytics = useAnalytics();

  const [tab, setTab] = useState<Tab>("results");
  const [preset, setPreset] = useState<SurveyDatePreset>("all");
  // Stable for the query key: recomputed only when the preset changes.
  const range = useMemo(() => surveyDateRange(preset), [preset]);

  const survey = useSurvey(surveyId);
  const stats = useSurveyStats(surveyId, range);
  const responses = useSurveyResponses(surveyId, range);
  const action = useSurveyAction(surveyId);

  const trackedOpen = useRef(false);
  useEffect(() => {
    if (!survey.data || trackedOpen.current) return;
    trackedOpen.current = true;
    analytics.track(ANALYTICS_EVENTS.SURVEY_OPENED, {
      survey_id: survey.data.id,
      status: surveyStatus(survey.data),
    });
  }, [survey.data, analytics]);

  const responseRows = useMemo(
    () => responses.data?.pages.flatMap((page) => page.results) ?? [],
    [responses.data],
  );

  const questions = useMemo(
    () => parseSurveyQuestions(survey.data?.questions),
    [survey.data?.questions],
  );

  const results = useMemo(
    () =>
      buildSurveyQuestionResults({
        questions,
        stats: stats.data,
        responses: responseRows,
        responsesComplete: !responses.hasNextPage,
      }),
    [questions, stats.data, responseRows, responses.hasNextPage],
  );

  const funnel = useMemo(
    () => (stats.data ? summarizeSurveyStats(stats.data) : null),
    [stats.data],
  );

  const runAction = (next: SurveyAction) => {
    const execute = () =>
      action.mutate(next, {
        onSuccess: () =>
          analytics.track(ANALYTICS_EVENTS.SURVEY_ACTION, {
            survey_id: surveyId,
            action: next,
            success: true,
          }),
        onError: (error) => {
          analytics.track(ANALYTICS_EVENTS.SURVEY_ACTION, {
            survey_id: surveyId,
            action: next,
            success: false,
          });
          Alert.alert(
            `Couldn't ${ACTION_COPY[next].label.toLowerCase()} the survey`,
            error instanceof Error ? error.message : "Try again in a moment.",
          );
        },
      });
    const copy = ACTION_COPY[next];
    if (!copy.confirm) {
      execute();
      return;
    }
    Alert.alert(`${copy.label} survey?`, copy.confirm, [
      { text: "Cancel", style: "cancel" },
      {
        text: copy.label,
        style: copy.destructive ? "destructive" : "default",
        onPress: execute,
      },
    ]);
  };

  const refreshing =
    (survey.isRefetching || stats.isRefetching || responses.isRefetching) &&
    !responses.isFetchingNextPage;
  const handleRefresh = () => {
    survey.refetch();
    stats.refetch();
    responses.refetch();
  };

  if (survey.isPending || survey.isError) {
    return (
      <View className="flex-1 bg-background">
        <FloatingSurveyHeader title="Survey" />
        <View className="flex-1 items-center justify-center px-8">
          {survey.isPending ? (
            <ActivityIndicator color={themeColors.accent[9]} />
          ) : (
            <>
              <Text className="mb-1 font-semibold text-[16px] text-gray-12">
                Couldn't load this survey
              </Text>
              <Text className="mb-4 text-center text-[13px] text-gray-10">
                It may have been deleted, or you may not have access to it.
              </Text>
              <Pressable
                onPress={() => survey.refetch()}
                className="rounded-lg bg-accent-9 px-4 py-2 active:opacity-80"
              >
                <Text className="font-semibold text-[14px] text-accent-contrast">
                  Try again
                </Text>
              </Pressable>
            </>
          )}
        </View>
      </View>
    );
  }

  const data = survey.data;
  const actions = surveyActions(data);

  return (
    <View className="flex-1 bg-background">
      <FloatingSurveyHeader title="Survey" />
      <ScrollView
        contentContainerStyle={{
          paddingTop: insets.top + SURVEY_HEADER_HEIGHT,
          paddingBottom: bottom("default"),
        }}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={handleRefresh}
            tintColor={themeColors.accent[9]}
            progressViewOffset={insets.top + SURVEY_HEADER_HEIGHT}
          />
        }
      >
        <View className="gap-2 px-4 pb-4">
          <View className="flex-row flex-wrap items-center gap-2">
            <Text className="shrink font-bold text-[22px] text-gray-12">
              {data.name}
            </Text>
            <SurveyStatusBadge
              status={surveyStatus(data)}
              archived={data.archived}
            />
          </View>
          {data.description ? (
            <Text className="text-[14px] text-gray-11 leading-snug">
              {data.description}
            </Text>
          ) : null}
          <Text className="text-[12px] text-gray-10">{scheduleLine(data)}</Text>

          <View className="mt-2 flex-row gap-2">
            {actions.map((next, index) => {
              const primary = index === 0;
              const busy = action.isPending && action.variables === next;
              return (
                <Pressable
                  key={next}
                  onPress={() => runAction(next)}
                  disabled={action.isPending}
                  accessibilityRole="button"
                  accessibilityState={{ disabled: action.isPending }}
                  className={`flex-1 flex-row items-center justify-center gap-2 rounded-lg px-4 py-2.5 ${primary ? "bg-accent-9" : "border border-gray-5 bg-card"} ${action.isPending ? "opacity-60" : "active:opacity-80"}`}
                >
                  {busy ? (
                    <ActivityIndicator
                      size="small"
                      color={
                        primary
                          ? themeColors.accent.contrast
                          : themeColors.gray[12]
                      }
                    />
                  ) : null}
                  <Text
                    className={`font-semibold text-[14px] ${primary ? "text-accent-contrast" : "text-gray-12"}`}
                  >
                    {ACTION_COPY[next].label}
                  </Text>
                </Pressable>
              );
            })}
          </View>
        </View>

        <View className="gap-2 pb-3">
          <ChipRow options={TABS} value={tab} onChange={setTab} />
          <ChipRow options={DATE_PRESETS} value={preset} onChange={setPreset} />
        </View>

        <View className="gap-3 px-4">
          {tab === "results" ? (
            <ResultsTab
              loading={stats.isPending}
              error={stats.isError}
              onRetry={() => stats.refetch()}
              funnel={funnel}
              results={results}
            />
          ) : (
            <ResponsesTab
              loading={responses.isPending}
              error={responses.isError}
              onRetry={() => responses.refetch()}
              rows={responseRows}
              hasMore={!!responses.hasNextPage}
              loadingMore={responses.isFetchingNextPage}
              onLoadMore={() => responses.fetchNextPage()}
            />
          )}
        </View>
      </ScrollView>
    </View>
  );
}

function SectionMessage({
  title,
  body,
  onRetry,
}: {
  title: string;
  body: string;
  onRetry?: () => void;
}) {
  return (
    <View className="items-center gap-1 rounded-xl border border-gray-5 bg-card px-6 py-8">
      <Text className="font-semibold text-[15px] text-gray-12">{title}</Text>
      <Text className="text-center text-[13px] text-gray-10">{body}</Text>
      {onRetry ? (
        <Pressable
          onPress={onRetry}
          className="mt-3 rounded-lg border border-gray-5 px-4 py-2 active:bg-gray-2"
        >
          <Text className="font-medium text-[13px] text-gray-12">
            Try again
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

function ResultsTab({
  loading,
  error,
  onRetry,
  funnel,
  results,
}: {
  loading: boolean;
  error: boolean;
  onRetry: () => void;
  funnel: SurveyFunnel | null;
  results: SurveyQuestionResult[];
}) {
  const themeColors = useThemeColors();
  if (loading) {
    return (
      <View className="items-center py-10">
        <ActivityIndicator color={themeColors.accent[9]} />
      </View>
    );
  }
  if (error || !funnel) {
    return (
      <SectionMessage
        title="Couldn't load results"
        body="Check your connection and try again."
        onRetry={onRetry}
      />
    );
  }
  return (
    <>
      <SurveyFunnelCard funnel={funnel} />
      {results.length === 0 ? (
        <SectionMessage
          title="No questions"
          body="This survey has no questions to show results for."
        />
      ) : (
        results.map((result) => (
          <QuestionResultCard
            key={result.question.id ?? result.question.index}
            result={result}
          />
        ))
      )}
    </>
  );
}

function ResponsesTab({
  loading,
  error,
  onRetry,
  rows,
  hasMore,
  loadingMore,
  onLoadMore,
}: {
  loading: boolean;
  error: boolean;
  onRetry: () => void;
  rows: SurveyResponseRow[];
  hasMore: boolean;
  loadingMore: boolean;
  onLoadMore: () => void;
}) {
  const themeColors = useThemeColors();
  if (loading) {
    return (
      <View className="items-center py-10">
        <ActivityIndicator color={themeColors.accent[9]} />
      </View>
    );
  }
  if (error) {
    return (
      <SectionMessage
        title="Couldn't load responses"
        body="Check your connection and try again."
        onRetry={onRetry}
      />
    );
  }
  if (rows.length === 0) {
    return (
      <SectionMessage
        title="No responses yet"
        body="Responses show up here as soon as people answer the survey."
      />
    );
  }
  return (
    <>
      {rows.map((row) => (
        <SurveyResponseCard key={row.uuid} response={row} />
      ))}
      {hasMore ? (
        <Pressable
          onPress={onLoadMore}
          disabled={loadingMore}
          className={`flex-row items-center justify-center gap-2 rounded-lg border border-gray-5 py-2.5 ${loadingMore ? "opacity-60" : "active:bg-gray-2"}`}
        >
          {loadingMore ? (
            <ActivityIndicator size="small" color={themeColors.gray[12]} />
          ) : null}
          <Text className="font-medium text-[14px] text-gray-12">
            Load more responses
          </Text>
        </Pressable>
      ) : null}
    </>
  );
}
