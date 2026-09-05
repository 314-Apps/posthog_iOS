import PostHogAPI
import PostHogDesignSystem
import PostHogDrilldown
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// The Max chat thread: transcript, suggested prompts, input bar.
public struct MaxChatView: View {
  @State private var model: MaxChatModel
  @State private var draft = ""
  @State private var drilldown: DrilldownTarget?

  private static let suggestedPrompts = [
    "What changed in signups this week?",
    "Summarize yesterday's errors",
    "Which flags rolled out recently?",
  ]

  private let bottomAnchorID = "max-thread-bottom"

  private let onOpenPerson: (String) -> Void

  public init(
    context: ProjectContext,
    tokenProvider: TokenProviding,
    onOpenPerson: @escaping (String) -> Void = { _ in }
  ) {
    self._model = State(initialValue: MaxChatModel(context: context, tokenProvider: tokenProvider))
    self.onOpenPerson = onOpenPerson
  }

  public var body: some View {
    VStack(spacing: 0) {
      transcript
      if let errorText = model.errorText {
        Text(errorText)
          .font(.footnote)
          .foregroundStyle(PHColor.danger)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, PHSpacing.lg)
          .padding(.top, PHSpacing.xs)
      }
      inputBar
    }
    .background(PHColor.background)
    .navigationTitle(model.conversationTitle ?? "Max")
    .navigationBarTitleDisplayMode(.inline)
    .actorsDrilldown($drilldown, context: model.context, onOpenPerson: onOpenPerson)
  }

  private var canSend: Bool {
    !model.isStreaming && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var showsTypingIndicator: Bool {
    guard model.isStreaming else { return false }
    guard let last = model.messages.last, last.role == .assistant else { return true }
    return last.text.isEmpty && last.visualization == nil
  }

  @ViewBuilder
  private var transcript: some View {
    if model.messages.isEmpty {
      emptyThread
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: PHSpacing.md) {
            ForEach(model.messages) { message in
              bubble(message)
            }
            if showsTypingIndicator {
              TypingIndicator()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Color.clear.frame(height: 1).id(bottomAnchorID)
          }
          .padding(.horizontal, PHSpacing.lg)
          .padding(.vertical, PHSpacing.md)
        }
        .onChange(of: model.messages) {
          withAnimation { proxy.scrollTo(bottomAnchorID, anchor: .bottom) }
        }
      }
    }
  }

  @ViewBuilder
  private func bubble(_ message: MaxMessage) -> some View {
    switch message.role {
    case .user:
      userBubble(message)
    case .assistant:
      assistantBubble(message)
    }
  }

  private func userBubble(_ message: MaxMessage) -> some View {
    Text(message.text)
      .font(.subheadline)
      .foregroundStyle(Color.white)
      .padding(.horizontal, PHSpacing.md)
      .padding(.vertical, PHSpacing.sm)
      .background(
        PHColor.accent,
        in: UnevenRoundedRectangle(
          topLeadingRadius: 18,
          bottomLeadingRadius: 18,
          bottomTrailingRadius: 4,
          topTrailingRadius: 18,
          style: .continuous
        )
      )
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.leading, PHSpacing.xxl)
  }

  @ViewBuilder
  private func assistantBubble(_ message: MaxMessage) -> some View {
    if let viz = message.visualization {
      PHCard {
        InsightRenderer(
          query: viz.query ?? DataQuery(raw: .object([:])),
          result: viz.result,
          onDrill: viz.query.map { query in { drilldown = DrilldownTarget(source: query, drill: $0) } }
        )
        .frame(maxHeight: 240)
      }
    } else if !message.text.isEmpty {
      // LocalizedStringKey gives streamed answers basic markdown for free.
      Text(LocalizedStringKey(message.text))
        .font(.subheadline)
        .foregroundStyle(PHColor.textPrimary)
        .padding(PHSpacing.md)
        .background(PHColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: PHRadius.card, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: PHRadius.card, style: .continuous)
            .strokeBorder(PHColor.border, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, PHSpacing.xxl)
    }
  }

  private var emptyThread: some View {
    VStack(spacing: PHSpacing.lg) {
      Spacer()
      Image(systemName: "sparkles")
        .font(.system(size: 36, weight: .medium))
        .foregroundStyle(PHColor.ai)
      Text("Ask Max about your product data")
        .font(.headline)
        .foregroundStyle(PHColor.textPrimary)
      VStack(spacing: PHSpacing.sm) {
        ForEach(Self.suggestedPrompts, id: \.self) { prompt in
          promptChip(prompt)
        }
      }
      Spacer()
    }
    .frame(maxWidth: .infinity)
    .padding(PHSpacing.xl)
  }

  private func promptChip(_ prompt: String) -> some View {
    Button {
      model.send(prompt)
    } label: {
      Text(prompt)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(PHColor.textPrimary)
        .padding(.horizontal, PHSpacing.lg)
        .frame(minHeight: 44)
        .background(PHColor.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(PHColor.border, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }

  private var inputBar: some View {
    HStack(alignment: .bottom, spacing: PHSpacing.sm) {
      TextField("Ask Max anything", text: $draft, axis: .vertical)
        .lineLimit(1...4)
        .font(.subheadline)
        .padding(.horizontal, PHSpacing.md)
        .padding(.vertical, PHSpacing.sm)
        .frame(minHeight: 44)
        .background(PHColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: PHRadius.control, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: PHRadius.control, style: .continuous)
            .strokeBorder(PHColor.border, lineWidth: 1)
        )
        .onSubmit(sendDraft)
      Button(action: sendDraft) {
        Image(systemName: "arrow.up")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(Color.white)
          .frame(width: 38, height: 38)
          .background(canSend ? PHColor.ai : PHColor.textInactive, in: Circle())
      }
      .buttonStyle(.plain)
      .disabled(!canSend)
      .accessibilityLabel("Send")
      .padding(.bottom, 3)
    }
    .padding(.horizontal, PHSpacing.lg)
    .padding(.vertical, PHSpacing.sm)
  }

  private func sendDraft() {
    guard canSend else { return }
    let text = draft
    draft = ""
    model.send(text)
  }
}

/// Three pulsing dots shown while Max is answering. Static under Reduce Motion.
struct TypingIndicator: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulsing = false

  var body: some View {
    HStack(spacing: 5) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(PHColor.textTertiary)
          .frame(width: 7, height: 7)
          .opacity(pulsing ? 0.3 : 1)
          .animation(
            reduceMotion
              ? nil
              : .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.2),
            value: pulsing
          )
      }
    }
    .padding(.horizontal, PHSpacing.md)
    .frame(minHeight: 34)
    .background(PHColor.surface, in: Capsule())
    .overlay(Capsule().strokeBorder(PHColor.border, lineWidth: 1))
    .onAppear {
      guard !reduceMotion else { return }
      pulsing = true
    }
    .accessibilityLabel("Max is thinking")
  }
}
