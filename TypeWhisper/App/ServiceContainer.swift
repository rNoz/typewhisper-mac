import Foundation
import Combine

@MainActor
final class ServiceContainer: ObservableObject {
    static let shared = ServiceContainer()

    // Services
    let modelManagerService: ModelManagerService
    let audioFileService: AudioFileService
    let audioRecordingService: AudioRecordingService
    let hotkeyService: HotkeyService
    let textInsertionService: TextInsertionService
    let historyService: HistoryService
    let textDiffService: TextDiffService
    let profileService: ProfileService
    let translationService: TranslationService
    let audioDuckingService: AudioDuckingService
    let mediaPlaybackService: MediaPlaybackService
    let dictionaryService: DictionaryService
    let snippetService: SnippetService
    let soundService: SoundService

    // HTTP API
    let httpServer: HTTPServer
    let apiServerViewModel: APIServerViewModel

    // ViewModels
    let modelManagerViewModel: ModelManagerViewModel
    let fileTranscriptionViewModel: FileTranscriptionViewModel
    let settingsViewModel: SettingsViewModel
    let dictationViewModel: DictationViewModel
    let historyViewModel: HistoryViewModel
    let profilesViewModel: ProfilesViewModel
    let dictionaryViewModel: DictionaryViewModel
    let snippetsViewModel: SnippetsViewModel
    let homeViewModel: HomeViewModel

    private init() {
        // Services
        modelManagerService = ModelManagerService()
        audioFileService = AudioFileService()
        audioRecordingService = AudioRecordingService()
        hotkeyService = HotkeyService()
        textInsertionService = TextInsertionService()
        historyService = HistoryService()
        textDiffService = TextDiffService()
        profileService = ProfileService()
        translationService = TranslationService()
        audioDuckingService = AudioDuckingService()
        mediaPlaybackService = MediaPlaybackService()
        dictionaryService = DictionaryService()
        snippetService = SnippetService()
        soundService = SoundService()

        // HTTP API
        let router = APIRouter()
        let handlers = APIHandlers(modelManager: modelManagerService, audioFileService: audioFileService, translationService: translationService)
        handlers.register(on: router)
        httpServer = HTTPServer(router: router)
        apiServerViewModel = APIServerViewModel(httpServer: httpServer)

        // ViewModels
        modelManagerViewModel = ModelManagerViewModel(modelManager: modelManagerService)
        fileTranscriptionViewModel = FileTranscriptionViewModel(
            modelManager: modelManagerService,
            audioFileService: audioFileService
        )
        settingsViewModel = SettingsViewModel(modelManager: modelManagerService)
        dictationViewModel = DictationViewModel(
            audioRecordingService: audioRecordingService,
            textInsertionService: textInsertionService,
            hotkeyService: hotkeyService,
            modelManager: modelManagerService,
            settingsViewModel: settingsViewModel,
            historyService: historyService,
            profileService: profileService,
            translationService: translationService,
            audioDuckingService: audioDuckingService,
            mediaPlaybackService: mediaPlaybackService,
            dictionaryService: dictionaryService,
            snippetService: snippetService,
            soundService: soundService
        )
        historyViewModel = HistoryViewModel(
            historyService: historyService,
            textDiffService: textDiffService
        )
        profilesViewModel = ProfilesViewModel(
            profileService: profileService,
            settingsViewModel: settingsViewModel
        )
        dictionaryViewModel = DictionaryViewModel(dictionaryService: dictionaryService)
        snippetsViewModel = SnippetsViewModel(snippetService: snippetService)
        homeViewModel = HomeViewModel(
            historyService: historyService,
            dictionaryService: dictionaryService,
            profileService: profileService
        )

        // Set shared references
        ModelManagerViewModel._shared = modelManagerViewModel
        FileTranscriptionViewModel._shared = fileTranscriptionViewModel
        SettingsViewModel._shared = settingsViewModel
        DictationViewModel._shared = dictationViewModel
        APIServerViewModel._shared = apiServerViewModel
        HistoryViewModel._shared = historyViewModel
        ProfilesViewModel._shared = profilesViewModel
        DictionaryViewModel._shared = dictionaryViewModel
        SnippetsViewModel._shared = snippetsViewModel
        HomeViewModel._shared = homeViewModel
    }

    func initialize() async {
        hotkeyService.setup()
        historyService.purgeOldRecords()

        if apiServerViewModel.isEnabled {
            apiServerViewModel.startServer()
        }

        // Register SpeechAnalyzer model provider on macOS 26+
        if #available(macOS 26, *) {
            await SpeechAnalyzerModelProvider.populateCache()
            ModelInfo._speechAnalyzerModelProvider = { SpeechAnalyzerModelProvider.availableModels() }
        }

        await modelManagerService.loadSelectedModel()
    }
}
