import PostHogFoundation
import SwiftUI

/// "+12.4%" pill. `isIncreaseBad` flips the good/bad coloring (bounce rate).
public struct DeltaBadge: View {
  private let fraction: Double
  private let isIncreaseBad: Bool

  public init(fraction: Double, isIncreaseBad: Bool = false) {
    self.fraction = fraction
    self.isIncreaseBad = isIncreaseBad
  }

  private var isGood: Bool {
    isIncreaseBad ? fraction < 0 : fraction >= 0
  }

  public var body: some View {
    Text(MetricFormat.signedPercent(fraction: fraction))
      .font(.caption.weight(.bold))
      .phMetricStyle()
      .foregroundStyle(isGood ? PHColor.success : PHColor.danger)
      .padding(.horizontal, PHSpacing.sm)
      .padding(.vertical, 3)
      .background(
        (isGood ? PHColor.successFill : PHColor.dangerFill).opacity(0.14),
        in: Capsule()
      )
  }
}
