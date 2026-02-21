import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TypeWhisper", category: "MediaPlaybackService")

@MainActor
class MediaPlaybackService {
    private var didPause = false
    private var pauseGeneration = 0

    #if !APPSTORE
    // Dynamically loaded functions from private MediaRemote framework
    private let sendCommand: (@convention(c) (Int, CFDictionary?) -> Bool)?
    private let getIsPlaying: (@convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void)?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        if let handle, let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommand = unsafeBitCast(sym, to: (@convention(c) (Int, CFDictionary?) -> Bool).self)
        } else {
            sendCommand = nil
            logger.info("MediaRemote framework not available - media pause feature disabled")
        }
        if let handle, let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getIsPlaying = unsafeBitCast(sym, to: (@convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void).self)
        } else {
            getIsPlaying = nil
        }
    }

    func pausePlayback() {
        guard !didPause, let sendCommand else { return }
        pauseGeneration += 1
        let generation = pauseGeneration

        guard let getIsPlaying else {
            // Fallback: no status check available, pause unconditionally
            _ = sendCommand(1, nil)
            didPause = true
            logger.info("Media playback paused (no status check available)")
            return
        }

        getIsPlaying(DispatchQueue.main) { isPlaying in
            Task { @MainActor in
                guard self.pauseGeneration == generation else {
                    logger.info("Media pause check outdated (generation mismatch), skipping")
                    return
                }
                guard isPlaying else {
                    logger.info("No media playing, skipping pause")
                    return
                }
                _ = sendCommand(1, nil)
                self.didPause = true
                logger.info("Media playback paused")
            }
        }
    }

    func resumePlayback() {
        pauseGeneration += 1
        guard didPause, let sendCommand else { return }
        // kMRPlay = 0
        _ = sendCommand(0, nil)
        didPause = false
        logger.info("Media playback resumed")
    }
    #else
    func pausePlayback() {}
    func resumePlayback() {}
    #endif
}
