import SwiftUI
import Combine

// MARK: - Live Game State (derived from replaying entries through engines)

struct ScotchLiveState {
    var frontNineA: Int = 0
    var frontNineB: Int = 0
    var backNineA: Int = 0
    var backNineB: Int = 0
    var totalA: Int { frontNineA + backNineA }
    var totalB: Int { frontNineB + backNineB }
    var lastOutput: SixPointScotchHoleOutput?

    var pillText: String {
        let diff = totalA - totalB
        if diff == 0 { return "AS" }
        let leader = diff > 0 ? "A" : "B"
        return "\(leader) +\(abs(diff))"
    }
}

struct NassauLiveState {
    var frontStatus: NassauMatchStatus = NassauMatchStatus(leadingTeam: nil, holesUp: 0, isClosed: false, closedDescription: nil, pressStatuses: [])
    var backStatus: NassauMatchStatus = NassauMatchStatus(leadingTeam: nil, holesUp: 0, isClosed: false, closedDescription: nil, pressStatuses: [])
    var overallStatus: NassauMatchStatus = NassauMatchStatus(leadingTeam: nil, holesUp: 0, isClosed: false, closedDescription: nil, pressStatuses: [])

    var pillText: String { overallStatus.displayString }
}

struct StablefordLiveState {
    var pointsByPlayerID: [String: Int] = [:]

    var pillText: String {
        guard let top = pointsByPlayerID.max(by: { $0.value < $1.value }) else { return "—" }
        return "+\(top.value)"
    }
}

struct SkinsLiveState {
    var grossSkinsTotal: [String: Int] = [:]
    var netSkinsTotal: [String: Int] = [:]
    var grossCarryover: Int = 0
    var netCarryover: Int = 0
    var lastOutput: SkinsHoleOutput?

    var pillText: String {
        let totals = grossSkinsTotal.isEmpty ? netSkinsTotal : grossSkinsTotal
        guard let top = totals.max(by: { $0.value < $1.value }), top.value > 0 else { return "—" }
        return "\(top.value) skin\(top.value == 1 ? "" : "s")"
    }
}

struct StrokePlayLiveState {
    var leaderboard: [StrokePlayStanding] = []
    var grossTotalByPlayer: [String: Int] = [:]
    var netTotalByPlayer: [String: Int] = [:]
    var vsParByPlayer: [String: Int] = [:]
    var lastOutput: StrokePlayHoleOutput?
    
    // Best Ball fields
    var teamLeaderboard: [BestBallTeamStanding] = []
    var config: StrokePlayGameConfig?
    var teamDisplayNameByID: [String: String] = [:]

    var pillText: String {
        // For team best ball (single team), show team vs par
        if let cfg = config, cfg.format == .teamBestBall,
           let teamStanding = teamLeaderboard.first {
            let vsPar = teamStanding.vsPar
            if vsPar == 0 { return "E" }
            return vsPar > 0 ? "+\(vsPar)" : "\(vsPar)"
        }
        
        // For 2v2 best ball, show team leader with separator for clarity
        if let cfg = config, cfg.format == .bestBall2v2,
           let teamLeader = teamLeaderboard.first(where: { $0.rank == 1 }) {
            let vsPar = teamLeader.vsPar
            let vsParStr = vsPar == 0 ? "E" : (vsPar > 0 ? "+\(vsPar)" : "\(vsPar)")
            return "\(teamLeader.teamName) · \(vsParStr)"
        }
        
        // For individual, show individual leader
        guard let leader = leaderboard.first(where: { $0.rank == 1 }) else { return "—" }
        let vsPar = leader.vsPar
        if vsPar == 0 { return "E" }
        return vsPar > 0 ? "+\(vsPar)" : "\(vsPar)"
    }
}

// MARK: - ViewModel

@MainActor
final class SaturdayScoringViewModel: ObservableObject {

    @Published var round: SaturdayRound

    // Current hole gross inputs (player ID → gross string)
    @Published var grossInputs: [String: String] = [:]

