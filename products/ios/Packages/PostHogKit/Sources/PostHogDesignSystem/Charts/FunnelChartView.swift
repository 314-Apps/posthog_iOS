import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Mobile-first funnel: one column per step, height proportional to count,
/// conversion percentage under each step. Designed for a phone, not a clone
/// of the web viz.
public struct FunnelChartView: View {
  private let steps: [FunnelStep]
  private let onSelectStep: ((Int) -> Void)?

  public init(steps: [FunnelStep], onSelectStep: ((_ order: Int) -> Void)? = nil) {
    self.steps = steps
    self.onSelectStep = onSelectStep
  }

  private var maxCount: Double {
    max(steps.map(\.count).max() ?? 1, 1)
  }

  public var body: some View {
    if let onSelectStep {
      columns(onSelectStep: onSelectStep)
    } else {
      columns(onSelectStep: nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
  }

  private func columns(onSelectStep: ((Int) -> Void)?) -> some View {
    HStack(alignment: .bottom, spacing: PHSpacing.sm) {
      ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
        column(index: index, step: step, onSelectStep: onSelectStep)
      }
    }
  }

  @ViewBuilder
  private func column(index: Int, step: FunnelStep, onSelectStep: ((Int) -> Void)?) -> some View {
    if let onSelectStep {
      Button {
        onSelectStep(step.order)
      } label: {
        bar(index: index, step: step)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(PHPressableStyle())
      .accessibilityLabel(stepLabel(step))
    } else {
      bar(index: index, step: step)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func bar(index: Int, step: FunnelStep) -> some View {
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
  }

  private func conversion(_ step: FunnelStep) -> Double {
    guard let first = steps.first, first.count > 0 else { return 0 }
    return step.count / first.count
  }

  private func barColor(index: Int) -> Color {
    index == steps.count - 1 ? PHColor.accent : PHColor.series(at: 0).opacity(1 - Double(index) * 0.25)
  }

  private func stepLabel(_ step: FunnelStep) -> String {
    let count = MetricFormat.full(step.count)
    let rate = MetricFormat.percent(fraction: conversion(step))
    return "\(step.displayName), \(count), \(rate) conversion. Double tap to see the people."
  }

  private var accessibilitySummary: String {
    guard let first = steps.first, let last = steps.last, first.count > 0 else {
      return "Empty funnel"
    }
    let rate = MetricFormat.percent(fraction: last.count / first.count)
    return "Funnel with \(steps.count) steps, overall conversion \(rate)"
  }
}
