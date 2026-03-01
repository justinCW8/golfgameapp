import Foundation
import Combine

@MainActor
final class RoundScoringViewModel: ObservableObject {
    @Published var currentHole = 1
    @Published var teeTossFirst: TeamSide?
    @Published var holeHistory: [SixPointScotchHoleOutput] = []
    @Published var playerGrossInputs = ["", "", "", ""]
    @Published var proxWinner: ProxWinner = .none
    @Published var leaderTeedOff = false
    @Published var trailerTeedOff = false
    @Published var requestPress = false
    @Published var requestRoll = false
    @Published var requestReroll = false

    @Published var hasScoredCurrentHole = false
    @Published var lastOutput: SixPointScotchHoleOutput?
    @Published var errorMessage: String?
    @Published var holeResults: [HoleResult] = []
    @Published var strokesByPlayerByHole: [HoleStrokeAllocation] = []

    private let sessionStore: SessionModel
    private var engine = SixPointScotchEngine()
    private var scoredHoleInputs: [SixPointScotchHoleInput] = []
    private let requiredInputCount = 4

    init(sessionStore: SessionModel) {
        self.sessionStore = sessionStore
        restoreFromSession()
    }

    var players: [PlayerSnapshot] {
        sessionStore.activeRoundSession?.setup.players ?? []
    }

    var playerNames: [String] {
        players.map(\.name)
    }

    var canScore: Bool {
        !requiresTeeTossChoice &&
        allRequiredInputs.count == requiredInputCount &&
        allRequiredInputs.allSatisfy { value in
            Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        }
    }

    var latestAuditLines: [String] {
        guard let audit = lastOutput?.auditLog, !audit.isEmpty else { return [] }
        return Array(audit.suffix(8))
    }

    var currentNineLedger: NineLedger {
        currentHole <= 9 ? engine.frontNine : engine.backNine
    }

    var leadingTeam: TeamSide? {
        leaderForLedger(currentNineLedger)
    }

    var trailingTeam: TeamSide? {
        trailingForLedger(currentNineLedger)
    }

    var pressesRemainingThisNine: Int {
        max(0, 2 - currentNineLedger.usedPresses)
    }

    var requiresTeeTossChoice: Bool {
        currentHole == 1 && teeTossFirst == nil
    }

    var teesFirstTeam: TeamSide? {
        leadingTeam ?? teeTossFirst
    }

    var teesSecondTeam: TeamSide? {
        guard let first = teesFirstTeam else { return nil }
        return first == .teamA ? .teamB : .teamA
    }

    var canRequestPress: Bool {
        !requiresTeeTossChoice &&
        trailingTeam != nil &&
        !leaderTeedOff &&
        pressesRemainingThisNine > 0 &&
        !hasScoredCurrentHole
    }

    var canRequestRoll: Bool {
        !requiresTeeTossChoice &&
        trailingTeam != nil &&
        leaderTeedOff &&
        !trailerTeedOff &&
        !hasScoredCurrentHole
    }

    var canRequestReroll: Bool {
        !requiresTeeTossChoice &&
        leadingTeam != nil &&
        requestRoll &&
        !trailerTeedOff &&
        !hasScoredCurrentHole
    }

    var currentHoleStrokeIndex: Int {
        holeConfig(for: currentHole)?.strokeIndex ?? currentHole
    }

    var currentHolePar: Int {
        holeConfig(for: currentHole)?.par ?? 4
    }

    var sortedHoleResults: [HoleResult] {
        holeResults.sorted { $0.holeNumber < $1.holeNumber }
    }

    var totalGrossByPlayerID: [String: Int] {
        aggregate(
            values: holeResults.map(\.grossByPlayerID),
            playerIDs: players.map(\.id)
        )
    }

    var totalNetByPlayerID: [String: Int] {
        aggregate(
            values: holeResults.map(\.netByPlayerID),
            playerIDs: players.map(\.id)
        )
    }

