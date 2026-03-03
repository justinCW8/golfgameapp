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
    @Published var pickupFlags: [String: Bool] = [:]
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

    // MARK: - Accessors

    var event: EventSession? { sessionStore.activeEventSession }

    var group: EventGroup? { event?.groups.first(where: { $0.id == groupID }) }

    var groupPlayers: [PlayerSnapshot] {
        guard let event, let group else { return [] }
        let playerSet = Set(group.playerIDs)
        return event.players.filter { playerSet.contains($0.id) }
    }

    var groupName: String { group?.name ?? "Group" }

    var currentHole: Int {
        guard let event else { return 1 }
        return event.currentHoleByGroup[groupID, default: 1]
    }

    var isComplete: Bool { currentHole > 18 }

    var holeConfig: CourseHoleStub? {
        event?.holes.first(where: { $0.number == currentHole })
    }

    var currentPar: Int { holeConfig?.par ?? 4 }
    var currentStrokeIndex: Int { holeConfig?.strokeIndex ?? currentHole }
    var currentYardage: Int { holeConfig?.yardage ?? 0 }

    var canScore: Bool {
        guard !isComplete, !groupPlayers.isEmpty else { return false }
        return groupPlayers.allSatisfy { player in
            if pickupFlags[player.id] == true { return true }
            let text = grossInputs[player.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(text) != nil
        }
    }

    // MARK: - Input

    func grossText(for playerID: String) -> String {
        grossInputs[playerID, default: ""]
    }

    func setGrossText(_ value: String, for playerID: String) {
        grossInputs[playerID] = value
        if !value.isEmpty { pickupFlags[playerID] = false }
    }

    func isPickup(for playerID: String) -> Bool { pickupFlags[playerID] == true }

    func togglePickup(for player: PlayerSnapshot) {
        let key = player.id
        if pickupFlags[key] == true {
            pickupFlags[key] = false
        } else {
            pickupFlags[key] = true
            grossInputs[key] = ""
        }
    }

    // MARK: - Calculations

    func strokeCount(for player: PlayerSnapshot) -> Int {
        strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: currentStrokeIndex)
    }

    func courseHandicap(for player: PlayerSnapshot) -> Int {
        max(0, Int(player.handicapIndex.rounded(.down)))
    }

    func pickupGross(for player: PlayerSnapshot) -> Int {
        currentPar + 2 + strokeCount(for: player)
    }

    func netPreview(for player: PlayerSnapshot) -> String {
        if pickupFlags[player.id] == true { return "PU" }
        let text = grossInputs[player.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gross = Int(text) else { return "—" }
        return String(gross - strokeCount(for: player))
    }

    func pointsPreview(for player: PlayerSnapshot) -> String {
        if pickupFlags[player.id] == true { return "0" }
        let text = grossInputs[player.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gross = Int(text) else { return "—" }
        let output = StablefordEngine.scoreHole(
            StablefordHoleScoreInput(gross: gross, par: currentPar, handicapStrokes: strokeCount(for: player))
        )
        return String(output.points)
    }

    func runningTotal(for playerID: String) -> Int {
        event?.holeResultsByPlayer[playerID, default: []].reduce(0) { $0 + $1.points } ?? 0
    }

    // MARK: - Score Hole

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
        let hole = currentHole

        for playerID in group.playerIDs {
            guard let player = playerByID[playerID] else { continue }
            let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: currentStrokeIndex)
            let isPlayerPickup = pickupFlags[playerID] == true

            let gross: Int
            if isPlayerPickup {
                gross = currentPar + 2 + strokes
            } else {
                let raw = grossInputs[playerID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let g = Int(raw) else {
                    errorMessage = "Enter valid gross scores for all players."
                    return
                }
                gross = g
            }

            let output = StablefordEngine.scoreHole(
                StablefordHoleScoreInput(gross: gross, par: currentPar, handicapStrokes: strokes)
            )

            let result = StablefordHoleResult(
                playerID: player.id,
                holeNumber: hole,
                gross: gross,
                net: output.net,
                points: isPlayerPickup ? 0 : output.points,
                strokes: strokes
            )
            holeResults.append(result)
        }

        for result in holeResults {
            var playerResults = event.holeResultsByPlayer[result.playerID, default: []]
            if let idx = playerResults.firstIndex(where: { $0.holeNumber == result.holeNumber }) {
                playerResults[idx] = result
            } else {
                playerResults.append(result)
            }
            playerResults.sort { $0.holeNumber < $1.holeNumber }
            event.holeResultsByPlayer[result.playerID] = playerResults
        }

        event.currentHoleByGroup[groupID] = min(hole + 1, 19)
        event.updatedAt = Date()
        sessionStore.updateActiveEventSession(event)

        lastScoredResults = holeResults
        for player in groupPlayers {
            grossInputs[player.id] = ""
            pickupFlags[player.id] = false
        }
        infoMessage = "Scored hole \(hole)."
        errorMessage = nil
    }

    // MARK: - Edit Last Hole

    func editLastHole() {
        guard var event = sessionStore.activeEventSession else { return }
        let holeToEdit = currentHole - 1
        guard holeToEdit >= 1 else { return }

        for player in groupPlayers {
            if let result = event.holeResultsByPlayer[player.id]?.first(where: { $0.holeNumber == holeToEdit }) {
                grossInputs[player.id] = String(result.gross)
                pickupFlags[player.id] = false
            }
        }

        for player in groupPlayers {
            event.holeResultsByPlayer[player.id]?.removeAll { $0.holeNumber == holeToEdit }
        }

        event.currentHoleByGroup[groupID] = holeToEdit
        event.updatedAt = Date()
        sessionStore.updateActiveEventSession(event)

        lastScoredResults = []
        infoMessage = nil
        errorMessage = nil
    }

    func seedInputs() {
        for player in groupPlayers {
            if grossInputs[player.id] == nil { grossInputs[player.id] = "" }
            if pickupFlags[player.id] == nil { pickupFlags[player.id] = false }
        }
    }

    // MARK: - Leaderboard (static, used by EventHomeView)

    static func leaderboardRows(from event: EventSession) -> [StablefordLeaderboardRow] {
        let rows = event.players.map { player -> StablefordLeaderboardRow in
            let results = event.holeResultsByPlayer[player.id, default: []]
            let total = results.reduce(0) { $0 + $1.points }
            let thru = results.map(\.holeNumber).max() ?? 0
            return StablefordLeaderboardRow(player: player, totalPoints: total, thruHole: thru)
        }
        return rows.sorted { lhs, rhs in
            if lhs.totalPoints != rhs.totalPoints { return lhs.totalPoints > rhs.totalPoints }
            // Countback: back 9, back 6, back 3, hole 18
            let lhsPts = Dictionary(
                uniqueKeysWithValues: event.holeResultsByPlayer[lhs.player.id, default: []].map { ($0.holeNumber, $0.points) }
            )
            let rhsPts = Dictionary(
                uniqueKeysWithValues: event.holeResultsByPlayer[rhs.player.id, default: []].map { ($0.holeNumber, $0.points) }
            )
            let segments: [ClosedRange<Int>] = [10...18, 13...18, 16...18, 18...18]
            for seg in segments {
                let l = seg.reduce(0) { $0 + (lhsPts[$1] ?? 0) }
                let r = seg.reduce(0) { $0 + (rhsPts[$1] ?? 0) }
                if l != r { return l > r }
            }
            if lhs.thruHole != rhs.thruHole { return lhs.thruHole > rhs.thruHole }
            return lhs.player.name.localizedCaseInsensitiveCompare(rhs.player.name) == .orderedAscending
        }
    }

    static func maxCompletedHole(from event: EventSession) -> Int {
        event.holeResultsByPlayer.values
            .flatMap { $0.map(\.holeNumber) }
            .max() ?? 0
    }
}
