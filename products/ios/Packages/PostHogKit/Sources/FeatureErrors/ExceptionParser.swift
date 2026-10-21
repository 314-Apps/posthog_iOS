import Foundation
import PostHogFoundation

/// One exception in the `$exception_list` chain (outermost first).
struct ExceptionInfo: Sendable, Equatable {
  struct Frame: Sendable, Equatable {
    let rawID: String?
    let mangledName: String?
    let resolvedName: String?
    let source: String?
    let line: Int?
    let inApp: Bool

    /// Best display name available at this symbolication stage.
    var displayName: String {
      resolvedName ?? mangledName ?? rawID ?? "Unknown frame"
    }

    var location: String? {
      guard let source else { return nil }
      guard let line else { return source }
      return "\(source):\(line)"
    }
  }

  let type: String?
  let value: String?
  let frames: [Frame]
}

/// Pulls `$exception_list` out of an `$exception` event's properties JSON.
/// Anything malformed yields [] so the card can show its honest empty state.
enum ExceptionParser {
  static func parse(propertiesJSON: String) -> [ExceptionInfo] {
    guard let properties = decode(propertiesJSON),
      let list = exceptionList(in: properties)
    else { return [] }
    return list.compactMap(exception(from:))
  }

  private static func decode(_ json: String) -> JSONValue? {
    try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
  }

  /// `$exception_list` is normally an array, but some capture paths
  /// double-encode it as a JSON string.
  private static func exceptionList(in properties: JSONValue) -> [JSONValue]? {
    guard let raw = properties["$exception_list"] else { return nil }
    if let array = raw.arrayValue { return array }
    guard let string = raw.stringValue else { return nil }
    return decode(string)?.arrayValue
  }

  private static func exception(from raw: JSONValue) -> ExceptionInfo? {
    guard let object = raw.objectValue else { return nil }
    let frames = object["stacktrace"]?["frames"]?.arrayValue ?? []
    return ExceptionInfo(
      type: object["type"]?.stringValue,
      value: object["value"]?.stringValue,
      frames: frames.compactMap(frame(from:))
    )
  }

  private static func frame(from raw: JSONValue) -> ExceptionInfo.Frame? {
    guard let object = raw.objectValue else { return nil }
    return ExceptionInfo.Frame(
      rawID: object["raw_id"]?.stringValue,
      mangledName: object["mangled_name"]?.stringValue,
      resolvedName: object["resolved_name"]?.stringValue,
      source: object["source"]?.stringValue,
      line: object["line"]?.intValue,
      inApp: object["in_app"]?.boolValue ?? false
    )
  }
}
