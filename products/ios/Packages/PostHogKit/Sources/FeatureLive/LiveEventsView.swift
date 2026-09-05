import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Live events tail. The feed pauses when the reader scrolls away from the
/// top, because rows inserting above make the list unreadable, and stops
/// whenever the app leaves the foreground so the socket does not drain the
/// battery for rows nobody sees.
public struct LiveEventsView: View {
  @State private var model: LiveEventsModel
  @State private var selectedEvent: LiveEvent?
  @State private var pausedByScroll = false
  @Environment(\.scenePhase) private var scenePhase

  private let topAnchorID = "live-feed-top"

  public init(context: ProjectContext) {
    self._model = State(initialValue: LiveEventsModel(context: context))
  }

  public var body: some View {
    Group {
      switch model.phase {
      case .loading:
        loadingList
      case .unavailable:
        EmptyStateView(
          systemImage: "bolt.slash",
          title: "Live events aren't available for this project",
          message: "Open live events on the web to check your setup."
        )
      case .failed:
        EmptyStateView(
          systemImage: "wifi.exclamationmark",
          title: "Couldn't reach live events",
          message: "Check your connection and try again.",
          actionTitle: "Retry"
        ) {
          Task { await model.prepare() }
        }
      case .ready:
        if let feed = model.feed {
          feedView(feed)
        }
      }
    }
    .background(PHColor.background)
    .navigationTitle("Live events")
    .task { await model.prepare() }
    .onDisappear { model.suspend() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        model.resumeLive()
      } else {
        model.suspend()
      }
    }
    .sheet(item: $selectedEvent) { event in
      LiveEventDetailView(event: event)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
  }

  private var loadingList: some View {
    List {
      ForEach(0..<8, id: \.self) { _ in
        SkeletonView(cornerRadius: 10).frame(height: 44).listRowBackground(Color.clear)
      }
    }
    .listStyle(.plain)
  }

  private func feedView(_ feed: LiveFeedModel) -> some View {
    @Bindable var feed = feed
    return VStack(spacing: 0) {
      statusBar(feed)
      feedContent(feed)
    }
    .searchable(text: $feed.filter, prompt: "Filter by event or distinct ID")
  }

  @ViewBuilder
  private func feedContent(_ feed: LiveFeedModel) -> some View {
    if feed.rows.isEmpty {
      if feed.connectionState == .dropped {
        EmptyStateView(
          systemImage: "wifi.exclamationmark",
          title: "Connection dropped",
          message: "Check your connection and retry.",
          actionTitle: "Retry"
        ) {
          feed.start()
        }
      } else {
        EmptyStateView(
          systemImage: "dot.radiowaves.left.and.right",
          title: "Waiting for events",
          message: "Events appear here the moment your SDKs send them."
        )
      }
    } else if feed.visibleRows.isEmpty {
      EmptyStateView(
        systemImage: "magnifyingglass",
        title: "No matching events",
        message: "Try a different event name or ID."
      )
    } else {
      feedList(feed)
    }
  }

