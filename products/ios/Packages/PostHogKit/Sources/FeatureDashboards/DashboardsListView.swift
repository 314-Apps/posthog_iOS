import PostHogAPI
import PostHogDesignSystem
import PostHogQueries
import SwiftUI

/// Dashboards root: pinned first, searchable, cached-first paint.
public struct DashboardsListView: View {
  @State private var model: DashboardsListModel
  private let onOpen: (Int) -> Void

  public init(context: ProjectContext, onOpen: @escaping (Int) -> Void) {
    self._model = State(initialValue: DashboardsListModel(context: context))
    self.onOpen = onOpen
  }

  public var body: some View {
    Group {
      switch model.state {
      case .loading:
        List {
          ForEach(0..<6, id: \.self) { _ in
            SkeletonView(cornerRadius: 10).frame(height: 44).listRowBackground(Color.clear)
          }
        }
        .listStyle(.plain)
      case .failed(let message):
        EmptyStateView(
          systemImage: "wifi.exclamationmark",
          title: "Couldn't load dashboards",
          message: message,
          actionTitle: "Retry"
        ) {
          Task { await model.load(forceRefresh: true) }
        }
      case .loaded where model.filtered.isEmpty:
        EmptyStateView(
          systemImage: "rectangle.grid.2x2",
          title: "No dashboards",
          message: "Dashboards you create on the web show up here."
        )
      case .loaded:
        List {
          if !model.pinned.isEmpty {
            Section("Pinned") {
              ForEach(model.pinned) { row($0) }
            }
          }
          Section(model.pinned.isEmpty ? "" : "All") {
            ForEach(model.unpinned) { row($0) }
          }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load(forceRefresh: true) }
      }
    }
    .background(PHColor.background)
    .searchable(text: $model.search, prompt: "Search dashboards")
    .navigationTitle("Dashboards")
    .task { await model.load() }
  }

  private func row(_ dashboard: DashboardSummary) -> some View {
    Button {
      onOpen(dashboard.id)
    } label: {
      HStack(spacing: PHSpacing.md) {
        Image(systemName: dashboard.pinned ? "pin.fill" : "rectangle.grid.2x2")
          .font(.subheadline)
          .foregroundStyle(dashboard.pinned ? PHColor.accent : PHColor.textTertiary)
          .frame(width: 22)
        VStack(alignment: .leading, spacing: 1) {
          Text(dashboard.name)
            .font(.body.weight(.semibold))
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(1)
          if let description = dashboard.description, !description.isEmpty {
            Text(description)
              .font(.caption)
              .foregroundStyle(PHColor.textSecondary)
              .lineLimit(1)
          }
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(PHColor.textTertiary)
      }
      .frame(minHeight: 44)
    }
  }
}

@MainActor
@Observable
final class DashboardsListModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var dashboards: [DashboardSummary] = []
  var search = ""

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  var filtered: [DashboardSummary] {
    guard !search.isEmpty else { return dashboards }
    return dashboards.filter { $0.name.localizedCaseInsensitiveContains(search) }
  }

  var pinned: [DashboardSummary] { filtered.filter(\.pinned) }
  var unpinned: [DashboardSummary] { filtered.filter { !$0.pinned } }

  func load(forceRefresh: Bool = false) async {
    let key = context.cacheKey("dashboards-list")
    if !forceRefresh, dashboards.isEmpty {
      if let hit = await context.cache.read(key, as: [DashboardSummary].self, staleAfter: 300) {
        dashboards = hit.value
        state = .loaded
        if !hit.isStale { return }
      }
    }
    do {
      let page = try await context.client.dashboards(projectID: context.projectID)
      dashboards = page.results.sorted { lhs, rhs in
        if lhs.pinned != rhs.pinned { return lhs.pinned }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
      state = .loaded
      await context.cache.write(key, value: dashboards)
    } catch {
      if dashboards.isEmpty {
        state = .failed("Check your connection and try again.")
      }
    }
  }
}
