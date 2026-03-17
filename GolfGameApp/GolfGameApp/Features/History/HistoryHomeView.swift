import SwiftUI
import MessageUI

// MARK: - History Home

struct HistoryHomeView: View {
    @EnvironmentObject var store: AppSessionStore
    @State private var expandedArchiveDays: Set<Date> = []
    @State private var showArchiveAllConfirm = false
    @State private var showDeleteAllArchivedConfirm = false

    private var hasAnyHistory: Bool {
        !store.completedRounds.isEmpty || !store.archivedRounds.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasAnyHistory {
                    emptyState
                } else {
                    historyList
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !store.completedRounds.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Archive All") { showArchiveAllConfirm = true }
                    }
                }
            }
        }
        .alert("Archive All Active Rounds?", isPresented: $showArchiveAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Archive All") {
                store.archiveAllCompletedRounds()
            }
        } message: {
            Text("Moves all active history rounds into Archive.")
        }
        .alert("Delete All Archived Rounds?", isPresented: $showDeleteAllArchivedConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                store.deleteAllArchivedRounds()
            }
        } message: {
            Text("This permanently removes all archived rounds.")
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

    private var archiveGroups: [(day: Date, rounds: [SaturdayRound])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.archivedRounds) { round in
            calendar.startOfDay(for: round.createdAt)
        }
        return grouped
            .map { (day: $0.key, rounds: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }

    // MARK: - Round list

    private var historyList: some View {
        List {
            if !store.completedRounds.isEmpty {
                Section("Active") {
                    ForEach(store.completedRounds) { round in
                        NavigationLink {
                            HistoryRoundDetailView(round: round, store: store)
                        } label: {
                            HistoryRoundRow(round: round)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                store.archiveCompletedRound(id: round.id)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }

            if !store.archivedRounds.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showDeleteAllArchivedConfirm = true
                    } label: {
                        Label("Delete All Archived", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } header: {
                    Text("Archive")
                }

                ForEach(archiveGroups, id: \.day) { group in
                    Section {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedArchiveDays.contains(group.day) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedArchiveDays.insert(group.day)
                                    } else {
                                        expandedArchiveDays.remove(group.day)
                                    }
                                }
                            )
                        ) {
                            ForEach(group.rounds) { round in
                                NavigationLink {
                                    HistoryRoundDetailView(round: round, store: store)
                                } label: {
                                    HistoryRoundRow(round: round)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.deleteArchivedRound(id: round.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } label: {
                            Text(group.day.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
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
    @EnvironmentObject private var buddyStore: BuddyStore
    @State private var showScorecard = false
    @State private var showingMessageComposer = false
    @State private var showCannotTextAlert = false
    @State private var showSendConfirmAlert = false

    private var messageData: RoundTextMessageData {
        RoundTextMessageData(
            recipients: buddyStore.phoneNumbers(forPlayers: round.players.map(\.name)),
            body: RoundTextMessageComposer.messageBody(for: round),
            attachmentData: RoundMessageSnapshotRenderer.pngData(for: round),
            attachmentUTI: "public.png",
            attachmentFilename: "golf-round-summary.png"
        )
    }

    private var recipientEntries: [(name: String, phone: String)] {
        buddyStore.textingRecipients(forPlayers: round.players.map(\.name))
    }

    private var recipientPreviewText: String {
        if recipientEntries.isEmpty {
            return "No saved phone numbers matched this group. You can still review and send from the composer."
        }
        return recipientEntries
            .map { "\($0.name): \($0.phone)" }
            .joined(separator: "\n")
    }

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

                Button {
                    if MFMessageComposeViewController.canSendText() {
                        showSendConfirmAlert = true
                    } else {
                        showCannotTextAlert = true
                    }
                } label: {
                    HStack {
                        Text("Text Scorecard + Settlement")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "message.fill")
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
        .sheet(isPresented: $showingMessageComposer) {
            RoundMessageComposeView(
                recipients: messageData.recipients,
                body: messageData.body,
                attachmentData: messageData.attachmentData,
                attachmentUTI: messageData.attachmentUTI,
                attachmentFilename: messageData.attachmentFilename
            )
        }
        .alert("Send Scorecard + Settlement?", isPresented: $showSendConfirmAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Open Message") {
                showingMessageComposer = true
            }
        } message: {
            Text(recipientPreviewText)
        }
        .alert("Text Messaging Unavailable", isPresented: $showCannotTextAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This simulator cannot send SMS. Use a real iPhone to text your group.")
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
