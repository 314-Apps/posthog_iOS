import PostHogDesignSystem
import PostHogFoundation
import SwiftUI

/// Transport bar under the player: play, scrub, and speed.
struct ReplayPlayerControls: View {
  @Bindable var player: ReplayPlayerModel

  @State private var scrubbing: Double?

  private let speeds: [Double] = [1, 2, 4, 8]

  var body: some View {
    VStack(spacing: PHSpacing.xs) {
      Slider(
        value: Binding(
          get: { scrubbing ?? player.position },
          set: { scrubbing = $0 }
        ),
        in: 0...max(player.duration, 1),
        onEditingChanged: { editing in
          guard !editing, let target = scrubbing else { return }
          player.seek(to: target)
          scrubbing = nil
        }
      )
      .tint(PHColor.accent)
      .accessibilityLabel("Playback position")

      HStack(spacing: PHSpacing.md) {
        Button {
          player.togglePlayback()
        } label: {
          Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            .font(.title3)
            .foregroundStyle(PHColor.textPrimary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

        Text("\(clock(scrubbing ?? player.position)) / \(clock(player.duration))")
          .font(.footnote)
          .monospacedDigit()
          .foregroundStyle(PHColor.textSecondary)

        Spacer()

        Menu {
          ForEach(speeds, id: \.self) { rate in
            Button("\(speedLabel(rate))x") { player.setSpeed(rate) }
          }
        } label: {
          Text("Speed")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(PHColor.link)
            .frame(minHeight: 44)
        }
      }
    }
  }

  private func clock(_ milliseconds: Double) -> String {
    MetricFormat.duration(seconds: Int((milliseconds / 1000).rounded(.down)))
  }

  private func speedLabel(_ rate: Double) -> String {
    rate == rate.rounded() ? String(Int(rate)) : String(rate)
  }
}
