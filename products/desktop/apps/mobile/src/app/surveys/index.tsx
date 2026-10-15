import { Text } from "@components/text";
import type { Survey, SurveyStatusFilter } from "@posthog/api-client/types";
import { useRouter } from "expo-router";
import { ChatCenteredText, MagnifyingGlass } from "phosphor-react-native";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  TextInput,
  View,
} from "react-native";
import { ChipRow } from "@/features/surveys/components/ChipRow";
import {
  FloatingSurveyHeader,
  SURVEY_HEADER_HEIGHT,
} from "@/features/surveys/components/FloatingSurveyHeader";
import { SurveyRow } from "@/features/surveys/components/SurveyRow";
import { useSurveyResponseCounts, useSurveys } from "@/features/surveys/hooks";
import { useDebouncedValue } from "@/hooks/useDebouncedValue";
import { useScreenInsets } from "@/hooks/useScreenInsets";
import { useThemeColors } from "@/lib/theme";

const MIN_VISIBLE_ROWS = 15;

type Filter = "all" | SurveyStatusFilter | "archived";

const FILTERS: ReadonlyArray<{ value: Filter; label: string }> = [
  { value: "all", label: "All" },
  { value: "running", label: "Running" },
  { value: "draft", label: "Draft" },
  { value: "complete", label: "Complete" },
  { value: "archived", label: "Archived" },
];

export default function SurveysScreen() {
  const themeColors = useThemeColors();
  const { insets, bottom } = useScreenInsets();
  const router = useRouter();
  const [filter, setFilter] = useState<Filter>("all");
  const [search, setSearch] = useState("");
  const debouncedSearch = useDebouncedValue(search.trim(), 300);

  // The list endpoint has no archived filter, so the archived view and the
  // status views both filter the loaded pages here.
  const statusFilter =
    filter === "all" || filter === "archived" ? null : filter;
  const surveys = useSurveys(debouncedSearch, statusFilter);

  const visible = useMemo(() => {
    const all = surveys.data?.pages.flatMap((page) => page.results) ?? [];
    return all.filter((s) =>
      filter === "archived" ? s.archived : !s.archived,
    );
  }, [surveys.data, filter]);

  const visibleIds = useMemo(() => visible.map((s) => s.id), [visible]);
  const responseCounts = useSurveyResponseCounts(visibleIds);

  const handleOpen = useCallback(
    (survey: Survey) =>
      router.push({ pathname: "/surveys/[id]", params: { id: survey.id } }),
    [router],
  );

  const { hasNextPage, isFetchingNextPage, fetchNextPage } = surveys;
  const handleEndReached = useCallback(() => {
    if (hasNextPage && !isFetchingNextPage) fetchNextPage();
  }, [hasNextPage, isFetchingNextPage, fetchNextPage]);

  // Filtering out archived rows can leave a page too short to scroll, and a
  // list that cannot scroll never reaches its end.
  useEffect(() => {
    if (visible.length < MIN_VISIBLE_ROWS) handleEndReached();
  }, [visible.length, handleEndReached]);

  return (
    <View className="flex-1 bg-background">
      <FloatingSurveyHeader title="Surveys" />

      <View
        className="flex-1"
        style={{ paddingTop: insets.top + SURVEY_HEADER_HEIGHT }}
      >
        <View className="mb-3 px-4">
          <View className="flex-row items-center gap-2 rounded-lg border border-gray-5 bg-card px-3 py-2">
            <MagnifyingGlass size={16} color={themeColors.gray[10]} />
            <TextInput
              value={search}
              onChangeText={setSearch}
              placeholder="Search surveys"
              placeholderTextColor={themeColors.gray[10]}
              className="flex-1 text-[14px] text-gray-12"
              autoCapitalize="none"
              autoCorrect={false}
              clearButtonMode="while-editing"
            />
          </View>
        </View>

        <View className="mb-2">
          <ChipRow options={FILTERS} value={filter} onChange={setFilter} />
        </View>

        {surveys.isPending ? (
          <View className="flex-1 items-center justify-center">
            <ActivityIndicator color={themeColors.accent[9]} />
          </View>
        ) : surveys.isError ? (
          <ErrorState onRetry={() => surveys.refetch()} />
        ) : (
          <FlatList
            data={visible}
            keyExtractor={(s) => s.id}
            renderItem={({ item }) => (
              <SurveyRow
                survey={item}
                responseCount={responseCounts.data?.[item.id]}
                onPress={handleOpen}
              />
            )}
            onEndReached={handleEndReached}
            onEndReachedThreshold={0.5}
            ListEmptyComponent={
              hasNextPage ? null : (
                <EmptyState searching={!!debouncedSearch} filter={filter} />
              )
            }
            ListFooterComponent={
              isFetchingNextPage ? (
                <View className="py-4">
                  <ActivityIndicator color={themeColors.accent[9]} />
                </View>
              ) : null
            }
            refreshControl={
              <RefreshControl
                refreshing={surveys.isRefetching && !isFetchingNextPage}
                onRefresh={() => surveys.refetch()}
                tintColor={themeColors.accent[9]}
              />
            }
            contentContainerStyle={{ paddingBottom: bottom("default") }}
          />
        )}
      </View>
    </View>
  );
}

function EmptyState({
  searching,
  filter,
}: {
  searching: boolean;
  filter: Filter;
}) {
  const themeColors = useThemeColors();
  const message = searching
    ? "No surveys match your search."
    : filter === "all"
      ? "Create a survey in PostHog on the web, then come back here to see its results."
      : "No surveys with this status.";
  return (
    <View className="items-center px-8 py-16">
      <View className="mb-4 h-12 w-12 items-center justify-center rounded-full bg-gray-3">
        <ChatCenteredText
          size={22}
          color={themeColors.gray[11]}
          weight="bold"
        />
      </View>
      <Text className="mb-1 font-semibold text-[16px] text-gray-12">
        No surveys
      </Text>
      <Text className="text-center text-[13px] text-gray-10 leading-snug">
        {message}
      </Text>
    </View>
  );
}

function ErrorState({ onRetry }: { onRetry: () => void }) {
  return (
    <View className="items-center px-8 py-16">
      <Text className="mb-1 font-semibold text-[16px] text-gray-12">
        Couldn't load surveys
      </Text>
      <Text className="mb-4 text-center text-[13px] text-gray-10">
        Check your connection and try again.
      </Text>
      <Pressable
        onPress={onRetry}
        className="rounded-lg bg-accent-9 px-4 py-2 active:opacity-80"
      >
        <Text className="font-semibold text-[14px] text-accent-contrast">
          Try again
        </Text>
      </Pressable>
    </View>
  );
}
