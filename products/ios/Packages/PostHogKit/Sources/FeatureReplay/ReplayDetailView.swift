import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// One recording: person header, the embedded web player, and a video export
/// that lands in the share sheet.
public struct ReplayDetailView: View {
  @State private var model: ReplayDetailModel
  @State private var player: ReplayPlayerModel
  @State private var exporter: ReplayExportModel
  @State private var isWebLoading = true

  private let sessionID: String
  private let onOpenWeb: ((String) -> Void)?

  public init(context: ProjectContext, sessionID: String, onOpenWeb: ((String) -> Void)? = nil) {
    self._model = State(initialValue: ReplayDetailModel(context: context, sessionID: sessionID))
    self._player = State(initialValue: ReplayPlayerModel(context: context, sessionID: sessionID))
    self._exporter = State(initialValue: ReplayExportModel(context: context, sessionID: sessionID))
    self.sessionID = sessionID
    self.onOpenWeb = onOpenWeb
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        headerCard
        playerCard
        exportStatus
      }
      .padding(PHSpacing.lg)
    }
    .background(PHColor.background)
    .navigationTitle("Recording")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        exportAction
      }
    }
    .task { await model.load() }
    .task { await player.load() }
  }

  // MARK: Header

  @ViewBuilder
  private var headerCard: some View {
    if let recording = model.recording {
      PHCard {
        VStack(alignment: .leading, spacing: PHSpacing.xs) {
          Text(recording.personDisplay)
            .font(.headline)
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(1)
          Text(headerDetail(recording))
            .font(.caption)
            .foregroundStyle(PHColor.textSecondary)
            .monospacedDigit()
        }
      }
    } else if !model.loadFailed {
      SkeletonView(cornerRadius: PHRadius.card).frame(height: 72)
    }
  }

  private func headerDetail(_ recording: SessionRecording) -> String {
    var parts: [String] = []
    if let start = recording.startTime {
      parts.append("Started \(RelativeDateFormat.ago(start))")
    }
    if let duration = recording.recordingDuration {
      parts.append(MetricFormat.duration(seconds: Int(duration)))
    }
    return parts.joined(separator: " · ")
  }

  // MARK: Player

  @ViewBuilder
  private var playerCard: some View {
    switch player.state {
    case .loading:
      SkeletonView(cornerRadius: PHRadius.card)
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
    case .ready(let url):
      ZStack {
        PHColor.background
        ReplayWebPlayer(url: url, isLoading: $isWebLoading)
        if isWebLoading {
          SkeletonView(cornerRadius: PHRadius.card)
        }
      }
      .aspectRatio(16.0 / 10.0, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: PHRadius.card, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: PHRadius.card, style: .continuous)
          .strokeBorder(PHColor.border, lineWidth: 1)
      )
    case .unavailable:
      PHCard {
        VStack(alignment: .leading, spacing: PHSpacing.md) {
          Text(
            "This recording can't play in the app yet. Watch it on the web, "
              + "where it plays without a shared link."
          )
          .font(.subheadline)
          .foregroundStyle(PHColor.textSecondary)
          if let onOpenWeb {
            Button {
              onOpenWeb("/replay/\(sessionID)")
            } label: {
              Text("Open on web")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, PHSpacing.xl)
                .frame(minHeight: 44)
                .background(PHColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
          }
        }
      }
    case .failed:
      PHCard {
        VStack(alignment: .leading, spacing: PHSpacing.md) {
          Text("Couldn't load the player. Check your connection and try again.")
            .font(.subheadline)
            .foregroundStyle(PHColor.textSecondary)
          Button {
            isWebLoading = true
            Task { await player.load() }
          } label: {
            Text("Retry")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(Color.white)
              .padding(.horizontal, PHSpacing.xl)
              .frame(minHeight: 44)
              .background(PHColor.accent, in: Capsule())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  // MARK: Export

  @ViewBuilder
  private var exportAction: some View {
    switch exporter.state {
    case .rendering:
      ProgressView()
    case .ready(let fileURL):
      ShareLink(item: fileURL)
    case .idle, .failed:
      Menu {
        Button {
          Task { await exporter.export() }
        } label: {
          Label("Export video", systemImage: "square.and.arrow.up")
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
    }
  }

  @ViewBuilder
  private var exportStatus: some View {
    switch exporter.state {
    case .rendering:
      HStack(spacing: PHSpacing.sm) {
        ProgressView()
        Text("Rendering on the server. This can take a minute.")
          .font(.footnote)
          .foregroundStyle(PHColor.textSecondary)
      }
    case .failed(let message):
      Text(message)
        .font(.footnote)
        .foregroundStyle(PHColor.danger)
    case .ready:
      Text("Video ready. Share it from the toolbar.")
        .font(.footnote)
        .foregroundStyle(PHColor.textSecondary)
    case .idle:
      EmptyView()
    }
  }
}

@MainActor
@Observable
final class ReplayDetailModel {
  private(set) var recording: SessionRecording?
  private(set) var loadFailed = false

  private let context: ProjectContext
  private let sessionID: String

  init(context: ProjectContext, sessionID: String) {
    self.context = context
    self.sessionID = sessionID
  }

  func load() async {
    loadFailed = false
    do {
      recording = try await context.client.sessionRecording(
        projectID: context.projectID,
        sessionID: sessionID
      )
    } catch {
      PHLog.api.error("recording load failed: \(error)")
      if recording == nil {
        loadFailed = true
      }
    }
  }
}
