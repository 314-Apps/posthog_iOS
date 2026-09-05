import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogQueries

/// A chat participant. Reasoning and tool chatter never reach the transcript.
public enum MaxRole: Sendable, Equatable {
  case user
  case assistant
}

/// One decoded Max SSE frame. Parsing is defensive: junk data, control
/// signals, and message types the app does not render map to `.ignored`,
/// never an error, so one odd frame cannot kill the stream.
public enum MaxStreamEvent: Sendable, Equatable {
  case message(role: MaxRole, id: String?, content: String)
  case visualization(query: DataQuery?, answerBody: JSONValue)
  case conversationUpdate(status: String?, title: String?)
  case ignored

  public static func parse(_ event: ServerSentEvent) -> MaxStreamEvent {
    guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(event.data.utf8)) else {
      return .ignored
    }
    switch event.event {
    case "message":
      return parseMessage(json)
    case "conversation":
      return .conversationUpdate(
        status: json["status"]?.stringValue,
        title: json["title"]?.stringValue
      )
    default:
      return .ignored
    }
  }

  private static func parseMessage(_ json: JSONValue) -> MaxStreamEvent {
    let type = json["type"]?.stringValue ?? ""
    if type.hasPrefix("ai/viz") {
      guard let answer = json["answer"] else { return .ignored }
      return .visualization(query: answer["query"].map(DataQuery.init(raw:)), answerBody: answer)
    }
    switch type {
    case "ai":
      return .message(role: .assistant, id: json["id"]?.stringValue, content: json["content"]?.stringValue ?? "")
    case "human":
      return .message(role: .user, id: json["id"]?.stringValue, content: json["content"]?.stringValue ?? "")
    default:
      return .ignored
    }
  }
}
