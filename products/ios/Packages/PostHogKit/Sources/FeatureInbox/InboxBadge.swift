import PostHogQueries

/// Unread count for the shell's tab badge. Returns 0 on failure so a flaky
/// connection never blocks tab rendering.
public enum InboxBadge {
  public static func unreadCount(context: ProjectContext) async -> Int {
    (try? await context.client.notificationUnreadCount(projectID: context.projectID)) ?? 0
  }
}
