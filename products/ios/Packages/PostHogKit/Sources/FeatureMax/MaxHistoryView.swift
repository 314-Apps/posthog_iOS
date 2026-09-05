import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Past Max conversations. Rows open a fresh thread for now because the API
/// for replaying a stored transcript is not wired yet.
public struct MaxHistoryView: View {
  @State private var model: MaxHistoryModel
  private let onOpenNew: () -> Void

  public init(context: ProjectContext, onOpenNew: @escaping () -> Void) {
    self._model = State(initialValue: MaxHistoryModel(context: context))
    self.onOpenNew = onOpenNew
  }

  public var body: some View {
    Group {
      switch model.phase {
      case .loading:
        loadingList
      case .failed:
        EmptyStateView(
          systemImage: "bubble.left.and.bubble.right",
          title: "Couldn't load conversations",
          message: "Check your connection and try again.",
          actionTitle: "Retry"
        ) {
          Task { await model.load() }
        }
      case .ready:
        if model.conversations.isEmpty {
          EmptyStateView(
            systemImage: "sparkles",
            title: "No conversations yet",
            message: "Start one and ask Max about your data.",
            actionTitle: "New conversation",
            action: onOpenNew
          )
        } else {
          conversationList
        }
      }
    }
    .background(PHColor.background)
    .navigationTitle("Conversations")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(action: onOpenNew) {
          Label("New conversation", systemImage: "square.and.pencil")
        }
      }
    }
    .task { await model.load() }
  }

  private var loadingList: some View {
    List {
      ForEach(0..<8, id: \.self) { _ in
        SkeletonView(cornerRadius: 10).frame(height: 44).listRowBackground(Color.clear)
      }
    }
    .listStyle(.plain)
  }

  private var conversationList: some View {
    List {
      if let errorText = model.deleteErrorText {
        Text(errorText)
          .font(.footnote)
          .foregroundStyle(PHColor.danger)
          .listRowBackground(Color.clear)
      }
      ForEach(model.conversations) { conversation in
        row(conversation)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .refreshable { await model.load() }
  }

  private func row(_ conversation: Conversation) -> some View {
    Button(action: onOpenNew) {
      VStack(alignment: .leading, spacing: 2) {
        Text(conversation.title?.isEmpty == false ? conversation.title! : "Untitled conversation")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(PHColor.textPrimary)
          .lineLimit(2)
        if let createdAt = conversation.createdAt {
          Text(RelativeDateFormat.ago(createdAt))
            .font(.caption)
            .foregroundStyle(PHColor.textTertiary)
        }
      }
      .frame(minHeight: 44)
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button("Delete", role: .destructive) {
        Task { await model.delete(conversation) }
      }
    }
  }
}

@MainActor
@Observable
final class MaxHistoryModel {
  enum Phase {
    case loading
    case failed
    case ready
  }

  private(set) var phase: Phase = .loading
  private(set) var conversations: [Conversation] = []
  private(set) var deleteErrorText: String?

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  func load() async {
    if conversations.isEmpty {
      phase = .loading
    }
    do {
      let page = try await context.client.conversations(projectID: context.projectID)
      conversations = page.results
      phase = .ready
    } catch is CancellationError {
      return
    } catch {
      PHLog.api.error("conversation list failed: \(error)")
      if conversations.isEmpty {
        phase = .failed
      }
    }
  }

  /// Optimistic: the row disappears immediately and returns if the delete fails.
  func delete(_ conversation: Conversation) async {
    guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
    deleteErrorText = nil
    conversations.remove(at: index)
    do {
      try await context.client.deleteConversation(
        projectID: context.projectID,
        conversationID: conversation.id
      )
    } catch {
      conversations.insert(conversation, at: min(index, conversations.count))
      deleteErrorText = "Couldn't delete the conversation. Try again."
    }
  }
}
