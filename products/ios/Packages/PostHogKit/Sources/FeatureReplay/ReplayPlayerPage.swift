import Foundation
import PostHogFoundation

/// The player page that ships inside the app.
///
/// It is built from `products/ios/player` and committed, because iOS CI checks
/// out only this tree and cannot rebuild it.
enum ReplayPlayerPage {
  static let bundled: Data? = {
    guard let url = Bundle.module.url(forResource: "player", withExtension: "html"),
      let data = try? Data(contentsOf: url)
    else {
      PHLog.api.error("bundled replay player is missing from the app")
      return nil
    }
    return data
  }()
}
