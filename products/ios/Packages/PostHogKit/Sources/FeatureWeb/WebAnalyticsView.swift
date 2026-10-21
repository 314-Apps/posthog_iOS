import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Web analytics: overview tiles plus ranked breakdowns, all served by the
/// query endpoint. One date preset drives every section.
public struct WebAnalyticsView: View {
  enum DatePreset: String, CaseIterable {
    case day = "24h"
    case week = "7d"
    case month = "30d"

    var dateFrom: String {
      switch self {
      case .day: "-24h"
      case .week: "-7d"
      case .month: "-30d"
      }
    }
  }

  @State private var model: WebAnalyticsModel

  public init(context: ProjectContext) {
    self._model = State(initialValue: WebAnalyticsModel(context: context))
  }

  public var body: some View {
    VStack(spacing: PHSpacing.sm) {
      dateChips
      ScrollView {
        VStack(spacing: PHSpacing.lg) {
          overviewSection
          breakdownSection("Top pages", state: model.pages)
          breakdownSection("Referrers", state: model.referrers)
          breakdownSection("Devices", state: model.devices)
        }
        .padding(.horizontal, PHSpacing.lg)
        .padding(.bottom, PHSpacing.xl)
      }
      .refreshable { await model.load() }
    }
    .background(PHColor.background)
    .navigationTitle("Web analytics")
    .task { await model.load() }
  }

  private var dateChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: PHSpacing.sm) {
        ForEach(DatePreset.allCases, id: \.self) { preset in
          FilterChip(preset.rawValue, isSelected: model.datePreset == preset) {
            model.datePreset = preset
            Task { await model.reload() }
          }
        }
      }
      .padding(.horizontal, PHSpacing.lg)
    }
    .padding(.top, PHSpacing.sm)
  }

  private var overviewSection: some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Overview")
        switch model.overview {
        case .loading:
          SkeletonView(cornerRadius: 10)
            .frame(height: 168)
        case .failed:
          sectionMessage("Couldn't load. Pull to refresh.")
        case .loaded(let items) where items.isEmpty:
          sectionMessage("No data for this range.")
        case .loaded(let items):
          WebOverviewGridView(items: items)
        }
      }
    }
  }

  private func breakdownSection(
    _ title: String,
    state: WebAnalyticsModel.SectionState<[WebStatsRow]>
  ) -> some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel(title)
        switch state {
        case .loading:
          VStack(spacing: PHSpacing.sm) {
            ForEach(0..<4, id: \.self) { _ in
              SkeletonView(cornerRadius: 6)
                .frame(height: 28)
            }
          }
        case .failed:
          sectionMessage("Couldn't load. Pull to refresh.")
        case .loaded(let rows) where rows.isEmpty:
          sectionMessage("No data for this range.")
        case .loaded(let rows):
          rankedList(rows)
        }
      }
    }
  }

  private func sectionMessage(_ text: String) -> some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(PHColor.textSecondary)
      .padding(.vertical, PHSpacing.md)
      .frame(maxWidth: .infinity)
  }

  private func rankedList(_ rows: [WebStatsRow]) -> some View {
    let maxVisitors = rows.map(\.visitors).max() ?? 0
    return VStack(spacing: PHSpacing.xs) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        rankedRow(row, fillFraction: maxVisitors > 0 ? row.visitors / maxVisitors : 0)
      }
    }
  }

  private func rankedRow(_ row: WebStatsRow, fillFraction: Double) -> some View {
    HStack(spacing: PHSpacing.md) {
      Text(row.label)
        .font(.subheadline)
        .foregroundStyle(PHColor.textPrimary)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 0)
      Text(MetricFormat.compact(row.visitors))
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(PHColor.textPrimary)
    }
    .padding(.horizontal, PHSpacing.sm)
    .padding(.vertical, 6)
    .background(alignment: .leading) {
      GeometryReader { proxy in
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(PHColor.series(at: 0).opacity(0.12))
          .frame(width: proxy.size.width * fillFraction)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

@MainActor
@Observable
final class WebAnalyticsModel {
  enum SectionState<Value: Sendable>: Sendable {
    case loading
    case loaded(Value)
    case failed
  }

  /// The ranked breakdowns, keyed by the server's `breakdownBy` value.
  enum Breakdown: String, CaseIterable, Sendable {
    case pages = "Page"
    case referrers = "InitialReferringDomain"
    case devices = "DeviceType"
  }

  private(set) var overview: SectionState<[WebOverviewItem]> = .loading
  private(set) var pages: SectionState<[WebStatsRow]> = .loading
  private(set) var referrers: SectionState<[WebStatsRow]> = .loading
  private(set) var devices: SectionState<[WebStatsRow]> = .loading
  var datePreset: WebAnalyticsView.DatePreset = .week

  private let context: ProjectContext
  /// Bumped per load so a slow response for an old date range cannot overwrite fresh sections.
  private var generation = 0

  init(context: ProjectContext) {
    self.context = context
  }

  /// Date changes drop every section back to skeletons before the re-run.
  func reload() async {
    overview = .loading
    pages = .loading
    referrers = .loading
    devices = .loading
    await load()
  }

  /// Runs all four sections concurrently; each one succeeds or fails on its own.
  func load() async {
    generation += 1
    let requested = generation
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.loadOverview(requested) }
      for breakdown in Breakdown.allCases {
        group.addTask { await self.loadBreakdown(breakdown, requested: requested) }
      }
    }
  }

  private func loadOverview(_ requested: Int) async {
    let query = DataQuery.webOverview(WebOverviewQuery.make(dateFrom: datePreset.dateFrom))
    do {
      let result = try await context.runner.run(query, projectID: context.projectID)
      guard requested == generation else { return }
      if case .webOverview(let items) = result {
        overview = .loaded(items)
      } else {
        overview = .loaded([])
      }
    } catch {
      guard requested == generation else { return }
      overview = .failed
    }
  }

  private func loadBreakdown(_ breakdown: Breakdown, requested: Int) async {
    do {
      let result = try await context.runner.run(tableQuery(breakdown), projectID: context.projectID)
      guard requested == generation else { return }
      if case .unknown(let body) = result {
        set(.loaded(WebStatsRows.parse(body)), for: breakdown)
      } else {
        set(.loaded([]), for: breakdown)
      }
    } catch {
      guard requested == generation else { return }
      set(.failed, for: breakdown)
    }
  }

  private func set(_ state: SectionState<[WebStatsRow]>, for breakdown: Breakdown) {
    switch breakdown {
    case .pages: pages = state
    case .referrers: referrers = state
    case .devices: devices = state
    }
  }

  /// WebStatsTableQuery is not a modeled kind; the runner hands its body back raw.
  private func tableQuery(_ breakdown: Breakdown) -> DataQuery {
    DataQuery(raw: [
      "kind": "WebStatsTableQuery",
      "breakdownBy": .string(breakdown.rawValue),
      "dateRange": ["date_from": .string(datePreset.dateFrom)],
      "properties": [],
      "limit": 10,
    ])
  }
}
