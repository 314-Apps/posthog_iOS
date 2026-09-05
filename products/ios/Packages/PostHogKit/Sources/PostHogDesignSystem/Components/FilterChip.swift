import SwiftUI

/// Selectable pill for date presets, statuses, and segmented rows.
/// Selected = filled accent, per the design language.
public struct FilterChip: View {
  private let title: String
  private let isSelected: Bool
  private let action: () -> Void

  public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
    self.title = title
    self.isSelected = isSelected
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Text(title)
        .font(.footnote.weight(isSelected ? .bold : .semibold))
        .foregroundStyle(isSelected ? Color.white : PHColor.textSecondary)
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background(isSelected ? PHColor.accent : PHColor.surface, in: Capsule())
        .overlay(
          Capsule().strokeBorder(isSelected ? PHColor.accent : PHColor.border, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .sensoryFeedback(.selection, trigger: isSelected) { old, new in new && !old }
  }
}
