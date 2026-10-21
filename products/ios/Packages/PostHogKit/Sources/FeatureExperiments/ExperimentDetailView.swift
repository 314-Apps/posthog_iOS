import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Read-only experiment summary: setup facts and metric names. Significance
/// analysis is not reproduced here, so the results card links to the web.
public struct ExperimentDetailView: View {
  @State private var model: ExperimentDetailModel

  private let onOpenWeb: (String) -> Void

  public init(context: ProjectContext, experimentID: Int, onOpenWeb: @escaping (String) -> Void) {
    self._model = State(
      initialValue: ExperimentDetailModel(context: context, experimentID: experimentID))
    self.onOpenWeb = onOpenWeb
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        if let experiment = model.experiment {
          headerCard(experiment)
          metricsCard(experiment)
          resultsCard(experiment)
        } else if model.failed {
          EmptyStateView(
            systemImage: "wifi.exclamationmark",
            title: "Couldn't load this experiment",
            message: "Check your connection and try again.",
            actionTitle: "Retry"
          ) {
            Task { await model.load() }
          }
        } else {
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 150)
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 110)
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 110)
        }
      }
      .padding(PHSpacing.lg)
    }
    .background(PHColor.background)
    .navigationTitle("Experiment")
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.load() }
  }

  private func headerCard(_ experiment: Experiment) -> some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.sm) {
        HStack(alignment: .top, spacing: PHSpacing.sm) {
          Text(experiment.name)
            .font(.title3.weight(.bold))
            .foregroundStyle(PHColor.textPrimary)
          Spacer()
          ExperimentLifecycleBadge(lifecycle: experiment.lifecycle)
        }
        if let description = experiment.description, !description.isEmpty {
          Text(description)
            .font(.subheadline)
            .foregroundStyle(PHColor.textSecondary)
        }
        VStack(alignment: .leading, spacing: PHSpacing.xs) {
          if let started = experiment.startDate {
            factRow("Started", value: started.formatted(date: .abbreviated, time: .omitted))
          }
          if let ended = experiment.endDate {
            factRow("Ended", value: ended.formatted(date: .abbreviated, time: .omitted))
          }
          if let variantCount = experiment.variantCount {
            factRow("Variants", value: "\(variantCount)")
          }
          if let key = experiment.featureFlagKey, !key.isEmpty {
            factRow("Feature flag", value: key, mono: true)
          }
        }
      }
    }
  }

  private func factRow(_ label: String, value: String, mono: Bool = false) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: PHSpacing.sm) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(PHColor.textTertiary)
        .frame(width: 88, alignment: .leading)
      Text(value)
        .font(mono ? PHFont.mono(13) : .caption.weight(.semibold))
        .foregroundStyle(PHColor.textSecondary)
        .textSelection(.enabled)
    }
  }

  private func metricsCard(_ experiment: Experiment) -> some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Metrics")
        let names = experiment.metricDisplayNames
        if names.isEmpty {
          Text("No metrics yet. Add them to this experiment on the web.")
            .font(.subheadline)
            .foregroundStyle(PHColor.textSecondary)
        } else {
          ForEach(Array(names.enumerated()), id: \.offset) { index, name in
            HStack(alignment: .firstTextBaseline, spacing: PHSpacing.md) {
              Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(PHColor.textTertiary)
                .monospacedDigit()
              Text(name)
                .font(.subheadline)
                .foregroundStyle(PHColor.textPrimary)
            }
          }
        }
      }
    }
  }

  private func resultsCard(_ experiment: Experiment) -> some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Results")
        Text("Results analysis renders on the web for now.")
          .font(.subheadline)
          .foregroundStyle(PHColor.textSecondary)
        Button {
          onOpenWeb("/experiments/\(experiment.id)")
        } label: {
          Text("Open results")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, PHSpacing.xl)
            .frame(minHeight: 44)
            .background(PHColor.accent, in: Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }
}

@MainActor
@Observable
final class ExperimentDetailModel {
  private(set) var experiment: Experiment?
  private(set) var failed = false

  private let context: ProjectContext
  private let experimentID: Int

  init(context: ProjectContext, experimentID: Int) {
    self.context = context
    self.experimentID = experimentID
  }

  func load() async {
    failed = false
    do {
      experiment = try await context.client.experiment(
        projectID: context.projectID,
        experimentID: experimentID
      )
    } catch {
      PHLog.api.error("experiment load failed: \(error)")
      failed = experiment == nil
    }
  }
}
