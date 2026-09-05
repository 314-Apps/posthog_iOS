#if DEBUG
  import Foundation
  import PostHogAPI
  import PostHogAuth
  import PostHogFoundation

  /// In-process canned server for UI-test scenarios: golden paths run against
  /// deterministic fixtures, no network. Debug builds only.
  final class FixtureTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var flagActive = true

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      var path = request.url?.path() ?? ""
      if path.hasSuffix("/") { path.removeLast() }
      let method = request.httpMethod ?? "GET"
      let body = respond(path: path, method: method, requestBody: request.httpBody)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
      )!
      return (Data(body.utf8), response)
    }

    // swiftlint:disable function_body_length
    private func respond(path: String, method: String, requestBody: Data?) -> String {
      switch (method, path) {
      case ("GET", "/api/users/@me"):
        return #"""
          {"id": 1, "uuid": "0001-uitest", "email": "demo@example.com", "first_name": "Demo",
           "organizations": [{"id": "org-1", "name": "Hogflix"}],
           "organization": {"id": "org-1"}, "team": {"id": 1}}
          """#
      case ("GET", "/api/organizations/org-1/projects"):
        return #"""
          {"count": 1, "next": null, "previous": null,
           "results": [{"id": 1, "name": "Hogflix", "organization": "org-1"}]}
          """#
      case ("GET", "/api/projects/1/dashboards"):
        return #"""
          {"count": 2, "next": null, "previous": null, "results": [
            {"id": 10, "name": "Growth overview", "description": "Signups and conversion", "pinned": true},
            {"id": 11, "name": "Revenue", "description": null, "pinned": false}]}
          """#
      case ("GET", "/api/projects/1/dashboards/10"):
        return #"""
          {"id": 10, "name": "Growth overview", "description": "Signups and conversion", "pinned": true,
           "tiles": [{"id": 100, "text": null, "insight": {
              "id": 500, "short_id": "abc123", "name": "Weekly signups", "derived_name": null,
              "query": {"kind": "TrendsQuery", "series": [{"kind": "EventsNode", "event": "user signed up"}],
                        "interval": "day", "dateRange": {"date_from": "-7d"}},
              "result": [{"label": "user signed up", "count": 11573,
                          "data": [1180, 1287, 1349, 1502, 1610, 2141, 2504],
                          "labels": ["8-Mar", "9-Mar", "10-Mar", "11-Mar", "12-Mar", "13-Mar", "14-Mar"],
                          "days": []}]}}]}
          """#
      case ("GET", "/api/projects/1/feature_flags"):
        return flagsList()
      case ("GET", "/api/projects/1/feature_flags/42"):
        return flagDetail()
      case ("POST", "/api/projects/1/feature_flags/42/enable"):
        lock.withLock { flagActive = true }
        return flagDetail()
      case ("POST", "/api/projects/1/feature_flags/42/disable"):
        lock.withLock { flagActive = false }
        return flagDetail()
      case ("GET", "/api/projects/1/feature_flags/42/activity"):
        return #"""
          {"count": 1, "next": null, "previous": null, "results": [
            {"id": "1", "activity": "updated", "created_at": "2026-03-14T09:26:53Z",
             "user": {"first_name": "Annika", "email": "annika@example.com"}, "detail": {}}]}
          """#
      case ("GET", "/api/projects/1/notifications"):
        return #"""
          {"count": 1, "next": null, "previous": null, "results": [
            {"id": "n1", "type": "alert_firing", "title": "Alert firing: API error rate",
             "body": "Error rate above 0.5% for 15 min on API health",
             "priority": "critical", "created_at": "2026-03-14T09:12:00Z", "is_read": false,
             "resource_type": "insight", "resource_id": "500"}]}
          """#
      case ("GET", "/api/projects/1/notifications/unread_count"):
        return #"{"count": 1}"#
      case ("GET", "/api/projects/1/alerts"):
        return #"{"count": 0, "next": null, "previous": null, "results": []}"#
      case ("POST", "/api/projects/1/query"):
        // The same endpoint answers a drill-down, so the body picks the shape.
        if let requestBody, String(bytes: requestBody, encoding: .utf8)?.contains("ActorsQuery") == true {
          return actorsPage()
        }
        return #"""
          {"results": [{"label": "dau", "count": 12847,
                        "data": [900, 1100, 1400, 1700, 2100, 2600, 3047],
                        "labels": ["9a", "10a", "11a", "12p", "1p", "2p", "3p"], "days": [],
                        "compare_label": "current"},
                       {"label": "dau", "count": 11428,
                        "data": [850, 1000, 1250, 1500, 1900, 2300, 2628],
                        "labels": [], "days": [], "compare_label": "previous"}]}
          """#
      default:
        return #"{"count": 0, "next": null, "previous": null, "results": []}"#
      }
    }
    // swiftlint:enable function_body_length

    private func actorsPage() -> String {
      #"""
      {"columns": ["person", "created_at"], "hasMore": false, "missing_actors_count": 0,
       "hogql": "SELECT persons.id FROM persons LIMIT 100",
       "results": [
         [{"id": "0198c4a1-0000-4000-8000-000000000001", "distinct_ids": ["seat-1a2b3c"],
           "properties": {"email": "ada@example.com"}}, "2026-03-14T09:00:00Z"],
         [{"id": "0198c4a1-0000-4000-8000-000000000002", "distinct_ids": ["seat-4d5e6f"],
           "properties": {"name": "Rowan Pike"}}, "2026-03-14T09:05:00Z"]]}
      """#
    }

    private func flagsList() -> String {
      #"{"count": 1, "next": null, "previous": null, "results": [\#(flagJSON())]}"#
    }

    private func flagDetail() -> String { flagJSON() }

    private func flagJSON() -> String {
      let active = lock.withLock { flagActive }
      return #"""
        {"id": 42, "key": "new-billing-flow", "name": "New hosted billing checkout",
         "active": \#(active), "deleted": false,
         "filters": {"groups": [{"properties": [], "rollout_percentage": 34}]}}
        """#
    }
  }

  extension StoredSession {
    /// The seeded session UI-test scenarios sign in with.
    static var uiTestFixture: StoredSession {
      StoredSession(
        accessToken: "pha_uitest",
        refreshToken: "rt_uitest",
        expiresAt: Date.now.addingTimeInterval(3600),
        region: .us,
        scopeVersion: AuthConfiguration.scopeVersion,
        scopedTeams: [1],
        selectedProjectID: 1
      )
    }
  }
#endif
