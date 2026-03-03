import Foundation

// MARK: - Configuration

enum NassauFormat: String, Codable {
    case singles   // 1v1
    case fourball  // 2v2 best ball
}

struct NassauPressConfig: Codable, Equatable {
    /// nil = auto-press disabled; 1/2/3 = trigger when a side falls behind by this many holes
    var autoPressTrigger: Int?
    /// nil = unlimited; 1 or 2 = max presses per segment
    var maxPressesPerSegment: Int?
    var manualPressEnabled: Bool

    static let `default` = NassauPressConfig(autoPressTrigger: 2, maxPressesPerSegment: nil, manualPressEnabled: true)
}

// MARK: - Engine Input / Output

struct NassauHoleInput: Codable, Equatable {
    var holeNumber: Int
    var par: Int
    /// 1 element for singles, 2 for fourball (net scores after handicap adjustment)
    var sideANetScores: [Int]
    var sideBNetScores: [Int]
    /// Manual press requested before this hole is scored (nil = no manual press)
    var manualPressBy: TeamSide?
}

struct NassauMatchStatus: Equatable {
    /// nil = All Square
    var leadingTeam: TeamSide?
    var holesUp: Int
    var isClosed: Bool
    /// e.g. "3&2" when closed early
    var closedDescription: String?
    /// Status of each active press sub-bet
    var pressStatuses: [NassauPressStatus]

    var displayString: String {
        if isClosed, let desc = closedDescription {
            let winner = leadingTeam == .teamA ? "A" : "B"
            return "\(winner) won \(desc)"
        }
        guard let leader = leadingTeam else { return "AS" }
        let name = leader == .teamA ? "A" : "B"
        return "\(name) \(holesUp)UP"
    }
}

struct NassauPressStatus: Equatable {
    var startHole: Int
    var matchStatus: NassauMatchStatus
}

struct NassauHoleOutput: Equatable {
    var holeNumber: Int
    /// nil = halved
    var holeWinner: TeamSide?
    var frontStatus: NassauMatchStatus
    var backStatus: NassauMatchStatus
    var overallStatus: NassauMatchStatus
    /// Set when an auto-press fires after this hole (takes effect next hole)
    var autoPressTriggeredFor: TeamSide?
    var auditLog: [String]
}

// MARK: - Internal Ledger Types

struct NassauSegmentLedger: Codable, Equatable {
    /// Absolute hole number that ends this segment (9 for front, 18 for back/overall)
    let segmentEndHole: Int
    /// Number of total holes in this segment (9 or 18)
    let segmentTotalHoles: Int
    /// Positive = side A leading; negative = side B leading; 0 = AS
    var aUp: Int = 0
    var holesPlayed: Int = 0
    var presses: [NassauPressLedger] = []
    /// Count of presses triggered in this segment (across manual + auto)
    var totalPressesTriggered: Int = 0

    var holesRemaining: Int { segmentTotalHoles - holesPlayed }
    var isClosed: Bool { holesPlayed > 0 && abs(aUp) > holesRemaining }
    var leadingTeam: TeamSide? { aUp > 0 ? .teamA : aUp < 0 ? .teamB : nil }
    var holesUp: Int { abs(aUp) }

    init(segmentEndHole: Int, segmentTotalHoles: Int) {
        self.segmentEndHole = segmentEndHole
        self.segmentTotalHoles = segmentTotalHoles
    }

    mutating func recordHole(winner: TeamSide?) {
        holesPlayed += 1
        switch winner {
        case .teamA: aUp += 1
        case .teamB: aUp -= 1
        case nil: break
        }
        for i in presses.indices where !presses[i].isSettled {
            presses[i].recordHole(winner: winner)
        }
    }

    mutating func addPress(startHole: Int) {
        presses.append(NassauPressLedger(startHole: startHole, parentEndHole: segmentEndHole))
        totalPressesTriggered += 1
    }

    func matchStatus() -> NassauMatchStatus {
        let closed = isClosed
        let desc: String? = closed ? "\(holesUp)&\(holesRemaining)" : nil
        let pressStatuses = presses.map { p in
            NassauPressStatus(startHole: p.startHole, matchStatus: p.matchStatus())
        }
        return NassauMatchStatus(
            leadingTeam: leadingTeam,
            holesUp: holesUp,
            isClosed: closed,
            closedDescription: desc,
            pressStatuses: pressStatuses
        )
    }
}

struct NassauPressLedger: Codable, Equatable {
    var startHole: Int
    var parentEndHole: Int
    var aUp: Int = 0
    var holesPlayed: Int = 0

