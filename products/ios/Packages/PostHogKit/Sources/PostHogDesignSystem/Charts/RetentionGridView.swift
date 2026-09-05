import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Retention triangle as a shaded grid: cohorts as rows, intervals as columns,
/// cell tint scaled to the cohort's own size.
public struct RetentionGridView: View {
  private let rows: [RetentionRow]

  public init(rows: [RetentionRow]) {
    self.rows = rows
  }

  private var columnCount: Int {
    rows.map(\.counts.count).max() ?? 0
  }

  public var body: some View {
    Grid(horizontalSpacing: 3, verticalSpacing: 3) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        GridRow {
          Text(row.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(PHColor.textSecondary)
            .frame(width: 52, alignment: .leading)
          ForEach(0..<columnCount, id: \.self) { column in
            cell(row: row, column: column)
          }
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Retention grid with \(rows.count) cohorts")
  }

  @ViewBuilder
  private func cell(row: RetentionRow, column: Int) -> some View {
    if row.counts.indices.contains(column) {
      let base = max(row.counts.first ?? 1, 1)
      let fraction = row.counts[column] / base
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(PHColor.series(at: 0).opacity(max(fraction, 0.06)))
        .frame(height: 28)
        .overlay {
          Text(MetricFormat.percent(fraction: fraction))
            .font(.system(size: 9, weight: .bold))
            .phMetricStyle()
            .foregroundStyle(fraction > 0.45 ? Color.white : PHColor.textPrimary)
        }
    } else {
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(Color.clear)
        .frame(height: 28)
    }
  }
}
