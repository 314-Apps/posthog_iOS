import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Mobile-first funnel: one column per step, height proportional to count,
/// conversion percentage under each step. Designed for a phone, not a clone
/// of the web viz.
public struct FunnelChartView: View {
  private let steps: [FunnelStep]

  public init(steps: [FunnelStep]) {
    self.steps = steps
  }

  private var maxCount: Double {
    max(steps.map(\.count).max() ?? 1, 1)
  }

  public var body: some View {
    HStack(alignment: .bottom, spacing: PHSpacing.sm) {
      ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
        VStack(alignment: .leading, spacing: PHSpacing.sm) {
          VStack {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(barColor(index: index))
              .frame(height: max(96 * step.count / maxCount, 6))
          }
          .frame(height: 96)
          VStack(alignment: .leading, spacing: 1) {
            Text(step.displayName)
              .font(.caption.weight(.bold))
              .foregroundStyle(PHColor.textPrimary)
              .lineLimit(2)
            Text(
              "\(MetricFormat.full(step.count)) · \(MetricFormat.percent(fraction: conversion(step)))"
            )
            .font(.caption2)
            .phMetricStyle()
            .foregroundStyle(PHColor.textTertiary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilitySummary)
  }

  private func conversion(_ step: FunnelStep) -> Double {
    guard let first = steps.first, first.count > 0 else { return 0 }
    return step.count / first.count
  }

  private func barColor(index: Int) -> Color {
    index == steps.count - 1 ? PHColor.accent : PHColor.series(at: 0).opacity(1 - Double(index) * 0.25)
  }

  private var accessibilitySummary: String {
    guard let first = steps.first, let last = steps.last, first.count > 0 else {
      return "Empty funnel"
    }
    let rate = MetricFormat.percent(fraction: last.count / first.count)
    return "Funnel with \(steps.count) steps, overall conversion \(rate)"
  }
}
