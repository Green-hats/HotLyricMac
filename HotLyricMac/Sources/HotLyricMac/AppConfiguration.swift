import Foundation

struct AppConfiguration: Decodable, Sendable {
    struct MediaSessionApp: Decodable, Sendable {
        struct Match: Decodable, Sendable { let bundleIdentifier: String }
        struct Options: Decodable, Sendable {
            let positionMode: String
            let defaultLrcProvider: String
            let mediaPropertiesMode: String
        }
        let appId: String
        let sessionType: String
        let match: Match
        let options: Options
    }

    let mediaSessionApps: [MediaSessionApp]

    static let current: AppConfiguration = {
        guard
            let url = Bundle.module.url(forResource: "configuration", withExtension: "json", subdirectory: "Resources"),
            let data = try? Data(contentsOf: url),
            let value = try? JSONDecoder().decode(AppConfiguration.self, from: data)
        else {
            return AppConfiguration(mediaSessionApps: [])
        }
        return value
    }()

    func options(for player: PlayerKind) -> MediaSessionApp.Options? {
        let appId = player == .appleMusic ? "apple_music" : "spotify"
        return mediaSessionApps.first { $0.appId == appId }?.options
    }
}
