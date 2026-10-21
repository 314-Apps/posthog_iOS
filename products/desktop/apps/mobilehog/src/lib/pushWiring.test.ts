import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const root = join(dirname(fileURLToPath(import.meta.url)), "../..");

describe("mobilehog push wiring", () => {
  it("points Expo Updates and push at the mobilehog EAS project", () => {
    const appJson = JSON.parse(
      readFileSync(join(root, "app.json"), "utf8"),
    ) as {
      expo: {
        extra: { eas: { projectId: string } };
        updates: { enabled: boolean; url: string };
        plugins: unknown[];
      };
    };
    const projectId = "d8e0731d-1107-4421-aa33-abf130eca27f";
    expect(appJson.expo.extra.eas.projectId).toBe(projectId);
    expect(appJson.expo.updates.enabled).toBe(true);
    expect(appJson.expo.updates.url).toContain(projectId);
    expect(
      JSON.stringify(appJson.expo.plugins).includes("expo-notifications"),
    ).toBe(true);
  });

  it("registers for push from the root layout after sign-in", () => {
    const layout = readFileSync(join(root, "src/app/_layout.tsx"), "utf8");
    expect(layout).toContain("usePushNotifications");
    const notifications = readFileSync(
      join(root, "src/lib/notifications.ts"),
      "utf8",
    );
    expect(notifications).toContain("registerPushToken");
    expect(notifications).toContain("getExpoPushTokenAsync");
    expect(notifications).toContain("/api/users/@me/push_tokens/");
  });

  it("does not allow arbitrary ATS loads in release infoPlist", () => {
    const appJson = JSON.parse(
      readFileSync(join(root, "app.json"), "utf8"),
    ) as {
      expo: {
        ios: {
          infoPlist: {
            NSAppTransportSecurity: Record<string, unknown>;
          };
        };
      };
    };
    const ats = appJson.expo.ios.infoPlist.NSAppTransportSecurity;
    expect(ats.NSAllowsLocalNetworking).toBe(true);
    expect(ats.NSAllowsArbitraryLoads).toBeUndefined();
  });
});
