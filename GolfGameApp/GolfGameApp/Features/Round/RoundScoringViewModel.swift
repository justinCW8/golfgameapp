import Foundation
import Combine

@MainActor
final class RoundScoringViewModel: ObservableObject {
    @Published var currentHole = 1
    @Published var holeHistory: [SixPointScotchHoleOutput] = []
    @Published var teamANetInputs = ["", ""]
    @Published var teamBNetInputs = ["", ""]
    @Published var teamAGrossInputs = ["", ""]
    @Published var teamBGrossInputs = ["", ""]
    @Published var proxWinner: ProxWinner = .none
    @Published var leaderTeedOff = false
    @Published var trailerTeedOff = false
    @Published var requestPress = false
    @Published var requestRoll = false
    @Published var requestReroll = false

    @Published var hasScoredCurrentHole = false
    @Published var lastOutput: SixPointScotchHoleOutput?
    @Published var errorMessage: String?

    private let sessionStore: SessionModel
    private var engine = SixPointScotchEngine()
    private var scoredHoleInputs: [SixPointScotchHoleInput] = []
    private let requiredInputCount = 8

    var playerNames: [String] {
        sessionStore.activeRoundSession?.setup.players.map(\.name) ?? []
    }

    init(sessionStore: SessionModel) {
        self.sessionStore = sessionStore
        restoreFromSession()
    }

    var canScore: Bool {
        allRequiredInputs.count == requiredInputCount && allRequiredInputs.allSatisfy { value in
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

    var canRequestPress: Bool {
        trailingTeam != nil && !leaderTeedOff && pressesRemainingThisNine > 0 && !hasScoredCurrentHole
    }

    var canRequestRoll: Bool {
        trailingTeam != nil && leaderTeedOff && !trailerTeedOff && !hasScoredCurrentHole
    }

    var canRequestReroll: Bool {
        leadingTeam != nil && requestRoll && !trailerTeedOff && !hasScoredCurrentHole
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
        guard canScore else {
            errorMessage = "Enter all 8 required scores as whole numbers."
            return
        }
        guard !requestReroll || requestRoll else {
            errorMessage = "Re-roll requires roll on this hole."
            return
        }

        do {
            let teamANet = try parseIntPair(teamANetInputs, label: "Team A net")
            let teamBNet = try parseIntPair(teamBNetInputs, label: "Team B net")
            let teamAGross = try parseIntPair(teamAGrossInputs, label: "Team A gross")
            let teamBGross = try parseIntPair(teamBGrossInputs, label: "Team B gross")
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
                par: 4,
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

    private func parseIntPair(_ raw: [String], label: String) throws -> [Int] {
        guard raw.count == 2 else { throw ValidationError("\(label) must have 2 values.") }
        return try raw.map {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Int(trimmed) else {
                throw ValidationError("\(label) must be whole numbers.")
            }
            return value
        }
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
        teamANetInputs = ["", ""]
        teamBNetInputs = ["", ""]
        teamAGrossInputs = ["", ""]
        teamBGrossInputs = ["", ""]
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

    func pressTapped() {
        if requestPress {
            requestPress = false
            return
        }
        guard canRequestPress else { return }
        requestPress = true
    }

    func rollTapped() {
        if requestRoll {
            requestRoll = false
            requestReroll = false
            return
        }
        guard canRequestRoll else { return }
        requestRoll = true
    }

    func rerollTapped() {
        if requestReroll {
            requestReroll = false
            return
        }
        guard canRequestReroll else { return }
        requestReroll = true
    }

    func leaderTeedOffTapped() {
        leaderTeedOff = true
    }

    func trailerTeedOffTapped() {
        trailerTeedOff = true
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
            currentHole: currentHole,
            isCurrentHoleScored: hasScoredCurrentHole,
            scoredHoleInputs: scoredHoleInputs
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
        hasScoredCurrentHole = session.isCurrentHoleScored
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
}

private struct ValidationError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

private extension RoundScoringViewModel {
    var allRequiredInputs: [String] {
        teamANetInputs + teamBNetInputs + teamAGrossInputs + teamBGrossInputs
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
