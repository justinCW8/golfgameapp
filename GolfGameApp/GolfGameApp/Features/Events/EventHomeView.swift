import SwiftUI
import Combine

struct EventHomeView: View {
    @EnvironmentObject private var session: SessionModel
    @State private var path: [EventRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                if let active = session.activeEventSession {
                    ActiveEventCard(event: active)

                    Button("Open Leaderboard") {
                        path.append(.leaderboard)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Create New Event") {
                        path.append(.setup)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("No event configured")
                        .foregroundStyle(.secondary)

                    Button("Create Event") {
                        path.append(.setup)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("Events")
            .navigationDestination(for: EventRoute.self) { route in
                switch route {
                case .setup:
                    EventSetupFlowView { _ in
                        path.append(.leaderboard)
                    }
                case .leaderboard:
                    EventLeaderboardView(session: session)
                }
            }
        }
    }
}

private enum EventRoute: Hashable {
    case setup
    case leaderboard
}

@MainActor
private final class EventSetupViewModel: ObservableObject {
    @Published var eventName: String = ""
    @Published var eventDate: Date = Date()
    @Published var courseName: String = DemoCourseFactory.name
    @Published var players: [PlayerDraft] = (1...8).map {
        PlayerDraft(name: "Player \($0)", handicapIndex: 0)
    }
    @Published var groupByPlayerID: [String: Int] = [:]
    @Published var errorMessage: String?

    init() {
        syncAssignments()
    }

    var trimmedEventName: String {
        eventName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var namedPlayers: [PlayerDraft] {
        players.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var hasValidEventName: Bool {
        !trimmedEventName.isEmpty
    }

    var hasValidPlayerCount: Bool {
        let count = namedPlayers.count
        return count >= 4 && count % 4 == 0
    }

    var groupCount: Int {
        max(1, namedPlayers.count / 4)
    }

    var groupSizes: [Int: Int] {
        var counts: [Int: Int] = [:]
        for player in namedPlayers {
            let key = groupByPlayerID[player.id.uuidString] ?? 1
            counts[key, default: 0] += 1
        }
        return counts
    }

    var canFinishAssignment: Bool {
        guard hasValidEventName, hasValidPlayerCount else { return false }
        guard namedPlayers.allSatisfy({ groupByPlayerID[$0.id.uuidString] != nil }) else { return false }

        let expectedSize = namedPlayers.count / groupCount
        return (1...groupCount).allSatisfy { groupSizes[$0, default: 0] == expectedSize }
    }

    func addPlayer() {
        players.append(PlayerDraft(name: "", handicapIndex: 0))
        syncAssignments()
    }

    func removeLastPlayer() {
        guard players.count > 4 else { return }
        let removed = players.removeLast()
        groupByPlayerID.removeValue(forKey: removed.id.uuidString)
        syncAssignments()
    }

    func assignedGroup(for player: PlayerDraft) -> Int {
        groupByPlayerID[player.id.uuidString] ?? 1
    }

    func setGroup(_ group: Int, for player: PlayerDraft) {
        groupByPlayerID[player.id.uuidString] = group
    }

    func commit(into session: SessionModel) {
        guard canFinishAssignment else {
            errorMessage = "Each group must have the same number of players."
            return
        }

        let snapshots = namedPlayers.map {
            PlayerSnapshot(
                id: $0.id.uuidString,
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                handicapIndex: $0.handicapIndex
            )
        }

        let groups = (1...groupCount).map { index in
            let ids = namedPlayers
                .filter { groupByPlayerID[$0.id.uuidString] == index }
                .map { $0.id.uuidString }
            return EventGroup(id: "group-\(index)", name: "Group \(index)", playerIDs: ids)
        }

        session.startEventSession(
            name: trimmedEventName,
            date: eventDate,
            courseName: courseName,
            holes: DemoCourseFactory.holes18(),
            players: snapshots,
            groups: groups
        )

        errorMessage = nil
    }

    private func syncAssignments() {
        let named = namedPlayers
        let count = max(1, named.count / 4)

        for (index, player) in named.enumerated() {
            if groupByPlayerID[player.id.uuidString] == nil {
                groupByPlayerID[player.id.uuidString] = min((index / 4) + 1, max(1, count))
            }
        }

        for player in players where player.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            groupByPlayerID.removeValue(forKey: player.id.uuidString)
        }
    }
}

private struct EventSetupFlowView: View {
    @StateObject private var viewModel = EventSetupViewModel()
    let onFinish: (EventSession) -> Void

    var body: some View {
        EventBasicsScreen(viewModel: viewModel, onFinish: onFinish)
    }
}

private struct EventBasicsScreen: View {
    @ObservedObject var viewModel: EventSetupViewModel
    let onFinish: (EventSession) -> Void

    var body: some View {
        Form {
            Section("Event") {
                TextField("Event name", text: $viewModel.eventName)
                DatePicker("Date", selection: $viewModel.eventDate, displayedComponents: .date)
            }

            Section("Course") {
                Text(viewModel.courseName)
                Text("Demo course is used until course lookup is implemented.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink("Next: Players") {
                    EventPlayersScreen(viewModel: viewModel, onFinish: onFinish)
                }
                .disabled(!viewModel.hasValidEventName)
            }
        }
        .navigationTitle("Create Event")
    }
}

private struct EventPlayersScreen: View {
    @ObservedObject var viewModel: EventSetupViewModel
    let onFinish: (EventSession) -> Void

    var body: some View {
        Form {
            Section("Players") {
                ForEach($viewModel.players) { $player in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Player name", text: $player.name)
                        HStack {
                            Text("HI")
                            Spacer()
                            TextField("0.0", value: $player.handicapIndex, format: .number.precision(.fractionLength(1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                        }
                    }
                    .padding(.vertical, 4)
                }

                HStack {
                    Button("Add Player") {
                        viewModel.addPlayer()
                    }
                    Spacer()
                    Button("Remove Last") {
                        viewModel.removeLastPlayer()
                    }
                    .disabled(viewModel.players.count <= 4)
                }
            }

            Section {
                Text("Use 4, 8, 12... named players for equal groups of 4.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NavigationLink("Next: Groups") {
                    EventGroupAssignmentScreen(viewModel: viewModel, onFinish: onFinish)
                }
                .disabled(!viewModel.hasValidPlayerCount)
            }
        }
        .navigationTitle("Players")
    }
}

private struct EventGroupAssignmentScreen: View {
    @EnvironmentObject private var session: SessionModel
    @ObservedObject var viewModel: EventSetupViewModel
    let onFinish: (EventSession) -> Void

    var body: some View {
        List {
            Section("Assign Groups") {
                ForEach(viewModel.namedPlayers) { player in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(player.name)
                            Text(String(format: "HI %.1f", player.handicapIndex))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Group", selection: Binding(
                            get: { viewModel.assignedGroup(for: player) },
                            set: { viewModel.setGroup($0, for: player) }
                        )) {
                            ForEach(1...viewModel.groupCount, id: \.self) { group in
                                Text("Group \(group)").tag(group)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            Section("Group Counts") {
                ForEach(1...viewModel.groupCount, id: \.self) { group in
                    HStack {
                        Text("Group \(group)")
                        Spacer()
                        Text("\(viewModel.groupSizes[group, default: 0]) players")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish") {
                    viewModel.commit(into: session)
                    if let event = session.activeEventSession {
                        onFinish(event)
                    }
                }
                .disabled(!viewModel.canFinishAssignment)
            }
        }
    }
}

private struct EventLeaderboardView: View {
    @ObservedObject var session: SessionModel

    var body: some View {
        Group {
            if let event = session.activeEventSession {
                List {
                    Section("Event") {
                        Text(event.name)
                            .font(.headline)
                        Text(event.date, style: .date)
                            .foregroundStyle(.secondary)
                        Text(event.courseName)
                            .foregroundStyle(.secondary)
                        Text("Thru \(EventGroupScoringViewModel.maxCompletedHole(from: event))")
                            .foregroundStyle(.secondary)
                    }

                    Section("Leaderboard") {
                        ForEach(Array(EventGroupScoringViewModel.leaderboardRows(from: event).enumerated()), id: \.element.id) { index, row in
                            HStack {
                                Text("#\(index + 1)")
                                    .frame(width: 32, alignment: .leading)
                                VStack(alignment: .leading) {
                                    Text(row.player.name)
                                    Text("Thru \(row.thruHole)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(row.totalPoints) pts")
                                    .font(.headline)
                            }
                        }
                    }

                    Section("Groups") {
                        ForEach(event.groups) { group in
                            NavigationLink {
                                EventGroupScoringView(session: session, groupID: group.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(group.name)
                                        Text("\(group.playerIDs.count) players")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    let hole = event.currentHoleByGroup[group.id, default: 1]
                                    Text(hole > 18 ? "Complete" : "Hole \(hole)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Stableford Live")
            } else {
                Text("No active event")
                    .foregroundStyle(.secondary)
                    .navigationTitle("Stableford Live")
            }
        }
    }
}

private struct EventGroupScoringView: View {
    @StateObject private var viewModel: EventGroupScoringViewModel

    init(session: SessionModel, groupID: String) {
        _viewModel = StateObject(wrappedValue: EventGroupScoringViewModel(sessionStore: session, groupID: groupID))
    }

    var body: some View {
        Form {
            Section("Group") {
                Text(viewModel.groupName)
                    .font(.headline)
                if viewModel.isComplete {
                    Text("All holes completed.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Hole \(viewModel.currentHole) • Par \(viewModel.currentPar) • SI \(viewModel.currentStrokeIndex)")
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.isComplete {
                Section("Player Gross Entry") {
                    ForEach(viewModel.groupPlayers) { player in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(player.name)
                                Text(String(format: "HI %.1f", player.handicapIndex))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField(
                                "Gross",
                                text: Binding(
                                    get: { viewModel.grossText(for: player.id) },
                                    set: { viewModel.setGrossText($0, for: player.id) }
                                )
                            )
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 70)
                        }

                        HStack {
                            Text("Net")
                            Spacer()
                            Text(viewModel.netPreview(for: player))
                        }
                        HStack {
                            Text("Stableford")
                            Spacer()
                            Text(viewModel.pointsPreview(for: player))
                        }
                    }
                }

                Section {
                    Button("Score Hole") {
                        viewModel.scoreHole()
                    }
                    .disabled(!viewModel.canScore)
                }
            }

            if !viewModel.lastScoredResults.isEmpty {
                Section("Last Scored Hole") {
                    ForEach(viewModel.lastScoredResults) { result in
                        VStack(alignment: .leading) {
                            Text("Player ID: \(result.playerID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Gross \(result.gross), Net \(result.net), Points \(result.points)")
                        }
                    }
                }
            }

            if let info = viewModel.infoMessage {
                Section {
                    Text(info)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(viewModel.groupName)
        .onAppear {
            viewModel.seedInputs()
        }
    }
}

private struct ActiveEventCard: View {
    let event: EventSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.name)
                .font(.headline)
            Text(event.date, style: .date)
                .foregroundStyle(.secondary)
            Text(event.courseName)
                .foregroundStyle(.secondary)
            Text("Players: \(event.players.count) • Groups: \(event.groups.count)")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
