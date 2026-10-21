import PostHogDesignSystem
import SwiftUI

/// Create or edit form for one alert. Save and delete disable their buttons
/// while a request is in flight so a tap can never double-submit.
struct AlertEditorSheet: View {
  @State private var model: AlertEditorModel
  @State private var confirmingDelete = false
  @Environment(\.dismiss) private var dismiss

  private let onComplete: () -> Void

  init(model: AlertEditorModel, onComplete: @escaping () -> Void) {
    self._model = State(initialValue: model)
    self.onComplete = onComplete
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $model.name)
          Toggle("Enabled", isOn: $model.enabled)
            .tint(PHColor.accent)
          Picker("Interval", selection: $model.interval) {
            ForEach(AlertEditorModel.intervals, id: \.value) { option in
              Text(option.label).tag(option.value)
            }
          }
        }
        Section {
          TextField("Lower bound", text: $model.lowerText)
            .keyboardType(.decimalPad)
          TextField("Upper bound", text: $model.upperText)
            .keyboardType(.decimalPad)
        } header: {
          Text("Threshold")
        } footer: {
          Text("Leave a bound empty to skip that check.")
        }
        if let errorMessage = model.errorMessage {
          Section {
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(PHColor.danger)
          }
        }
        if model.isEditingExisting {
          Section {
            deleteButton
          }
        }
      }
      .navigationTitle(model.isEditingExisting ? "Edit alert" : "New alert")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(model.isBusy)
        }
        ToolbarItem(placement: .confirmationAction) {
          saveButton
        }
      }
      .confirmationDialog(
        "Delete this alert?",
        isPresented: $confirmingDelete,
        titleVisibility: .visible
      ) {
        Button("Delete alert", role: .destructive) {
          Task {
            if await model.delete() {
              onComplete()
              dismiss()
            }
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Notifications for this alert stop immediately.")
      }
      .interactiveDismissDisabled(model.isBusy)
    }
  }

  private var saveButton: some View {
    Button {
      Task {
        if await model.save() {
          onComplete()
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
    .disabled(model.isBusy)
  }

  private var deleteButton: some View {
    Button(role: .destructive) {
      confirmingDelete = true
    } label: {
      if model.isDeleting {
        ProgressView()
      } else {
        Text("Delete alert")
      }
    }
    .disabled(model.isBusy)
  }
}
