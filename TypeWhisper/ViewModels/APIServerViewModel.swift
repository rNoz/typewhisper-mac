import Foundation
import Combine

@MainActor
final class APIServerViewModel: ObservableObject {
    nonisolated(unsafe) static var _shared: APIServerViewModel?
    static var shared: APIServerViewModel {
        guard let instance = _shared else {
            fatalError("APIServerViewModel not initialized")
        }
        return instance
    }

    @Published var isRunning = false
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: UserDefaultsKeys.apiServerEnabled) }
    }
    @Published var port: UInt16 {
        didSet { UserDefaults.standard.set(Int(port), forKey: UserDefaultsKeys.apiServerPort) }
    }
    @Published var errorMessage: String?

    private let httpServer: HTTPServer

    init(httpServer: HTTPServer) {
        self.httpServer = httpServer
        self.isEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.apiServerEnabled)
        let savedPort = UserDefaults.standard.integer(forKey: UserDefaultsKeys.apiServerPort)
        self.port = savedPort > 0 ? UInt16(savedPort) : 8978

        httpServer.onStateChange = { [weak self] running in
            DispatchQueue.main.async {
                self?.isRunning = running
                if !running {
                    self?.errorMessage = "Server stopped unexpectedly"
                    self?.removePortFile()
                }
            }
        }
    }

    func startServer() {
        errorMessage = nil
        do {
            try httpServer.start(port: port)
            writePortFile()
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
        }
    }

    func stopServer() {
        httpServer.stop()
        isRunning = false
        errorMessage = nil
        removePortFile()
    }

    func restartIfNeeded() {
        if isEnabled {
            stopServer()
            startServer()
        }
    }

    // MARK: - Port File

    private static var portFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypeWhisper")
            .appendingPathComponent("api-port")
    }

    private func writePortFile() {
        let url = Self.portFileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? String(port).write(to: url, atomically: true, encoding: .utf8)
    }

    private func removePortFile() {
        try? FileManager.default.removeItem(at: Self.portFileURL)
    }
}
