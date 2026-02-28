import Foundation

enum SixPointScotchActionError: Error, Equatable {
    case holeOutOfRange
    case invalidPlayerCount
    case pressRequiresTrailingTeam
    case pressWindowClosed
    case pressLimitReached
    case rollRequiresTrailingTeam
    case rollWindowInvalid
    case rerollRequiresRoll
    case rerollRequiresLeadingTeam
    case rerollWindowInvalid
}

struct SixPointScotchHoleInput: Equatable {
    var holeNumber: Int
    var par: Int
    var teamANetScores: [Int]
    var teamBNetScores: [Int]
    var teamAGrossScores: [Int]
    var teamBGrossScores: [Int]
    var teamAProxFeet: Double?
    var teamBProxFeet: Double?
    var requestPressBy: TeamSide?
    var requestRollBy: TeamSide?
    var requestRerollBy: TeamSide?
    var leaderTeedOff: Bool
    var trailerTeedOff: Bool
}

struct SixPointScotchHoleOutput: Equatable {
    var holeNumber: Int
    var rawTeamAPoints: Int
    var rawTeamBPoints: Int
    var multipliedTeamAPoints: Int
    var multipliedTeamBPoints: Int
    var multiplier: Int
    var frontNineTeamA: Int
    var frontNineTeamB: Int
    var backNineTeamA: Int
    var backNineTeamB: Int
    var totalTeamA: Int
    var totalTeamB: Int
    var auditLog: [String]
}

struct SixPointScotchEngine {
    private(set) var frontNine = NineLedger()
    private(set) var backNine = NineLedger()
    private(set) var auditLog: [String] = []

    mutating func scoreHole(_ input: SixPointScotchHoleInput) throws -> SixPointScotchHoleOutput {
        guard (1...18).contains(input.holeNumber) else {
            throw SixPointScotchActionError.holeOutOfRange
        }
        guard input.teamANetScores.count == 2,
              input.teamBNetScores.count == 2,
              input.teamAGrossScores.count == 2,
              input.teamBGrossScores.count == 2 else {
            throw SixPointScotchActionError.invalidPlayerCount
        }

        let isFrontNine = input.holeNumber <= 9
        var ledger = isFrontNine ? frontNine : backNine
        let leader = leaderForCurrentNine(ledger: ledger)
        let trailing = trailingForCurrentNine(ledger: ledger)

        var holeAudit: [String] = ["Hole \(input.holeNumber)"]
        var rollFlag = 0
        var rerollFlag = 0

        if let pressTeam = input.requestPressBy {
            guard ledger.usedPresses < 2 else { throw SixPointScotchActionError.pressLimitReached }
            guard trailing == pressTeam else { throw SixPointScotchActionError.pressRequiresTrailingTeam }
            guard input.leaderTeedOff == false else { throw SixPointScotchActionError.pressWindowClosed }
            ledger.usedPresses += 1
            ledger.activePresses += 1
            holeAudit.append("Press requested by \(pressTeam.rawValue) (active this hole).")
        }

        if let rollTeam = input.requestRollBy {
            guard trailing == rollTeam else { throw SixPointScotchActionError.rollRequiresTrailingTeam }
            guard input.leaderTeedOff, input.trailerTeedOff == false else { throw SixPointScotchActionError.rollWindowInvalid }
            rollFlag = 1
            holeAudit.append("Roll requested by \(rollTeam.rawValue).")
        }

        if let rerollTeam = input.requestRerollBy {
            guard rollFlag == 1 else { throw SixPointScotchActionError.rerollRequiresRoll }
            guard leader == rerollTeam else { throw SixPointScotchActionError.rerollRequiresLeadingTeam }
            guard input.trailerTeedOff == false else { throw SixPointScotchActionError.rerollWindowInvalid }
            rerollFlag = 1
            holeAudit.append("Re-roll requested by \(rerollTeam.rawValue).")
        }

        var rawA = 0
        var rawB = 0

        applyBucket(points: 2, winner: lowManWinner(teamANet: input.teamANetScores, teamBNet: input.teamBNetScores), toA: &rawA, toB: &rawB)
        applyBucket(points: 2, winner: lowTeamWinner(teamANet: input.teamANetScores, teamBNet: input.teamBNetScores), toA: &rawA, toB: &rawB)
        applyBucket(points: 1, winner: naturalBirdieWinner(par: input.par, teamAGross: input.teamAGrossScores, teamBGross: input.teamBGrossScores), toA: &rawA, toB: &rawB)
        applyBucket(points: 1, winner: proxWinner(teamAProxFeet: input.teamAProxFeet, teamBProxFeet: input.teamBProxFeet), toA: &rawA, toB: &rawB)

        if rawA == 6 {
            rawA = 12
            holeAudit.append("Umbrella: teamA swept all buckets (12 raw points).")
        } else if rawB == 6 {
            rawB = 12
            holeAudit.append("Umbrella: teamB swept all buckets (12 raw points).")
        }

        let exponent = ledger.activePresses + rollFlag + rerollFlag
        let multiplier = Int(pow(2.0, Double(exponent)))
        let finalA = rawA * multiplier
        let finalB = rawB * multiplier
        holeAudit.append("Multiplier=2^\(exponent)=\(multiplier). Raw A/B=\(rawA)/\(rawB). Final A/B=\(finalA)/\(finalB).")

        ledger.teamAPoints += finalA
        ledger.teamBPoints += finalB

        if isFrontNine {
            frontNine = ledger
        } else {
            backNine = ledger
        }

        auditLog.append(contentsOf: holeAudit)

        return SixPointScotchHoleOutput(
            holeNumber: input.holeNumber,
            rawTeamAPoints: rawA,
            rawTeamBPoints: rawB,
            multipliedTeamAPoints: finalA,
            multipliedTeamBPoints: finalB,
            multiplier: multiplier,
            frontNineTeamA: frontNine.teamAPoints,
            frontNineTeamB: frontNine.teamBPoints,
            backNineTeamA: backNine.teamAPoints,
            backNineTeamB: backNine.teamBPoints,
            totalTeamA: frontNine.teamAPoints + backNine.teamAPoints,
            totalTeamB: frontNine.teamBPoints + backNine.teamBPoints,
            auditLog: auditLog
        )
    }

