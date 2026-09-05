import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Error tracking issues, query-driven: every filter re-runs the
/// ErrorTrackingQuery server-side. Rows open detail, where triage happens.
public struct ErrorsListView: View {
  enum StatusFilter: String, CaseIterable {
    case active = "Active"
    case resolved = "Resolved"
    case suppressed = "Suppressed"
    case all = "All"

    var queryValue: String {
      switch self {
      case .active: "active"
      case .resolved: "resolved"
      case .suppressed: "suppressed"
      case .all: "all"
      }
    }
  }

  enum Sort: String, CaseIterable {
    case lastSeen = "Last seen"
    case firstSeen = "First seen"
    case occurrences = "Occurrences"
    case users = "Users"

    var orderBy: String {
      switch self {
      case .lastSeen: "last_seen"
      case .firstSeen: "first_seen"
      case .occurrences: "occurrences"
      case .users: "users"
      }
    }
  }

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

  @State private var model: ErrorsListModel

  private let onOpen: (String) -> Void

  public init(context: ProjectContext, onOpen: @escaping (String) -> Void) {
    self._model = State(initialValue: ErrorsListModel(context: context))
    self.onOpen = onOpen
  }

  public var body: some View {
    VStack(spacing: PHSpacing.sm) {
      filters
      content
    }
    .background(PHColor.background)
    .navigationTitle("Errors")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        sortMenu
      }
    }
    .onChange(of: model.sort) {
      Task { await model.reload() }
    }
    .task { await model.load() }
  }

  private var filters: some View {
    VStack(spacing: PHSpacing.sm) {
      chipRow(StatusFilter.allCases, selection: model.status) { filter in
        model.status = filter
        Task { await model.reload() }
      }
      chipRow(DatePreset.allCases, selection: model.datePreset) { preset in
        model.datePreset = preset
        Task { await model.reload() }
      }
    }
    .padding(.top, PHSpacing.sm)
  }

  private func chipRow<Option: RawRepresentable & Hashable>(
    _ options: [Option],
    selection: Option,
    onSelect: @escaping (Option) -> Void
  ) -> some View where Option.RawValue == String {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: PHSpacing.sm) {
        ForEach(options, id: \.self) { option in
          FilterChip(option.rawValue, isSelected: selection == option) {
            onSelect(option)
          }
        }
      }
      .padding(.horizontal, PHSpacing.lg)
    }
  }

  private var sortMenu: some View {
    Menu {
      Picker("Sort by", selection: $model.sort) {
        ForEach(Sort.allCases, id: \.self) { sort in
          Text(sort.rawValue).tag(sort)
        }
      }
    } label: {
      Image(systemName: "arrow.up.arrow.down")
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      List {
        ForEach(0..<6, id: \.self) { _ in
          SkeletonView(cornerRadius: 10).frame(height: 96).listRowBackground(Color.clear)
        }
      }
      .listStyle(.plain)
    case .failed(let message):
      EmptyStateView(
        systemImage: "wifi.exclamationmark",
        title: "Couldn't load issues",
        message: message,
        actionTitle: "Retry"
      ) {
        Task { await model.load(forceRefresh: true) }
      }
      .frame(maxHeight: .infinity)
    case .loaded where model.rows.isEmpty:
      EmptyStateView(
        systemImage: "ladybug",
        title: "No issues here",
        message: "Exceptions your SDKs capture show up here."
      )
      .frame(maxHeight: .infinity)
    case .loaded:
      List(model.rows) { row in
        rowView(row)
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .refreshable { await model.load(forceRefresh: true) }
    }
  }

  private func rowView(_ row: ErrorTrackingRow) -> some View {
    Button {
      onOpen(row.id)
    } label: {
      VStack(alignment: .leading, spacing: PHSpacing.xs) {
        HStack(spacing: PHSpacing.sm) {
          Text(row.displayTitle)
            .font(.body.weight(.semibold))
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(1)
          Spacer()
          ErrorStatusBadge(status: row.status)
        }
        if let subtitle = row.displaySubtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(PHColor.textSecondary)
            .lineLimit(1)
        }
        if !row.volume.isEmpty {
          VolumeSparkline(values: row.volume)
        }
        Text("\(MetricFormat.compact(row.occurrences)) events · \(MetricFormat.compact(row.users)) users")
          .font(.caption.weight(.semibold))
          .foregroundStyle(PHColor.textSecondary)
          .monospacedDigit()
      }
      .padding(.vertical, PHSpacing.xs)
    }
  }
}

@MainActor
@Observable
final class ErrorsListModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var rows: [ErrorTrackingRow] = []
  var status: ErrorsListView.StatusFilter = .active
  var sort: ErrorsListView.Sort = .lastSeen
  var datePreset: ErrorsListView.DatePreset = .week

  private let context: ProjectContext
  /// Bumped per load so a slow response for old filters cannot overwrite fresh rows.
  private var generation = 0

  init(context: ProjectContext) {
    self.context = context
  }

  /// Filter changes drop stale rows so skeletons show while the query re-runs.
  func reload() async {
    rows = []
    state = .loading
    await load(forceRefresh: true)
  }

  func load(forceRefresh: Bool = false) async {
    generation += 1
    let requested = generation
    let key = context.cacheKey("errors-list")
    if !forceRefresh, rows.isEmpty, isDefaultFilters {
      if let hit = await context.cache.read(key, as: [ErrorTrackingRow].self, staleAfter: 120) {
        rows = hit.value
        state = .loaded
        if !hit.isStale { return }
      }
    }
    do {
      let result = try await context.runner.run(query, projectID: context.projectID)
      guard requested == generation else { return }
      if case .unknown(let body) = result {
        rows = ErrorTrackingRows.parse(body)
      } else {
        rows = []
      }
      state = .loaded
      if isDefaultFilters {
        await context.cache.write(key, value: rows)
      }
    } catch {
      guard requested == generation, rows.isEmpty else { return }
      state = .failed("Check your connection and try again.")
    }
  }

  /// The cache holds only the default view — filtered results must not paint
  /// the next cold launch.
  private var isDefaultFilters: Bool {
    status == .active && sort == .lastSeen && datePreset == .week
  }

  private var query: DataQuery {
    DataQuery(raw: [
      "kind": "ErrorTrackingQuery",
      "orderBy": .string(sort.orderBy),
      "dateRange": ["date_from": .string(datePreset.dateFrom)],
      "status": .string(status.queryValue),
      "volumeResolution": 20,
    ])
  }
}
