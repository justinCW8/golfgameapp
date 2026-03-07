import Foundation

// MARK: - Errors

enum SkinsActionError: Error, Equatable {
    case holeOutOfRange
    case notEnoughPlayers    // fewer than 2
    case duplicatePlayerID
}

// MARK: - Mode

enum SkinsMode: String, Codable, CaseIterable {
    case gross
    case net
    case both
}

// MARK: - Input / Output

struct SkinsPlayerScore {
    var playerID: String
    var gross: Int
    /// Handicap strokes received on this hole (0 if gross-only mode or no strokes).
    var handicapStrokes: Int
}

struct SkinsHoleInput {
    var holeNumber: Int           // 1...18
    var par: Int
    var scores: [SkinsPlayerScore]
    var mode: SkinsMode
    var carryoverEnabled: Bool
}

struct SkinsHoleResult {
    /// nil when the hole is tied.
    var winnerID: String?
    /// Number of skins awarded (1 + carryover) on a win; 0 on a tie.
    var skinsAwarded: Int
    var isTie: Bool
}

struct SkinsHoleOutput {
    var holeNumber: Int
    /// Populated when mode is .gross or .both; zero result when mode is .net.
    var grossResult: SkinsHoleResult
    /// Populated when mode is .net or .both; zero result when mode is .gross.
    var netResult: SkinsHoleResult
    /// Running gross carryover after this hole (0 when mode is .net).
    var grossCarryover: Int
    /// Running net carryover after this hole (0 when mode is .gross).
    var netCarryover: Int
    /// Cumulative gross skins per player (playerID → count).
    var grossSkinsTotal: [String: Int]
    /// Cumulative net skins per player (playerID → count).
    var netSkinsTotal: [String: Int]
    /// Full audit log across all scored holes.
    var auditLog: [String]
}

// MARK: - Engine

struct SkinsEngine {
    private(set) var grossCarryover: Int = 0
    private(set) var netCarryover: Int = 0
    private(set) var grossSkinsTotal: [String: Int] = [:]
    private(set) var netSkinsTotal: [String: Int] = [:]
    private(set) var auditLog: [String] = []

    mutating func scoreHole(_ input: SkinsHoleInput) throws -> SkinsHoleOutput {
        guard (1...18).contains(input.holeNumber) else {
            throw SkinsActionError.holeOutOfRange
        }
        guard input.scores.count >= 2 else {
            throw SkinsActionError.notEnoughPlayers
        }
        let ids = input.scores.map { $0.playerID }
        guard Set(ids).count == ids.count else {
            throw SkinsActionError.duplicatePlayerID
        }

        // Ensure every player has an entry in the running totals.
        for score in input.scores {
            if grossSkinsTotal[score.playerID] == nil { grossSkinsTotal[score.playerID] = 0 }
            if netSkinsTotal[score.playerID] == nil { netSkinsTotal[score.playerID] = 0 }
        }

        var holeAudit: [String] = ["Hole \(input.holeNumber)"]

        // --- Gross track ---
        let grossResult: SkinsHoleResult
        if input.mode == .net {
            grossResult = SkinsHoleResult(winnerID: nil, skinsAwarded: 0, isTie: false)
        } else {
            let grossPairs = input.scores.map { ($0.playerID, $0.gross) }
            grossResult = evaluate(scores: grossPairs, carryover: grossCarryover,
                                   carryoverEnabled: input.carryoverEnabled)
            if let winner = grossResult.winnerID {
                grossSkinsTotal[winner, default: 0] += grossResult.skinsAwarded
                grossCarryover = 0
                holeAudit.append("Gross: \(winner) wins \(grossResult.skinsAwarded) skin(s)")
            } else if grossResult.isTie {
                if input.carryoverEnabled {
                    grossCarryover += 1
                    holeAudit.append("Gross: tie · carryover now \(grossCarryover)")
                } else {
                    holeAudit.append("Gross: tie · skin void")
                }
            }
        }

        // --- Net track ---
        let netResult: SkinsHoleResult
        if input.mode == .gross {
            netResult = SkinsHoleResult(winnerID: nil, skinsAwarded: 0, isTie: false)
        } else {
            let netPairs = input.scores.map { ($0.playerID, $0.gross - $0.handicapStrokes) }
            netResult = evaluate(scores: netPairs, carryover: netCarryover,
                                 carryoverEnabled: input.carryoverEnabled)
            if let winner = netResult.winnerID {
                netSkinsTotal[winner, default: 0] += netResult.skinsAwarded
                netCarryover = 0
                holeAudit.append("Net: \(winner) wins \(netResult.skinsAwarded) skin(s)")
            } else if netResult.isTie {
                if input.carryoverEnabled {
                    netCarryover += 1
                    holeAudit.append("Net: tie · carryover now \(netCarryover)")
                } else {
                    holeAudit.append("Net: tie · skin void")
                }
            }
        }

        auditLog.append(contentsOf: holeAudit)

        return SkinsHoleOutput(
            holeNumber: input.holeNumber,
            grossResult: grossResult,
            netResult: netResult,
            grossCarryover: grossCarryover,
            netCarryover: netCarryover,
            grossSkinsTotal: grossSkinsTotal,
            netSkinsTotal: netSkinsTotal,
            auditLog: auditLog
        )
    }

    // MARK: - Private helpers

    /// Determines the outright winner for a set of (playerID, score) pairs.
    /// Returns a result with `winnerID` set when exactly one player has the lowest score,
    /// or `isTie = true` when multiple players share the lowest score.
    private func evaluate(
        scores: [(String, Int)],
        carryover: Int,
        carryoverEnabled: Bool
    ) -> SkinsHoleResult {
        guard let minimum = scores.map({ $0.1 }).min() else {
            return SkinsHoleResult(winnerID: nil, skinsAwarded: 0, isTie: false)
        }
        let winners = scores.filter { $0.1 == minimum }
        if winners.count == 1 {
            return SkinsHoleResult(winnerID: winners[0].0,
                                   skinsAwarded: 1 + carryover,
                                   isTie: false)
        } else {
            return SkinsHoleResult(winnerID: nil, skinsAwarded: 0, isTie: true)
        }
    }
}
