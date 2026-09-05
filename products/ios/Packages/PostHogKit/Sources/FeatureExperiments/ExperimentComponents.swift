import PostHogAPI
import PostHogDesignSystem
import SwiftUI

/// Lifecycle pill shared by list rows and the detail header.
struct ExperimentLifecycleBadge: View {
  let lifecycle: Experiment.Lifecycle

  var body: some View {
    Text(label)
      .font(.caption.weight(.bold))
      .foregroundStyle(tint)
      .padding(.horizontal, PHSpacing.sm + 2)
      .padding(.vertical, 4)
      .background(tint.opacity(0.14), in: Capsule())
  }

  private var label: String {
    switch lifecycle {
    case .draft: "Draft"
    case .running: "Running"
    case .complete: "Complete"
    }
  }

  private var tint: Color {
    switch lifecycle {
    case .draft: PHColor.textSecondary
    case .running: PHColor.success
    case .complete: PHColor.link
    }
  }
}

extension Experiment {
  /// Labels for the metrics card. Metrics stay raw JSON, so every field access
  /// is defensive; a metric without a usable name gets a positional label.
  var metricDisplayNames: [String] {
    let metrics = metricsRaw?.arrayValue ?? []
    return metrics.enumerated().map { index, metric in
      if let name = metric["name"]?.stringValue, !name.isEmpty { return name }
      if let kind = metric["kind"]?.stringValue, !kind.isEmpty { return kind }
      return "Metric \(index + 1)"
    }
  }
}
