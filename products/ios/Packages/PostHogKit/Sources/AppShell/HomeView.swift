import PostHogAPI
import PostHogDesignSystem
import PostHogDrilldown
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Home — the project pulse. Every card paints from cache instantly and
/// refreshes in the background; each taps through to a deeper surface.
struct HomeView: View {
  @State private var model: HomeModel
  @State private var drilldown: DrilldownTarget?
  @State private var inspecting: QueryInspection?
  private let projectName: String?
  private let onOpenDashboard: (Int) -> Void
  private let onOpenFlags: () -> Void
  private let onOpenSettings: () -> Void
  private let onOpenSwitcher: () -> Void
  private let onOpenProduct: (HomeProduct) -> Void
  private let onOpenPerson: (String) -> Void

  init(
    context: ProjectContext,
    projectName: String?,
    onOpenDashboard: @escaping (Int) -> Void,
    onOpenFlags: @escaping () -> Void,
    onOpenSettings: @escaping () -> Void,
    onOpenSwitcher: @escaping () -> Void,
    onOpenProduct: @escaping (HomeProduct) -> Void,
    onOpenPerson: @escaping (String) -> Void
  ) {
    self._model = State(initialValue: HomeModel(context: context))
    self.projectName = projectName
    self.onOpenDashboard = onOpenDashboard
    self.onOpenFlags = onOpenFlags
    self.onOpenSettings = onOpenSettings
    self.onOpenSwitcher = onOpenSwitcher
    self.onOpenProduct = onOpenProduct
    self.onOpenPerson = onOpenPerson
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        todayCard
        if let items = model.webOverview {
          webCard(items)
        }
        dashboardsSection
        flagsSection
        productsSection
      }
      .padding(.horizontal, PHSpacing.lg)
      .padding(.bottom, PHSpacing.xl)
    }
    .background(PHColor.background)
    .navigationTitle("Home")
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button(action: onOpenSwitcher) {
          HStack(spacing: 6) {
            Text(projectName ?? "Project")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(PHColor.textPrimary)
            Image(systemName: "chevron.down")
              .font(.caption2.weight(.bold))
              .foregroundStyle(PHColor.textSecondary)
          }
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button(action: onOpenSettings) {
          Image(systemName: "person.crop.circle")
            .font(.title3)
            .foregroundStyle(PHColor.textPrimary)
        }
        .accessibilityLabel("Settings")
      }
    }
    .task {
      model.widgetProjectName = projectName
      await model.load()
    }
    .refreshable { await model.load(forceRefresh: true) }
    .actorsDrilldown($drilldown, context: model.context, onOpenPerson: onOpenPerson)
    .queryProvenance($inspecting)
  }

  private var todayCard: some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.sm) {
        HStack {
          PHCardLabel("Unique users · today")
          Spacer()
          if let delta = model.todayDelta {
            DeltaBadge(fraction: delta)
          }
        }
        if let series = model.todaySeries {
          Button {
            guard let query = model.todayQuery else { return }
            drilldown = DrilldownTarget(source: query, drill: .aggregate)
          } label: {
            HStack(alignment: .bottom, spacing: PHSpacing.lg) {
              Text(MetricFormat.full(series.first(where: { !$0.isPrevious })?.count ?? 0))
                .font(PHFont.metricLarge())
                .phMetricStyle()
                .foregroundStyle(PHColor.textPrimary)
                .contentTransition(.numericText())
              TrendsChartView(series: series.filter { !$0.isPrevious }, style: .bar, showsAxes: false)
                .frame(height: 48)
            }
            .contentShape(Rectangle())
            // Grouped so VoiceOver reads the metric once, instead of the number
            // and then every bar of the sparkline.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Unique users today")
            .accessibilityValue(MetricFormat.full(series.first(where: { !$0.isPrevious })?.count ?? 0))
          }
          .buttonStyle(.plain)
          .disabled(model.todayQuery == nil)
          .accessibilityHint("Shows the people counted here")
        } else {
          SkeletonView().frame(height: 56)
        }
      }
    }
  }

  private func webCard(_ items: [WebOverviewItem]) -> some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Web · last 7 days")
        WebOverviewGridView(items: Array(items.prefix(4))) { _ in
          guard let query = model.webOverviewQuery else { return }
          inspecting = QueryInspection(query: query)
        }
      }
    }
  }

  private var dashboardsSection: some View {
    VStack(alignment: .leading, spacing: PHSpacing.sm) {
      Text("Pinned dashboards")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(PHColor.textPrimary)
        .padding(.horizontal, 2)
      if model.dashboards.isEmpty {
        SkeletonView(cornerRadius: PHRadius.control).frame(height: 92)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: PHSpacing.sm + 2) {
            ForEach(model.dashboards.prefix(8)) { dashboard in
              Button {
                onOpenDashboard(dashboard.id)
              } label: {
                VStack(alignment: .leading, spacing: PHSpacing.sm) {
                  Image(systemName: dashboard.pinned ? "pin.fill" : "rectangle.grid.2x2")
                    .font(.body)
                    .foregroundStyle(PHColor.accent)
                  Spacer(minLength: 0)
                  Text(dashboard.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PHColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                }
                .padding(PHSpacing.md)
                .frame(width: 170, height: 92, alignment: .topLeading)
                .background(PHColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: PHRadius.control, style: .continuous))
                .overlay(
                  RoundedRectangle(cornerRadius: PHRadius.control, style: .continuous)
                    .strokeBorder(PHColor.border, lineWidth: 1)
                )
              }
              .buttonStyle(.plain)
            }
          }
          .padding(2)
        }
      }
    }
  }

  private var productsSection: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: PHSpacing.sm + 2) {
      ForEach(HomeProduct.allCases) { product in
        productChip(product.title, systemImage: product.systemImage) { onOpenProduct(product) }
      }
    }
  }

  private func productChip(
    _ title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: systemImage)
          .font(.body.weight(.medium))
          .foregroundStyle(PHColor.textPrimary)
        Text(title)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(PHColor.textSecondary)
      }
      .frame(maxWidth: .infinity, minHeight: 58)
      .background(PHColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: PHRadius.control, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: PHRadius.control, style: .continuous)
          .strokeBorder(PHColor.border, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  private var flagsSection: some View {
    VStack(alignment: .leading, spacing: PHSpacing.sm) {
      HStack {
        Text("Feature flags")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(PHColor.textPrimary)
        Spacer()
        Button("See all", action: onOpenFlags)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(PHColor.link)
      }
      .padding(.horizontal, 2)
      PHCard {
        if model.flags.isEmpty {
          SkeletonView().frame(height: 90)
        } else {
          VStack(spacing: 0) {
            ForEach(Array(model.flags.prefix(3).enumerated()), id: \.element.id) { index, flag in
              if index > 0 {
                Divider().overlay(PHColor.divider)
              }
              HStack {
                Text(flag.key)
                  .font(PHFont.mono())
                  .foregroundStyle(PHColor.textPrimary)
                  .lineLimit(1)
                Spacer()
                Circle()
                  .fill(flag.active ? PHColor.successFill : PHColor.textInactive.opacity(0.4))
                  .frame(width: 9, height: 9)
              }
              .frame(minHeight: 42)
            }
          }
        }
      }
    }
  }
}

