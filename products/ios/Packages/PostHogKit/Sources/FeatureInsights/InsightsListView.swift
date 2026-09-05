import PostHogAPI
import PostHogDesignSystem
import PostHogQueries
import SwiftUI

/// Saved insights: server-side search, newest first.
public struct InsightsListView: View {
  @State private var model: InsightsListModel
  private let onOpen: (Int) -> Void

  public init(context: ProjectContext, onOpen: @escaping (Int) -> Void) {
    self._model = State(initialValue: InsightsListModel(context: context))
    self.onOpen = onOpen
  }

  public var body: some View {
    Group {
      switch model.state {
      case .loading:
        List {
          ForEach(0..<8, id: \.self) { _ in
            SkeletonView(cornerRadius: 10).frame(height: 40).listRowBackground(Color.clear)
          }
        }
        .listStyle(.plain)
      case .failed(let message):
        EmptyStateView(
          systemImage: "wifi.exclamationmark",
          title: "Couldn't load insights",
          message: message,
          actionTitle: "Retry"
        ) {
          Task { await model.load() }
        }
      case .loaded where model.insights.isEmpty:
        EmptyStateView(
          systemImage: "chart.xyaxis.line",
          title: "No insights",
          message: "Saved insights show up here."
        )
      case .loaded:
        List(model.insights) { insight in
          Button {
            onOpen(insight.id)
          } label: {
            HStack(spacing: PHSpacing.md) {
              Image(systemName: icon(for: insight))
                .font(.subheadline)
                .foregroundStyle(PHColor.series(at: 0))
                .frame(width: 22)
              VStack(alignment: .leading, spacing: 1) {
                Text(insight.displayName)
                  .font(.body.weight(.semibold))
                  .foregroundStyle(PHColor.textPrimary)
                  .lineLimit(1)
                if let description = insight.description, !description.isEmpty {
                  Text(description)
                    .font(.caption)
                    .foregroundStyle(PHColor.textSecondary)
                    .lineLimit(1)
                }
              }
              Spacer()
              if insight.favorited {
                Image(systemName: "star.fill")
                  .font(.caption)
                  .foregroundStyle(PHColor.highlight)
              }
              Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(PHColor.textTertiary)
            }
            .frame(minHeight: 44)
          }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
      }
    }
    .background(PHColor.background)
    .searchable(text: $model.search, prompt: "Search insights")
    .navigationTitle("Insights")
    .task { await model.load() }
    .task(id: model.search) {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      await model.load()
    }
  }

  private func icon(for insight: Insight) -> String {
    let kind = insight.query.map { DataQuery(raw: $0).renderSource.kind } ?? ""
    return switch kind {
    case "FunnelsQuery": "chart.bar.xaxis"
    case "RetentionQuery": "square.grid.3x3.bottomleft.filled"
    case "PathsQuery": "arrow.triangle.branch"
    case "HogQLQuery", "EventsQuery": "tablecells"
    default: "chart.xyaxis.line"
    }
  }
}

@MainActor
@Observable
final class InsightsListModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var insights: [Insight] = []
  var search = ""

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  func load() async {
    do {
      let page = try await context.client.insights(
        projectID: context.projectID,
        search: search.isEmpty ? nil : search
      )
      insights = page.results
      state = .loaded
    } catch {
      if insights.isEmpty {
        state = .failed("Check your connection and try again.")
      }
    }
  }
}