    // Scotch flags for current hole
    @Published var proxWinnerID: String? = nil          // player ID closest to pin (GIR required)
    @Published var scotchPressBy: TeamSide? = nil
    @Published var scotchRollBy: TeamSide? = nil
    @Published var scotchRerollBy: TeamSide? = nil
    @Published var nassauManualPressBy: TeamSide? = nil

    // Expanded game strip pill
    @Published var expandedGame: GameType? = nil

    // Derived live states (recomputed when entries change)
    @Published var scotchState = ScotchLiveState()
    @Published var nassauState = NassauLiveState()
    @Published var stablefordState = StablefordLiveState()
    @Published var skinsState = SkinsLiveState()
    @Published var strokePlayState = StrokePlayLiveState()

    // Replayed engine for press/roll state queries
    private var replayedScotchEngine: SixPointScotchEngine?

    private let store: AppSessionStore

    init(round: SaturdayRound, store: AppSessionStore) {
        self.round = round
        self.store = store
        replayEngines()
        resetInputsForCurrentHole()
    }

    var currentHole: Int { round.currentHole }
    var isComplete: Bool { round.isComplete }

    var currentHoleStub: CourseHoleStub? {
        round.holes.first(where: { $0.number == round.currentHole })
    }

    var canScoreHole: Bool {
        round.players.allSatisfy { player in
            if let raw = grossInputs[player.id], let val = Int(raw), val > 0 { return true }
            return false
        }
    }

    // MARK: - Scoring

    func scoreHole() {
        guard canScoreHole, let stub = currentHoleStub else { return }

        var grossByPlayerID: [String: Int] = [:]
        for player in round.players {
            if let raw = grossInputs[player.id], let val = Int(raw) {
                grossByPlayerID[player.id] = val
            }
        }

        // Build scotch flags
        var proxFeetByPlayerID: [String: Double] = [:]
        if let winnerID = proxWinnerID {
            proxFeetByPlayerID[winnerID] = 1.0
        }
        let scotchFlags = ScotchHoleFlags(
            proxFeetByPlayerID: proxFeetByPlayerID,
            requestPressBy: scotchPressBy,
            requestRollBy: scotchRollBy,
            requestRerollBy: scotchRerollBy
        )

        let entry = SaturdayHoleEntry(
            holeNumber: stub.number,
            grossByPlayerID: grossByPlayerID,
            scotchFlags: scotchFlags,
            nassauManualPressBy: nassauManualPressBy
        )

        // Replace or append
        if let idx = round.holeEntries.firstIndex(where: { $0.holeNumber == stub.number }) {
            round.holeEntries[idx] = entry
        } else {
            round.holeEntries.append(entry)
        }

        // Advance hole
        if round.currentHole < 18 {
            round.currentHole += 1
        } else {
            round.isComplete = true
        }

        store.updateSaturdayRound(round)
        replayEngines()
        resetInputsForCurrentHole()
    }

    func editPreviousHole() {
        guard round.currentHole > 1 || round.isComplete else { return }
        if round.isComplete {
            round.isComplete = false
        } else {
            round.currentHole -= 1
        }
        round.holeEntries.removeAll { $0.holeNumber == round.currentHole }
        store.updateSaturdayRound(round)
        replayEngines()
        resetInputsForCurrentHole()
    }

    func autofillRemainingHolesForTesting() {
        guard !round.isComplete else { return }
        guard round.currentHole >= 1, round.currentHole <= 18 else { return }

        for holeNumber in round.currentHole...18 {
            guard let stub = round.holes.first(where: { $0.number == holeNumber }) else { continue }
            var grossByPlayerID: [String: Int] = [:]
            for player in round.players {
                let handicapStrokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                let adjustment = Int.random(in: -1...2)
                let gross = max(1, stub.par + handicapStrokes + adjustment)
                grossByPlayerID[player.id] = gross
            }

            let entry = SaturdayHoleEntry(
                holeNumber: holeNumber,
                grossByPlayerID: grossByPlayerID,
                scotchFlags: ScotchHoleFlags(proxFeetByPlayerID: [:], requestPressBy: nil, requestRollBy: nil, requestRerollBy: nil),
                nassauManualPressBy: nil
            )

            if let existingIndex = round.holeEntries.firstIndex(where: { $0.holeNumber == holeNumber }) {
                round.holeEntries[existingIndex] = entry
            } else {
                round.holeEntries.append(entry)
            }
        }

        round.currentHole = 18
        round.isComplete = true
        store.updateSaturdayRound(round)
        replayEngines()
        resetInputsForCurrentHole()
    }

