import PostHogAPI
import PostHogDesignSystem
import SwiftUI

/// Capsule status label shared by list rows and the issue header.
/// Unknown statuses render nothing rather than a misleading badge.
struct ErrorStatusBadge: View {
  let status: ErrorTrackingIssue.Status

  var body: some View {
    if status != .unknown {
      Text(label)
        .font(.caption2.weight(.bold))
        .foregroundStyle(foreground)
        .padding(.horizontal, PHSpacing.sm)
        .padding(.vertical, 3)
        .background(fill, in: Capsule())
    }
  }

  private var label: String {
    switch status {
    case .active: "Active"
    case .resolved: "Resolved"
    case .suppressed: "Suppressed"
    case .archived: "Archived"
    case .unknown: ""
    }
  }

  private var foreground: Color {
    switch status {
    case .active: PHColor.danger
    case .resolved: PHColor.success
    case .suppressed, .archived, .unknown: PHColor.textSecondary
    }
  }

  private var fill: Color {
    switch status {
    case .active: PHColor.dangerFill.opacity(0.14)
    case .resolved: PHColor.successFill.opacity(0.14)
    case .suppressed, .archived, .unknown: PHColor.divider
    }
  }
}

/// Compact bar sparkline for an issue's volume buckets. Decorative — the
/// counts line beside it carries the numbers.
struct VolumeSparkline: View {
  let values: [Double]
  var height: CGFloat = 40

  var body: some View {
    let peak = max(values.max() ?? 0, 1)
    HStack(alignment: .bottom, spacing: 2) {
      ForEach(Array(values.enumerated()), id: \.offset) { _, value in
        Capsule(style: .continuous)
          .fill(value > 0 ? PHColor.accent.opacity(0.85) : PHColor.divider)
          .frame(maxWidth: .infinity)
          .frame(height: max(height * value / peak, 3))
      }
    }
    .frame(height: height, alignment: .bottom)
    .accessibilityHidden(true)
  }
}
