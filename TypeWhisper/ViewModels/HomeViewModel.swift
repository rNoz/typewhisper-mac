import Foundation
import Combine

enum TimePeriod: String, CaseIterable {
    case week
    case month

    var displayName: String {
        switch self {
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        }
    }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        }
    }
}

struct ActivityDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let wordCount: Int
}

struct TutorialStep: Identifiable {
    let id: Int
    let title: String
    let description: String
    let systemImage: String
    let isCompleted: Bool
}

@MainActor
final class HomeViewModel: ObservableObject {
    nonisolated(unsafe) static var _shared: HomeViewModel?
    static var shared: HomeViewModel {
        guard let instance = _shared else {
            fatalError("HomeViewModel not initialized")
        }
        return instance
    }

    @Published var selectedTimePeriod: TimePeriod = .week
    @Published var wordsCount: Int = 0
    @Published var averageWPM: String = "—"
    @Published var appsUsed: Int = 0
    @Published var timeSaved: String = "—"
    @Published var chartData: [ActivityDataPoint] = []
    @Published var tutorialSteps: [TutorialStep] = []
    @Published var completedStepCount: Int = 0
    @Published var showTutorial: Bool {
        didSet { UserDefaults.standard.set(!showTutorial, forKey: "tutorialDismissed") }
    }

    private let historyService: HistoryService
    private let dictionaryService: DictionaryService
    private let profileService: ProfileService
    private var cancellables = Set<AnyCancellable>()
    private var refreshWorkItem: DispatchWorkItem?

    init(historyService: HistoryService, dictionaryService: DictionaryService, profileService: ProfileService) {
        self.historyService = historyService
        self.dictionaryService = dictionaryService
        self.profileService = profileService
        self.showTutorial = !UserDefaults.standard.bool(forKey: "tutorialDismissed")

        setupBindings()
        refresh()
    }

    private func setupBindings() {
        historyService.$records
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        dictionaryService.$entries
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        profileService.$profiles
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        $selectedTimePeriod
            .dropFirst()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    func refresh() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -selectedTimePeriod.days, to: Date()) ?? Date()
        let filtered = historyService.records.filter { $0.timestamp >= cutoff }

        // Words count
        wordsCount = filtered.reduce(0) { $0 + $1.wordsCount }

        // Average WPM
        let totalMinutes = filtered.reduce(0.0) { $0 + $1.durationSeconds } / 60.0
        if totalMinutes > 0 && wordsCount > 0 {
            let wpm = Int(Double(wordsCount) / totalMinutes)
            averageWPM = "\(wpm)"
        } else {
            averageWPM = "—"
        }

        // Apps used
        let uniqueApps = Set(filtered.compactMap { $0.appBundleIdentifier })
        appsUsed = uniqueApps.count

        // Time saved (typing at 45 WPM baseline vs dictation duration)
        let typingMinutes = Double(wordsCount) / 45.0
        let dictationMinutes = totalMinutes
        let savedMinutes = typingMinutes - dictationMinutes
        if savedMinutes > 0 {
            let mins = Int(savedMinutes)
            if mins >= 60 {
                let hours = mins / 60
                let remainder = mins % 60
                timeSaved = String(localized: "\(hours)h \(remainder)m")
            } else {
                timeSaved = String(localized: "\(mins)m")
            }
        } else {
            timeSaved = "—"
        }

        // Chart data
        chartData = buildChartData(records: filtered)

        // Tutorial
        refreshTutorial()
    }

    private func buildChartData(records: [TranscriptionRecord]) -> [ActivityDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = selectedTimePeriod.days

        var dataByDay: [Date: Int] = [:]
        for i in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                dataByDay[date] = 0
            }
        }

        for record in records {
            let day = calendar.startOfDay(for: record.timestamp)
            dataByDay[day, default: 0] += record.wordsCount
        }

        return dataByDay
            .map { ActivityDataPoint(date: $0.key, wordCount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func refreshTutorial() {
        let hasRecordings = !historyService.records.isEmpty
        let hasDictionary = !dictionaryService.entries.isEmpty
        let hasProfiles = !profileService.profiles.isEmpty
        let historyVisited = UserDefaults.standard.bool(forKey: "historyTabVisited")

        let steps = [
            TutorialStep(
                id: 1,
                title: String(localized: "Make your first recording"),
                description: String(localized: "Press your hotkey and start dictating."),
                systemImage: "mic.fill",
                isCompleted: hasRecordings
            ),
            TutorialStep(
                id: 2,
                title: String(localized: "Customize your hotkey"),
                description: String(localized: "Go to Dictation settings and set your preferred shortcut."),
                systemImage: "keyboard",
                isCompleted: UserDefaults.standard.bool(forKey: "hotkeyCustomized")
            ),
            TutorialStep(
                id: 3,
                title: String(localized: "Add vocabulary"),
                description: String(localized: "Add terms and corrections to the Dictionary."),
                systemImage: "book.closed",
                isCompleted: hasDictionary
            ),
            TutorialStep(
                id: 4,
                title: String(localized: "Create a profile"),
                description: String(localized: "Set up app-specific settings in Profiles."),
                systemImage: "person.crop.rectangle.stack",
                isCompleted: hasProfiles
            ),
            TutorialStep(
                id: 5,
                title: String(localized: "Review your history"),
                description: String(localized: "Check and edit past transcriptions in History."),
                systemImage: "clock.arrow.circlepath",
                isCompleted: historyVisited
            )
        ]

        tutorialSteps = steps
        completedStepCount = steps.filter(\.isCompleted).count

        // Auto-dismiss tutorial when all steps completed
        if completedStepCount == steps.count {
            showTutorial = false
        }
    }

    func dismissTutorial() {
        showTutorial = false
    }
}
