import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Columnar results (HogQL, events) as a horizontally scrollable table.
public struct TableResultView: View {
  private let table: TableResult
  private let maxRows: Int
  private let onSelectRow: ((Int) -> Void)?

  public init(
    table: TableResult,
    maxRows: Int = 50,
    onSelectRow: ((_ rowIndex: Int) -> Void)? = nil
  ) {
    self.table = table
    self.maxRows = maxRows
    self.onSelectRow = onSelectRow
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
        ForEach(Array(table.rows.prefix(maxRows).enumerated()), id: \.offset) { rowIndex, row in
          GridRow {
            ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, value in
              cell(value, rowIndex: rowIndex, columnIndex: columnIndex)
            }
          }
          Divider().gridCellUnsizedAxes(.horizontal)
        }
      }
    }
  }

  /// `GridRow` has to stay a direct child of `Grid`, so the tap lands on every
  /// cell of the row instead of on one wrapper around the row.
  @ViewBuilder
  private func cell(_ value: JSONValue, rowIndex: Int, columnIndex: Int) -> some View {
    let text =
      Text(display(value))
      .font(PHFont.mono(12, weight: .regular))
      .foregroundStyle(PHColor.textPrimary)
      .lineLimit(1)
      .padding(.vertical, PHSpacing.sm)
    if let onSelectRow {
      text
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onSelectRow(rowIndex) }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(cellLabel(value, columnIndex: columnIndex))
    } else {
      text
    }
  }

  private func cellLabel(_ value: JSONValue, columnIndex: Int) -> String {
    let shown = display(value)
    guard table.columns.indices.contains(columnIndex) else {
      return "\(shown). Double tap to see where this data comes from."
    }
    return "\(table.columns[columnIndex]), \(shown). Double tap to see where this data comes from."
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
