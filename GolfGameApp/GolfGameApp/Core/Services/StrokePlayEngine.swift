import Foundation

// MARK: - Errors

enum StrokePlayActionError: Error, Equatable {
    case holeOutOfRange
    case duplicatePlayerID
}

// MARK: - Input / Output

struct StrokePlayPlayerScore {
    var playerID: String
    var gross: Int
    /// Handicap strokes received on this hole (0 for gross-only tracking).
    var handicapStrokes: Int
}

struct StrokePlayHoleInput {
    var holeNumber: Int          // 1...18
    var par: Int
    var scores: [StrokePlayPlayerScore]
}

struct StrokePlayStanding {
    var playerID: String
    var grossTotal: Int
    var netTotal: Int
    /// Net total minus cumulative par of holes scored. Negative = under par.
    var vsPar: Int
    /// 1-based rank. Tied players share the same rank.
    var rank: Int
}

struct StrokePlayHoleOutput {
    var holeNumber: Int
    /// Running gross totals per player (playerID → gross strokes taken).
    var grossTotalByPlayer: [String: Int]
    /// Running net totals per player (playerID → net strokes taken).
    var netTotalByPlayer: [String: Int]
    /// Running net-vs-par per player (playerID → delta). Negative = under par.
    var vsParByPlayer: [String: Int]
    /// Leaderboard sorted by net total ascending (best score first).
    var leaderboard: [StrokePlayStanding]
    /// Full audit log across all scored holes.
    var auditLog: [String]
}

// MARK: - Engine

/// Pure stateful stroke-play engine. Tracks gross and net totals per player
/// across 18 holes and produces a ranked leaderboard after each hole.
struct StrokePlayEngine {
    private(set) var grossTotalByPlayer: [String: Int] = [:]
    private(set) var netTotalByPlayer: [String: Int] = [:]
    /// Cumulative par of all scored holes per player (for vs-par calculation).
    private(set) var parScoredByPlayer: [String: Int] = [:]
    private(set) var auditLog: [String] = []

    mutating func scoreHole(_ input: StrokePlayHoleInput) throws -> StrokePlayHoleOutput {
        guard (1...18).contains(input.holeNumber) else {
            throw StrokePlayActionError.holeOutOfRange
        }
        let ids = input.scores.map { $0.playerID }
        guard Set(ids).count == ids.count else {
            throw StrokePlayActionError.duplicatePlayerID
        }

        var holeAudit: [String] = ["Hole \(input.holeNumber)"]

        for score in input.scores {
            let net = score.gross - score.handicapStrokes
            grossTotalByPlayer[score.playerID, default: 0] += score.gross
            netTotalByPlayer[score.playerID, default: 0] += net
            parScoredByPlayer[score.playerID, default: 0] += input.par

            let runningVsPar = netTotalByPlayer[score.playerID]! - parScoredByPlayer[score.playerID]!
            let vsParStr = runningVsPar == 0 ? "E" : (runningVsPar > 0 ? "+\(runningVsPar)" : "\(runningVsPar)")
            holeAudit.append("\(score.playerID): \(score.gross) gross · \(net) net · \(vsParStr)")
        }

        auditLog.append(contentsOf: holeAudit)

        let vsParByPlayer: [String: Int] = Dictionary(
            uniqueKeysWithValues: input.scores.map { score in
                let net = netTotalByPlayer[score.playerID] ?? 0
                let par = parScoredByPlayer[score.playerID] ?? 0
                return (score.playerID, net - par)
            }
        )

        let leaderboard = buildLeaderboard(playerIDs: input.scores.map { $0.playerID })

        return StrokePlayHoleOutput(
            holeNumber: input.holeNumber,
            grossTotalByPlayer: grossTotalByPlayer,
            netTotalByPlayer: netTotalByPlayer,
            vsParByPlayer: vsParByPlayer,
            leaderboard: leaderboard,
            auditLog: auditLog
        )
    }

    // MARK: - Private helpers

    private func buildLeaderboard(playerIDs: [String]) -> [StrokePlayStanding] {
        let unsorted = playerIDs.map { id -> StrokePlayStanding in
            let gross = grossTotalByPlayer[id] ?? 0
            let net = netTotalByPlayer[id] ?? 0
            let par = parScoredByPlayer[id] ?? 0
            return StrokePlayStanding(playerID: id, grossTotal: gross, netTotal: net,
                                     vsPar: net - par, rank: 0)
        }
        let sorted = unsorted.sorted { $0.netTotal < $1.netTotal }

        var ranked: [StrokePlayStanding] = []
        for (i, standing) in sorted.enumerated() {
            // Share rank with any previously ranked player who has the same net total.
            let rank = ranked.first(where: { $0.netTotal == standing.netTotal })?.rank ?? (i + 1)
            ranked.append(StrokePlayStanding(
                playerID: standing.playerID,
                grossTotal: standing.grossTotal,
                netTotal: standing.netTotal,
                vsPar: standing.vsPar,
                rank: rank
            ))
        }
        return ranked
    }
}
