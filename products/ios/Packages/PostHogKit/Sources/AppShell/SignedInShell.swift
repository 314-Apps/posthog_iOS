import CoreSpotlight
import FeatureActivity
import FeatureDashboards
import FeatureErrors
import FeatureExperiments
import FeatureFlags
import FeatureInbox
import FeatureInsights
import FeatureLive
import FeatureMax
import FeaturePeople
import FeatureReplay
import FeatureSQL
import FeatureSettings
import FeatureSurveys
import FeatureWeb
import PostHogAPI
import PostHogDesignSystem
import PostHogQueries
import SwiftUI

/// The signed-in tab shell: Home, Dashboards, Flags (Phase 1's fixed slots).
struct SignedInShell: View {
  @Environment(SessionStore.self) private var session
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @State private var router = Router()
  @State private var showingSwitcher = false
  @State private var showingSettings = false
  @State private var showingMaxHistory = false
  @State private var unreadCount = 0
  @AppStorage("tab.slot3") private var slot3 = PinnableTab.flags.rawValue

  private var pinnedTab: PinnableTab { PinnableTab(rawValue: slot3) ?? .flags }

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
          onOpenProduct: { open(product: $0) },
          onOpenPerson: { router.pushOnSelectedTab(.person(id: $0)) }
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
        slot3Root
          .navigationDestination(for: Route.self) { destination(for: $0) }
      }
      .tabItem { Label(pinnedTab.title, systemImage: pinnedTab.systemImage) }
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

      NavigationStack(path: $router.maxPath) {
        MaxChatView(context: context, tokenProvider: session.tokenProvider) {
          router.pushOnSelectedTab(.person(id: $0))
        }
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              showingMaxHistory = true
            } label: {
              Image(systemName: "clock.arrow.circlepath")
            }
            .accessibilityLabel("Conversation history")
          }
        }
        .navigationDestination(for: Route.self) { destination(for: $0) }
      }
      .tabItem { Label("Max", systemImage: "sparkles") }
      .tag(AppTab.max)
    }
    .tint(PHColor.accent)
    .sheet(isPresented: $showingMaxHistory) {
      NavigationStack {
        MaxHistoryView(context: context) { showingMaxHistory = false }
      }
      .presentationDetents([.medium, .large])
    }
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
          regionName: context.region.displayName,
          billingDestination: { BillingView(context: context) },
          onSignOut: {
            showingSettings = false
            Task { await session.signOut() }
          }
        )
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
    .onAppear { consumeHandoff() }
    .onContinueUserActivity(CSSearchableItemActionType) { activity in
      guard
        let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
        let route = SpotlightIndexer.route(for: identifier, currentProjectID: context.projectID)
      else { return }
      router.open(route)
    }
    .onChange(of: router.selectedTab) { _, tab in
      Analytics.screen(tab.rawValue)
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { consumeHandoff() }
    }
  }

  private func consumeHandoff() {
    if let tab = TabHandoff.consume() {
      router.selectedTab = tab
    }
  }

  @ViewBuilder
  private var slot3Root: some View {
    switch pinnedTab {
    case .flags:
      FlagsListView(context: context) { router.open(.flag(id: $0)) }
    case .errors:
      ErrorsListView(context: context) { router.pushOnSelectedTab(.errorIssue(id: $0)) }
    case .replay:
      ReplayListView(context: context) { router.pushOnSelectedTab(.replay(sessionID: $0)) }
    case .web:
      WebAnalyticsView(context: context)
    }
  }

  private func open(product: HomeProduct) {
    if let route = product.route {
      router.pushOnSelectedTab(route)
    } else if let path = product.webPath {
      openWeb(path: path)
    }
  }

  @ViewBuilder
  // A route-to-screen mapping switch grows with every surface by design.
  // swiftlint:disable:next cyclomatic_complexity
  private func destination(for route: Route) -> some View {
    switch route {
    case .dashboard(let id):
      DashboardDetailView(context: context, dashboardID: id) {
        router.pushOnSelectedTab(.person(id: $0))
      }
    case .insight(let id):
      InsightDetailView(context: context, insightID: id) {
        router.pushOnSelectedTab(.person(id: $0))
      }
    case .flag(let id):
      FlagDetailView(context: context, flagID: id)
    case .errorsList:
      ErrorsListView(context: context) { router.pushOnSelectedTab(.errorIssue(id: $0)) }
    case .errorIssue(let id):
      ErrorIssueDetailView(context: context, issueID: id)
    case .liveEvents:
      LiveEventsView(context: context)
    case .replayList:
      ReplayListView(context: context) { router.pushOnSelectedTab(.replay(sessionID: $0)) }
    case .replay(let sessionID):
      ReplayDetailView(context: context, sessionID: sessionID) { openWeb(path: $0) }
    case .experimentsList:
      ExperimentsListView(context: context) { router.pushOnSelectedTab(.experiment(id: $0)) }
    case .experiment(let id):
      ExperimentDetailView(context: context, experimentID: id) { openWeb(path: $0) }
    case .surveysList:
      SurveysListView(context: context) { router.pushOnSelectedTab(.survey(id: $0)) }
    case .survey(let id):
      SurveyDetailView(context: context, surveyID: id)
    case .webAnalytics:
      WebAnalyticsView(context: context)
    case .peopleList:
      PeopleView(context: context) { router.pushOnSelectedTab(.person(id: $0)) }
    case .person(let id):
      PersonDetailView(context: context, personID: id)
    case .sqlRunner:
      SQLRunnerView(context: context)
    case .activityFeed:
      ActivityFeedView(context: context)
    case .annotations:
      AnnotationsView(context: context)
    case .billing:
      BillingView(context: context)
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