/// Every product reachable from the Home grid. Native surfaces route in-app;
/// web cases open the matching web page so nothing dead-ends.
enum HomeProduct: String, CaseIterable, Identifiable {
  case errors, live, replay, persons, web, experiments, surveys, sql, activity, annotations
  case notebooks, heatmaps

  var id: String { rawValue }

  var title: String {
    switch self {
    case .errors: "Errors"
    case .live: "Live"
    case .replay: "Replay"
    case .persons: "People"
    case .web: "Web"
    case .experiments: "Experiments"
    case .surveys: "Surveys"
    case .sql: "SQL"
    case .activity: "Activity"
    case .annotations: "Annotations"
    case .notebooks: "Notebooks"
    case .heatmaps: "Heatmaps"
    }
  }

  var systemImage: String {
    switch self {
    case .errors: "ant"
    case .live: "bolt"
    case .replay: "play.rectangle"
    case .persons: "person.2"
    case .web: "globe"
    case .experiments: "testtube.2"
    case .surveys: "bubble.left.and.bubble.right"
    case .sql: "terminal"
    case .activity: "clock.arrow.circlepath"
    case .annotations: "text.bubble"
    case .notebooks: "book.closed"
    case .heatmaps: "flame"
    }
  }

  /// Native route, or nil for deliberate web surfaces.
  var route: Route? {
    switch self {
    case .errors: .errorsList
    case .live: .liveEvents
    case .replay: .replayList
    case .persons: .peopleList
    case .web: .webAnalytics
    case .experiments: .experimentsList
    case .surveys: .surveysList
    case .sql: .sqlRunner
    case .activity: .activityFeed
    case .annotations: .annotations
    case .notebooks, .heatmaps: nil
    }
  }

