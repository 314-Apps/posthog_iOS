import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Web analytics overview as a 2-column grid of stat tiles.
public struct WebOverviewGridView: View {
  private let items: [WebOverviewItem]
  private let onSelectItem: ((String) -> Void)?

  public init(items: [WebOverviewItem], onSelectItem: ((_ key: String) -> Void)? = nil) {
    self.items = items
    self.onSelectItem = onSelectItem
  }

  public var body: some View {
    LazyVGrid(
      columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
      alignment: .leading,
      spacing: PHSpacing.lg
    ) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        tile(item)
      }
    }
  }

  @ViewBuilder
  private func tile(_ item: WebOverviewItem) -> some View {
    let stat = StatTile(
      label: item.key.capitalizedFirst,
      value: formattedValue(item),
      deltaFraction: item.changeFromPreviousPct.map { $0 / 100 },
      isIncreaseBad: item.isIncreaseBad
    )
    if let onSelectItem {
      Button {
        onSelectItem(item.key)
      } label: {
        stat
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(PHPressableStyle())
      .accessibilityLabel(tileLabel(item))
    } else {
      stat
    }
  }

  private func tileLabel(_ item: WebOverviewItem) -> String {
    "\(item.key.capitalizedFirst), \(formattedValue(item)). Double tap to see where this data comes from."
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
