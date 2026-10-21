import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Project annotations: list, create sheet, and swipe-to-delete. Deletes are
/// optimistic because a swipe must feel instant; the row returns if the API
/// rejects the change.
public struct AnnotationsView: View {
  @State private var model: AnnotationsModel
  @State private var isCreating = false

  private let context: ProjectContext

  public init(context: ProjectContext) {
    self.context = context
    self._model = State(initialValue: AnnotationsModel(context: context))
  }

  public var body: some View {
    content
      .background(PHColor.background)
      .navigationTitle("Annotations")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            isCreating = true
          } label: {
            Image(systemName: "plus")
          }
          .accessibilityLabel("New annotation")
        }
      }
      .sheet(isPresented: $isCreating) {
        AnnotationCreateSheet(model: AnnotationCreateModel(context: context)) {
          Task { await model.load() }
        }
      }
      .task { await model.load() }
  }

  @ViewBuilder private var content: some View {
    switch model.state {
    case .loading:
      List {
        ForEach(0..<6, id: \.self) { _ in
          SkeletonView(cornerRadius: 10).frame(height: 64).listRowBackground(Color.clear)
        }
      }
      .listStyle(.plain)
    case .failed(let message):
      EmptyStateView(
        systemImage: "wifi.exclamationmark",
        title: "Couldn't load annotations",
        message: message,
        actionTitle: "Retry"
      ) {
        Task { await model.load() }
      }
      .frame(maxHeight: .infinity)
    case .loaded where model.annotations.isEmpty:
      EmptyStateView(
        systemImage: "pin",
        title: "No annotations yet",
        message: "Mark releases and incidents so charts show why a metric moved.",
        actionTitle: "New annotation"
      ) {
        isCreating = true
      }
      .frame(maxHeight: .infinity)
    case .loaded:
      List {
        ForEach(model.annotations) { annotation in
          row(annotation)
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .refreshable { await model.load() }
    }
  }

  private func row(_ annotation: Annotation) -> some View {
    VStack(alignment: .leading, spacing: PHSpacing.xs) {
      Text(displayContent(annotation))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(PHColor.textPrimary)
        .lineLimit(3)
      HStack(spacing: PHSpacing.sm) {
        if let marker = annotation.dateMarker {
          Text(marker.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(PHColor.textSecondary)
        }
        if let scope = annotation.scope, !scope.isEmpty {
          scopeBadge(scope)
        }
      }
    }
    .padding(.vertical, PHSpacing.xs)
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button("Delete", role: .destructive) {
        Task { await model.delete(annotation) }
      }
    }
  }

  private func displayContent(_ annotation: Annotation) -> String {
    guard let content = annotation.content, !content.isEmpty else { return "No text" }
    return content
  }

  private func scopeBadge(_ scope: String) -> some View {
    Text(scopeLabel(scope))
      .font(.caption2.weight(.bold))
      .foregroundStyle(PHColor.textSecondary)
      .padding(.horizontal, PHSpacing.sm)
      .padding(.vertical, 2)
      .background(PHColor.divider, in: Capsule())
  }

  private func scopeLabel(_ scope: String) -> String {
    let spaced = scope.replacingOccurrences(of: "_", with: " ")
    return spaced.prefix(1).uppercased() + spaced.dropFirst()
  }
}

/// Create form for one annotation. Save disables itself while the request is
/// in flight so a tap can never double-submit.
struct AnnotationCreateSheet: View {
  @State private var model: AnnotationCreateModel
  @Environment(\.dismiss) private var dismiss

  private let onCreated: () -> Void

  init(model: AnnotationCreateModel, onCreated: @escaping () -> Void) {
    self._model = State(initialValue: model)
    self.onCreated = onCreated
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("What happened?", text: $model.content, axis: .vertical)
            .lineLimit(3...6)
          DatePicker("Date", selection: $model.dateMarker)
        } footer: {
          Text("Shows on charts at this date.")
        }
        if let errorMessage = model.errorMessage {
          Section {
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(PHColor.danger)
          }
        }
      }
      .navigationTitle("New annotation")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(model.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          saveButton
        }
      }
      .interactiveDismissDisabled(model.isSaving)
    }
  }

  private var saveButton: some View {
    Button {
      Task {
        if await model.save() {
          onCreated()
          dismiss()
        }
      }
    } label: {
      if model.isSaving {
        ProgressView()
      } else {
        Text("Save")
      }
    }
    .disabled(model.isSaving)
  }
}

@MainActor
@Observable
final class AnnotationsModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var annotations: [Annotation] = []

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  func load() async {
    do {
      let page = try await context.client.annotations(projectID: context.projectID)
      annotations = page.results
      state = .loaded
    } catch {
      PHLog.api.error("annotations load failed: \(error)")
      if annotations.isEmpty {
        state = .failed("Check your connection and try again.")
      }
    }
  }

  func delete(_ annotation: Annotation) async {
    guard let index = annotations.firstIndex(of: annotation) else { return }
    let previous = annotations
    annotations.remove(at: index)
    do {
      try await context.client.deleteAnnotation(projectID: context.projectID, annotationID: annotation.id)
    } catch {
      PHLog.api.error("annotation delete failed: \(error)")
      annotations = previous
    }
  }
}

@MainActor
@Observable
final class AnnotationCreateModel {
  var content = ""
  var dateMarker: Date = .now
  private(set) var isSaving = false
  private(set) var errorMessage: String?

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  /// Returns true when the save landed, so the sheet can dismiss.
  func save() async -> Bool {
    guard !isSaving else { return false }
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      errorMessage = "Enter what happened before you save."
      return false
    }
    isSaving = true
    defer { isSaving = false }
    errorMessage = nil
    do {
      _ = try await context.client.createAnnotation(
        projectID: context.projectID,
        content: trimmed,
        dateMarker: dateMarker
      )
      return true
    } catch {
      PHLog.api.error("annotation create failed: \(error)")
      errorMessage = "Couldn't save the annotation. Try again."
      return false
    }
  }
}
