import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TypeWhisper", category: "MediaPlaybackService")

@MainActor
class MediaPlaybackService {
    private var didPause = false

    #if !APPSTORE
    // Dynamically loaded function from private MediaRemote framework
    private let sendCommand: (@convention(c) (Int, CFDictionary?) -> Bool)?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        if let handle, let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommand = unsafeBitCast(sym, to: (@convention(c) (Int, CFDictionary?) -> Bool).self)
        } else {
            sendCommand = nil
            logger.info("MediaRemote framework not available - media pause feature disabled")
        }
    }

    func pausePlayback() {
        guard !didPause, let sendCommand else { return }
        // kMRPause = 1
        _ = sendCommand(1, nil)
        didPause = true
        logger.info("Media playback paused")
    }

    func resumePlayback() {
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
