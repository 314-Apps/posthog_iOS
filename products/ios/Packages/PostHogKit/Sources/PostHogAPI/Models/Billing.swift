import Foundation
import PostHogFoundation

/// One product row in the billing response. The billing serializer varies by
/// plan and deploy, so every field extracts through `JSONValue` and junk or
/// missing values become nil instead of failing the whole response.
public struct BillingProduct: Decodable, Sendable, Equatable {
  public let name: String?
  public let type: String?
  public let currentUsage: Double?
  public let usageLimit: Double?
  public let percentageUsage: Double?

  init(json: JSONValue) {
    self.name = json["name"]?.stringValue
    self.type = json["type"]?.stringValue
    self.currentUsage = json["current_usage"]?.numberValue
    self.usageLimit = json["usage_limit"]?.numberValue
    self.percentageUsage = json["percentage_usage"]?.numberValue
  }

  public init(from decoder: Decoder) throws {
    self.init(json: (try? JSONValue(from: decoder)) ?? .null)
  }
}

/// The billing overview. Decoding is fully defensive because `/api/billing/`
/// has no committed schema for this client to lock against.
public struct BillingStatus: Decodable, Sendable, Equatable {
  public let planName: String?
  public let products: [BillingProduct]

  public init(from decoder: Decoder) throws {
    let root = (try? JSONValue(from: decoder)) ?? .null
    let productEntries = root["products"]?.arrayValue ?? []
    self.planName =
      root["billing_plan"]?.stringValue
      ?? root["subscription"]?["plan"]?["name"]?.stringValue
      ?? productEntries.compactMap { $0["current_plan"]?["name"]?.stringValue }.first
    // Non-object entries carry nothing a row could show, so they drop out.
    self.products = productEntries.filter { $0.objectValue != nil }.map(BillingProduct.init(json:))
  }
}

extension APIClient {
  /// Org-level: the billing API has no project segment.
  public func billingStatus() async throws -> BillingStatus {
    try await send(.get("/api/billing/"))
  }
}
