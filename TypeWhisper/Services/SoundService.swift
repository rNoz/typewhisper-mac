import AppKit

enum SoundEvent {
    case recordingStarted
    case transcriptionSuccess
    case error

    var fileName: String {
        switch self {
        case .recordingStarted: return "recording_start"
        case .transcriptionSuccess: return "transcription_success"
        case .error: return "error"
        }
    }
}

@MainActor
class SoundService {
    private var sounds: [SoundEvent: NSSound] = [:]

    init() {
        preloadSounds()
    }

    func play(_ event: SoundEvent, enabled: Bool) {
        guard enabled else { return }
        if let sound = sounds[event] {
            sound.stop()
            sound.play()
        }
    }

    private func preloadSounds() {
        for event in [SoundEvent.recordingStarted, .transcriptionSuccess, .error] {
            if let url = Bundle.main.url(forResource: event.fileName, withExtension: "wav") {
                sounds[event] = NSSound(contentsOf: url, byReference: true)
            }
        }
    }
}
