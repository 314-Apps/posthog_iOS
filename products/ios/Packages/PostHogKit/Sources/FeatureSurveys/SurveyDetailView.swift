import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// One survey: header, read-only questions, response totals, and the launch or
/// stop control behind a confirmation. Complete surveys get no action.
public struct SurveyDetailView: View {
  @State private var model: SurveyDetailModel
  @State private var confirmingLaunch = false
  @State private var confirmingStop = false

  public init(context: ProjectContext, surveyID: String) {
    self._model = State(initialValue: SurveyDetailModel(context: context, surveyID: surveyID))
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        if let survey = model.survey {
          headerCard(survey)
          questionsCard(survey)
          responsesCard
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
      "Launch this survey?",
      isPresented: $confirmingLaunch,
      titleVisibility: .visible
    ) {
      Button("Launch survey") {
        Task { await model.launch() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("It goes live and starts collecting responses right away.")
    }
    .confirmationDialog(
      "Stop this survey?",
      isPresented: $confirmingStop,
      titleVisibility: .visible
    ) {
      Button("Stop survey", role: .destructive) {
        Task { await model.stop() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("It stops collecting responses right away.")
    }
    .sensoryFeedback(.success, trigger: model.lastActionSucceeded)
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

  private func questionsCard(_ survey: Survey) -> some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Questions")
        let summaries = survey.questionSummaries
        if summaries.isEmpty {
          Text("No questions to show.")
            .font(.subheadline)
            .foregroundStyle(PHColor.textTertiary)
        } else {
          ForEach(Array(summaries.enumerated()), id: \.offset) { index, summary in
            HStack(alignment: .top, spacing: PHSpacing.md) {
              Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(PHColor.textSecondary)
                .frame(width: 20, height: 20)
                .background(PHColor.surfaceSecondary, in: Circle())
              Text(summary)
                .font(.subheadline)
                .foregroundStyle(PHColor.textPrimary)
            }
          }
        }
        Text("Edit questions on the web")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(PHColor.link)
      }
    }
  }

  private var responsesCard: some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Responses")
        switch model.stats {
        case .loading:
          SkeletonView(cornerRadius: 10).frame(height: 56)
        case .loaded(let summary):
          HStack(alignment: .top, spacing: PHSpacing.xl) {
            StatTile(label: "Shown", value: tileValue(summary.shown))
            StatTile(label: "Responded", value: tileValue(summary.responded))
            StatTile(label: "Dismissed", value: tileValue(summary.dismissed))
          }
        case .unavailable:
          Text("Response details render on the web.")
            .font(.subheadline)
            .foregroundStyle(PHColor.textSecondary)
        }
      }
    }
  }

  private func tileValue(_ count: Int?) -> String {
    count.map(MetricFormat.compact) ?? "-"
  }

  @ViewBuilder
  private func actionSection(_ survey: Survey) -> some View {
    switch survey.lifecycle {
    case .draft:
      actionButton("Launch survey", isDestructive: false) { confirmingLaunch = true }
    case .running:
      actionButton("Stop survey", isDestructive: true) { confirmingStop = true }
    case .complete:
      EmptyView()
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
  enum StatsState: Equatable {
    case loading
    case loaded(SurveyStatsSummary)
    case unavailable
  }

  private(set) var survey: Survey?
  private(set) var loadFailed = false
  private(set) var stats: StatsState = .loading
  private(set) var isUpdating = false
  private(set) var lastActionSucceeded = false
  private(set) var actionError: String?

  private let context: ProjectContext
  private let surveyID: String

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
    await loadStats()
  }

  func launch() async {
    guard survey?.lifecycle == .draft else { return }
    await updateDates(startDate: .now, endDate: nil)
  }

  func stop() async {
    guard survey?.lifecycle == .running else { return }
    await updateDates(startDate: nil, endDate: .now)
  }

  private func loadStats() async {
    do {
      let raw = try await context.client.surveyStats(projectID: context.projectID, surveyID: surveyID)
      let summary = SurveyStatsSummary.parse(raw)
      stats = summary.hasAnyValue ? .loaded(summary) : .unavailable
    } catch {
      PHLog.api.error("survey stats load failed: \(error)")
      stats = .unavailable
    }
  }

  private func updateDates(startDate: Date?, endDate: Date?) async {
    guard !isUpdating else { return }
    isUpdating = true
    actionError = nil
    defer { isUpdating = false }
    do {
      survey = try await context.client.updateSurveyDates(
        projectID: context.projectID,
        surveyID: surveyID,
        startDate: startDate,
        endDate: endDate
      )
      lastActionSucceeded.toggle()
      await context.cache.removeSubtree(context.cacheKey("surveys-list"))
    } catch {
      PHLog.api.error("survey update failed: \(error)")
      actionError = "Couldn't update the survey. Try again."
    }
  }
}