    /// How many holes remain in this press bet (based on parent segment)
    var holesInPress: Int { parentEndHole - startHole + 1 }
    var holesRemaining: Int { holesInPress - holesPlayed }
    var isClosed: Bool { holesPlayed > 0 && abs(aUp) > holesRemaining }
    var isSettled: Bool { isClosed || holesRemaining == 0 }
    var leadingTeam: TeamSide? { aUp > 0 ? .teamA : aUp < 0 ? .teamB : nil }
    var holesUp: Int { abs(aUp) }

    mutating func recordHole(winner: TeamSide?) {
        holesPlayed += 1
        switch winner {
        case .teamA: aUp += 1
        case .teamB: aUp -= 1
        case nil: break
        }
    }

    func matchStatus() -> NassauMatchStatus {
        let closed = isClosed
        let desc: String? = closed ? "\(holesUp)&\(holesRemaining)" : nil
        return NassauMatchStatus(
            leadingTeam: leadingTeam,
            holesUp: holesUp,
            isClosed: closed,
            closedDescription: desc,
            pressStatuses: []
        )
    }
}

// MARK: - Engine Errors

enum NassauEngineError: Error, Equatable {
    case holeOutOfRange
    case invalidNetScoreCount
    case manualPressLimitReached
    case manualPressDisabled
    case manualPressRequiresTrailingTeam
}

// MARK: - NassauEngine

struct NassauEngine {
    private(set) var front = NassauSegmentLedger(segmentEndHole: 9, segmentTotalHoles: 9)
    private(set) var back = NassauSegmentLedger(segmentEndHole: 18, segmentTotalHoles: 9)
    private(set) var overall = NassauSegmentLedger(segmentEndHole: 18, segmentTotalHoles: 18)
    private(set) var auditLog: [String] = []

    mutating func scoreHole(
        _ input: NassauHoleInput,
        config: NassauPressConfig
    ) throws -> NassauHoleOutput {
        guard (1...18).contains(input.holeNumber) else {
            throw NassauEngineError.holeOutOfRange
        }

        let isFront = input.holeNumber <= 9
        let expectedCount = input.sideANetScores.count
        guard expectedCount >= 1,
              input.sideBNetScores.count == expectedCount else {
            throw NassauEngineError.invalidNetScoreCount
        }

        var holeAudit: [String] = ["Hole \(input.holeNumber)"]

        // --- Manual press (fires BEFORE this hole is scored) ---
        if let pressTeam = input.manualPressBy {
            guard config.manualPressEnabled else {
                throw NassauEngineError.manualPressDisabled
            }
            let activeLedger = isFront ? front : back
            let trailingTeam = trailingTeam(in: activeLedger)
            guard trailingTeam == pressTeam else {
                throw NassauEngineError.manualPressRequiresTrailingTeam
            }
            if let limit = config.maxPressesPerSegment,
               activeLedger.totalPressesTriggered >= limit {
                throw NassauEngineError.manualPressLimitReached
            }
            let pressName = pressTeam == .teamA ? "A" : "B"
            holeAudit.append("Manual press by side \(pressName) starting hole \(input.holeNumber).")
            if isFront {
                front.addPress(startHole: input.holeNumber)
            } else {
                back.addPress(startHole: input.holeNumber)
            }
        }

        // --- Determine hole winner ---
        let holeWinner = determineHoleWinner(sideA: input.sideANetScores, sideB: input.sideBNetScores)
        let winnerName: String
        switch holeWinner {
        case .teamA: winnerName = "Side A"
        case .teamB: winnerName = "Side B"
        case nil: winnerName = "Halved"
        }
        holeAudit.append("Hole winner: \(winnerName)")

        // --- Update ledgers ---
        overall.recordHole(winner: holeWinner)
        if isFront {
            front.recordHole(winner: holeWinner)
        } else {
            back.recordHole(winner: holeWinner)
        }

        // --- Check for auto-press (fires for NEXT hole) ---
        var autoPressTriggeredFor: TeamSide? = nil
        if let trigger = config.autoPressTrigger, trigger > 0 {
            let activeLedger = isFront ? front : back
            let nextHoleExists = input.holeNumber < (isFront ? 9 : 18)
            if nextHoleExists, !activeLedger.isClosed {
                // Check if the trailing team just hit the trigger threshold
                let trailingAUp = isFront ? front.aUp : back.aUp
                let trailingTeam: TeamSide?
                if trailingAUp < 0 && abs(trailingAUp) == trigger {
                    trailingTeam = .teamB
                } else if trailingAUp > 0 && trailingAUp == trigger {
                    trailingTeam = .teamA
                } else {
                    trailingTeam = nil
                }

                if let trailing = trailingTeam {
                    let withinLimit: Bool
                    if let limit = config.maxPressesPerSegment {
                        withinLimit = activeLedger.totalPressesTriggered < limit
                    } else {
                        withinLimit = true
                    }
                    if withinLimit {
                        autoPressTriggeredFor = trailing
                        let nextHole = input.holeNumber + 1
                        let name = trailing == .teamA ? "A" : "B"
                        holeAudit.append("Auto-press for side \(name) starting hole \(nextHole).")
                        if isFront {
                            front.addPress(startHole: nextHole)
                        } else {
                            back.addPress(startHole: nextHole)
                        }
                    }
                }
            }
        }

        auditLog.append(contentsOf: holeAudit)

        return NassauHoleOutput(
            holeNumber: input.holeNumber,
            holeWinner: holeWinner,
            frontStatus: front.matchStatus(),
            backStatus: back.matchStatus(),
            overallStatus: overall.matchStatus(),
            autoPressTriggeredFor: autoPressTriggeredFor,
            auditLog: holeAudit
        )
    }

