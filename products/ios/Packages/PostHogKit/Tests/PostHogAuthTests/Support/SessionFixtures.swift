import Foundation

@testable import PostHogAuth

func makeSession(
  accessToken: String = "pha_old",
  refreshToken: String = "rt_old",
  expiresIn: TimeInterval,
  scopedTeams: [Int] = [1, 2],
  selectedProjectID: Int? = 1
) -> StoredSession {
  StoredSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: Date.now.addingTimeInterval(expiresIn),
    region: .us,
    scopeVersion: AuthConfiguration.scopeVersion,
    scopedTeams: scopedTeams,
    selectedProjectID: selectedProjectID
  )
}

let freshTokenBody = Data(
  #"{"access_token":"pha_new","refresh_token":"rt_new","expires_in":3600,"scoped_teams":[1,2]}"#.utf8
)
