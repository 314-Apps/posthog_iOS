import Foundation
import PostHogAPI

/// Everything a feature needs to talk to one project on one instance.
/// Built by the app shell per signed-in session; features take it by value.
public struct ProjectContext: Sendable {
  public let region: Region
  public let projectID: Int
  public let client: APIClient
  public let runner: QueryRunner
  public let cache: DiskCache

  public init(region: Region, projectID: Int, client: APIClient, cache: DiskCache) {
    self.region = region
    self.projectID = projectID
    self.client = client
    self.runner = QueryRunner(client: client)
    self.cache = cache
  }

  /// Cache keys are namespaced per region + project so switches are clean.
  public func cacheKey(_ resource: String) -> String {
    "\(region.storageKey)/\(projectID)/\(resource)"
  }
}
