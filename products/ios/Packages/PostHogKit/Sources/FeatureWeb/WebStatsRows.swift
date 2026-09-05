import PostHogFoundation

/// One row of a WebStatsTableQuery breakdown.
struct WebStatsRow: Sendable, Equatable {
  let label: String
  let visitors: Double
  let views: Double?
}

/// Maps the `QueryResult.unknown` body of a WebStatsTableQuery run.
/// WebStatsTableQuery is not a modeled query kind, so the shape is read
/// defensively: rows are positional arrays whose order comes from `columns`
/// when the server sends it, and comparison cells arrive as
/// `[current, previous]` pairs.
enum WebStatsRows {
  private static let breakdownColumn = "context.columns.breakdown_value"
  private static let visitorsColumn = "context.columns.visitors"
  private static let viewsColumn = "context.columns.views"

  static func parse(_ body: JSONValue) -> [WebStatsRow] {
    guard let results = body["results"]?.arrayValue else { return [] }
    let columns = body["columns"]?.arrayValue?.compactMap(\.stringValue) ?? []
    guard
      let labelIndex = index(of: breakdownColumn, in: columns, fallback: 0),
      let visitorsIndex = index(of: visitorsColumn, in: columns, fallback: 1)
    else { return [] }
    let viewsIndex = index(of: viewsColumn, in: columns, fallback: 2)
    return results.compactMap { raw in
      guard
        let cells = raw.arrayValue,
        cells.indices.contains(labelIndex),
        let visitors = number(in: cells, at: visitorsIndex)
      else { return nil }
      return WebStatsRow(
        label: label(from: cells[labelIndex]),
        visitors: visitors,
        views: number(in: cells, at: viewsIndex)
      )
    }
  }

  /// Column order is positional (0/1/2) until the server names the columns;
  /// then only the named indices count, so a renamed column reads as absent
  /// instead of pulling a neighbor's values.
  private static func index(of column: String, in columns: [String], fallback: Int) -> Int? {
    columns.isEmpty ? fallback : columns.firstIndex(of: column)
  }

  /// A comparison cell is a `[current, previous]` pair; keep the current value.
  private static func currentValue(_ cell: JSONValue) -> JSONValue {
    cell.arrayValue?.first ?? cell
  }

  private static func number(in cells: [JSONValue], at index: Int?) -> Double? {
    guard let index, cells.indices.contains(index) else { return nil }
    return currentValue(cells[index]).numberValue
  }

  private static func label(from cell: JSONValue) -> String {
    let value = currentValue(cell)
    if let string = value.stringValue, !string.isEmpty { return string }
    if let int = value.intValue { return String(int) }
    if let number = value.numberValue { return String(number) }
    return "(none)"
  }
}
