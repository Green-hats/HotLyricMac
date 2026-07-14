import AppKit
import Foundation

actor PlayerService {
    private var activePlayer: PlayerKind?
    private var lastReadings: [PlayerKind: PlayerReading] = [:]
    private var lastProbeDates: [PlayerKind: Date] = [:]
    private let secondaryProbeInterval: TimeInterval = 5

    private struct PlayerReading: Sendable {
        let track: Track?
        let access: PlayerAccessState
    }

    func currentTrack(preferred: PlayerKind, forced: PlayerKind?, now: Date = Date()) -> PlayerPollResult {
        var players = PlayerProbePlanner.playersToProbe(
            forced: forced,
            active: activePlayer,
            now: now,
            lastProbeDates: lastProbeDates,
            secondaryInterval: secondaryProbeInterval
        )
        for player in players { probe(player, at: now) }

        if
            forced == nil,
            let activePlayer,
            lastReadings[activePlayer]?.track == nil
        {
            let other = activePlayer == .appleMusic ? PlayerKind.spotify : .appleMusic
            if !players.contains(other) {
                players.append(other)
                probe(other, at: now)
            }
        }

        let selected = MediaSessionSelector.select(
            preferred: preferred,
            active: activePlayer,
            forced: forced,
            appleMusic: lastReadings[.appleMusic]?.track,
            spotify: lastReadings[.spotify]?.track
        )
        if let selected {
            activePlayer = selected.player
        } else if lastReadings.values.allSatisfy({ $0.track == nil }) {
            activePlayer = nil
        }

        let access: [PlayerKind: PlayerAccessState]
        if let forced {
            access = [forced: lastReadings[forced]?.access ?? .notRunning]
        } else {
            access = [
                .appleMusic: lastReadings[.appleMusic]?.access ?? .notRunning,
                .spotify: lastReadings[.spotify]?.access ?? .notRunning
            ]
        }
        return PlayerPollResult(track: selected, access: access)
    }

    func togglePlayPause(for player: PlayerKind) { command(player, appleMusic: "playpause", spotify: "playpause") }
    func next(for player: PlayerKind) { command(player, appleMusic: "next track", spotify: "next track") }
    func previous(for player: PlayerKind) { command(player, appleMusic: "previous track", spotify: "previous track") }

    private func probe(_ player: PlayerKind, at date: Date) {
        let value = read(player)
        lastReadings[player] = PlayerReading(track: value.track, access: value.access)
        lastProbeDates[player] = date
    }

    private func read(_ player: PlayerKind) -> (track: Track?, access: PlayerAccessState) {
        let application = player == .appleMusic ? "Music" : "Spotify"
        let script = """
        if application \"\(application)\" is not running then return \"\"
        tell application \"\(application)\"
            set trackName to name of current track
            set artistName to artist of current track
            set albumName to album of current track
            set trackDuration to duration of current track
            set trackPosition to player position
            set playbackState to (player state as text)
            return trackName & ASCII character 30 & artistName & ASCII character 30 & albumName & ASCII character 30 & trackDuration & ASCII character 30 & trackPosition & ASCII character 30 & playbackState
        end tell
        """
        let execution = run(script)
        if execution.errorCode == -1743 { return (nil, .permissionDenied) }
        if let message = execution.errorMessage { return (nil, .unavailable(message)) }
        guard let value = execution.value, !value.isEmpty else { return (nil, .notRunning) }
        let fields = value.components(separatedBy: String(UnicodeScalar(30)))
        guard fields.count >= 6 else { return (nil, .unavailable("播放器返回了无效的曲目信息")) }

        // Spotify's scripting dictionary reports duration in milliseconds;
        // Music reports duration and player position in seconds.
        let rawDuration = Double(fields[3]) ?? 0
        let duration = PlayerTimeNormalizer.duration(rawDuration, player: player)
        let rawPosition = Double(fields[4]) ?? 0
        let position = min(max(rawPosition, 0), duration > 0 ? duration : .greatestFiniteMagnitude)
        return (Track(
            title: fields[0],
            artist: fields[1],
            album: fields[2],
            duration: duration,
            position: position,
            isPlaying: fields[5].lowercased().contains("playing"),
            player: player
        ), .available)
    }

    private func command(_ player: PlayerKind, appleMusic: String, spotify: String) {
        let application = player == .appleMusic ? "Music" : "Spotify"
        let action = player == .appleMusic ? appleMusic : spotify
        _ = run("tell application \"\(application)\" to \(action)")
    }

    private func run(_ source: String) -> (value: String?, errorCode: Int?, errorMessage: String?) {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        let code = (error?["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue
        let message = error?["NSAppleScriptErrorMessage"] as? String
        return (error == nil ? result?.stringValue : nil, code, message)
    }
}

enum PlayerProbePlanner {
    static func playersToProbe(
        forced: PlayerKind?,
        active: PlayerKind?,
        now: Date,
        lastProbeDates: [PlayerKind: Date],
        secondaryInterval: TimeInterval = 5
    ) -> [PlayerKind] {
        if let forced { return [forced] }
        guard let active else { return PlayerKind.allCases }
        let other = active == .appleMusic ? PlayerKind.spotify : .appleMusic
        guard
            let lastSecondaryProbe = lastProbeDates[other],
            now.timeIntervalSince(lastSecondaryProbe) < secondaryInterval
        else { return [active, other] }
        return [active]
    }
}

enum PlayerTimeNormalizer {
    static func duration(_ rawValue: TimeInterval, player: PlayerKind) -> TimeInterval {
        max(0, player == .spotify ? rawValue / 1_000 : rawValue)
    }
}

enum MediaSessionSelector {
    static func select(
        preferred: PlayerKind,
        active: PlayerKind?,
        forced: PlayerKind? = nil,
        appleMusic: Track?,
        spotify: Track?
    ) -> Track? {
        let sessions: [PlayerKind: Track] = [.appleMusic: appleMusic, .spotify: spotify].compactMapValues { $0 }
        let fallback: PlayerKind = preferred == .appleMusic ? .spotify : .appleMusic

        if let forced { return sessions[forced] }
        if let active, let activeTrack = sessions[active] {
            let other: PlayerKind = active == .appleMusic ? .spotify : .appleMusic
            if activeTrack.isPlaying { return activeTrack }
            if let otherTrack = sessions[other], otherTrack.isPlaying { return otherTrack }
            return activeTrack
        }
        if let preferredTrack = sessions[preferred], preferredTrack.isPlaying { return preferredTrack }
        if let fallbackTrack = sessions[fallback], fallbackTrack.isPlaying { return fallbackTrack }
        return sessions[preferred] ?? sessions[fallback]
    }
}
