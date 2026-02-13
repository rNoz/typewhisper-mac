import SwiftUI
import Charts

struct HomeSettingsView: View {
    @ObservedObject private var viewModel = HomeViewModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Time period picker
                HStack {
                    Text(String(localized: "Dashboard"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Picker("", selection: $viewModel.selectedTimePeriod) {
                        ForEach(TimePeriod.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                // Stats grid
                statsGrid

                // Activity chart
                chartSection

                // Tutorial
                if viewModel.showTutorial {
                    tutorialSection
                }
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private var statsGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatCard(
                    title: String(localized: "Words"),
                    value: "\(viewModel.wordsCount)",
                    systemImage: "text.word.spacing"
                )
                StatCard(
                    title: String(localized: "Avg. WPM"),
                    value: viewModel.averageWPM,
                    systemImage: "speedometer"
                )
                StatCard(
                    title: String(localized: "Apps Used"),
                    value: "\(viewModel.appsUsed)",
                    systemImage: "app.badge"
                )
                StatCard(
                    title: String(localized: "Time Saved"),
                    value: viewModel.timeSaved,
                    systemImage: "clock.badge.checkmark"
                )
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Activity"))
                .font(.headline)

            if viewModel.chartData.isEmpty || viewModel.chartData.allSatisfy({ $0.wordCount == 0 }) {
                Text(String(localized: "No activity in this period."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(viewModel.chartData) { point in
                    BarMark(
                        x: .value(String(localized: "Date"), point.date, unit: .day),
                        y: .value(String(localized: "Words"), point.wordCount)
                    )
                    .foregroundStyle(.blue.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: viewModel.selectedTimePeriod == .week ? 1 : 5)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tutorialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Getting Started"))
                    .font(.headline)

                Text("\(viewModel.completedStepCount)/\(viewModel.tutorialSteps.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())

                Spacer()

                Button(String(localized: "Dismiss")) {
                    viewModel.dismissTutorial()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }

            ForEach(viewModel.tutorialSteps) { step in
                HStack(spacing: 12) {
                    Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(step.isCompleted ? .green : .secondary)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .fontWeight(.medium)
                            .strikethrough(step.isCompleted)
                            .foregroundStyle(step.isCompleted ? .secondary : .primary)
                        Text(step.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