    // MARK: - Engine Replay

    func replayEngines() {
        let entries = round.holeEntries.sorted { $0.holeNumber < $1.holeNumber }

        // Scotch replay
        if round.activeGames.contains(where: { $0.type == .sixPointScotch }) {
            var engine = SixPointScotchEngine()
            var state = ScotchLiveState()
            let teamAIDs = round.teamAPlayers.map(\.id)
            let teamBIDs = round.teamBPlayers.map(\.id)

            for entry in entries {
                guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
                let teamANet = round.teamAPlayers.map { player -> Int in
                    let gross = entry.grossByPlayerID[player.id] ?? (stub.par + 2)
                    let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                    return gross - strokes
                }
                let teamBNet = round.teamBPlayers.map { player -> Int in
                    let gross = entry.grossByPlayerID[player.id] ?? (stub.par + 2)
                    let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                    return gross - strokes
                }
                let teamAGross = teamAIDs.compactMap { entry.grossByPlayerID[$0] }
                let teamBGross = teamBIDs.compactMap { entry.grossByPlayerID[$0] }

                let teamAProx = round.teamAPlayers.compactMap { entry.scotchFlags.proxFeetByPlayerID[$0.id] }.min()
                let teamBProx = round.teamBPlayers.compactMap { entry.scotchFlags.proxFeetByPlayerID[$0.id] }.min()

                let input = SixPointScotchHoleInput(
                    holeNumber: entry.holeNumber,
                    par: stub.par,
                    teamANetScores: teamANet,
                    teamBNetScores: teamBNet,
                    teamAGrossScores: teamAGross,
                    teamBGrossScores: teamBGross,
                    teamAProxFeet: teamAProx,
                    teamBProxFeet: teamBProx,
                    requestPressBy: entry.scotchFlags.requestPressBy,
                    requestRollBy: entry.scotchFlags.requestRollBy,
                    requestRerollBy: entry.scotchFlags.requestRerollBy
                )
                if let output = try? engine.scoreHole(input) {
                    state.frontNineA = output.frontNineTeamA
                    state.frontNineB = output.frontNineTeamB
                    state.backNineA = output.backNineTeamA
                    state.backNineB = output.backNineTeamB
                    state.lastOutput = output
                }
            }
            scotchState = state
            replayedScotchEngine = engine
        }

        // Nassau replay
        if let nassauGame = round.activeGames.first(where: { $0.type == .nassau }),
           let nassauConfig = nassauGame.nassauConfig {
            var engine = NassauEngine()
            var state = NassauLiveState()
            let format = nassauConfig.format

            for entry in entries {
                guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }

                let sideANet: [Int]
                let sideBNet: [Int]

                if format == .fourball {
                    sideANet = round.teamAPlayers.map { player -> Int in
                        let gross = entry.grossByPlayerID[player.id] ?? (stub.par + 2)
                        let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                        return gross - strokes
                    }
                    sideBNet = round.teamBPlayers.map { player -> Int in
                        let gross = entry.grossByPlayerID[player.id] ?? (stub.par + 2)
                        let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                        return gross - strokes
                    }
                } else {
                    // Singles: first two players
                    let p1 = round.players.first
                    let p2 = round.players.dropFirst().first
                    sideANet = [p1].compactMap { p -> Int? in
                        guard let p else { return nil }
                        let gross = entry.grossByPlayerID[p.id] ?? (stub.par + 2)
                        let strokes = strokeCountForHandicapIndex(p.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                        return gross - strokes
                    }
                    sideBNet = [p2].compactMap { p -> Int? in
                        guard let p else { return nil }
                        let gross = entry.grossByPlayerID[p.id] ?? (stub.par + 2)
                        let strokes = strokeCountForHandicapIndex(p.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                        return gross - strokes
                    }
                }

                let nassauInput = NassauHoleInput(
                    holeNumber: entry.holeNumber,
                    par: stub.par,
                    sideANetScores: sideANet,
                    sideBNetScores: sideBNet,
                    manualPressBy: entry.nassauManualPressBy
                )
                if let output = try? engine.scoreHole(nassauInput, config: nassauConfig.pressConfig) {
                    state.frontStatus = output.frontStatus
                    state.backStatus = output.backStatus
                    state.overallStatus = output.overallStatus
                }
            }
            nassauState = state
        }

        // Stableford replay
        if round.activeGames.contains(where: { $0.type == .stableford }) {
            var pointsByPlayerID: [String: Int] = [:]
            for player in round.players { pointsByPlayerID[player.id] = 0 }

            for entry in entries {
                guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
                for player in round.players {
                    let gross = entry.grossByPlayerID[player.id] ?? (stub.par + 2)
                    let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                    let output = StablefordEngine.scoreHole(StablefordHoleScoreInput(gross: gross, par: stub.par, handicapStrokes: strokes))
                    pointsByPlayerID[player.id, default: 0] += output.points
                }
            }
            stablefordState = StablefordLiveState(pointsByPlayerID: pointsByPlayerID)
        }

        // Skins replay
        if let skinsGame = round.activeGames.first(where: { $0.type == .skins }),
           let skinsConfig = skinsGame.skinsConfig {
            var engine = SkinsEngine()
            var lastOutput: SkinsHoleOutput?

            for entry in entries {
                guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
                let scores = round.players.map { player -> SkinsPlayerScore in
                    let gross = entry.grossByPlayerID[player.id] ?? (stub.par + 2)
                    let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                    return SkinsPlayerScore(playerID: player.id, gross: gross, handicapStrokes: strokes)
                }
                let input = SkinsHoleInput(
                    holeNumber: entry.holeNumber,
                    par: stub.par,
                    scores: scores,
                    mode: skinsConfig.mode,
                    carryoverEnabled: skinsConfig.carryoverEnabled
                )
                if let output = try? engine.scoreHole(input) {
                    lastOutput = output
                }
            }
            skinsState = SkinsLiveState(
                grossSkinsTotal: lastOutput?.grossSkinsTotal ?? [:],
                netSkinsTotal: lastOutput?.netSkinsTotal ?? [:],
                grossCarryover: lastOutput?.grossCarryover ?? 0,
                netCarryover: lastOutput?.netCarryover ?? 0,
                lastOutput: lastOutput
            )
        }

        // Stroke play replay
        if let strokePlayGame = round.activeGames.first(where: { $0.type == .strokePlay }) {
            let config = strokePlayGame.strokePlayConfig ?? StrokePlayGameConfig()
            let engineConfig = StrokePlayEngineConfig(
                format: config.format,
                pairings: config.bestBallPairings
            )
            var engine = StrokePlayEngine(config: engineConfig)
            var lastOutput: StrokePlayHoleOutput?

            for entry in entries {
                guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
                let scores = round.players.map { player -> StrokePlayPlayerScore in
                    let gross = entry.grossByPlayerID[player.id] ?? stub.par
                    let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                    return StrokePlayPlayerScore(playerID: player.id, gross: gross, handicapStrokes: strokes)
                }
                let input = StrokePlayHoleInput(holeNumber: entry.holeNumber, par: stub.par, scores: scores)
                if let output = try? engine.scoreHole(input) {
                    lastOutput = output
                }
            }
            strokePlayState = StrokePlayLiveState(
                leaderboard: lastOutput?.leaderboard ?? [],
                grossTotalByPlayer: lastOutput?.grossTotalByPlayer ?? [:],
                netTotalByPlayer: lastOutput?.netTotalByPlayer ?? [:],
                vsParByPlayer: lastOutput?.vsParByPlayer ?? [:],
                lastOutput: lastOutput,
                teamLeaderboard: lastOutput?.bestBallTeamStandings ?? [],
                config: config,
                teamDisplayNameByID: strokePlayTeamDisplayNames(for: config)
            )
        }
    }

    // MARK: - Helpers

    private func resetInputsForCurrentHole() {
        grossInputs = [:]
        proxWinnerID = nil
        scotchPressBy = nil
        scotchRollBy = nil
        scotchRerollBy = nil
        nassauManualPressBy = nil
    }

    func netScore(for player: PlayerSnapshot, gross: Int, hole: CourseHoleStub) -> Int {
        let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: hole.strokeIndex)
        return gross - strokes
    }

