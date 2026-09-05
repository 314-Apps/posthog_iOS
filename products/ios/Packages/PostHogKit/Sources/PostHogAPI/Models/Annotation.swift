import Foundation

/// A project annotation: a note pinned to a point in time so charts can
/// explain a spike. Fields beyond `id` are optional because older rows and
/// org-scoped annotations omit them.
public struct Annotation: Codable, Sendable, Equatable, Identifiable {
  public let id: Int
  public let content: String?
  public let dateMarker: Date?
  public let scope: String?
  public let creationType: String?
  public let createdAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case content
    case dateMarker = "date_marker"
    case scope
    case creationType = "creation_type"
    case createdAt = "created_at"
  }

  public init(
    id: Int,
    content: String?,
    dateMarker: Date?,
    scope: String?,
    creationType: String?,
    createdAt: Date?
  ) {
    self.id = id
    self.content = content
    self.dateMarker = dateMarker
    self.scope = scope
    self.creationType = creationType
    self.createdAt = createdAt
  }
}

/// Create body: the app always writes project-scoped annotations.
private struct AnnotationCreatePayload: Encodable {
  let content: String
  let dateMarker: Date
  let scope: String

  enum CodingKeys: String, CodingKey {
    case content
    case dateMarker = "date_marker"
    case scope
  }
}

extension APIClient {
  public func annotations(projectID: Int) async throws -> Paginated<Annotation> {
    try await send(.get("/api/projects/\(projectID)/annotations/"))
  }

  public func createAnnotation(projectID: Int, content: String, dateMarker: Date) async throws -> Annotation {
    let payload = AnnotationCreatePayload(content: content, dateMarker: dateMarker, scope: "project")
    let body = try Self.makeEncoder().encode(payload)
    return try await send(.post("/api/projects/\(projectID)/annotations/", body: body))
  }

  /// Annotations soft-delete: the API expects a PATCH that sets `deleted`,
  /// not an HTTP DELETE.
  public func deleteAnnotation(projectID: Int, annotationID: Int) async throws {
    let body = Data(#"{"deleted":true}"#.utf8)
    try await sendRaw(.patch("/api/projects/\(projectID)/annotations/\(annotationID)/", body: body))
  }
}
