import SwiftUI

// MARK: - History Home

struct HistoryHomeView: View {
    @EnvironmentObject var store: AppSessionStore

    var body: some View {
        NavigationStack {
            Group {
                if store.completedRounds.isEmpty {
                    emptyState
                } else {
                    roundList
                }
            }
            .navigationTitle("History")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Rounds Yet")
                .font(.headline)
            Text("Completed rounds will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Round list

    private var roundList: some View {
        List {
            ForEach(store.completedRounds) { round in
                NavigationLink {
                    HistoryRoundDetailView(round: round, store: store)
                } label: {
                    HistoryRoundRow(round: round)
                }
            }
            .onDelete { indexSet in
                store.completedRounds.remove(atOffsets: indexSet)
                store.persistCompletedRounds()
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Round Row

private struct HistoryRoundRow: View {
    let round: SaturdayRound

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var playerNames: String {
        round.players.map { String($0.name.split(separator: " ").first ?? Substring($0.name)) }.joined(separator: ", ")
    }

    private var gameLabels: String {
        round.activeGames.map(\.type.title).joined(separator: " · ")
    }

    private var holesPlayed: Int {
        round.holeEntries.map(\.holeNumber).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(round.courseName.isEmpty ? "Course" : round.courseName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Self.dateFormatter.string(from: round.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(playerNames)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(gameLabels)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(holesPlayed == 18 ? "18 holes" : "\(holesPlayed) holes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Round Detail

struct HistoryRoundDetailView: View {
    let round: SaturdayRound
    let store: AppSessionStore
    @State private var showScorecard = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header card
                VStack(spacing: 6) {
                    Text(round.courseName.isEmpty ? "Course" : round.courseName)
                        .font(.title3.weight(.semibold))
                    Text(round.createdAt, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(round.players.map(\.name).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Settlement tabs (reuse RoundSummaryView content inline)
                HistorySettlementView(round: round)
                    .padding(.horizontal)

                // Scorecard button
                Button {
                    showScorecard = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scorecard")
                                .font(.subheadline.weight(.semibold))
                            Text("\(round.holeEntries.count) of 18 holes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "tablecells.fill")
                            .foregroundStyle(.blue)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Round Detail")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScorecard) {
            ScorecardSheet(round: round)
        }
    }
}

// MARK: - Settlement view for history

private struct HistorySettlementView: View {
    let round: SaturdayRound
    @State private var selectedTab = 0

    private var activeTabs: [GameType] { round.activeGames.map(\.type) }

    var body: some View {
        VStack(spacing: 0) {
            if activeTabs.count > 1 {
                Picker("", selection: $selectedTab) {
                    ForEach(activeTabs.indices, id: \.self) { i in
                        Text(activeTabs[i].title).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 12)
            }
            if activeTabs.indices.contains(selectedTab) {
                summaryContent(for: activeTabs[selectedTab])
            }
        }
    }

    @ViewBuilder
    private func summaryContent(for game: GameType) -> some View {
        switch game {
        case .nassau:
            if let nassauGame = round.activeGames.first(where: { $0.type == .nassau }),
               let config = nassauGame.nassauConfig {
                NassauSummaryView(round: round, config: config)
            }
        case .sixPointScotch:
            if let scotchGame = round.activeGames.first(where: { $0.type == .sixPointScotch }),
               let config = scotchGame.scotchConfig {
                ScotchSummaryView(round: round, config: config)
            }
        case .stableford:
            StablefordSummaryView(round: round)
        case .skins:
            if let skinsGame = round.activeGames.first(where: { $0.type == .skins }),
               let config = skinsGame.skinsConfig {
                SkinsSummaryView(round: round, config: config)
            }
        case .strokePlay:
            StrokePlaySummaryView(round: round)
        }
    }
}

