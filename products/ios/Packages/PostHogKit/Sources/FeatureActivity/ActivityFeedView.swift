import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Project-wide activity feed. Scope chips re-request server-side; pages
/// stream in through `client.pages` and a sentinel row pulls the next one
/// when it scrolls into view.
public struct ActivityFeedView: View {
  enum ScopeFilter: String, CaseIterable {
    case all = "All"
    case featureFlags = "Feature flags"
    case insights = "Insights"
    case dashboards = "Dashboards"

    var scopeValue: String? {
      switch self {
      case .all: nil
      case .featureFlags: "FeatureFlag"
      case .insights: "Insight"
      case .dashboards: "Dashboard"
      }
    }
  }

  @State private var model: ActivityFeedModel

  public init(context: ProjectContext) {
    self._model = State(initialValue: ActivityFeedModel(context: context))
  }

  public var body: some View {
    VStack(spacing: 0) {
      chips
      content
    }
    .background(PHColor.background)
    .navigationTitle("Activity")
    .task { await model.load() }
  }

  private var chips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: PHSpacing.sm) {
        ForEach(ScopeFilter.allCases, id: \.self) { filter in
          FilterChip(filter.rawValue, isSelected: model.scope == filter) {
            model.scope = filter
            Task { await model.reload() }
          }
        }
      }
      .padding(.horizontal, PHSpacing.lg)
    }
    .padding(.vertical, PHSpacing.sm)
  }

  @ViewBuilder private var content: some View {
    switch model.state {
    case .loading:
      List {
        ForEach(0..<8, id: \.self) { _ in
          SkeletonView(cornerRadius: 10).frame(height: 52).listRowBackground(Color.clear)
        }
      }
      .listStyle(.plain)
    case .failed(let message):
      EmptyStateView(
        systemImage: "wifi.exclamationmark",
        title: "Couldn't load activity",
        message: message,
        actionTitle: "Retry"
      ) {
        Task { await model.reload() }
      }
      .frame(maxHeight: .infinity)
    case .loaded where model.entries.isEmpty:
      EmptyStateView(
        systemImage: "clock.arrow.circlepath",
        title: "No activity yet",
        message: "Changes people make in this project show up here."
      )
      .frame(maxHeight: .infinity)
    case .loaded:
      List {
        ForEach(model.entries) { entry in
          row(entry)
        }
        if model.hasMore {
          loadMoreSentinel
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .refreshable { await model.load() }
    }
  }

  private func row(_ entry: ProjectActivityEntry) -> some View {
    HStack(alignment: .top, spacing: PHSpacing.md) {
      Circle()
        .fill(PHColor.series(at: 0).opacity(0.8))
        .frame(width: 7, height: 7)
        .padding(.top, 5)
      VStack(alignment: .leading, spacing: 1) {
        Text(ActivityPhrasing.line(for: entry))
          .font(.subheadline)
          .foregroundStyle(PHColor.textPrimary)
        Text(RelativeDateFormat.ago(entry.createdAt))
          .font(.caption)
          .foregroundStyle(PHColor.textTertiary)
      }
    }
    .padding(.vertical, PHSpacing.xs)
  }

  private var loadMoreSentinel: some View {
    HStack {
      Spacer()
      ProgressView()
      Spacer()
    }
    .listRowBackground(Color.clear)
    .task { model.loadMore() }
  }
}

/// Builds the "<actor> <verb> <scope noun>" line for a feed row.
enum ActivityPhrasing {
  static func line(for entry: ProjectActivityEntry) -> String {
    "\(entry.actorName) \(verb(entry.activity)) \(noun(entry.scope))"
  }

  static func verb(_ activity: String) -> String {
    activity.replacingOccurrences(of: "_", with: " ")
  }

  static func noun(_ scope: String?) -> String {
    switch scope {
    case nil, "": "an item"
    case "FeatureFlag": "a feature flag"
    case "Insight": "an insight"
    case "Dashboard": "a dashboard"
    case "Experiment": "an experiment"
    case "Survey": "a survey"
    case "Notebook": "a notebook"
    case "Cohort": "a cohort"
    case .some(let other): withArticle(humanized(other))
    }
  }

  /// "SessionRecordingPlaylist" reads as "session recording playlist".
  private static func humanized(_ scope: String) -> String {
    var words = ""
    for character in scope {
      if character.isUppercase, !words.isEmpty { words.append(" ") }
      words.append(contentsOf: character.lowercased())
    }
    return words
  }

  private static func withArticle(_ noun: String) -> String {
    let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
    guard let first = noun.first else { return "an item" }
    return vowels.contains(first) ? "an \(noun)" : "a \(noun)"
  }
}

@MainActor
@Observable
final class ActivityFeedModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var entries: [ProjectActivityEntry] = []
  private(set) var hasMore = false
  var scope: ActivityFeedView.ScopeFilter = .all

  private let context: ProjectContext
  /// Bumped per load so a slow response for old filters cannot overwrite fresh rows.
  private var generation = 0
  private var streamTask: Task<Void, Never>?
  /// Sentinel demand: each yield lets the stream task pull one more page.
  private var demand: AsyncStream<Void>.Continuation?

  init(context: ProjectContext) {
    self.context = context
  }

  /// Scope changes drop stale rows so skeletons show while the feed re-fetches.
  func reload() async {
    entries = []
    hasMore = false
    state = .loading
    await load()
  }

  /// Streams pages from `client.pages`, holding between pages until the
  /// sentinel asks for more. Returns once the first page (or its error) landed
  /// so pull-to-refresh can end its spinner.
  func load() async {
    generation += 1
    let requested = generation
    streamTask?.cancel()
    demand?.finish()
    // Extra sentinel appearances collapse into at most one buffered pull.
    let (pageDemand, demandContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    demand = demandContinuation
    let stream = context.client.pages(
      startingAt: APIClient.activityLogRequest(projectID: context.projectID, scope: scope.scopeValue),
      of: ProjectActivityEntry.self
    )
    await withCheckedContinuation { (firstPage: CheckedContinuation<Void, Never>) in
      var pending: CheckedContinuation<Void, Never>? = firstPage
      let markFirstPageDone = {
        pending?.resume()
        pending = nil
      }
      streamTask = Task { [weak self] in
        defer { markFirstPageDone() }
        var isFirstPage = true
        var demandIterator = pageDemand.makeAsyncIterator()
        do {
          for try await page in stream {
            guard let self, self.apply(page, resetting: isFirstPage, requested: requested) else { return }
            isFirstPage = false
            markFirstPageDone()
            if page.next == nil { return }
            guard await demandIterator.next() != nil else { return }
          }
        } catch {
          PHLog.api.error("activity load failed: \(error)")
          self?.fail(requested: requested)
        }
      }
    }
  }

  func loadMore() {
    guard hasMore else { return }
    demand?.yield(())
  }

  private func apply(_ page: Paginated<ProjectActivityEntry>, resetting: Bool, requested: Int) -> Bool {
    guard requested == generation else { return false }
    if resetting {
      entries = page.results
    } else {
      entries += page.results
    }
    hasMore = page.next != nil
    state = .loaded
    return true
  }

  private func fail(requested: Int) {
    guard requested == generation else { return }
    if entries.isEmpty {
      state = .failed("Check your connection and try again.")
    }
  }
}
