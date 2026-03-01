import Foundation
import Combine

@MainActor
final class RoundScoringViewModel: ObservableObject {
    @Published var currentHole = 1
    @Published var teamANetInputs = ["", ""]
    @Published var teamBNetInputs = ["", ""]
    @Published var teamAGrossInputs = ["", ""]
    @Published var teamBGrossInputs = ["", ""]
    @Published var teamAProxInput = ""
    @Published var teamBProxInput = ""

    @Published var usePress = false
    @Published var useRoll = false
    @Published var useReroll = false

    @Published var holeHistory: [SixPointScotchHoleOutput] = []
    @Published var hasScoredCurrentHole = false
    @Published var lastOutput: SixPointScotchHoleOutput?
    @Published var errorMessage: String?

    private var engine = SixPointScotchEngine()

    func scoreCurrentHole() {
        guard currentHole <= 18 else {
            errorMessage = "Round is complete."
            return
        }
        guard !hasScoredCurrentHole else {
            errorMessage = "This hole is already scored. Tap Next Hole."
            return
        }

        do {
            let teamANet = try parseIntPair(teamANetInputs, label: "Team A net")
            let teamBNet = try parseIntPair(teamBNetInputs, label: "Team B net")
            let teamAGross = try parseIntPair(teamAGrossInputs, label: "Team A gross")
            let teamBGross = try parseIntPair(teamBGrossInputs, label: "Team B gross")
            let teamAProx = parseOptionalDouble(teamAProxInput)
            let teamBProx = parseOptionalDouble(teamBProxInput)

            let ledger = currentHole <= 9 ? engine.frontNine : engine.backNine
            let leader = leaderForLedger(ledger)
            let trailing = trailingForLedger(ledger)

            if usePress && trailing == nil {
                throw ValidationError("Press requires a trailing team on this nine.")
            }
            if useRoll && trailing == nil {
                throw ValidationError("Roll requires a trailing team on this nine.")
            }
            if useReroll && leader == nil {
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
                requestPressBy: usePress ? trailing : nil,
                requestRollBy: useRoll ? trailing : nil,
                requestRerollBy: useReroll ? leader : nil,
                leaderTeedOff: useRoll || useReroll,
                trailerTeedOff: false
            )

            let output = try engine.scoreHole(input)
            holeHistory.append(output)
            lastOutput = output
            hasScoredCurrentHole = true
            errorMessage = nil
            resetActionToggles()
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
        lastOutput = holeHistory.last
        errorMessage = nil
        resetInputsForNextHole()
    }

    var isRoundComplete: Bool {
        currentHole == 18 && hasScoredCurrentHole
    }

    var isRequiredInputValid: Bool {
        (try? parseIntPair(teamANetInputs, label: "")) != nil &&
        (try? parseIntPair(teamBNetInputs, label: "")) != nil &&
        (try? parseIntPair(teamAGrossInputs, label: "")) != nil &&
        (try? parseIntPair(teamBGrossInputs, label: "")) != nil
    }

    var latestAuditLines: [String] {
        guard let output = lastOutput else { return [] }
        return Array(output.auditLog.suffix(8))
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

    private func parseOptionalDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return Double(trimmed)
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
        teamAProxInput = ""
        teamBProxInput = ""
        resetActionToggles()
    }

    private func resetActionToggles() {
        usePress = false
        useRoll = false
        useReroll = false
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
}

private struct ValidationError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
