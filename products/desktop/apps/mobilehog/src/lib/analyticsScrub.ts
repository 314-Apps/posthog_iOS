import type { AnalyticsProperties } from "@posthog/platform/analytics";

const BLOCKED_PROPERTY_KEYS = new Set([
  "prompt",
  "message",
  "messages",
  "content",
  "body",
  "text",
  "token",
  "tokens",
  "api_key",
  "apikey",
  "authorization",
  "password",
  "image",
  "images",
  "search",
  "query",
  "response",
  "transcript",
  "exception",
  "stack",
  "stacktrace",
]);

/** Drop keys that can carry prompts, tokens, bodies, or search text. */
export function scrubProperties(
  properties?: Record<string, unknown>,
): AnalyticsProperties | undefined {
  if (!properties) return undefined;
  const cleaned: AnalyticsProperties = {};
  for (const [key, value] of Object.entries(properties)) {
    if (BLOCKED_PROPERTY_KEYS.has(key.toLowerCase())) continue;
    if (
      typeof value === "string" ||
      typeof value === "number" ||
      typeof value === "boolean"
    ) {
      cleaned[key] = value;
    }
  }
  return cleaned;
}

/** Keep the error name only — never ship message or stack off-device. */
export function scrubError(error: unknown): Error {
  const name = error instanceof Error ? error.name || "Error" : "Error";
  const scrubbed = new Error(name);
  scrubbed.name = name;
  scrubbed.stack = undefined;
  return scrubbed;
}
