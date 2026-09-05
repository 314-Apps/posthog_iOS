import FeatureDashboards
import FeatureErrors
import FeatureFlags
import FeatureInbox
import FeatureInsights
import FeatureLive
import FeatureSettings
import PostHogAPI
import PostHogDesignSystem
import PostHogQueries
import SwiftUI

/// The signed-in tab shell: Home, Dashboards, Flags (Phase 1's fixed slots).
struct SignedInShell: View {
  @Environment(SessionStore.self) private var session
  @Environment(\.openURL) private var openURL
  @State private var router = Router()
  @State private var showingSwitcher = false
  @State private var showingSettings = false
  @State private var unreadCount = 0

  let context: ProjectContext

  var body: some View {
    @Bindable var router = router
    TabView(selection: $router.selectedTab) {
      NavigationStack(path: $router.homePath) {
        HomeView(
          context: context,
          projectName: session.availableProjects.first(where: { $0.id == context.projectID })?.name,
          onOpenDashboard: { router.open(.dashboard(id: $0)) },
          onOpenFlags: { router.selectedTab = .flags },
          onOpenSettings: { showingSettings = true },
          onOpenSwitcher: { showingSwitcher = true },
          onOpenErrors: { router.pushOnSelectedTab(.errorsList) },
          onOpenLive: { router.pushOnSelectedTab(.liveEvents) },
          onOpenWeb: { openWeb(path: $0) }
        )
        .navigationDestination(for: Route.self) { destination(for: $0) }
      }
      .tabItem { Label("Home", systemImage: "house") }
      .tag(AppTab.home)

      NavigationStack(path: $router.dashboardsPath) {
        DashboardsListView(context: context) { router.open(.dashboard(id: $0)) }
          .navigationDestination(for: Route.self) { destination(for: $0) }
      }
      .tabItem { Label("Dashboards", systemImage: "rectangle.grid.2x2") }
      .tag(AppTab.dashboards)

      NavigationStack(path: $router.flagsPath) {
        FlagsListView(context: context) { router.open(.flag(id: $0)) }
          .navigationDestination(for: Route.self) { destination(for: $0) }
      }
      .tabItem { Label("Flags", systemImage: "flag") }
      .tag(AppTab.flags)

      NavigationStack(path: $router.inboxPath) {
        VStack(spacing: 0) {
          PushPrePermissionCard()
            .padding(.horizontal, PHSpacing.lg)
            .padding(.top, PHSpacing.sm)
          InboxView(context: context) { open($0) }
        }
        .background(PHColor.background)
        .navigationDestination(for: Route.self) { destination(for: $0) }
      }
      .tabItem { Label("Inbox", systemImage: "bell") }
      .badge(unreadCount)
      .tag(AppTab.inbox)
    }
    .tint(PHColor.accent)
    .task {
      unreadCount = await InboxBadge.unreadCount(context: context)
    }
    .sheet(isPresented: $showingSwitcher) {
      NavigationStack {
        ProjectPickerView { projectID in
          showingSwitcher = false
          Task { await session.selectProject(projectID) }
        }
      }
      .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $showingSettings) {
      NavigationStack {
        SettingsView(
          email: session.user?.email,
          regionName: context.region.displayName
        ) {
          showingSettings = false
          Task { await session.signOut() }
        }
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { showingSettings = false }
          }
        }
      }
    }
    .onOpenURL { url in
      _ = router.handle(deepLink: url, currentProjectID: context.projectID)
    }
    .task { await session.loadProjects() }
  }

  @ViewBuilder
  private func destination(for route: Route) -> some View {
    switch route {
    case .dashboard(let id):
      DashboardDetailView(context: context, dashboardID: id)
    case .insight(let id):
      InsightDetailView(context: context, insightID: id)
    case .flag(let id):
      FlagDetailView(context: context, flagID: id)
    case .errorsList:
      ErrorsListView(context: context) { router.pushOnSelectedTab(.errorIssue(id: $0)) }
    case .errorIssue(let id):
      ErrorIssueDetailView(context: context, issueID: id)
    case .liveEvents:
      LiveEventsView(context: context)
    }
  }

  private func open(_ destination: InboxDestination) {
    switch destination {
    case .insight(let id):
      router.open(.insight(id: id))
    case .flag(let id):
      router.open(.flag(id: id))
    case .errorIssue(let id):
      router.pushOnSelectedTab(.errorIssue(id: id))
    case .web(let path):
      openWeb(path: path)
    }
  }

  private func openWeb(path: String) {
    let url = context.region.apiBaseURL.appending(path: "/project/\(context.projectID)\(path)")
    openURL(url)
  }
}
