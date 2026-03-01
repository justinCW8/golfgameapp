import Foundation
import Combine

struct StablefordLeaderboardRow: Identifiable {
    var id: String { player.id }
    var player: PlayerSnapshot
    var totalPoints: Int
    var thruHole: Int
}

@MainActor
final class EventGroupScoringViewModel: ObservableObject {
    @Published var grossInputs: [String: String] = [:]
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var lastScoredResults: [StablefordHoleResult] = []

    private let sessionStore: SessionModel
    private let groupID: String

    init(sessionStore: SessionModel, groupID: String) {
        self.sessionStore = sessionStore
        self.groupID = groupID
        seedInputs()
    }

    var event: EventSession? {
        sessionStore.activeEventSession
    }

    var group: EventGroup? {
        event?.groups.first(where: { $0.id == groupID })
    }

    var groupPlayers: [PlayerSnapshot] {
        guard let event, let group else { return [] }
        let playerSet = Set(group.playerIDs)
        return event.players.filter { playerSet.contains($0.id) }
    }

    var groupName: String {
        group?.name ?? "Group"
    }

    var currentHole: Int {
        guard let event else { return 1 }
        return event.currentHoleByGroup[groupID, default: 1]
    }

    var isComplete: Bool {
        currentHole > 18
    }

    var holeConfig: CourseHoleStub? {
        event?.holes.first(where: { $0.number == currentHole })
    }

    var currentPar: Int {
        holeConfig?.par ?? 4
    }

    var currentStrokeIndex: Int {
        holeConfig?.strokeIndex ?? currentHole
    }

    var canScore: Bool {
        guard !isComplete else { return false }
        guard !groupPlayers.isEmpty else { return false }
        return groupPlayers.allSatisfy { player in
            Int(grossInputs[player.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        }
    }

    func grossText(for playerID: String) -> String {
        grossInputs[playerID, default: ""]
    }

    func setGrossText(_ value: String, for playerID: String) {
        grossInputs[playerID] = value
    }

    func strokeCount(for player: PlayerSnapshot) -> Int {
        strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: currentStrokeIndex)
    }

    func netPreview(for player: PlayerSnapshot) -> String {
        let raw = grossText(for: player.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gross = Int(raw) else { return "-" }
        return String(gross - strokeCount(for: player))
    }

    func pointsPreview(for player: PlayerSnapshot) -> String {
        let raw = grossText(for: player.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gross = Int(raw) else { return "-" }
        let output = StablefordEngine.scoreHole(
            StablefordHoleScoreInput(
                gross: gross,
                par: currentPar,
                handicapStrokes: strokeCount(for: player)
            )
        )
        return String(output.points)
    }

    func scoreHole() {
        guard var event = sessionStore.activeEventSession else {
            errorMessage = "No active event session."
            return
        }
        guard let group = event.groups.first(where: { $0.id == groupID }) else {
            errorMessage = "Group not found."
            return
        }
        guard !isComplete else {
            errorMessage = "This group has completed all 18 holes."
            return
        }

        let playerByID = Dictionary(uniqueKeysWithValues: event.players.map { ($0.id, $0) })
        var holeResults: [StablefordHoleResult] = []

        for playerID in group.playerIDs {
            guard let player = playerByID[playerID] else { continue }
            let raw = grossInputs[playerID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let gross = Int(raw) else {
                errorMessage = "Enter valid gross scores for all players in \(group.name)."
                return
            }

            let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: currentStrokeIndex)
            let output = StablefordEngine.scoreHole(
                StablefordHoleScoreInput(
                    gross: gross,
                    par: currentPar,
                    handicapStrokes: strokes
                )
            )

            let result = StablefordHoleResult(
                playerID: player.id,
                holeNumber: currentHole,
                gross: gross,
                net: output.net,
                points: output.points,
                strokes: strokes
            )
            holeResults.append(result)
        }

        for result in holeResults {
            var playerResults = event.holeResultsByPlayer[result.playerID, default: []]
            if let existingIndex = playerResults.firstIndex(where: { $0.holeNumber == result.holeNumber }) {
                playerResults[existingIndex] = result
            } else {
                playerResults.append(result)
            }
            playerResults.sort { $0.holeNumber < $1.holeNumber }
            event.holeResultsByPlayer[result.playerID] = playerResults
        }

        event.currentHoleByGroup[groupID] = min(currentHole + 1, 19)
        event.updatedAt = Date()
        sessionStore.updateActiveEventSession(event)

        lastScoredResults = holeResults
        for player in groupPlayers {
            grossInputs[player.id] = ""
        }
        infoMessage = "Scored hole \(currentHole) for \(group.name)."
        errorMessage = nil
    }

    func seedInputs() {
        for player in groupPlayers {
            if grossInputs[player.id] == nil {
                grossInputs[player.id] = ""
            }
        }
    }

    static func leaderboardRows(from event: EventSession) -> [StablefordLeaderboardRow] {
        let rows = event.players.map { player -> StablefordLeaderboardRow in
            let results = event.holeResultsByPlayer[player.id, default: []]
            let total = results.reduce(0) { $0 + $1.points }
            let thru = results.map(\.holeNumber).max() ?? 0
            return StablefordLeaderboardRow(player: player, totalPoints: total, thruHole: thru)
        }

        return rows.sorted {
            if $0.totalPoints != $1.totalPoints { return $0.totalPoints > $1.totalPoints }
            if $0.thruHole != $1.thruHole { return $0.thruHole > $1.thruHole }
            return $0.player.name.localizedCaseInsensitiveCompare($1.player.name) == .orderedAscending
        }
    }

    static func maxCompletedHole(from event: EventSession) -> Int {
        event.holeResultsByPlayer.values
            .flatMap { $0.map(\.holeNumber) }
            .max() ?? 0
    }
}