    func netDisplay(forPlayerAt index: Int) -> String {
        guard players.indices.contains(index) else { return "-" }
        let raw = playerGrossInputs[index].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gross = Int(raw) else { return "-" }
        let strokes = strokeCount(for: players[index], onHoleStrokeIndex: currentHoleStrokeIndex)
        return String(gross - strokes)
    }

    func scoreCurrentHole() {
        guard currentHole <= 18 else {
            errorMessage = "Round is complete."
            return
        }
        guard !hasScoredCurrentHole else {
            errorMessage = "This hole is already scored. Tap Next Hole."
            return
        }
        guard !requiresTeeTossChoice else {
            errorMessage = "Set the tee toss before scoring Hole 1."
            return
        }
        guard canScore else {
            errorMessage = "Enter all 4 player gross scores as whole numbers."
            return
        }
        guard !requestReroll || requestRoll else {
            errorMessage = "Re-roll requires roll on this hole."
            return
        }

        do {
            let grossScores = try parseGrossScores(playerGrossInputs)
            let holePar = currentHolePar
            let playerIDs = players.map(\.id)
            guard playerIDs.count == 4 else {
                throw ValidationError("Round requires exactly 4 players.")
            }

            let strokesByPlayer = Dictionary(uniqueKeysWithValues: players.map { player in
                (player.id, strokeCount(for: player, onHoleStrokeIndex: currentHoleStrokeIndex))
            })
            let grossByPlayer = Dictionary(uniqueKeysWithValues: zip(playerIDs, grossScores))
            let netByPlayer = Dictionary(uniqueKeysWithValues: playerIDs.map { id in
                (id, (grossByPlayer[id] ?? 0) - (strokesByPlayer[id] ?? 0))
            })

            let teamAIDs = teamPlayerIDs(for: .teamA)
            let teamBIDs = teamPlayerIDs(for: .teamB)
            guard teamAIDs.count == 2, teamBIDs.count == 2 else {
                throw ValidationError("Team assignments are incomplete.")
            }

            let teamAGross = teamAIDs.map { grossByPlayer[$0] ?? 0 }
            let teamBGross = teamBIDs.map { grossByPlayer[$0] ?? 0 }
            let teamANet = teamAIDs.map { netByPlayer[$0] ?? 0 }
            let teamBNet = teamBIDs.map { netByPlayer[$0] ?? 0 }

            let (teamAProx, teamBProx) = proxDistancesFromWinner(proxWinner)
            let leader = leadingTeam
            let trailing = trailingTeam

            if requestPress && trailing == nil {
                throw ValidationError("Press requires a trailing team on this nine.")
            }
            if requestRoll && trailing == nil {
                throw ValidationError("Roll requires a trailing team on this nine.")
            }
            if requestReroll && leader == nil {
                throw ValidationError("Re-roll requires a leading team on this nine.")
            }

            let input = SixPointScotchHoleInput(
                holeNumber: currentHole,
                par: holePar,
                teamANetScores: teamANet,
                teamBNetScores: teamBNet,
                teamAGrossScores: teamAGross,
                teamBGrossScores: teamBGross,
                teamAProxFeet: teamAProx,
                teamBProxFeet: teamBProx,
                requestPressBy: requestPress ? trailing : nil,
                requestRollBy: requestRoll ? trailing : nil,
                requestRerollBy: requestReroll ? leader : nil,
                leaderTeedOff: leaderTeedOff,
                trailerTeedOff: trailerTeedOff
            )

            let output = try engine.scoreHole(input)
            scoredHoleInputs.append(input)
            holeHistory.append(output)
            lastOutput = output
            hasScoredCurrentHole = true

            let holeResult = HoleResult(
                holeNumber: currentHole,
                grossByPlayerID: grossByPlayer,
                netByPlayerID: netByPlayer
            )
            upsertHoleResult(holeResult)
            upsertHoleStrokeAllocation(
                HoleStrokeAllocation(holeNumber: currentHole, strokesByPlayerID: strokesByPlayer)
            )

            errorMessage = nil
            resetHoleActionState()
            persistRoundState()
        } catch let error as ValidationError {
            errorMessage = error.message
        } catch let error as SixPointScotchActionError {
            errorMessage = message(for: error)
        } catch {
            errorMessage = "Unable to score this hole."
        }
    }

