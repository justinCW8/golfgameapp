import Foundation
import Combine

@MainActor
final class NassauScoringViewModel: ObservableObject {

    // MARK: - Published State

    @Published var playerGrossInputs: [String: String] = [:]     // playerID -> gross text
    @Published var holeHistory: [NassauHoleOutput] = []
    @Published var hasScoredCurrentHole = false
    @Published var isComplete = false
    @Published var pendingAutoPress: TeamSide? = nil             // Banner shown after auto-press fires
    @Published var pendingManualPress: Bool = false              // User toggled manual press for this hole
    @Published var errorMessage: String? = nil
    @Published var showSettlement = false

    // MARK: - Private

    private let sessionStore: SessionModel
    private var engine = NassauEngine()
    private var holeInputs: [NassauHoleInput] = []
    private var holeResults: [NassauHoleResult] = []

    // MARK: - Init

    init(sessionStore: SessionModel) {
        self.sessionStore = sessionStore
        restoreFromSession()
    }

    // MARK: - Session Accessors

    var nassauSession: NassauSession? { sessionStore.activeNassauSession }

    var players: [PlayerSnapshot] { nassauSession?.players ?? [] }

    var format: NassauFormat { nassauSession?.format ?? .fourball }

    var currentHole: Int { nassauSession?.currentHole ?? 1 }

    var holes: [CourseHoleStub] { nassauSession?.holes ?? [] }

    var pressConfig: NassauPressConfig { nassauSession?.pressConfig ?? .default }

    var currentHoleConfig: CourseHoleStub? {
        holes.first(where: { $0.number == currentHole })
    }

    var courseName: String { nassauSession?.courseName ?? "" }

    var pairings: [TeamPairing] { nassauSession?.pairings ?? [] }

    // MARK: - Team Helpers

    func teamPlayerIDs(for team: TeamSide) -> [String] {
        pairings.first(where: { $0.team == team })?.players.map(\.id) ?? []
    }

    func teamName(for team: TeamSide) -> String {
        let ids = teamPlayerIDs(for: team)
        let names = players.filter { ids.contains($0.id) }.map { $0.name.components(separatedBy: " ").first ?? $0.name }
        return names.isEmpty ? (team == .teamA ? "Side A" : "Side B") : names.joined(separator: "/")
    }

    func sideLabel(for team: TeamSide) -> String {
        format == .singles
            ? (team == .teamA ? "Player A" : "Player B")
            : teamName(for: team)
    }

    /// For singles, player[0] = side A, player[1] = side B.
    /// For fourball, sides determined by pairings.
    func sideFor(playerID: String) -> TeamSide? {
        if format == .singles {
            guard let idx = players.firstIndex(where: { $0.id == playerID }) else { return nil }
            return idx == 0 ? .teamA : .teamB
        }
        if teamPlayerIDs(for: .teamA).contains(playerID) { return .teamA }
        if teamPlayerIDs(for: .teamB).contains(playerID) { return .teamB }
        return nil
    }

    // MARK: - Handicap (Difference Method)

    var minCourseHandicap: Int {
        let chs = players.map { Int($0.handicapIndex.rounded(.down)) }
        return chs.min() ?? 0
    }

    func adjustedStrokes(for player: PlayerSnapshot, onHole hole: CourseHoleStub) -> Int {
        let playerCH = Int(player.handicapIndex.rounded(.down))
        let adjustedCH = max(0, playerCH - minCourseHandicap)
        return strokeCountForHandicapIndex(Double(adjustedCH), onHoleStrokeIndex: hole.strokeIndex)
    }

    func netScore(for player: PlayerSnapshot, gross: Int, onHole hole: CourseHoleStub) -> Int {
        gross - adjustedStrokes(for: player, onHole: hole)
    }

    // MARK: - canScore

