import type {
  SurveyDateRange,
  SurveyStatusFilter,
} from "@posthog/api-client/types";
import type { SurveyAction } from "@posthog/core/surveys/surveyResults";
import {
  useInfiniteQuery,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { getPostHogApiClient } from "@/lib/posthogApiClient";

const SURVEYS_PAGE_SIZE = 50;
const RESPONSES_PAGE_SIZE = 200;

const surveyKeys = {
  all: ["surveys"] as const,
  list: (search: string, status: SurveyStatusFilter | null) =>
    [...surveyKeys.all, "list", search, status] as const,
  responseCounts: (ids: string[]) =>
    [...surveyKeys.all, "response-counts", ids] as const,
  detail: (id: string) => [...surveyKeys.all, "detail", id] as const,
  stats: (id: string, range: SurveyDateRange) =>
    [...surveyKeys.all, "stats", id, range] as const,
  responses: (id: string, range: SurveyDateRange) =>
    [...surveyKeys.all, "responses", id, range] as const,
};

export function useSurveys(search: string, status: SurveyStatusFilter | null) {
  return useInfiniteQuery({
    queryKey: surveyKeys.list(search, status),
    queryFn: ({ pageParam }) =>
      getPostHogApiClient().listSurveys({
        search: search || undefined,
        status: status ?? undefined,
        limit: SURVEYS_PAGE_SIZE,
        offset: pageParam,
      }),
    initialPageParam: 0,
    getNextPageParam: (lastPage, pages) =>
      lastPage.hasMore ? pages.length * SURVEYS_PAGE_SIZE : undefined,
    staleTime: 30 * 1000,
  });
}

export function useSurveyResponseCounts(surveyIds: string[]) {
  return useQuery({
    queryKey: surveyKeys.responseCounts(surveyIds),
    queryFn: () => getPostHogApiClient().getSurveyResponseCounts(surveyIds),
    enabled: surveyIds.length > 0,
    staleTime: 60 * 1000,
  });
}

export function useSurvey(surveyId: string) {
  return useQuery({
    queryKey: surveyKeys.detail(surveyId),
    queryFn: () => getPostHogApiClient().getSurvey(surveyId),
    enabled: !!surveyId,
    staleTime: 30 * 1000,
  });
}

export function useSurveyStats(surveyId: string, range: SurveyDateRange) {
  return useQuery({
    queryKey: surveyKeys.stats(surveyId, range),
    queryFn: () => getPostHogApiClient().getSurveyStats(surveyId, range),
    enabled: !!surveyId,
    staleTime: 60 * 1000,
  });
}

export function useSurveyResponses(surveyId: string, range: SurveyDateRange) {
  return useInfiniteQuery({
    queryKey: surveyKeys.responses(surveyId, range),
    queryFn: ({ pageParam }) =>
      getPostHogApiClient().listSurveyResponses(surveyId, {
        ...range,
        limit: RESPONSES_PAGE_SIZE,
        offset: pageParam,
      }),
    initialPageParam: 0,
    getNextPageParam: (lastPage) =>
      lastPage.has_more ? lastPage.offset + lastPage.limit : undefined,
    enabled: !!surveyId,
    staleTime: 60 * 1000,
  });
}

function runSurveyAction(
  surveyId: string,
  action: SurveyAction,
): Promise<unknown> {
  const client = getPostHogApiClient();
  switch (action) {
    case "launch":
      return client.launchSurvey(surveyId);
    case "stop":
      return client.stopSurvey(surveyId);
    case "resume":
      return client.updateSurvey(surveyId, { end_date: null });
    case "archive":
      return client.updateSurvey(surveyId, { archived: true });
    case "unarchive":
      return client.updateSurvey(surveyId, { archived: false });
  }
}

export function useSurveyAction(surveyId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (action: SurveyAction) => runSurveyAction(surveyId, action),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: surveyKeys.detail(surveyId) });
      queryClient.invalidateQueries({ queryKey: [...surveyKeys.all, "list"] });
    },
  });
}
