import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Surveys root. Read-mostly: rows open detail, where launching and stopping
/// confirm. Creation and editing stay on the web.
public struct SurveysListView: View {
  enum LifecycleFilter: String, CaseIterable {
    case all = "All"
    case draft = "Draft"
    case running = "Running"
    case complete = "Complete"

    var lifecycle: Survey.Lifecycle? {
      switch self {
      case .all: nil
      case .draft: .draft
      case .running: .running
      case .complete: .complete
      }
    }
  }

  @State private var model: SurveysListModel

  private let onOpen: (String) -> Void

  public init(context: ProjectContext, onOpen: @escaping (String) -> Void) {
    self._model = State(initialValue: SurveysListModel(context: context))
    self.onOpen = onOpen
  }

  public var body: some View {
    VStack(spacing: 0) {
      chips
      content
    }
    .background(PHColor.background)
    .navigationTitle("Surveys")
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
    .padding(.vertical, PHSpacing.sm)
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      List {
        ForEach(0..<8, id: \.self) { _ in
          SkeletonView(cornerRadius: 10).frame(height: 48).listRowBackground(Color.clear)
        }
      }
      .listStyle(.plain)
    case .failed(let message):
      EmptyStateView(
        systemImage: "wifi.exclamationmark",
        title: "Couldn't load surveys",
        message: message,
        actionTitle: "Retry"
      ) {
        Task { await model.load(forceRefresh: true) }
      }
    case .loaded where model.filtered.isEmpty:
      EmptyStateView(
        systemImage: "text.bubble",
        title: "No surveys yet",
        message: "Surveys you create on the web show up here."
      )
    case .loaded:
      List(model.filtered) { survey in
        row(survey)
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .refreshable { await model.load(forceRefresh: true) }
    }
  }

  private func row(_ survey: Survey) -> some View {
    Button {
      onOpen(survey.id)
    } label: {
      HStack(spacing: PHSpacing.md) {
        VStack(alignment: .leading, spacing: 2) {
          Text(survey.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(1)
          HStack(spacing: PHSpacing.sm) {
            if let typeLabel = survey.typeLabel {
              Text(typeLabel)
                .font(.caption)
                .foregroundStyle(PHColor.textSecondary)
            }
            if let startDate = survey.startDate {
              Text("Started \(RelativeDateFormat.ago(startDate))")
                .font(.caption)
                .foregroundStyle(PHColor.textTertiary)
            }
          }
        }
        Spacer()
        SurveyLifecycleBadge(lifecycle: survey.lifecycle)
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
final class SurveysListModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var surveys: [Survey] = []
  var filter: SurveysListView.LifecycleFilter = .all

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  var filtered: [Survey] {
    surveys.filter { survey in
      if survey.archived { return false }
      guard let target = filter.lifecycle else { return true }
      return survey.lifecycle == target
    }
  }

  func load(forceRefresh: Bool = false) async {
    let key = context.cacheKey("surveys-list")
    if !forceRefresh, surveys.isEmpty {
      if let hit = await context.cache.read(key, as: [Survey].self, staleAfter: 300) {
        surveys = hit.value
        state = .loaded
        if !hit.isStale { return }
      }
    }
    do {
      let page = try await context.client.surveys(projectID: context.projectID)
      surveys = page.results
      state = .loaded
      await context.cache.write(key, value: surveys)
    } catch {
      if surveys.isEmpty {
        state = .failed("Check your connection and try again.")
      }
    }
  }
}
