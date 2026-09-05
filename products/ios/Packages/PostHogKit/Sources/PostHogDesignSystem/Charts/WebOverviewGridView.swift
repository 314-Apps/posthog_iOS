import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Web analytics overview as a 2-column grid of stat tiles.
public struct WebOverviewGridView: View {
  private let items: [WebOverviewItem]

  public init(items: [WebOverviewItem]) {
    self.items = items
  }

  public var body: some View {
    LazyVGrid(
      columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
      alignment: .leading,
      spacing: PHSpacing.lg
    ) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        StatTile(
          label: item.key.capitalizedFirst,
          value: formattedValue(item),
          deltaFraction: item.changeFromPreviousPct.map { $0 / 100 },
          isIncreaseBad: item.isIncreaseBad
        )
      }
    }
  }

  private func formattedValue(_ item: WebOverviewItem) -> String {
    guard let value = item.value else { return "–" }
    switch item.unit {
    case .unit:
      return MetricFormat.compact(value)
    case .percentage:
      return MetricFormat.percent(fraction: value / 100)
    case .durationSeconds:
      return MetricFormat.duration(seconds: Int(value))
    case .currency:
      return value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
  }
}

extension String {
  var capitalizedFirst: String {
    guard let first = first else { return self }
    return first.uppercased() + dropFirst()
  }
}