  var webPath: String? {
    switch self {
    case .notebooks: "/notebooks"
    case .heatmaps: "/heatmaps"
    default: nil
    }
  }
}

@MainActor
@Observable
final class HomeModel {
  var widgetProjectName: String?
  private(set) var todaySeries: [SeriesResult]?
  private(set) var todayQuery: DataQuery?
  private(set) var todayDelta: Double?
  private(set) var webOverview: [WebOverviewItem]?
  private(set) var webOverviewQuery: DataQuery?
  private(set) var dashboards: [DashboardSummary] = []
  private(set) var flags: [FeatureFlag] = []

  let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  func load(forceRefresh: Bool = false) async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.loadToday() }
      group.addTask { await self.loadWebOverview() }
      group.addTask { await self.loadDashboards(forceRefresh: forceRefresh) }
      group.addTask { await self.loadFlags(forceRefresh: forceRefresh) }
    }
    SpotlightIndexer.index(dashboards: dashboards, flags: flags, projectID: context.projectID)
  }

  private func loadToday() async {
    let query = DataQuery.trends(
      TrendsQuery.make(
        series: [TrendsQuery.eventsNode(math: "dau")],
        interval: "hour",
        dateFrom: "dStart",
        compare: true
      )
    )
    guard let result = try? await context.runner.run(query, projectID: context.projectID, refresh: .blocking),
      case .series(let series) = result
    else { return }
    todaySeries = series
    todayQuery = query
    let current = series.first { !$0.isPrevious }?.count ?? 0
    let previous = series.first(where: \.isPrevious)?.count ?? 0
    todayDelta = previous > 0 ? (current - previous) / previous : nil
    WidgetSnapshotStore.write(
      WidgetSnapshot(
        projectName: widgetProjectName ?? "PostHog",
        value: current,
        deltaFraction: todayDelta,
        updatedAt: .now
      )
    )
  }

  private func loadWebOverview() async {
    let query = DataQuery.webOverview(WebOverviewQuery.make(dateFrom: "-7d"))
    guard let result = try? await context.runner.run(query, projectID: context.projectID, refresh: .lazyAsync),
      case .webOverview(let items) = result, !items.isEmpty
    else { return }
    webOverview = items
    webOverviewQuery = query
  }

  private func loadDashboards(forceRefresh: Bool) async {
    let key = context.cacheKey("dashboards-list")
    if !forceRefresh {
      if let hit = await context.cache.read(key, as: [DashboardSummary].self, staleAfter: 300) {
        dashboards = hit.value
        if !hit.isStale { return }
      }
    }
    guard let page = try? await context.client.dashboards(projectID: context.projectID) else { return }
    dashboards = page.results.sorted { lhs, rhs in
      if lhs.pinned != rhs.pinned { return lhs.pinned }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
    await context.cache.write(key, value: dashboards)
  }

  private func loadFlags(forceRefresh: Bool) async {
    let key = context.cacheKey("flags-list")
    if !forceRefresh, let hit = await context.cache.read(key, as: [FeatureFlag].self, staleAfter: 120) {
      flags = hit.value
      if !hit.isStale { return }
    }
    guard let page = try? await context.client.featureFlags(projectID: context.projectID) else { return }
    flags = page.results
    await context.cache.write(key, value: flags)
  }
}
