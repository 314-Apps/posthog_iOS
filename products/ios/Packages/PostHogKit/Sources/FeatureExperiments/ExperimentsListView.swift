import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Experiments root, read-only: launching and concluding stay on the web, the
/// list answers "what is running right now" at a glance.
public struct ExperimentsListView: View {
  enum LifecycleFilter: String, CaseIterable {
    case all = "All"
    case running = "Running"
    case draft = "Draft"
    case complete = "Complete"

    var lifecycle: Experiment.Lifecycle? {
      switch self {
      case .all: nil
      case .running: .running
      case .draft: .draft
      case .complete: .complete
      }
    }
  }

  @State private var model: ExperimentsListModel

  private let onOpen: (Int) -> Void

  public init(context: ProjectContext, onOpen: @escaping (Int) -> Void) {
    self._model = State(initialValue: ExperimentsListModel(context: context))
    self.onOpen = onOpen
  }

  public var body: some View {
    VStack(spacing: PHSpacing.sm) {
      chips
      content
    }
    .background(PHColor.background)
    .navigationTitle("Experiments")
    .task { await model.load() }
  }

  private var chips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: PHSpacing.sm) {
        ForEach(LifecycleFilter.allCases, id: \.self) { filter in
          FilterChip(filter.rawValue, isSelected: model.filter == filter) {
            model.filter = filter
          }
        }
      }
      .padding(.horizontal, PHSpacing.lg)
    }
    .padding(.top, PHSpacing.sm)
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      List {
        ForEach(0..<8, id: \.self) { _ in
          SkeletonView(cornerRadius: 10).frame(height: 56).listRowBackground(Color.clear)
        }
      }
      .listStyle(.plain)
    case .failed(let message):
      EmptyStateView(
        systemImage: "wifi.exclamationmark",
        title: "Couldn't load experiments",
        message: message,
        actionTitle: "Retry"
      ) {
        Task { await model.load(forceRefresh: true) }
      }
      .frame(maxHeight: .infinity)
    case .loaded where model.filtered.isEmpty:
      EmptyStateView(
        systemImage: "testtube.2",
        title: "No experiments yet",
        message: "Experiments you create on the web show up here."
      )
      .frame(maxHeight: .infinity)
    case .loaded:
      List(model.filtered) { experiment in
        row(experiment)
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .refreshable { await model.load(forceRefresh: true) }
    }
  }

  private func row(_ experiment: Experiment) -> some View {
    Button {
      onOpen(experiment.id)
    } label: {
      VStack(alignment: .leading, spacing: PHSpacing.xs) {
        HStack(spacing: PHSpacing.sm) {
          Text(experiment.name)
            .font(.body.weight(.semibold))
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(1)
          Spacer()
          ExperimentLifecycleBadge(lifecycle: experiment.lifecycle)
        }
        if let key = experiment.featureFlagKey, !key.isEmpty {
          Text(key)
            .font(PHFont.mono(12))
            .foregroundStyle(PHColor.textSecondary)
            .lineLimit(1)
        }
        if let started = experiment.startDate {
          Text("Started \(RelativeDateFormat.ago(started))")
            .font(.caption)
            .foregroundStyle(PHColor.textTertiary)
        }
      }
      .padding(.vertical, PHSpacing.xs)
      .frame(minHeight: 44)
    }
  }
}

@MainActor
@Observable
final class ExperimentsListModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var experiments: [Experiment] = []
  var filter: ExperimentsListView.LifecycleFilter = .all

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  var filtered: [Experiment] {
    experiments.filter { experiment in
      if experiment.archived { return false }
      guard let lifecycle = filter.lifecycle else { return true }
      return experiment.lifecycle == lifecycle
    }
  }

  func load(forceRefresh: Bool = false) async {
    let key = context.cacheKey("experiments-list")
    if !forceRefresh, experiments.isEmpty {
      if let hit = await context.cache.read(key, as: [Experiment].self, staleAfter: 300) {
        experiments = hit.value
        state = .loaded
        if !hit.isStale { return }
      }
    }
    do {
      let page = try await context.client.experiments(projectID: context.projectID)
      experiments = page.results
      state = .loaded
      await context.cache.write(key, value: experiments)
    } catch {
      if experiments.isEmpty {
        state = .failed("Check your connection and try again.")
      }
    }
  }
}
