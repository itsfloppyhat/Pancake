import Foundation

/// Persists the songs played in recent runs so a song stays out of rotation for
/// the run it played in plus the next three. Retention is measured in runs, not
/// in days, so a burst of runs in one afternoon ages history exactly as fast as
/// the same runs spread over a month.
@MainActor
final class PlayedSongHistoryStore: ObservableObject {
    static let shared = PlayedSongHistoryStore()

    @Published private(set) var runs: [RunSongHistory] = []

    private let storageKey = "PlayedSongHistoryStore.runs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Song keys that must not be queued or played in the current run.
    var avoidedSongKeys: Set<String> {
        CrossRunSongHistoryPolicy.avoidedSongKeys(in: runs)
    }

    /// Recently played songs, newest first, capped for inclusion in prompt text.
    var promptAvoidedSongs: [MusicSong] {
        CrossRunSongHistoryPolicy.recentAvoidedSongs(in: runs)
    }

    /// Opens a history slot for a run that is starting.
    func beginRun() {
        runs = CrossRunSongHistoryPolicy.beginningRun(in: runs)
        save()
    }

    /// Records a song against the run in progress.
    func recordPlayedSong(_ song: MusicSong) {
        let updated = CrossRunSongHistoryPolicy.recordingPlayedSong(song, in: runs)

        guard updated != runs else { return }

        runs = updated
        save()
    }

    /// Clears the window so every song becomes eligible again.
    func clearHistory() {
        runs = []
        defaults.removeObject(forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else {
            runs = []
            return
        }

        do {
            runs = try JSONDecoder().decode([RunSongHistory].self, from: data)
        } catch {
            print("Failed to load played song history: \(error)")
            runs = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(runs)
            defaults.set(data, forKey: storageKey)
        } catch {
            print("Failed to save played song history: \(error)")
        }
    }
}
