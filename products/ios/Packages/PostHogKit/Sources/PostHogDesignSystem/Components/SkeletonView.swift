import SwiftUI

/// Shimmer placeholder applied to real layouts — skeletons keep content shape,
/// never full-screen spinners. Honors Reduce Motion by staying static.
public struct SkeletonView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var phase: CGFloat = -1

  private let cornerRadius: CGFloat

  public init(cornerRadius: CGFloat = 8) {
    self.cornerRadius = cornerRadius
  }

  public var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(PHColor.divider)
      .overlay {
        if !reduceMotion {
          GeometryReader { proxy in
            LinearGradient(
              colors: [.clear, Color.white.opacity(0.5), .clear],
              startPoint: .leading,
              endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.6)
            .offset(x: phase * proxy.size.width * 1.6)
          }
          .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
          .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
              phase = 1
            }
          }
        }
      }
      .accessibilityHidden(true)
  }
}
