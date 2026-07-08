import AVFoundation
import Foundation

/// Speaks cheer messages over the workout music. Activating this app's audio
/// session with `.duckOthers` lowers the music (which plays in the Music app's
/// process) for the duration of the utterance, then restores it.
@MainActor
final class CheerAnnouncer: NSObject, ObservableObject {
    static let shared = CheerAnnouncer()

    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingAnnouncements: [String] = []

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Queues an announcement so overlapping cheers play one after another.
    func announce(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pendingAnnouncements.append(trimmed)
        speakNextIfIdle()
    }

    func announceCheer(from senderName: String, message: String) {
        announce("\(senderName) says: \(message)")
    }

    private func speakNextIfIdle() {
        guard !isSpeaking, !pendingAnnouncements.isEmpty else { return }

        isSpeaking = true
        duckBackgroundAudio()

        let utterance = AVSpeechUtterance(string: pendingAnnouncements.removeFirst())
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    private func finishCurrentUtterance() {
        restoreBackgroundAudio()
        isSpeaking = false
        speakNextIfIdle()
    }

    private func duckBackgroundAudio() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("CheerAnnouncer failed to duck audio: \(error)")
        }
    }

    private func restoreBackgroundAudio() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            try session.setCategory(.playback, mode: .default)
        } catch {
            print("CheerAnnouncer failed to restore audio: \(error)")
        }
    }
}

extension CheerAnnouncer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.finishCurrentUtterance()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.finishCurrentUtterance()
        }
    }
}