    func handicapStrokes(for player: PlayerSnapshot, on hole: CourseHoleStub) -> Int {
        strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: hole.strokeIndex)
    }

    func playerName(for id: String) -> String {
        round.players.first(where: { $0.id == id })?.name ?? id
    }

    private func strokePlayTeamDisplayNames(for config: StrokePlayGameConfig) -> [String: String] {
        let playersByID = Dictionary(uniqueKeysWithValues: round.players.map { ($0.id, $0) })

        return Dictionary(uniqueKeysWithValues: config.bestBallPairings.map { pairing in
            let memberNames = pairing.playerIDs.compactMap { playersByID[$0]?.name }
            let memberInitials = memberNames.map(teamMemberInitials(from:))
            let displayName = memberInitials.isEmpty ? pairing.teamName : memberInitials.joined(separator: "/")
            return (pairing.id, displayName)
        })
    }

    private func teamMemberInitials(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }

        let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
        if parts.count > 1 {
            return parts.compactMap(\.first).map(String.init).joined().uppercased()
        }

        if trimmed.count <= 3 {
            return trimmed.uppercased()
        }

        return String(trimmed.prefix(1)).uppercased()
    }

    // MARK: - Scotch Press/Roll State

    private var currentNineLedger: NineLedger? {
        guard let engine = replayedScotchEngine else { return nil }
        return round.currentHole <= 9 ? engine.frontNine : engine.backNine
    }

    var scotchTrailingTeam: TeamSide? {
        guard let ledger = currentNineLedger else { return nil }
        if ledger.teamAPoints == ledger.teamBPoints { return nil }
        return ledger.teamAPoints < ledger.teamBPoints ? .teamA : .teamB
    }

    var scotchLeadingTeam: TeamSide? {
        guard let ledger = currentNineLedger else { return nil }
        if ledger.teamAPoints == ledger.teamBPoints { return nil }
        return ledger.teamAPoints > ledger.teamBPoints ? .teamA : .teamB
    }

    var scotchPressesRemaining: Int {
        max(0, 2 - (currentNineLedger?.usedPresses ?? 0))
    }

    var canScotchPress: Bool {
        scotchTrailingTeam != nil && scotchPressesRemaining > 0
    }

    var projectedScotchMultiplier: Int {
        let existing = currentNineLedger?.activePresses ?? 0
        let p = scotchPressBy != nil ? 1 : 0
        let r = scotchRollBy != nil ? 1 : 0
        let rr = scotchRerollBy != nil ? 1 : 0
        return Int(pow(2.0, Double(existing + p + r + rr)))
    }

    var isScotchActive: Bool {
        round.activeGames.contains(where: { $0.type == .sixPointScotch })
    }

    var isSkinsActive: Bool {
        round.activeGames.contains(where: { $0.type == .skins })
    }

    // MARK: - Nassau Press State

    var isNassauActive: Bool {
        round.activeGames.contains(where: { $0.type == .nassau })
    }

    /// The team currently trailing in the active segment (front or back), or nil if level/segment closed.
    var nassauTrailingTeam: TeamSide? {
        guard !nassauState.overallStatus.isClosed else { return nil }
        let segStatus = currentHole <= 9 ? nassauState.frontStatus : nassauState.backStatus
        guard !segStatus.isClosed else { return nil }
        guard let leader = segStatus.leadingTeam else { return nil }
        return leader == .teamA ? .teamB : .teamA
    }

    /// True when a manual Nassau press is legal: game active, match not level, not on last hole of segment, round not done.
    var canNassauPress: Bool {
        guard isNassauActive, !isComplete else { return false }
        guard nassauTrailingTeam != nil else { return false }
        // No press on the final hole of a segment — nothing left to run the new bet
        let lastHole = round.holes.count   // e.g. 18 for a full round
        let isFinalFront = currentHole == 9
        let isFinalBack  = currentHole == lastHole
        return !isFinalFront && !isFinalBack
    }
}