    // MARK: - Private Helpers

    private func determineHoleWinner(sideA: [Int], sideB: [Int]) -> TeamSide? {
        let bestA = sideA.min() ?? Int.max
        let bestB = sideB.min() ?? Int.max
        if bestA == bestB { return nil }
        return bestA < bestB ? .teamA : .teamB
    }

    private func trailingTeam(in ledger: NassauSegmentLedger) -> TeamSide? {
        if ledger.aUp < 0 { return .teamB }
        if ledger.aUp > 0 { return .teamA }
        return nil
    }
}

// MARK: - Settlement

struct NassauSegmentResult {
    enum Outcome: Equatable {
        case sideAWon(description: String)  // e.g. "3&2"
        case sideBWon(description: String)
        case halved
    }
    var name: String     // "Front 9", "Back 9", "Overall"
    var outcome: Outcome
    /// +1 for A win, -1 for B win, 0 for halved
    var netForA: Int {
        switch outcome {
        case .sideAWon: return 1
        case .sideBWon: return -1
        case .halved: return 0
        }
    }
}

struct NassauSettlement {
    var front: NassauSegmentResult
    var back: NassauSegmentResult
    var overall: NassauSegmentResult
    var frontPresses: [NassauSegmentResult]
    var backPresses: [NassauSegmentResult]

    var totalNetForA: Int {
        let mainBets = [front, back, overall].map(\.netForA).reduce(0, +)
        let fpBets = frontPresses.map(\.netForA).reduce(0, +)
        let bpBets = backPresses.map(\.netForA).reduce(0, +)
        return mainBets + fpBets + bpBets
    }

    var totalBets: Int {
        3 + frontPresses.count + backPresses.count
    }
}

extension NassauEngine {
    func settlement() -> NassauSettlement {
        NassauSettlement(
            front: segmentResult(ledger: front, name: "Front 9"),
            back: segmentResult(ledger: back, name: "Back 9"),
            overall: segmentResult(ledger: overall, name: "Overall"),
            frontPresses: front.presses.enumerated().map { i, p in
                pressResult(ledger: p, name: "Front Press \(i + 1)")
            },
            backPresses: back.presses.enumerated().map { i, p in
                pressResult(ledger: p, name: "Back Press \(i + 1)")
            }
        )
    }

    private func segmentResult(ledger: NassauSegmentLedger, name: String) -> NassauSegmentResult {
        let outcome: NassauSegmentResult.Outcome
        if ledger.aUp > 0 {
            let desc = ledger.isClosed ? "\(ledger.holesUp)&\(ledger.holesRemaining)" : "\(ledger.holesUp)UP"
            outcome = .sideAWon(description: desc)
        } else if ledger.aUp < 0 {
            let desc = ledger.isClosed ? "\(ledger.holesUp)&\(ledger.holesRemaining)" : "\(ledger.holesUp)UP"
            outcome = .sideBWon(description: desc)
        } else {
            outcome = .halved
        }
        return NassauSegmentResult(name: name, outcome: outcome)
    }

    private func pressResult(ledger: NassauPressLedger, name: String) -> NassauSegmentResult {
        let outcome: NassauSegmentResult.Outcome
        if ledger.aUp > 0 {
            let desc = ledger.isClosed ? "\(ledger.holesUp)&\(ledger.holesRemaining)" : "\(ledger.holesUp)UP"
            outcome = .sideAWon(description: desc)
        } else if ledger.aUp < 0 {
            let desc = ledger.isClosed ? "\(ledger.holesUp)&\(ledger.holesRemaining)" : "\(ledger.holesUp)UP"
            outcome = .sideBWon(description: desc)
        } else {
            outcome = .halved
        }
        return NassauSegmentResult(name: name, outcome: outcome)
    }
}
