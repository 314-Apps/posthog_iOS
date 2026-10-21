import PostHogDesignSystem
import PostHogQueries
import SwiftUI

/// The SQL runner: HogQL editor, results table, and recent-query history.
public struct SQLRunnerView: View {
  @State private var model: SQLRunnerModel

  public init(context: ProjectContext) {
    self._model = State(initialValue: SQLRunnerModel(context: context))
  }

  private static let examples: [(title: String, query: String)] = [
    (
      "Top events",
      """
      SELECT event, count() AS total
      FROM events
      GROUP BY event
      ORDER BY total DESC
      LIMIT 20
      """
    ),
    (
      "Users per day",
      """
      SELECT toDate(timestamp) AS day, uniq(person_id) AS users
      FROM events
      WHERE timestamp >= now() - INTERVAL 7 DAY
      GROUP BY day
      ORDER BY day
      """
    ),
    (
      "Browser breakdown",
      """
      SELECT properties.$browser AS browser, count() AS total
      FROM events
      GROUP BY browser
      ORDER BY total DESC
      LIMIT 10
      """
    ),
  ]

  public var body: some View {
    List {
      Group {
        editor
        runButton
        if let errorText = model.errorText {
          Text(errorText)
            .font(.footnote)
            .foregroundStyle(PHColor.danger)
            .textSelection(.enabled)
        }
        if let result = model.result {
          resultsCard(result)
        }
      }
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .listRowInsets(
        EdgeInsets(top: PHSpacing.xs, leading: PHSpacing.lg, bottom: PHSpacing.xs, trailing: PHSpacing.lg)
      )

      if model.history.isEmpty {
        examplesSection
      } else {
        historySection
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(PHColor.background)
    .navigationTitle("SQL")
  }

  private var canRun: Bool {
    !model.isRunning && !model.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var editor: some View {
    TextEditor(text: $model.queryText)
      .font(PHFont.mono(14, weight: .regular))
      .foregroundStyle(PHColor.textPrimary)
      .autocorrectionDisabled()
      .textInputAutocapitalization(.never)
      .scrollContentBackground(.hidden)
      .frame(minHeight: 120)
      .padding(PHSpacing.sm)
      .background(PHColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: PHRadius.control, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: PHRadius.control, style: .continuous)
          .strokeBorder(PHColor.border, lineWidth: 1)
      )
      .accessibilityLabel("SQL query")
  }

  private var runButton: some View {
    Button {
      Task { await model.run() }
    } label: {
      HStack(spacing: PHSpacing.sm) {
        if model.isRunning {
          ProgressView().tint(Color.white)
        }
        Text("Run")
          .font(.subheadline.weight(.bold))
      }
      .foregroundStyle(Color.white)
      .padding(.horizontal, PHSpacing.xl)
      .frame(minHeight: 44)
      .background(canRun ? PHColor.accent : PHColor.textInactive, in: Capsule())
    }
    .buttonStyle(.plain)
    .disabled(!canRun)
    .accessibilityLabel("Run query")
  }

  private func resultsCard(_ result: TableResult) -> some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.sm) {
        PHCardLabel("Results")
        TableResultView(table: result)
        Text(result.rows.count == 1 ? "1 row" : "\(result.rows.count) rows")
          .font(.caption)
          .foregroundStyle(PHColor.textTertiary)
        if result.hasMore || result.rows.count > 50 {
          Text("Showing first 50 rows")
            .font(.caption)
            .foregroundStyle(PHColor.textTertiary)
        }
      }
    }
  }

  private var examplesSection: some View {
    Section {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: PHSpacing.sm) {
          ForEach(Self.examples, id: \.title) { example in
            FilterChip(example.title, isSelected: false) {
              model.queryText = example.query
            }
          }
        }
      }
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    } header: {
      PHCardLabel("Examples")
    }
  }

  private var historySection: some View {
    Section {
      ForEach(model.history, id: \.self) { query in
        historyRow(query)
      }
      .listRowBackground(PHColor.surface)
    } header: {
      PHCardLabel("Recent queries")
    }
  }

  private func historyRow(_ query: String) -> some View {
    Button {
      model.queryText = query
    } label: {
      Text(query)
        .font(PHFont.mono(12, weight: .regular))
        .foregroundStyle(PHColor.textPrimary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button("Delete", role: .destructive) {
        model.removeFromHistory(query)
      }
    }
  }
}
