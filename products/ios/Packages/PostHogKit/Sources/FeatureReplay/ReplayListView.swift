import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Session recordings, newest first. Date chips re-run the REST list;
/// rows open the detail player.
public struct ReplayListView: View {
  enum DatePreset: String, CaseIterable {
    case day = "24h"
    case week = "7d"
    case month = "30d"

    var dateFrom: String {
      switch self {
      case .day: "-24h"
      case .week: "-7d"
      case .month: "-30d"
      }
    }
  }

  @State private var model: ReplayListModel

  private let onOpen: (String) -> Void

  public init(context: ProjectContext, onOpen: @escaping (String) -> Void) {
    self._model = State(initialValue: ReplayListModel(context: context))
    self.onOpen = onOpen
  }

  public var body: some View {
    VStack(spacing: PHSpacing.sm) {
      dateChips
      content
    }
    .background(PHColor.background)
    .navigationTitle("Replay")
    .task { await model.load() }
  }

  private var dateChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: PHSpacing.sm) {
        ForEach(DatePreset.allCases, id: \.self) { preset in
          FilterChip(preset.rawValue, isSelected: model.datePreset == preset) {
            model.datePreset = preset
            Task { await model.reload() }
          }
        }
      }
      .padding(.horizontal, PHSpacing.lg)
    }
    .padding(.top, PHSpacing.sm)
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      List {
        ForEach(0..<6, id: \.self) { _ in
          SkeletonView(cornerRadius: 10).frame(height: 72).listRowBackground(Color.clear)
        }
      }
      .listStyle(.plain)
    case .failed(let message):
      EmptyStateView(
        systemImage: "wifi.exclamationmark",
        title: "Couldn't load recordings",
        message: message,
        actionTitle: "Retry"
      ) {
        Task { await model.load(forceRefresh: true) }
      }
      .frame(maxHeight: .infinity)
    case .loaded where model.recordings.isEmpty:
      EmptyStateView(
        systemImage: "play.rectangle",
        title: "No recordings yet",
        message: "Recordings appear once session replay is enabled in your SDKs."
      )
      .frame(maxHeight: .infinity)
    case .loaded:
      List(model.recordings) { recording in
        rowView(recording)
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .refreshable { await model.load(forceRefresh: true) }
    }
  }

  private func rowView(_ recording: SessionRecording) -> some View {
    Button {
      onOpen(recording.id)
    } label: {
      VStack(alignment: .leading, spacing: PHSpacing.xs) {
        HStack(spacing: PHSpacing.sm) {
          Text(recording.personDisplay)
            .font(.body.weight(.semibold))
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(1)
          Spacer()
          if let errors = recording.consoleErrorCount, errors > 0 {
            ConsoleErrorBadge(count: errors)
          }
        }
        Text(rowDetail(recording))
          .font(.caption)
          .foregroundStyle(PHColor.textSecondary)
          .monospacedDigit()
          .lineLimit(1)
      }
      .padding(.vertical, PHSpacing.xs)
      .opacity(recording.viewed ? 0.6 : 1)
    }
  }

  private func rowDetail(_ recording: SessionRecording) -> String {
    var parts: [String] = []
    if let start = recording.startTime {
      parts.append(RelativeDateFormat.ago(start))
    }
    if let duration = recording.recordingDuration {
      parts.append(MetricFormat.duration(seconds: Int(duration)))
    }
    if let clicks = recording.clickCount {
      parts.append("\(MetricFormat.compact(clicks)) clicks")
    }
    return parts.joined(separator: " · ")
  }
}

/// Console-error count capsule; only rendered when the count is positive.
struct ConsoleErrorBadge: View {
  let count: Int

  var body: some View {
    Label("\(count)", systemImage: "exclamationmark.triangle.fill")
      .font(.caption2.weight(.bold))
      .foregroundStyle(PHColor.danger)
      .padding(.horizontal, PHSpacing.sm)
      .padding(.vertical, 3)
      .background(PHColor.dangerFill.opacity(0.14), in: Capsule())
  }
}

@MainActor
@Observable
final class ReplayListModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var recordings: [SessionRecording] = []
  var datePreset: ReplayListView.DatePreset = .week

  private let context: ProjectContext
  /// Bumped per load so a slow response for old filters cannot overwrite fresh rows.
  private var generation = 0

  init(context: ProjectContext) {
    self.context = context
  }

  /// Filter changes drop stale rows so skeletons show while the list re-runs.
  func reload() async {
    recordings = []
    state = .loading
    await load(forceRefresh: true)
  }

  func load(forceRefresh: Bool = false) async {
    generation += 1
    let requested = generation
    let key = context.cacheKey("replay-list")
    if !forceRefresh, recordings.isEmpty, isDefaultFilters {
      if let hit = await context.cache.read(key, as: [SessionRecording].self, staleAfter: 120) {
        recordings = hit.value
        state = .loaded
        if !hit.isStale { return }
      }
    }
    do {
      let page = try await context.client.sessionRecordings(
        projectID: context.projectID,
        dateFrom: datePreset.dateFrom
      )
      guard requested == generation else { return }
      recordings = page.results
      state = .loaded
      if isDefaultFilters {
        await context.cache.write(key, value: recordings)
      }
    } catch {
      guard requested == generation, recordings.isEmpty else { return }
      state = .failed("Check your connection and try again.")
    }
  }

  /// The cache holds only the default view, so filtered results cannot paint
  /// the next cold launch.
  private var isDefaultFilters: Bool {
    datePreset == .week
  }
}
