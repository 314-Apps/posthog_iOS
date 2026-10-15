import "./generated.augment";
import type { Schemas } from "./generated";

export type McpCategory = Schemas.MCPServerCategoryEnum;
export type McpApprovalState = Schemas.MCPToolApprovalStateEnum;
export type McpAuthType = Schemas.MCPAuthTypeEnum;
export type McpRecommendedServer = Schemas.MCPServerTemplate;
export type McpServerInstallation = Schemas.MCPServerInstallation & {
  scope?: "personal" | "shared";
};
export type McpInstallationTool = Schemas.MCPServerInstallationTool & {
  /** Team-admin ceiling returned by gateway-aware backends. */
  team_state?: McpApprovalState | null;
  locked?: boolean;
  decided_by?: "rule" | "scope" | "team" | "preset" | "legacy" | "default";
};
export type McpOAuthRedirectResponse = Schemas.OAuthRedirectResponse;
export type McpInstallSource = "posthog" | "posthog-code" | "posthog-mobile";
export type McpInstallResponse =
  | McpServerInstallation
  | McpOAuthRedirectResponse;

export interface InstallCustomMcpServerOptions {
  name: string;
  url: string;
  auth_type: McpAuthType;
  api_key?: string;
  description?: string;
  client_id?: string;
  client_secret?: string;
  install_source?: McpInstallSource;
  posthog_code_callback_url?: string;
}

export interface InstallMcpTemplateOptions {
  template_id: string;
  api_key?: string;
  install_source?: McpInstallSource;
  posthog_code_callback_url?: string;
}

export interface UpdateMcpServerInstallationOptions {
  display_name?: string;
  description?: string;
  is_enabled?: boolean;
}

export type Survey = Schemas.Survey;
export type SurveyStatsResponse = Schemas.SurveyStatsResponse;
export type SurveyStatusFilter = "draft" | "running" | "complete";

export interface ListSurveysOptions {
  search?: string;
  status?: SurveyStatusFilter;
  limit?: number;
  offset?: number;
}

export interface SurveyListPage {
  results: Survey[];
  count: number;
  hasMore: boolean;
}

export interface SurveyDateRange {
  /** ISO 8601 timestamp; omitted means from the survey start. */
  since?: string;
  /** ISO 8601 timestamp; omitted means up to now. */
  until?: string;
}

export interface SurveyResponseAnswer {
  question_id: string;
  question_index: number;
  question_text: string;
  question_type: string;
  /** String for most question types, a string list for multiple choice. */
  answer: string | string[] | null;
}

export interface SurveyResponseRow {
  uuid: string;
  distinct_id: string;
  session_id: string | null;
  submitted_at: string;
  answers: SurveyResponseAnswer[];
  extra: Record<string, unknown>;
}

export interface SurveyResponsesPage {
  results: SurveyResponseRow[];
  has_more: boolean;
  limit: number;
  offset: number;
}

export interface ListSurveyResponsesOptions extends SurveyDateRange {
  limit?: number;
  offset?: number;
}

export interface UpdateSurveyOptions {
  archived?: boolean;
  end_date?: string | null;
}
