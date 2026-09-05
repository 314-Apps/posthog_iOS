import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Home — the project pulse. Every card paints from cache instantly and
/// refreshes in the background; each taps through to a deeper surface.
struct HomeView: View {
  @State private var model: HomeModel
  private let projectName: String?
  private let onOpenDashboard: (Int) -> Void
  private let onOpenFlags: () -> Void
  private let onOpenSettings: () -> Void
  private let onOpenSwitcher: () -> Void

  init(
    context: ProjectContext,
    projectName: String?,
    onOpenDashboard: @escaping (Int) -> Void,
    onOpenFlags: @escaping () -> Void,
    onOpenSettings: @escaping () -> Void,
    onOpenSwitcher: @escaping () -> Void
  ) {
    self._model = State(initialValue: HomeModel(context: context))
    self.projectName = projectName
    self.onOpenDashboard = onOpenDashboard
    self.onOpenFlags = onOpenFlags
    self.onOpenSettings = onOpenSettings
    self.onOpenSwitcher = onOpenSwitcher
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
    .task { await model.load() }
    .refreshable { await model.load(forceRefresh: true) }
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
          HStack(alignment: .bottom, spacing: PHSpacing.lg) {
            Text(MetricFormat.full(series.first(where: { !$0.isPrevious })?.count ?? 0))
              .font(PHFont.metricLarge())
              .phMetricStyle()
              .foregroundStyle(PHColor.textPrimary)
              .contentTransition(.numericText())
            TrendsChartView(series: series.filter { !$0.isPrevious }, style: .bar, showsAxes: false)
              .frame(height: 48)
          }
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
        WebOverviewGridView(items: Array(items.prefix(4)))
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

@MainActor
@Observable
final class HomeModel {
  private(set) var todaySeries: [SeriesResult]?
  private(set) var todayDelta: Double?
  private(set) var webOverview: [WebOverviewItem]?
  private(set) var dashboards: [DashboardSummary] = []
  private(set) var flags: [FeatureFlag] = []

  private let context: ProjectContext

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
    let current = series.first { !$0.isPrevious }?.count ?? 0
    let previous = series.first(where: \.isPrevious)?.count ?? 0
    todayDelta = previous > 0 ? (current - previous) / previous : nil
  }

  private func loadWebOverview() async {
    let query = DataQuery.webOverview(WebOverviewQuery.make(dateFrom: "-7d"))
    guard let result = try? await context.runner.run(query, projectID: context.projectID, refresh: .lazyAsync),
      case .webOverview(let items) = result, !items.isEmpty
    else { return }
    webOverview = items
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
