import Foundation
import Observation
import PostHogFoundation
import PostHogQueries

/// Editor state, the run lifecycle, and per-project query history for the SQL runner.
@MainActor
@Observable
public final class SQLRunnerModel {
  static let historyLimit = 10
  static let seedQuery =
    "SELECT event, count() AS total FROM events GROUP BY event ORDER BY total DESC LIMIT 20"
  private static let fallbackErrorText = "Couldn't run the query. Check your connection and try again."

  public var queryText: String = SQLRunnerModel.seedQuery
  public private(set) var result: TableResult?
  public private(set) var errorText: String?
  public private(set) var isRunning = false
  public private(set) var history: [String]

  private let context: ProjectContext
  private let defaults: UserDefaults
  private let historyKey: String

  public init(context: ProjectContext, defaults: UserDefaults = .standard) {
    self.context = context
    self.defaults = defaults
    let key = "sql.history.\(context.projectID)"
    self.historyKey = key
    self.history = Self.loadHistory(from: defaults, key: key)
  }

  /// Runs the editor's HogQL against the project. No-op while a run is in
  /// flight or when the editor is empty.
  public func run() async {
    let text = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isRunning else { return }
    isRunning = true
    defer { isRunning = false }
    errorText = nil
    do {
      let response = try await context.runner.run(
        .hogQL(HogQLQuery.make(text)),
        projectID: context.projectID,
        refresh: .blocking
      )
      guard case .table(let table) = response else {
        errorText = Self.fallbackErrorText
        return
      }
      result = table
      record(text)
    } catch QueryRunnerError.queryFailed(let message) {
      // A HogQL failure message names the exact problem in the query, so show it unedited.
      errorText = message
    } catch {
      PHLog.api.error("sql run failed: \(error)")
      errorText = Self.fallbackErrorText
    }
  }

  public func removeFromHistory(_ query: String) {
    history.removeAll { $0 == query }
    persistHistory()
  }

  private func record(_ query: String) {
    var updated = history.filter { $0 != query }
    updated.insert(query, at: 0)
    history = Array(updated.prefix(Self.historyLimit))
    persistHistory()
  }

  private func persistHistory() {
    guard let data = try? JSONEncoder().encode(history) else { return }
    defaults.set(data, forKey: historyKey)
  }

  private static func loadHistory(from defaults: UserDefaults, key: String) -> [String] {
    guard let data = defaults.data(forKey: key),
      let stored = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return stored
  }
}