    func goToNextHole() {
        guard hasScoredCurrentHole else {
            errorMessage = "Score the current hole first."
            return
        }
        guard currentHole < 18 else {
            errorMessage = "Round complete."
            return
        }

        currentHole += 1
        hasScoredCurrentHole = false
        errorMessage = nil
        resetInputsForNextHole()
        persistRoundState()
    }

    var isRoundComplete: Bool {
        currentHole == 18 && hasScoredCurrentHole
    }

    func pressTapped() {
        guard !requiresTeeTossChoice else { return }
        if requestPress {
            requestPress = false
            return
        }
        guard canRequestPress else { return }
        requestPress = true
    }

    func rollTapped() {
        guard !requiresTeeTossChoice else { return }
        if requestRoll {
            requestRoll = false
            requestReroll = false
            return
        }
        guard canRequestRoll else { return }
        requestRoll = true
    }

    func rerollTapped() {
        guard !requiresTeeTossChoice else { return }
        if requestReroll {
            requestReroll = false
            return
        }
        guard canRequestReroll else { return }
        requestReroll = true
    }

    func leaderTeedOffTapped() {
        guard !requiresTeeTossChoice else { return }
        leaderTeedOff = true
    }

    func trailerTeedOffTapped() {
        guard !requiresTeeTossChoice else { return }
        trailerTeedOff = true
    }

    func setTeeTossFirst(_ team: TeamSide) {
        teeTossFirst = team
        errorMessage = nil
        persistRoundState()
    }

    private func parseGrossScores(_ raw: [String]) throws -> [Int] {
        guard raw.count == requiredInputCount else {
            throw ValidationError("Exactly 4 gross scores are required.")
        }
        return try raw.map {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Int(trimmed) else {
                throw ValidationError("Gross scores must be whole numbers.")
            }
            return value
        }
    }

