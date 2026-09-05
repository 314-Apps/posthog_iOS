import FeatureDashboards
import FeatureFlags
import FeatureInsights
import FeatureSettings
import PostHogAPI
import PostHogDesignSystem
import PostHogQueries
import SwiftUI

/// The signed-in tab shell: Home, Dashboards, Flags (Phase 1's fixed slots).
struct SignedInShell: View {
  @Environment(SessionStore.self) private var session
  @State private var router = Router()
  @State private var showingSwitcher = false
  @State private var showingSettings = false

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
          onOpenSwitcher: { showingSwitcher = true }
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
    }
    .tint(PHColor.accent)
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
    }
  }
}
