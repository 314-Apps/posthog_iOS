import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Retention triangle as a shaded grid: cohorts as rows, intervals as columns,
/// cell tint scaled to the cohort's own size.
public struct RetentionGridView: View {
  private let rows: [RetentionRow]
  private let onSelectCell: ((Int, Int) -> Void)?

  public init(
    rows: [RetentionRow],
    onSelectCell: ((_ cohortIndex: Int, _ intervalIndex: Int) -> Void)? = nil
  ) {
    self.rows = rows
    self.onSelectCell = onSelectCell
  }

  private var columnCount: Int {
    rows.map(\.counts.count).max() ?? 0
  }

  public var body: some View {
    if let onSelectCell {
      grid(onSelectCell: onSelectCell)
    } else {
      grid(onSelectCell: nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Retention grid with \(rows.count) cohorts")
    }
  }

  private func grid(onSelectCell: ((Int, Int) -> Void)?) -> some View {
    Grid(horizontalSpacing: 3, verticalSpacing: 3) {
      ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
        GridRow {
          Text(row.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(PHColor.textSecondary)
            .frame(width: 52, alignment: .leading)
          ForEach(0..<columnCount, id: \.self) { column in
            cell(row: row, rowIndex: rowIndex, column: column, onSelectCell: onSelectCell)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func cell(
    row: RetentionRow,
    rowIndex: Int,
    column: Int,
    onSelectCell: ((Int, Int) -> Void)?
  ) -> some View {
    if row.counts.indices.contains(column) {
      let base = max(row.counts.first ?? 1, 1)
      let fraction = row.counts[column] / base
      if let onSelectCell {
        Button {
          onSelectCell(rowIndex, column)
        } label: {
          filledCell(fraction: fraction)
            .contentShape(Rectangle())
        }
        .buttonStyle(PHPressableStyle())
        .accessibilityLabel(cellLabel(row: row, column: column, fraction: fraction))
      } else {
        filledCell(fraction: fraction)
      }
    } else {
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(Color.clear)
        .frame(height: 28)
    }
  }

  private func filledCell(fraction: Double) -> some View {
    RoundedRectangle(cornerRadius: 5, style: .continuous)
      .fill(PHColor.series(at: 0).opacity(max(fraction, 0.06)))
      .frame(height: 28)
      .overlay {
        Text(MetricFormat.percent(fraction: fraction))
          .font(.system(size: 9, weight: .bold))
          .phMetricStyle()
          .foregroundStyle(fraction > 0.45 ? Color.white : PHColor.textPrimary)
      }
  }

  private func cellLabel(row: RetentionRow, column: Int, fraction: Double) -> String {
    let share = MetricFormat.percent(fraction: fraction)
    return "\(row.label), period \(column), \(share). Double tap to see the people."
  }
}