    var canScore: Bool {
        guard !isComplete, !hasScoredCurrentHole else { return false }
        return players.allSatisfy { player in
            let text = (playerGrossInputs[player.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(text) != nil
        }
    }

    // MARK: - canManualPress

    var canManualPress: Bool {
        guard pressConfig.manualPressEnabled else { return false }
        guard !hasScoredCurrentHole else { return false }
        let isFront = currentHole <= 9
        let activeLedger = isFront ? engine.front : engine.back
        guard !activeLedger.isClosed else { return false }
        if let limit = pressConfig.maxPressesPerSegment,
           activeLedger.totalPressesTriggered >= limit { return false }
        // Must have someone trailing (can only press when behind)
        return activeLedger.aUp != 0
    }

    var trailingSideLabel: String {
        let isFront = currentHole <= 9
        let ledger = isFront ? engine.front : engine.back
        if ledger.aUp > 0 { return sideLabel(for: .teamB) }
        if ledger.aUp < 0 { return sideLabel(for: .teamA) }
        return ""
    }

    // MARK: - Match Status

    var lastOutput: NassauHoleOutput? { holeHistory.last }

    var frontStatus: NassauMatchStatus {
        lastOutput?.frontStatus ?? engine.front.matchStatus()
    }
    var backStatus: NassauMatchStatus {
        lastOutput?.backStatus ?? engine.back.matchStatus()
    }
    var overallStatus: NassauMatchStatus {
        lastOutput?.overallStatus ?? engine.overall.matchStatus()
    }

    // MARK: - Net Preview

    func netPreview(for player: PlayerSnapshot) -> String {
        guard let hole = currentHoleConfig else { return "—" }
        let text = (playerGrossInputs[player.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gross = Int(text) else { return "—" }
        let net = netScore(for: player, gross: gross, onHole: hole)
        let strokes = adjustedStrokes(for: player, onHole: hole)
        return strokes > 0 ? "Net \(net) (\(strokes)↓)" : "Net \(net)"
    }

    func strokeDots(for player: PlayerSnapshot) -> Int {
        guard let hole = currentHoleConfig else { return 0 }
        return adjustedStrokes(for: player, onHole: hole)
    }

    // MARK: - Scoring

    func scoreCurrentHole() {
        guard let hole = currentHoleConfig else { return }
        guard canScore else { return }

        var sideANets: [Int] = []
        var sideBNets: [Int] = []
        var grossByID: [String: Int] = [:]
        var netByID: [String: Int] = [:]

        for player in players {
            let text = (playerGrossInputs[player.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let gross = Int(text) else { return }
            let net = netScore(for: player, gross: gross, onHole: hole)
            grossByID[player.id] = gross
            netByID[player.id] = net

            if let side = sideFor(playerID: player.id) {
                if side == .teamA { sideANets.append(net) }
                else { sideBNets.append(net) }
            }
        }

        let pressBy: TeamSide? = pendingManualPress ? trailingTeamForCurrentSegment() : nil

        let input = NassauHoleInput(
            holeNumber: currentHole,
            par: hole.par,
            sideANetScores: sideANets,
            sideBNetScores: sideBNets,
            manualPressBy: pressBy
        )

        do {
            let output = try engine.scoreHole(input, config: pressConfig)
            holeInputs.append(input)
            holeHistory.append(output)
            holeResults.append(NassauHoleResult(
                holeNumber: currentHole,
                grossByPlayerID: grossByID,
                netByPlayerID: netByID,
                holeWinner: output.holeWinner
            ))
            pendingAutoPress = output.autoPressTriggeredFor
            hasScoredCurrentHole = true
            pendingManualPress = false
            errorMessage = nil
            if currentHole >= 18 { isComplete = true }
            persistState()
        } catch {
            errorMessage = "Scoring error: \(error)"
        }
    }

    func goToNextHole() {
        guard hasScoredCurrentHole, currentHole < 18 else { return }
        hasScoredCurrentHole = false
        playerGrossInputs = [:]
        // pendingAutoPress stays visible for 1 hole then clears
        pendingAutoPress = nil
        persistState(advancingToHole: currentHole + 1)
    }

    func rescoreCurrentHole() {
        guard hasScoredCurrentHole, !holeInputs.isEmpty else { return }
        // Restore gross inputs from the results just scored
        if let lastResult = holeResults.last {
            for (playerID, gross) in lastResult.grossByPlayerID {
                playerGrossInputs[playerID] = String(gross)
            }
        }
        // Remove last scored entries
        holeInputs.removeLast()
        holeHistory.removeLast()
        holeResults.removeLast()
        hasScoredCurrentHole = false
        isComplete = false
        pendingAutoPress = nil
        pendingManualPress = false

        // Rebuild engine by replaying all previous inputs
        rebuildEngine()
        persistState()
    }

    func endRound() {
        isComplete = true
        showSettlement = true
        persistState()
    }

    func clearSession() {
        sessionStore.clearActiveNassauSession()
    }

    // MARK: - Settlement

    func settlement() -> NassauSettlement {
        engine.settlement()
    }

    func settlementSideLabel(for team: TeamSide) -> String {
        sideLabel(for: team)
    }

    // MARK: - Engine Replay

    private func rebuildEngine() {
        var rebuilt = NassauEngine()
        for input in holeInputs {
            _ = try? rebuilt.scoreHole(input, config: pressConfig)
        }
        engine = rebuilt
    }

    // MARK: - Persistence

    private func persistState(advancingToHole nextHole: Int? = nil) {
        let hole = nextHole ?? currentHole
        sessionStore.updateActiveNassauState(
            currentHole: hole,
            isComplete: isComplete,
            holeInputs: holeInputs,
            holeResults: holeResults
        )
    }

    private func restoreFromSession() {
        guard let session = nassauSession else { return }
        holeInputs = session.holeInputs
        holeResults = session.holeResults
        isComplete = session.isComplete
        // Single replay loop: rebuild engine AND capture outputs for display
        var rebuilt = NassauEngine()
        for input in holeInputs {
            if let output = try? rebuilt.scoreHole(input, config: session.pressConfig) {
                holeHistory.append(output)
            }
        }
        engine = rebuilt
        hasScoredCurrentHole = session.isCurrentHoleScored
    }

    // MARK: - Helpers

    private func trailingTeamForCurrentSegment() -> TeamSide? {
        let isFront = currentHole <= 9
        let ledger = isFront ? engine.front : engine.back
        if ledger.aUp > 0 { return .teamB }
        if ledger.aUp < 0 { return .teamA }
        return nil
    }

    enum Segment { case front, back }

    func isCurrentSegment(_ segment: Segment) -> Bool {
        switch segment {
        case .front: return currentHole <= 9
        case .back: return currentHole > 9
        }
    }

    func lastHolePlayerScores(for player: PlayerSnapshot) -> String? {
        guard let lastResult = holeResults.last else { return nil }
        guard let gross = lastResult.grossByPlayerID[player.id],
              let net = lastResult.netByPlayerID[player.id] else { return nil }
        return "Gross \(gross) · Net \(net)"
    }

    var totalGrossByPlayerID: [String: Int] {
        var totals: [String: Int] = [:]
        for result in holeResults {
            for (id, gross) in result.grossByPlayerID {
                totals[id, default: 0] += gross
            }
        }
        return totals
    }

    var totalNetByPlayerID: [String: Int] {
        var totals: [String: Int] = [:]
        for result in holeResults {
            for (id, net) in result.netByPlayerID {
                totals[id, default: 0] += net
            }
        }
        return totals
    }
}

private extension NassauSession {
    var isCurrentHoleScored: Bool {
        holeInputs.last?.holeNumber == currentHole - 1
    }
}
