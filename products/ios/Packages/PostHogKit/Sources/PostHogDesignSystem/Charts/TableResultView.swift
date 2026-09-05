import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Columnar results (HogQL, events) as a horizontally scrollable table.
public struct TableResultView: View {
  private let table: TableResult
  private let maxRows: Int

  public init(table: TableResult, maxRows: Int = 50) {
    self.table = table
    self.maxRows = maxRows
  }

  public var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      Grid(alignment: .leading, horizontalSpacing: PHSpacing.lg, verticalSpacing: 0) {
        GridRow {
          ForEach(Array(table.columns.enumerated()), id: \.offset) { _, column in
            Text(column)
              .font(.caption.weight(.bold))
              .foregroundStyle(PHColor.textSecondary)
              .padding(.vertical, PHSpacing.sm)
          }
        }
        Divider().gridCellUnsizedAxes(.horizontal)
        ForEach(Array(table.rows.prefix(maxRows).enumerated()), id: \.offset) { _, row in
          GridRow {
            ForEach(Array(row.enumerated()), id: \.offset) { _, value in
              Text(display(value))
                .font(PHFont.mono(12, weight: .regular))
                .foregroundStyle(PHColor.textPrimary)
                .lineLimit(1)
                .padding(.vertical, PHSpacing.sm)
            }
          }
          Divider().gridCellUnsizedAxes(.horizontal)
        }
      }
    }
  }

  private func display(_ value: JSONValue) -> String {
    switch value {
    case .string(let string): string
    case .number(let number): MetricFormat.full(number)
    case .bool(let bool): bool ? "true" : "false"
    case .null: "–"
    case .array, .object: "…"
    }
  }
}
