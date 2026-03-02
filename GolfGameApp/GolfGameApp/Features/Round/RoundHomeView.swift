//
//  RoundHomeView.swift
//  GolfGameApp
//
//  Created by juswaite on 2/27/26.
//

import SwiftUI
import Combine

struct RoundHomeView: View {
    @EnvironmentObject private var session: SessionModel
    @State private var path: [RoundRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 20) {
                Spacer()

                if let configuredRound = session.configuredRound {
                    ConfiguredRoundCard(round: configuredRound)

                    Button("Resume Round") {
                        path.append(.scoring)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(session.activeRoundSession == nil)
                }

                if session.configuredRound != nil {
                    Button("New Round") { path.append(.setup) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                } else {
                    Button("Start New Round") { path.append(.setup) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Round")
            .navigationDestination(for: RoundRoute.self) { route in
                switch route {
                case .setup:
                    RoundSetupFlowView { _ in
                        path.append(.scoring)
                    }
                case .scoring:
                    RoundScoringView(session: session)
                }
            }
        }
    }
}

private enum RoundRoute: Hashable {
    case setup
    case scoring
}

@MainActor
final class RoundSetupViewModel: ObservableObject {
    static let teeBoxOptions = ["Blue", "White", "Gold", "Red"]

    @Published var eventName = ""
    @Published var eventDate = Date()
    @Published var players = [
        PlayerDraft(),
        PlayerDraft(),
        PlayerDraft(),
        PlayerDraft()
    ]
    @Published var courseName = DemoCourseFactory.name
    @Published var teeBoxName = "White"
    @Published var holes = DemoCourseFactory.holes18()

    var hasValidEventName: Bool {
        !eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasFourNamedPlayers: Bool {
        players.count == 4 && players.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var sortedPlayersByHandicap: [PlayerDraft] {
        players.sorted { $0.handicapIndex < $1.handicapIndex }
    }

    var pairings: [TeamPairing] {
        let ordered = sortedPlayersByHandicap
        guard ordered.count == 4 else { return [] }

        let teamA = [
            PlayerSnapshot(id: ordered[0].id.uuidString, name: ordered[0].name, handicapIndex: ordered[0].handicapIndex),
            PlayerSnapshot(id: ordered[3].id.uuidString, name: ordered[3].name, handicapIndex: ordered[3].handicapIndex)
        ]
        let teamB = [
            PlayerSnapshot(id: ordered[1].id.uuidString, name: ordered[1].name, handicapIndex: ordered[1].handicapIndex),
            PlayerSnapshot(id: ordered[2].id.uuidString, name: ordered[2].name, handicapIndex: ordered[2].handicapIndex)
        ]

        return [
            TeamPairing(team: .teamA, players: teamA),
            TeamPairing(team: .teamB, players: teamB)
        ]
    }

    func commit(into session: SessionModel) {
        let snapshots = players.map {
            PlayerSnapshot(id: $0.id.uuidString, name: $0.name, handicapIndex: $0.handicapIndex)
        }

        let setup = RoundSetupSession(
            event: EventDraft(name: eventName, date: eventDate),
            courseName: courseName,
            teeBoxName: teeBoxName,
            players: snapshots,
            holes: holes,
            pairings: pairings
        )
        session.startRoundSession(with: setup)
    }
}

private struct RoundSetupFlowView: View {
    @StateObject private var viewModel = RoundSetupViewModel()
    let onFinish: (RoundSetupSession) -> Void

    var body: some View {
        EventCreationScreen(viewModel: viewModel, onFinish: onFinish)
    }
}

private struct EventCreationScreen: View {
    @ObservedObject var viewModel: RoundSetupViewModel
    let onFinish: (RoundSetupSession) -> Void

    var body: some View {
        Form {
            Section("Event Creation") {
                TextField("Event name", text: $viewModel.eventName)
                DatePicker("Date", selection: $viewModel.eventDate, displayedComponents: .date)
            }
            Section {
                NavigationLink("Next: Players") {
                    PlayerEntryScreen(viewModel: viewModel, onFinish: onFinish)
                }
                .disabled(!viewModel.hasValidEventName)
            }
        }
        .navigationTitle("Event")
    }
}

private struct PlayerEntryScreen: View {
    @ObservedObject var viewModel: RoundSetupViewModel
    @EnvironmentObject var buddyStore: BuddyStore
    let onFinish: (RoundSetupSession) -> Void

    private var nextEmptyIndex: Int? {
        viewModel.players.indices.first { viewModel.players[$0].name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        Form {
            // SAVED BUDDIES
            Section {
                if buddyStore.buddies.isEmpty {
                    Text("No buddies saved yet — enter players below and tap the bookmark to save them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(buddyStore.buddies) { buddy in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(buddy.name)
                                    .font(.subheadline)
                                Text(String(format: "HI %.1f", buddy.handicapIndex))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                if let idx = nextEmptyIndex {
                                    viewModel.players[idx].name = buddy.name
                                    viewModel.players[idx].handicapIndex = buddy.handicapIndex
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(nextEmptyIndex != nil ? .blue : .secondary)
                            }
                            .disabled(nextEmptyIndex == nil)
                            .buttonStyle(.plain)
                        }
                    }
                    .onDelete { offsets in
                        buddyStore.remove(at: offsets)
                    }
                }
            } header: {
                Text("Saved Buddies")
            } footer: {
                if !buddyStore.buddies.isEmpty {
                    Text("Tap + to fill the next open slot. Swipe to remove.")
                        .font(.caption)
                }
            }

            // PLAYER SLOTS
            Section("Players (exactly 4)") {
                ForEach(0..<4, id: \.self) { index in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading) {
                            TextField("Player \(index + 1) name", text: $viewModel.players[index].name)
                            HStack {
                                Text("HI")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                TextField("0.0", value: $viewModel.players[index].handicapIndex, format: .number.precision(.fractionLength(1)))
                                    .keyboardType(.decimalPad)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: 50)
                            }
                        }
                        Spacer()
                        let name = viewModel.players[index].name.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            Button {
                                buddyStore.add(name: name, handicapIndex: viewModel.players[index].handicapIndex)
                            } label: {
                                Image(systemName: buddyStore.buddies.contains(where: { $0.name.lowercased() == name.lowercased() }) ? "bookmark.fill" : "bookmark")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                NavigationLink("Next: Course") {
                    CourseStubScreen(viewModel: viewModel, onFinish: onFinish)
                }
                .disabled(!viewModel.hasFourNamedPlayers)
            }
        }
        .navigationTitle("Players")
    }
}

private struct CourseStubScreen: View {
    @ObservedObject var viewModel: RoundSetupViewModel
    let onFinish: (RoundSetupSession) -> Void

    var body: some View {
        Form {
            Section(viewModel.courseName) {
                Picker("Tee Box", selection: $viewModel.teeBoxName) {
                    ForEach(RoundSetupViewModel.teeBoxOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }
            Section {
                NavigationLink("Next: Teams") {
                    TeamAssignmentScreen(viewModel: viewModel, onFinish: onFinish)
                }
            }
        }
        .navigationTitle("Course")
    }
}

private struct TeamAssignmentScreen: View {
    @EnvironmentObject private var session: SessionModel
    @ObservedObject var viewModel: RoundSetupViewModel
    let onFinish: (RoundSetupSession) -> Void

    var body: some View {
        List {
            Section("Auto Pairing (Low HI + High HI)") {
                ForEach(viewModel.pairings) { pairing in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pairing.team == .teamA ? "Team A" : "Team B")
                            .font(.headline)
                        ForEach(pairing.players) { player in
                            HStack {
                                Text(player.name)
                                Spacer()
                                Text(String(format: "HI %.1f", player.handicapIndex))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Teams")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Start Round") {
                    viewModel.commit(into: session)
                    if let configured = session.configuredRound {
                        onFinish(configured)
                    }
                }
            }
        }
    }
}

private struct ConfiguredRoundCard: View {
    let round: RoundSetupSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(round.event.name)
                .font(.headline)
            Text(round.event.date, style: .date)
                .foregroundStyle(.secondary)
            Text(round.courseName)
                .foregroundStyle(.secondary)
            Text("Tee Box: \(round.teeBoxName)")
                .foregroundStyle(.secondary)
            Divider()
            Text("Players")
                .font(.subheadline.weight(.medium))
            ForEach(round.players) { player in
                HStack {
                    Text(player.name)
                    Spacer()
                    Text(String(format: "HI %.1f", player.handicapIndex))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