    private func strokeCount(for player: PlayerSnapshot, onHoleStrokeIndex si: Int) -> Int {
        strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: si)
    }

    private func holeConfig(for holeNumber: Int) -> CourseHoleStub? {
        sessionStore.activeRoundSession?.setup.holes.first(where: { $0.number == holeNumber })
    }

    private func teamPlayerIDs(for team: TeamSide) -> [String] {
        sessionStore.activeRoundSession?.setup.pairings.first(where: { $0.team == team })?.players.map(\.id) ?? []
    }

    private func leaderForLedger(_ ledger: NineLedger) -> TeamSide? {
        if ledger.teamAPoints == ledger.teamBPoints { return nil }
        return ledger.teamAPoints > ledger.teamBPoints ? .teamA : .teamB
    }

    private func trailingForLedger(_ ledger: NineLedger) -> TeamSide? {
        if ledger.teamAPoints == ledger.teamBPoints { return nil }
        return ledger.teamAPoints < ledger.teamBPoints ? .teamA : .teamB
    }

    private func resetInputsForNextHole() {
        playerGrossInputs = ["", "", "", ""]
        proxWinner = .none
        resetHoleActionState()
    }

    private func resetHoleActionState() {
        leaderTeedOff = false
        trailerTeedOff = false
        requestPress = false
        requestRoll = false
        requestReroll = false
    }

    private func upsertHoleResult(_ result: HoleResult) {
        if let index = holeResults.firstIndex(where: { $0.holeNumber == result.holeNumber }) {
            holeResults[index] = result
        } else {
            holeResults.append(result)
        }
        holeResults.sort { $0.holeNumber < $1.holeNumber }
    }

    private func upsertHoleStrokeAllocation(_ value: HoleStrokeAllocation) {
        if let index = strokesByPlayerByHole.firstIndex(where: { $0.holeNumber == value.holeNumber }) {
            strokesByPlayerByHole[index] = value
        } else {
            strokesByPlayerByHole.append(value)
        }
        strokesByPlayerByHole.sort { $0.holeNumber < $1.holeNumber }
    }

    private func message(for error: SixPointScotchActionError) -> String {
        switch error {
        case .holeOutOfRange: return "Hole number must be between 1 and 18."
        case .invalidPlayerCount: return "Exactly two player scores are required per team."
        case .pressRequiresTrailingTeam: return "Press can only be called by the trailing team."
        case .pressWindowClosed: return "Press must be called before leader tees off."
        case .pressLimitReached: return "Only two presses are allowed per nine."
        case .rollRequiresTrailingTeam: return "Roll can only be called by the trailing team."
        case .rollWindowInvalid: return "Roll must be after leader tees off and before trailer tees off."
        case .rerollRequiresRoll: return "Re-roll requires an active roll."
        case .rerollRequiresLeadingTeam: return "Re-roll can only be called by the leading team."
        case .rerollWindowInvalid: return "Re-roll must be before trailer tees off."
        }
    }

    private func persistRoundState() {
        sessionStore.updateActiveRoundState(
            teeTossFirst: teeTossFirst,
            currentHole: currentHole,
            isCurrentHoleScored: hasScoredCurrentHole,
            scoredHoleInputs: scoredHoleInputs,
            holeResults: holeResults,
            strokesByPlayerByHole: strokesByPlayerByHole
        )
    }

    private func restoreFromSession() {
        guard let session = sessionStore.activeRoundSession else { return }

        var rebuiltEngine = SixPointScotchEngine()
        var rebuiltOutputs: [SixPointScotchHoleOutput] = []

        for input in session.scoredHoleInputs {
            do {
                let output = try rebuiltEngine.scoreHole(input)
                rebuiltOutputs.append(output)
            } catch {
                errorMessage = "Saved round data is invalid for one or more holes."
                break
            }
        }

        engine = rebuiltEngine
        scoredHoleInputs = session.scoredHoleInputs
        holeHistory = rebuiltOutputs
        lastOutput = rebuiltOutputs.last
        currentHole = min(max(session.currentHole, 1), 18)
        teeTossFirst = session.teeTossFirst
        hasScoredCurrentHole = session.isCurrentHoleScored
        holeResults = session.holeResults.sorted { $0.holeNumber < $1.holeNumber }
        strokesByPlayerByHole = session.strokesByPlayerByHole.sorted { $0.holeNumber < $1.holeNumber }
    }

    private func proxDistancesFromWinner(_ winner: ProxWinner) -> (Double?, Double?) {
        switch winner {
        case .player1, .player2:
            return (1, 2)
        case .player3, .player4:
            return (2, 1)
        case .none:
            return (nil, nil)
        }
    }

    private func aggregate(values: [[String: Int]], playerIDs: [String]) -> [String: Int] {
        var totals = Dictionary(uniqueKeysWithValues: playerIDs.map { ($0, 0) })
        for dictionary in values {
            for (id, value) in dictionary {
                totals[id, default: 0] += value
            }
        }
        return totals
    }
}

private struct ValidationError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

private extension RoundScoringViewModel {
    var allRequiredInputs: [String] {
        playerGrossInputs
    }
}

enum ProxWinner: String, CaseIterable, Identifiable {
    case player1
    case player2
    case player3
    case player4
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .player1: return "Player 1"
        case .player2: return "Player 2"
        case .player3: return "Player 3"
        case .player4: return "Player 4"
        case .none: return "None"
        }
    }
}