  private func feedList(_ feed: LiveFeedModel) -> some View {
    ScrollViewReader { proxy in
      List {
        topSentinel(feed)
        ForEach(feed.visibleRows) { event in
          row(event, feed: feed)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .overlay(alignment: .top) {
        if feed.isPaused {
          pausedPill(feed, proxy: proxy)
        }
      }
    }
  }

  /// Zero-height first row: visible means the reader is at the top, so the
  /// tail may move; scrolled off screen means they are reading, so it pauses.
  private func topSentinel(_ feed: LiveFeedModel) -> some View {
    Color.clear
      .frame(height: 1)
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
      .id(topAnchorID)
      .onAppear {
        if pausedByScroll {
          pausedByScroll = false
          feed.resume()
        }
      }
      .onDisappear {
        // An empty filter result tears the list down too; that is not a scroll,
        // and pausing then would hide matches that arrive while it shows.
        if !feed.isPaused, !feed.visibleRows.isEmpty {
          pausedByScroll = true
          feed.pause()
        }
      }
  }

  private func row(_ event: LiveEvent, feed: LiveFeedModel) -> some View {
    Button {
      selectedEvent = event
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: PHSpacing.md) {
        VStack(alignment: .leading, spacing: 2) {
          Text(event.event)
            .font(event.event.hasPrefix("$") ? PHFont.mono(14) : .subheadline.weight(.semibold))
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(1)
          Text(event.distinctID)
            .font(.caption)
            .foregroundStyle(PHColor.textSecondary)
            .lineLimit(1)
        }
        Spacer()
        Text(feed.timeLabel(for: event))
          .font(.caption)
          .foregroundStyle(PHColor.textTertiary)
      }
      .frame(minHeight: 44)
    }
  }

  private func statusBar(_ feed: LiveFeedModel) -> some View {
    HStack(spacing: PHSpacing.sm) {
      statusPill(feed)
      if feed.connectionState == .dropped {
        Button("Retry") {
          feed.start()
        }
        .font(.footnote.weight(.bold))
        .foregroundStyle(PHColor.link)
      }
      Spacer()
      Button {
        pausedByScroll = false
        if feed.isPaused {
          feed.resume()
        } else {
          feed.pause()
        }
      } label: {
        Image(systemName: feed.isPaused ? "play.fill" : "pause.fill")
          .font(.footnote.weight(.bold))
          .foregroundStyle(PHColor.textSecondary)
          .frame(width: 34, height: 34)
          .background(PHColor.surface, in: Circle())
          .overlay(Circle().strokeBorder(PHColor.border, lineWidth: 1))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(feed.isPaused ? "Resume" : "Pause")
    }
    .padding(.horizontal, PHSpacing.lg)
    .padding(.vertical, PHSpacing.sm)
  }

  private func statusPill(_ feed: LiveFeedModel) -> some View {
    HStack(spacing: 6) {
      switch feed.connectionState {
      case .connecting:
        Text("Connecting…")
          .foregroundStyle(PHColor.textSecondary)
      case .live:
        PulsingDot()
        Text("Live")
          .foregroundStyle(PHColor.success)
      case .dropped:
        Text("Connection dropped")
          .foregroundStyle(PHColor.danger)
      }
    }
    .font(.caption.weight(.bold))
    .padding(.horizontal, PHSpacing.md)
    .frame(minHeight: 28)
    .background(PHColor.surface, in: Capsule())
    .overlay(Capsule().strokeBorder(PHColor.border, lineWidth: 1))
  }

  private func pausedPill(_ feed: LiveFeedModel, proxy: ScrollViewProxy) -> some View {
    Button {
      pausedByScroll = false
      feed.resume()
      withAnimation { proxy.scrollTo(topAnchorID, anchor: .top) }
    } label: {
      Label(pausedLabel(feed.bufferedCount), systemImage: "arrow.up")
        .font(.footnote.weight(.bold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background(PHColor.accent, in: Capsule())
    }
    .buttonStyle(.plain)
    .padding(.top, PHSpacing.sm)
    .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
  }

  private func pausedLabel(_ count: Int) -> String {
    switch count {
    case 0: "Paused"
    case 1: "1 new event"
    default: "\(count) new events"
    }
  }
}

/// The "live" indicator. Stays static under Reduce Motion.
struct PulsingDot: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulsing = false

  var body: some View {
    Circle()
      .fill(PHColor.successFill)
      .frame(width: 8, height: 8)
      .opacity(pulsing ? 0.4 : 1)
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
          pulsing = true
        }
      }
      .accessibilityHidden(true)
  }
}

@MainActor
@Observable
final class LiveEventsModel {
  enum Phase {
    case loading
    case unavailable
    case failed
    case ready
  }

  private(set) var phase: Phase = .loading
  private(set) var feed: LiveFeedModel?

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  func prepare() async {
    if let feed {
      feed.start()
      return
    }
    phase = .loading
    do {
      let detail = try await context.client.projectDetail(projectID: context.projectID)
      guard let token = detail.liveEventsToken, !token.isEmpty else {
        phase = .unavailable
        return
      }
      guard let liveBase = context.region.livestreamBaseURL else {
        phase = .unavailable
        return
      }
      let sse = SSEClient()
      let url = liveBase.appending(path: "/events")
      let headers = ["Authorization": "Bearer \(token)"]
      let feed = LiveFeedModel(events: { sse.events(url: url, headers: headers) })
      self.feed = feed
      phase = .ready
      feed.start()
    } catch is CancellationError {
      return
    } catch {
      PHLog.sse.error("live events token fetch failed: \(error)")
      phase = .failed
    }
  }

  func suspend() {
    feed?.stop()
  }

  func resumeLive() {
    guard let feed, !feed.isStreaming else { return }
    feed.start()
  }
}
