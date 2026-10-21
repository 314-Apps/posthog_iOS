import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Read-only billing overview: plan name plus a usage gauge per product.
/// Plan changes stay on the web, so the screen ends at a pointer there.
public struct BillingView: View {
  @State private var model: BillingModel

  public init(context: ProjectContext) {
    self._model = State(initialValue: BillingModel(context: context))
  }

  public var body: some View {
    content
      .background(PHColor.background)
      .navigationTitle("Billing")
      .task { await model.load() }
  }

  @ViewBuilder private var content: some View {
    switch model.state {
    case .loading:
      ScrollView {
        VStack(spacing: PHSpacing.md) {
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 60)
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 90)
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 90)
        }
        .padding(PHSpacing.lg)
      }
    case .failed(let message):
      EmptyStateView(
        systemImage: "wifi.exclamationmark",
        title: "Couldn't load billing",
        message: message,
        actionTitle: "Retry"
      ) {
        Task { await model.load() }
      }
      .frame(maxHeight: .infinity)
    case .loaded where model.isEmpty:
      EmptyStateView(
        systemImage: "creditcard",
        title: "No billing details",
        message: "Billing details aren't available for this account."
      )
      .frame(maxHeight: .infinity)
    case .loaded:
      ScrollView {
        VStack(alignment: .leading, spacing: PHSpacing.md) {
          if let planName = model.status?.planName {
            planHeader(planName)
          }
          ForEach(Array(model.products.enumerated()), id: \.offset) { _, product in
            productCard(product)
          }
          Text("Manage your plan on the web.")
            .font(.footnote)
            .foregroundStyle(PHColor.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, PHSpacing.sm)
        }
        .padding(PHSpacing.lg)
      }
      .refreshable { await model.load() }
    }
  }

  private func planHeader(_ planName: String) -> some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.xs) {
        PHCardLabel("Current plan")
        Text(planName)
          .font(.title3.weight(.bold))
          .foregroundStyle(PHColor.textPrimary)
      }
    }
  }

  private func productCard(_ product: BillingProduct) -> some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.sm) {
        Text(productTitle(product))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(PHColor.textPrimary)
        if let fraction = usageFraction(product) {
          ProgressView(value: fraction)
            .tint(fraction > 0.9 ? PHColor.danger : PHColor.accent)
        }
        if let caption = usageCaption(product) {
          Text(caption)
            .font(.caption)
            .foregroundStyle(PHColor.textSecondary)
            .monospacedDigit()
        }
      }
    }
  }

  private func productTitle(_ product: BillingProduct) -> String {
    if let name = product.name, !name.isEmpty { return name }
    if let type = product.type, !type.isEmpty { return type }
    return "Product"
  }

  private func usageFraction(_ product: BillingProduct) -> Double? {
    guard let percentage = product.percentageUsage else { return nil }
    return min(max(percentage / 100, 0), 1)
  }

  private func usageCaption(_ product: BillingProduct) -> String? {
    guard let usage = product.currentUsage, let limit = product.usageLimit else { return nil }
    return "\(MetricFormat.compact(usage)) of \(MetricFormat.compact(limit))"
  }
}

@MainActor
@Observable
final class BillingModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var status: BillingStatus?

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  var products: [BillingProduct] { status?.products ?? [] }

  var isEmpty: Bool {
    guard let status else { return true }
    return status.planName == nil && status.products.isEmpty
  }

  func load() async {
    do {
      status = try await context.client.billingStatus()
      state = .loaded
    } catch {
      PHLog.api.error("billing load failed: \(error)")
      if status == nil {
        state = .failed("Check your connection and try again.")
      }
    }
  }
}