    private func leaderForCurrentNine(ledger: NineLedger) -> TeamSide? {
        if ledger.teamAPoints == ledger.teamBPoints { return nil }
        return ledger.teamAPoints > ledger.teamBPoints ? .teamA : .teamB
    }

    private func trailingForCurrentNine(ledger: NineLedger) -> TeamSide? {
        if ledger.teamAPoints == ledger.teamBPoints { return nil }
        return ledger.teamAPoints < ledger.teamBPoints ? .teamA : .teamB
    }

    private func lowManWinner(teamANet: [Int], teamBNet: [Int]) -> TeamSide? {
        let a = teamANet.min() ?? Int.max
        let b = teamBNet.min() ?? Int.max
        if a == b { return nil }
        return a < b ? .teamA : .teamB
    }

    private func lowTeamWinner(teamANet: [Int], teamBNet: [Int]) -> TeamSide? {
        let a = teamANet.reduce(0, +)
        let b = teamBNet.reduce(0, +)
        if a == b { return nil }
        return a < b ? .teamA : .teamB
    }

    private func naturalBirdieWinner(par: Int, teamAGross: [Int], teamBGross: [Int]) -> TeamSide? {
        let target = par - 1
        let aHasBirdie = teamAGross.contains(target)
        let bHasBirdie = teamBGross.contains(target)
        if aHasBirdie == bHasBirdie { return nil }
        return aHasBirdie ? .teamA : .teamB
    }

    private func proxWinner(teamAProxFeet: Double?, teamBProxFeet: Double?) -> TeamSide? {
        switch (teamAProxFeet, teamBProxFeet) {
        case (.some, .none):
            return .teamA
        case (.none, .some):
            return .teamB
        case (.some(let a), .some(let b)):
            if a == b { return nil }
            return a < b ? .teamA : .teamB
        default:
            return nil
        }
    }

    private func applyBucket(points: Int, winner: TeamSide?, toA: inout Int, toB: inout Int) {
        switch winner {
        case .teamA: toA += points
        case .teamB: toB += points
        case nil: break
        }
    }
}

struct NineLedger: Equatable {
    var activePresses = 0
    var usedPresses = 0
    var teamAPoints = 0
    var teamBPoints = 0
}
