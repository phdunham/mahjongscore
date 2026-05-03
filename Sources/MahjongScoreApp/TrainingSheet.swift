import SwiftUI

/// Training panel shown from the toolbar. Lists dataset stats and exposes a
/// Train-now button.
struct TrainingSheet: View {
    @ObservedObject var coordinator: TrainingCoordinator
    @Binding var isPresented: Bool

    @State private var filter: Filter = .all
    enum Filter: String, CaseIterable { case all = "All", thin = "< 20 samples", empty = "Empty" }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            header
            summary
            statsList
            Divider()
            actions
        }
        .padding(DT.Spacing.lg)
        .frame(minWidth: 560, minHeight: 540)
        .onAppear { coordinator.refreshStats() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Train On-Device Classifier")
                    .font(.title2).bold()
                Text("Uses the cropped tile images your corrections have accumulated.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { isPresented = false }
        }
    }

    private var summary: some View {
        let stats = coordinator.stats
        return GroupBox {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DT.Spacing.md, verticalSpacing: DT.Spacing.xs) {
                GridRow {
                    Text("Total images").foregroundStyle(.secondary)
                    Text("\(stats.totalImages)").monospacedDigit()
                }
                GridRow {
                    Text("Classes with data").foregroundStyle(.secondary)
                    Text("\(stats.classesWithData) / 42").monospacedDigit()
                }
                GridRow {
                    Text("Classes < \(TrainingCoordinator.Stats.minSamplesPerClass) samples").foregroundStyle(.secondary)
                    Text("\(stats.classesBelowMinimum.count)").monospacedDigit()
                        .foregroundStyle(stats.classesBelowMinimum.isEmpty ? Color.primary : Color.orange)
                }
                GridRow {
                    Text("Classes < \(TrainingCoordinator.Stats.recommendedSamplesPerClass) samples").foregroundStyle(.secondary)
                    Text("\(stats.classesBelowRecommended.count)").monospacedDigit()
                        .foregroundStyle(stats.classesBelowRecommended.isEmpty ? Color.primary : Color.secondary)
                }
                if let lastTrained = coordinator.lastTrainedAt {
                    GridRow {
                        Text("Last trained").foregroundStyle(.secondary)
                        Text(lastTrained, style: .relative).monospacedDigit()
                    }
                }
                GridRow {
                    Text("Model file").foregroundStyle(.secondary)
                    Text(coordinator.modelAvailable ? "available" : "not yet trained")
                        .foregroundStyle(coordinator.modelAvailable ? Color.primary : Color.orange)
                }
            }
            .padding(.vertical, DT.Spacing.xs)
        }
    }

    private var statsList: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.xs) {
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 2),
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(filteredNotations, id: \.self) { notation in
                        HStack {
                            Text(notation)
                                .font(.body.monospaced())
                                .frame(minWidth: 32, alignment: .leading)
                            Text("\(coordinator.stats.classCounts[notation] ?? 0)")
                                .monospacedDigit()
                                .foregroundStyle(statusColor(for: notation))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 160)
        }
    }

    private var actions: some View {
        HStack {
            Button("Refresh stats") { coordinator.refreshStats() }
            Button {
                Task {
                    await coordinator.trainNow()
                    coordinator.refreshStats()
                }
            } label: {
                Label("Train now", systemImage: "sparkles")
                    .padding(.horizontal, DT.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .disabled({
                if case .training = coordinator.status { return true }
                return !coordinator.readyToTrain
            }())

            if case .training(let message) = coordinator.status {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusLine
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch coordinator.status {
        case .idle:
            EmptyView()
        case .training:
            EmptyView()
        case .succeeded(let acc, _):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                if let acc {
                    Text("Trained · validation \(Int(acc * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Trained").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .failed(let msg):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func statusColor(for notation: String) -> Color {
        let count = coordinator.stats.classCounts[notation] ?? 0
        if count == 0 { return .red }
        if count < TrainingCoordinator.Stats.minSamplesPerClass { return .orange }
        if count < TrainingCoordinator.Stats.recommendedSamplesPerClass { return .yellow }
        return .green
    }

    private var filteredNotations: [String] {
        let all = TrainingCoordinator.expectedTileNotations
        switch filter {
        case .all: return all
        case .thin:
            return all.filter {
                let c = coordinator.stats.classCounts[$0] ?? 0
                return c > 0 && c < TrainingCoordinator.Stats.recommendedSamplesPerClass
            }
        case .empty:
            return all.filter { (coordinator.stats.classCounts[$0] ?? 0) == 0 }
        }
    }
}
