import Foundation
import SwiftData

@Model
final class Profile {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var priority: Int
    var bundleIdentifiers: [String]
    var urlPatterns: [String]
    var inputLanguage: String?
    var translationTargetLanguage: String?
    var selectedTask: String?
    var whisperModeOverride: Bool?
    var engineOverride: String?
    var alwaysPaste: Bool?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        priority: Int = 0,
        bundleIdentifiers: [String] = [],
        urlPatterns: [String] = [],
        inputLanguage: String? = nil,
        translationTargetLanguage: String? = nil,
        selectedTask: String? = nil,
        whisperModeOverride: Bool? = nil,
        engineOverride: String? = nil,
        alwaysPaste: Bool? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.priority = priority
        self.bundleIdentifiers = bundleIdentifiers
        self.urlPatterns = urlPatterns
        self.inputLanguage = inputLanguage
        self.translationTargetLanguage = translationTargetLanguage
        self.selectedTask = selectedTask
        self.whisperModeOverride = whisperModeOverride
        self.engineOverride = engineOverride
        self.alwaysPaste = alwaysPaste
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
