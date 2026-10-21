import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// One survey: header, results or individual responses, date presets, and lifecycle controls.
public struct SurveyDetailView: View {
  @State private var model: SurveyDetailModel
  @State private var confirmingAction: SurveyAction?

  public init(context: ProjectContext, surveyID: String) {
    self._model = State(initialValue: SurveyDetailModel(context: context, surveyID: surveyID))
  }

  public var body: some View {
    @Bindable var model = model
    ScrollView {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        if let survey = model.survey {
          headerCard(survey)
          SurveyDatePresetRow(preset: $model.datePreset)
            .onChange(of: model.datePreset) { _, _ in
              Task { await model.reloadResults() }
            }
          SurveyTabRow(tab: $model.tab)
          switch model.tab {
          case .results:
            resultsSection
          case .responses:
            responsesSection
          }
          actionSection(survey)
        } else if model.loadFailed {
          EmptyStateView(
            systemImage: "wifi.exclamationmark",
            title: "Couldn't load this survey",
            message: "Check your connection and try again.",
            actionTitle: "Retry"
          ) {
            Task { await model.load() }
          }
        } else {
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 110)
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 140)
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 90)
        }
      }
      .padding(PHSpacing.lg)
    }
    .background(PHColor.background)
    .navigationTitle("Survey")
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.load() }
    .confirmationDialog(
      confirmTitle,
      isPresented: Binding(
        get: { confirmingAction != nil },
        set: { if !$0 { confirmingAction = nil } }
      ),
      titleVisibility: .visible
    ) {
      if let action = confirmingAction {
        Button(confirmButtonTitle(action), role: action == .stop || action == .archive ? .destructive : nil) {
          Task { await model.perform(action) }
        }
        Button("Cancel", role: .cancel) {}
      }
    } message: {
      Text(confirmMessage)
    }
    .sensoryFeedback(.success, trigger: model.lastActionSucceeded)
  }

  private var confirmTitle: String {
    switch confirmingAction {
    case .launch: "Launch this survey?"
    case .stop: "Stop this survey?"
    case .resume: "Resume this survey?"
    case .archive: "Archive this survey?"
    case .unarchive: "Unarchive this survey?"
    case nil: ""
    }
  }

  private var confirmMessage: String {
    switch confirmingAction {
    case .launch: "It goes live and starts collecting responses right away."
    case .stop: "It stops collecting responses right away."
    case .resume: "It starts showing to people again."
    case .archive: "It leaves the active list until you unarchive it."
    case .unarchive: "It returns to the active list."
    case nil: ""
    }
  }

  private func confirmButtonTitle(_ action: SurveyAction) -> String {
    switch action {
    case .launch: "Launch survey"
    case .stop: "Stop survey"
    case .resume: "Resume survey"
    case .archive: "Archive survey"
    case .unarchive: "Unarchive survey"
    }
  }

  private func headerCard(_ survey: Survey) -> some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.sm) {
        HStack(alignment: .top, spacing: PHSpacing.sm) {
          Text(survey.name)
            .font(.headline)
            .foregroundStyle(PHColor.textPrimary)
            .textSelection(.enabled)
          Spacer()
          SurveyLifecycleBadge(lifecycle: survey.lifecycle)
        }
        if let description = survey.description, !description.isEmpty {
          Text(description)
            .font(.subheadline)
            .foregroundStyle(PHColor.textSecondary)
        }
        HStack(spacing: PHSpacing.sm) {
          if let typeLabel = survey.typeLabel {
            Text(typeLabel)
              .font(.caption.weight(.semibold))
              .foregroundStyle(PHColor.textSecondary)
          }
          if let startDate = survey.startDate {
            Text("Started \(RelativeDateFormat.ago(startDate))")
              .font(.caption)
              .foregroundStyle(PHColor.textTertiary)
          }
          if let endDate = survey.endDate {
            Text("Ended \(RelativeDateFormat.ago(endDate))")
              .font(.caption)
              .foregroundStyle(PHColor.textTertiary)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var resultsSection: some View {
    switch model.resultsState {
    case .loading:
      SkeletonView(cornerRadius: PHRadius.card).frame(height: 100)
      SkeletonView(cornerRadius: PHRadius.card).frame(height: 160)
    case .loaded(let funnel, let questionResults):
      SurveyFunnelCard(funnel: funnel)
      if questionResults.isEmpty {
        PHCard {
          Text("No questions to show results for.")
            .font(.subheadline)
            .foregroundStyle(PHColor.textSecondary)
        }
      } else {
        ForEach(questionResults) { result in
          SurveyQuestionResultCard(result: result)
        }
      }
    case .failed:
      EmptyStateView(
        systemImage: "wifi.exclamationmark",
        title: "Couldn't load results",
        message: "Check your connection and try again.",
        actionTitle: "Retry"
      ) {
        Task { await model.reloadResults() }
      }
    }
  }

  @ViewBuilder
  private var responsesSection: some View {
    switch model.responsesState {
    case .loading where model.responses.isEmpty:
      SkeletonView(cornerRadius: PHRadius.card).frame(height: 90)
      SkeletonView(cornerRadius: PHRadius.card).frame(height: 90)
    case .failed where model.responses.isEmpty:
      EmptyStateView(
        systemImage: "wifi.exclamationmark",
        title: "Couldn't load responses",
        message: "Check your connection and try again.",
        actionTitle: "Retry"
      ) {
        Task { await model.reloadResults() }
      }
    case _ where model.responses.isEmpty:
      PHCard {
        Text("No responses in this range.")
          .font(.subheadline)
          .foregroundStyle(PHColor.textSecondary)
      }
    default:
      ForEach(model.responses) { row in
        SurveyResponseRowCard(row: row)
      }
      if model.responsesHasMore {
        Button {
          Task { await model.loadMoreResponses() }
        } label: {
          Group {
            if model.isLoadingMoreResponses {
              ProgressView()
            } else {
              Text("Load more")
                .font(.subheadline.weight(.semibold))
            }
          }
          .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(model.isLoadingMoreResponses)
      }
    }
  }

  @ViewBuilder
  private func actionSection(_ survey: Survey) -> some View {
    let actions = surveyActions(for: survey)
    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
      actionButton(
        confirmButtonTitle(action),
        isDestructive: action == .stop || action == .archive
      ) {
        confirmingAction = action
      }
    }
    if let message = model.actionError {
      Text(message)
        .font(.footnote)
        .foregroundStyle(PHColor.danger)
    }
  }

  private func actionButton(
    _ title: String,
    isDestructive: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Group {
        if model.isUpdating {
          ProgressView()
            .tint(Color.white)
        } else {
          Text(title)
            .font(.subheadline.weight(.bold))
        }
      }
      .foregroundStyle(Color.white)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(isDestructive ? PHColor.dangerFill : PHColor.accent, in: Capsule())
    }
    .buttonStyle(.plain)
    .disabled(model.isUpdating)
  }
}

@MainActor
@Observable
final class SurveyDetailModel {
  enum ResultsState: Equatable {
    case loading
    case loaded(SurveyFunnel, [SurveyQuestionResult])
    case failed
  }

  enum ResponsesState: Equatable {
    case loading
    case loaded
    case failed
  }

  private(set) var survey: Survey?
  private(set) var loadFailed = false
  private(set) var resultsState: ResultsState = .loading
  private(set) var responsesState: ResponsesState = .loading
  private(set) var responses: [SurveyResponseRow] = []
  private(set) var responsesHasMore = false
  private(set) var isLoadingMoreResponses = false
  private(set) var isUpdating = false
  private(set) var lastActionSucceeded = false
  private(set) var actionError: String?

  var datePreset: SurveyDatePreset = .all
  var tab: SurveyTabRow.Tab = .results

  /// Kept for existing tests that assert on the funnel tiles.
  var stats: SurveyDetailView.LegacyStatsState {
    switch resultsState {
    case .loading: .loading
    case .loaded(let funnel, _): funnel.hasAnyValue ? .loaded(funnel) : .unavailable
    case .failed: .unavailable
    }
  }

  private let context: ProjectContext
  private let surveyID: String
  private var responsesOffset = 0
  private let pageSize = 100
  private var rawStats: JSONValue?

  init(context: ProjectContext, surveyID: String) {
    self.context = context
    self.surveyID = surveyID
  }

  func load() async {
    loadFailed = false
    do {
      survey = try await context.client.survey(projectID: context.projectID, surveyID: surveyID)
    } catch {
      PHLog.api.error("survey load failed: \(error)")
      if survey == nil {
        loadFailed = true
        return
      }
    }
    await reloadResults()
  }

  func reloadResults() async {
    resultsState = .loading
    responsesState = .loading
    responses = []
    responsesOffset = 0
    responsesHasMore = false
    rawStats = nil

    let since = datePreset.since()
    async let statsTask = loadStatsRaw(since: since)
    async let responsesTask = loadResponsesPage(since: since, offset: 0)

    let stats = await statsTask
    let page = await responsesTask

    rawStats = stats
    if let page {
      responses = page.results
      responsesHasMore = page.hasMore
      responsesOffset = page.offset + page.results.count
      responsesState = .loaded
    } else {
      responsesState = .failed
    }

    rebuildQuestionResults(responsesComplete: !responsesHasMore)
  }

  func loadMoreResponses() async {
    guard responsesHasMore, !isLoadingMoreResponses else { return }
    isLoadingMoreResponses = true
    defer { isLoadingMoreResponses = false }
    guard let page = await loadResponsesPage(since: datePreset.since(), offset: responsesOffset)
    else { return }
    responses.append(contentsOf: page.results)
    responsesHasMore = page.hasMore
    responsesOffset = page.offset + page.results.count
    rebuildQuestionResults(responsesComplete: !responsesHasMore)
  }

  func launch() async { await perform(.launch) }
  func stop() async { await perform(.stop) }

  func perform(_ action: SurveyAction) async {
    guard !isUpdating else { return }
    isUpdating = true
    actionError = nil
    defer { isUpdating = false }
    do {
      switch action {
      case .launch:
        survey = try await context.client.updateSurvey(
          projectID: context.projectID,
          surveyID: surveyID,
          startDate: .now
        )
      case .stop:
        survey = try await context.client.updateSurvey(
          projectID: context.projectID,
          surveyID: surveyID,
          endDate: .now
        )
      case .resume:
        survey = try await context.client.updateSurvey(
          projectID: context.projectID,
          surveyID: surveyID,
          clearEndDate: true
        )
      case .archive:
        survey = try await context.client.updateSurvey(
          projectID: context.projectID,
          surveyID: surveyID,
          archived: true
        )
      case .unarchive:
        survey = try await context.client.updateSurvey(
          projectID: context.projectID,
          surveyID: surveyID,
          archived: false
        )
      }
      lastActionSucceeded.toggle()
      await context.cache.removeSubtree(context.cacheKey("surveys-list"))
    } catch {
      PHLog.api.error("survey update failed: \(error)")
      actionError = "Couldn't update the survey. Try again."
    }
  }

  private func rebuildQuestionResults(responsesComplete: Bool) {
    guard let survey else {
      resultsState = .failed
      return
    }
    guard let rawStats else {
      resultsState = .failed
      return
    }
    let funnel = SurveyFunnel.parse(rawStats)
    let questions = parseSurveyQuestions(survey.questionsRaw)
    let questionResults = buildSurveyQuestionResults(
      questions: questions,
      stats: rawStats,
      responses: responses,
      responsesComplete: responsesComplete
    )
    resultsState = .loaded(funnel, questionResults)
  }

  private func loadStatsRaw(since: String?) async -> JSONValue? {
    do {
      return try await context.client.surveyStats(
        projectID: context.projectID,
        surveyID: surveyID,
        since: since
      )
    } catch {
      PHLog.api.error("survey stats load failed: \(error)")
      return nil
    }
  }

  private func loadResponsesPage(since: String?, offset: Int) async -> SurveyResponsesPage? {
    do {
      return try await context.client.listSurveyResponses(
        projectID: context.projectID,
        surveyID: surveyID,
        since: since,
        limit: pageSize,
        offset: offset
      )
    } catch {
      PHLog.api.error("survey responses load failed: \(error)")
      return nil
    }
  }
}

extension SurveyDetailView {
  /// Compatibility wrapper for unit tests that assert on Shown/Responded/Dismissed tiles.
  enum LegacyStatsState: Equatable {
    case loading
    case loaded(SurveyFunnel)
    case unavailable
  }
}
