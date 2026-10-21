import type {
  AnalyticsProperties,
  IAnalytics,
} from "@posthog/platform/analytics";
import Constants from "expo-constants";
import { PostHog } from "posthog-react-native";
import { scrubError, scrubProperties } from "@/lib/analyticsScrub";

/**
 * Telemetry project key. Empty disables capture (local builds without a key).
 * Matches the shared posthog-code mobile project used by apps/mobile.
 */
const API_KEY = process.env.EXPO_PUBLIC_POSTHOG_API_KEY ?? "";
const API_HOST =
  process.env.EXPO_PUBLIC_POSTHOG_HOST ?? "https://us.i.posthog.com";

class MobilehogAnalytics implements IAnalytics {
  private client: PostHog | null = null;
  private currentUserId: string | null = null;
  private sessionId: string | null = null;

  initialize(): void {
    if (this.client || !API_KEY) return;
    this.client = new PostHog(API_KEY, {
      host: API_HOST,
      captureAppLifecycleEvents: true,
      // No session replay on mobilehog — task transcripts must not leave the device.
      enableSessionReplay: false,
    });
    this.client.register({
      team: "posthog-code",
      app: "mobilehog",
      app_version: Constants.expoConfig?.version ?? "unknown",
      os_platform: Constants.platform?.ios
        ? "ios"
        : Constants.platform?.android
          ? "android"
          : "unknown",
    });
    this.getOrCreateSessionId();
  }

  track(eventName: string, properties?: AnalyticsProperties): void {
    this.client?.capture(eventName, scrubProperties(properties));
  }

  identify(userId: string, properties?: AnalyticsProperties): void {
    this.currentUserId = userId;
    this.client?.identify(userId, scrubProperties(properties));
  }

  setCurrentUserId(userId: string | null): void {
    this.currentUserId = userId;
  }

  getCurrentUserId(): string | null {
    return this.currentUserId;
  }

  getOrCreateSessionId(): string {
    if (!this.sessionId) {
      this.sessionId = `mobilehog-${Date.now().toString(36)}`;
    }
    return this.sessionId;
  }

  resetUser(): void {
    this.currentUserId = null;
    this.client?.reset();
  }

  captureException(
    error: unknown,
    additionalProperties?: Record<string, unknown>,
  ): void {
    if (!this.client) return;
    this.client.captureException(
      scrubError(error),
      scrubProperties(additionalProperties),
    );
  }

  async flush(): Promise<void> {
    await this.client?.flush();
  }

  async shutdown(): Promise<void> {
    if (!this.client) return;
    await this.client.shutdown();
    this.client = null;
  }
}

export const mobilehogAnalytics: IAnalytics = new MobilehogAnalytics();
