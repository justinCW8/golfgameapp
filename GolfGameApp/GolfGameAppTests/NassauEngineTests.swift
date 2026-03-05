import Testing
@testable import GolfGameApp

// MARK: - Helpers

private func input(hole: Int, par: Int = 4, aNet: Int, bNet: Int, press: TeamSide? = nil) -> NassauHoleInput {
    NassauHoleInput(holeNumber: hole, par: par, sideANetScores: [aNet], sideBNetScores: [bNet], manualPressBy: press)
}

private func fourballInput(hole: Int, par: Int = 4, aNets: [Int], bNets: [Int]) -> NassauHoleInput {
    NassauHoleInput(holeNumber: hole, par: par, sideANetScores: aNets, sideBNetScores: bNets, manualPressBy: nil)
}

private let noPressConfig = NassauPressConfig(autoPressTrigger: nil, maxPressesPerSegment: nil, manualPressEnabled: false)
private let defaultConfig  = NassauPressConfig.default  // autoPress=2, unlimited, manual=true

// MARK: - Hole Winner

struct NassauHoleWinnerTests {

    @Test func singlesSideAWinsLowerNet() throws {
        var engine = NassauEngine()
        let out = try engine.scoreHole(input(hole: 1, aNet: 3, bNet: 4), config: noPressConfig)
        #expect(out.holeWinner == .teamA)
    }

    @Test func singlesSideBWinsLowerNet() throws {
        var engine = NassauEngine()
        let out = try engine.scoreHole(input(hole: 1, aNet: 5, bNet: 4), config: noPressConfig)
        #expect(out.holeWinner == .teamB)
    }

    @Test func singlesHalvedEqualNet() throws {
        var engine = NassauEngine()
        let out = try engine.scoreHole(input(hole: 1, aNet: 4, bNet: 4), config: noPressConfig)
        #expect(out.holeWinner == nil)
    }

    @Test func fourballBestBallMinNetWins() throws {
        var engine = NassauEngine()
        // A's best = 3, B's best = 4 → A wins
        let out = try engine.scoreHole(fourballInput(hole: 1, aNets: [3, 6], bNets: [4, 5]), config: noPressConfig)
        #expect(out.holeWinner == .teamA)
    }

    @Test func fourballBestBallTiedNets() throws {
        var engine = NassauEngine()
        let out = try engine.scoreHole(fourballInput(hole: 1, aNets: [4, 6], bNets: [5, 4]), config: noPressConfig)
        #expect(out.holeWinner == nil)
    }
}

// MARK: - Match Status

struct NassauMatchStatusTests {

    @Test func allSquareInitially() throws {
        var engine = NassauEngine()
        let out = try engine.scoreHole(input(hole: 1, aNet: 4, bNet: 4), config: noPressConfig)
        #expect(out.frontStatus.leadingTeam == nil)
        #expect(out.frontStatus.holesUp == 0)
        #expect(out.overallStatus.leadingTeam == nil)
    }

    @Test func leadUpdatesCorrectly() throws {
        var engine = NassauEngine()
        _ = try engine.scoreHole(input(hole: 1, aNet: 3, bNet: 4), config: noPressConfig) // A wins
        _ = try engine.scoreHole(input(hole: 2, aNet: 5, bNet: 4), config: noPressConfig) // B wins
        let out = try engine.scoreHole(input(hole: 3, aNet: 3, bNet: 4), config: noPressConfig) // A wins
        #expect(out.frontStatus.leadingTeam == .teamA)
        #expect(out.frontStatus.holesUp == 1)
        #expect(out.overallStatus.leadingTeam == .teamA)
        #expect(out.overallStatus.holesUp == 1)
    }

    @Test func backNineTrackedSeparatelyFromFront() throws {
        var engine = NassauEngine()
        // A wins all of front 9
        for hole in 1...9 {
            _ = try engine.scoreHole(input(hole: hole, aNet: 3, bNet: 4), config: noPressConfig)
        }
        // B wins first back nine hole
        let out = try engine.scoreHole(input(hole: 10, aNet: 5, bNet: 4), config: noPressConfig)
        #expect(out.frontStatus.leadingTeam == .teamA)
        #expect(out.frontStatus.holesUp == 9)
        #expect(out.backStatus.leadingTeam == .teamB)
        #expect(out.backStatus.holesUp == 1)
        #expect(out.overallStatus.leadingTeam == .teamA)
        #expect(out.overallStatus.holesUp == 8)
    }
}

// MARK: - Segment Closure

struct NassauClosureTests {

    @Test func segmentClosedWhenUpMoreThanRemaining() throws {
        var engine = NassauEngine()
        // A wins holes 1-5 → 5UP with 4 remaining → closed (5 > 4)
        for hole in 1...5 {
            _ = try engine.scoreHole(input(hole: hole, aNet: 3, bNet: 4), config: noPressConfig)
        }
        let out = try engine.scoreHole(input(hole: 6, aNet: 3, bNet: 4), config: noPressConfig)
        #expect(out.frontStatus.isClosed == true)
    }

    @Test func closedDescriptionFormat() throws {
        var engine = NassauEngine()
        // A wins holes 1-5: 5UP, 4 remaining → "5&4" at hole 5
        for hole in 1...4 {
            _ = try engine.scoreHole(input(hole: hole, aNet: 3, bNet: 4), config: noPressConfig)
        }
        let out = try engine.scoreHole(input(hole: 5, aNet: 3, bNet: 4), config: noPressConfig)
        #expect(out.frontStatus.isClosed == true)
        #expect(out.frontStatus.closedDescription == "5&4")
    }

    @Test func notClosedWhenUpEqualsRemaining() throws {
        var engine = NassauEngine()
        // A wins holes 1-4: 4UP, 5 remaining → not closed (4 == 5 is false)
        for hole in 1...4 {
            _ = try engine.scoreHole(input(hole: hole, aNet: 3, bNet: 4), config: noPressConfig)
        }
        let out = try engine.scoreHole(input(hole: 5, aNet: 4, bNet: 4), config: noPressConfig)
        #expect(out.frontStatus.isClosed == false)
    }
}

// MARK: - Auto-Press

struct NassauAutoPressTests {

    @Test func autoPressFiresAtTriggerThreshold() throws {
        var engine = NassauEngine()
        let config = NassauPressConfig(autoPressTrigger: 2, maxPressesPerSegment: nil, manualPressEnabled: false)
        _ = try engine.scoreHole(input(hole: 1, aNet: 5, bNet: 4), config: config) // B +1
        let out = try engine.scoreHole(input(hole: 2, aNet: 5, bNet: 4), config: config) // B +2 → trigger
        #expect(out.autoPressTriggeredFor == .teamB)
    }

    @Test func autoPressDoesNotFireBelowThreshold() throws {
        var engine = NassauEngine()
        let config = NassauPressConfig(autoPressTrigger: 2, maxPressesPerSegment: nil, manualPressEnabled: false)
        let out = try engine.scoreHole(input(hole: 1, aNet: 5, bNet: 4), config: config) // B +1 only
        #expect(out.autoPressTriggeredFor == nil)
    }

    @Test func autoPressDoesNotFireOnLastHoleOfSegment() throws {
        var engine = NassauEngine()
        let config = NassauPressConfig(autoPressTrigger: 2, maxPressesPerSegment: nil, manualPressEnabled: false)
        // B leads by 1 going into hole 8, then wins hole 9 to go 2-down — no next hole
        for hole in 1...7 {
            _ = try engine.scoreHole(input(hole: hole, aNet: 4, bNet: 4), config: config)
        }
        _ = try engine.scoreHole(input(hole: 8, aNet: 5, bNet: 4), config: config) // B +1
        let out = try engine.scoreHole(input(hole: 9, aNet: 5, bNet: 4), config: config) // B +2, but last front hole
        #expect(out.autoPressTriggeredFor == nil)
    }

    @Test func autoPressRespectsMaxPerSegmentLimit() throws {
        var engine = NassauEngine()
        let config = NassauPressConfig(autoPressTrigger: 1, maxPressesPerSegment: 1, manualPressEnabled: false)
        // Trigger at hole 2 (B goes 1-down) → press fires
        _ = try engine.scoreHole(input(hole: 1, aNet: 5, bNet: 4), config: config)
        let out1 = try engine.scoreHole(input(hole: 2, aNet: 4, bNet: 4), config: config) // still 1-down after halve, no new press
        // Halve hole 3 then go another hole down at hole 4
        _ = try engine.scoreHole(input(hole: 3, aNet: 5, bNet: 3), config: config) // A wins, now AS
        _ = try engine.scoreHole(input(hole: 4, aNet: 5, bNet: 4), config: config) // B +1 again
        let out2 = try engine.scoreHole(input(hole: 5, aNet: 4, bNet: 4), config: config)
        // Second auto-press should be blocked by limit
        #expect(out2.autoPressTriggeredFor == nil)
        _ = out1  // suppress unused warning
    }

    @Test func autoPressFiresOnBackNineIndependently() throws {
        var engine = NassauEngine()
        let config = NassauPressConfig(autoPressTrigger: 2, maxPressesPerSegment: nil, manualPressEnabled: false)
        // Score front 9 with no presses
        for hole in 1...9 {
            _ = try engine.scoreHole(input(hole: hole, aNet: 4, bNet: 4), config: config)
        }
        // B goes 2-down on back
        _ = try engine.scoreHole(input(hole: 10, aNet: 5, bNet: 4), config: config)
        let out = try engine.scoreHole(input(hole: 11, aNet: 5, bNet: 4), config: config)
        #expect(out.autoPressTriggeredFor == .teamB)
    }
}

// MARK: - Manual Press

struct NassauManualPressTests {

    @Test func manualPressThrowsWhenDisabled() throws {
        var engine = NassauEngine()
        let config = NassauPressConfig(autoPressTrigger: nil, maxPressesPerSegment: nil, manualPressEnabled: false)
        _ = try engine.scoreHole(input(hole: 1, aNet: 5, bNet: 4), config: config) // B leads

        do {
            _ = try engine.scoreHole(input(hole: 2, aNet: 4, bNet: 4, press: .teamB), config: config)
            #expect(Bool(false), "Expected manualPressDisabled")
        } catch let e as NassauEngineError {
            #expect(e == .manualPressDisabled)
        }
    }

    @Test func manualPressThrowsForLeadingTeam() throws {
        var engine = NassauEngine()
        let config = NassauPressConfig(autoPressTrigger: nil, maxPressesPerSegment: nil, manualPressEnabled: true)
        _ = try engine.scoreHole(input(hole: 1, aNet: 3, bNet: 4), config: config) // A leads

        do {
            // A is leading — only trailing team (B) may press
            _ = try engine.scoreHole(input(hole: 2, aNet: 4, bNet: 4, press: .teamA), config: config)
            #expect(Bool(false), "Expected manualPressRequiresTrailingTeam")
        } catch let e as NassauEngineError {
            #expect(e == .manualPressRequiresTrailingTeam)
        }
    }

    @Test func manualPressThrowsWhenAtLimit() throws {
        var engine = NassauEngine()
        let config = NassauPressConfig(autoPressTrigger: nil, maxPressesPerSegment: 1, manualPressEnabled: true)
        _ = try engine.scoreHole(input(hole: 1, aNet: 5, bNet: 4), config: config) // B leads
        _ = try engine.scoreHole(input(hole: 2, aNet: 4, bNet: 4, press: .teamB), config: config) // 1 press used

        do {
            _ = try engine.scoreHole(input(hole: 3, aNet: 4, bNet: 4, press: .teamB), config: config)
            #expect(Bool(false), "Expected manualPressLimitReached")
        } catch let e as NassauEngineError {
            #expect(e == .manualPressLimitReached)
        }
    }

    @Test func manualPressAppearsInPressStatuses() throws {
        var engine = NassauEngine()
        let config = NassauPressConfig(autoPressTrigger: nil, maxPressesPerSegment: nil, manualPressEnabled: true)
        _ = try engine.scoreHole(input(hole: 1, aNet: 5, bNet: 4), config: config) // B leads
        let out = try engine.scoreHole(input(hole: 2, aNet: 4, bNet: 4, press: .teamB), config: config)
        #expect(out.frontStatus.pressStatuses.count == 1)
        #expect(out.frontStatus.pressStatuses[0].startHole == 2)
    }
}

// MARK: - Press Sub-bet Tracking

struct NassauPressSubBetTests {

    @Test func pressSubBetTracksIndependently() throws {
        var engine = NassauEngine()
        let config = NassauPressConfig(autoPressTrigger: nil, maxPressesPerSegment: nil, manualPressEnabled: true)
        // B leads by 2 after holes 1 & 2
        _ = try engine.scoreHole(input(hole: 1, aNet: 5, bNet: 4), config: config)
        _ = try engine.scoreHole(input(hole: 2, aNet: 5, bNet: 4), config: config)
        // A (trailing) presses on hole 3 (starts fresh sub-bet); hole 3 halved
        _ = try engine.scoreHole(input(hole: 3, aNet: 4, bNet: 4, press: .teamA), config: config)
        // A wins hole 4 — sub-bet A+1, main bet still B+1
        let out = try engine.scoreHole(input(hole: 4, aNet: 3, bNet: 4), config: config)
        let press = out.frontStatus.pressStatuses[0].matchStatus
        #expect(press.leadingTeam == .teamA)  // A up 1 in press
        #expect(press.holesUp == 1)
        #expect(out.frontStatus.leadingTeam == .teamB)  // main bet still B leads
    }
}

// MARK: - Settlement

struct NassauSettlementTests {

    @Test func settlementFrontWinBackLossOverallHalved() throws {
        var engine = NassauEngine()
        // A wins all front 9
        for hole in 1...9 {
            _ = try engine.scoreHole(input(hole: hole, aNet: 3, bNet: 4), config: noPressConfig)
        }
        // B wins all back 9
        for hole in 10...18 {
            _ = try engine.scoreHole(input(hole: hole, aNet: 5, bNet: 4), config: noPressConfig)
        }
        let s = engine.settlement()
        #expect(s.front.outcome == .sideAWon(description: "9&0"))
        #expect(s.back.outcome == .sideBWon(description: "9&0"))
        #expect(s.overall.outcome == .halved)
        #expect(s.totalNetForA == 0)   // won front, lost back, halved overall
        #expect(s.totalBets == 3)
    }

    @Test func settlementAllSquareHalvesAll() throws {
        var engine = NassauEngine()
        for hole in 1...18 {
            _ = try engine.scoreHole(input(hole: hole, aNet: 4, bNet: 4), config: noPressConfig)
        }
        let s = engine.settlement()
        #expect(s.front.outcome == .halved)
        #expect(s.back.outcome == .halved)
        #expect(s.overall.outcome == .halved)
        #expect(s.totalNetForA == 0)
    }

    @Test func settlementCountsPressesInTotalBets() throws {
        var engine = NassauEngine()
        let config = NassauPressConfig(autoPressTrigger: nil, maxPressesPerSegment: nil, manualPressEnabled: true)
        // B leads after hole 1
        _ = try engine.scoreHole(input(hole: 1, aNet: 5, bNet: 4), config: config)
        // B presses on hole 2
        for hole in 2...9 {
            _ = try engine.scoreHole(input(hole: hole, aNet: 4, bNet: 4, press: hole == 2 ? .teamB : nil), config: config)
        }
        for hole in 10...18 {
            _ = try engine.scoreHole(input(hole: hole, aNet: 4, bNet: 4), config: config)
        }
        let s = engine.settlement()
        #expect(s.totalBets == 4)  // front + back + overall + 1 front press
        #expect(s.frontPresses.count == 1)
    }

    @Test func settlementNetForACalculation() throws {
        var engine = NassauEngine()
        // A wins front, back, and overall → net +3
        for hole in 1...18 {
            _ = try engine.scoreHole(input(hole: hole, aNet: 3, bNet: 4), config: noPressConfig)
        }
        let s = engine.settlement()
        #expect(s.totalNetForA == 3)
    }
}

// MARK: - Error Cases

struct NassauEngineErrorTests {

    @Test func holeOutOfRangeThrows() throws {
        var engine = NassauEngine()
        do {
            _ = try engine.scoreHole(input(hole: 0, aNet: 4, bNet: 4), config: noPressConfig)
            #expect(Bool(false), "Expected holeOutOfRange")
        } catch let e as NassauEngineError {
            #expect(e == .holeOutOfRange)
        }
        do {
            _ = try engine.scoreHole(input(hole: 19, aNet: 4, bNet: 4), config: noPressConfig)
            #expect(Bool(false), "Expected holeOutOfRange")
        } catch let e as NassauEngineError {
            #expect(e == .holeOutOfRange)
        }
    }

    @Test func invalidNetScoreCountThrows() throws {
        var engine = NassauEngine()
        let bad = NassauHoleInput(holeNumber: 1, par: 4, sideANetScores: [4, 5], sideBNetScores: [4], manualPressBy: nil)
        do {
            _ = try engine.scoreHole(bad, config: noPressConfig)
            #expect(Bool(false), "Expected invalidNetScoreCount")
        } catch let e as NassauEngineError {
            #expect(e == .invalidNetScoreCount)
        }
    }
}

// MARK: - Engine Replay

struct NassauEngineReplayTests {

    @Test func replayProducesSameMatchStatus() throws {
        var engine1 = NassauEngine()
        let config = NassauPressConfig(autoPressTrigger: 2, maxPressesPerSegment: nil, manualPressEnabled: true)
        let inputs: [NassauHoleInput] = [
            input(hole: 1, aNet: 3, bNet: 4),
            input(hole: 2, aNet: 5, bNet: 4),
            input(hole: 3, aNet: 5, bNet: 4),   // B +2 → auto-press on hole 4
            input(hole: 4, aNet: 4, bNet: 4),
            input(hole: 5, aNet: 4, bNet: 3),
        ]
        var lastOut1: NassauHoleOutput?
        for inp in inputs { lastOut1 = try engine1.scoreHole(inp, config: config) }

        var engine2 = NassauEngine()
        var lastOut2: NassauHoleOutput?
        for inp in inputs { lastOut2 = try engine2.scoreHole(inp, config: config) }

        #expect(lastOut1?.frontStatus == lastOut2?.frontStatus)
        #expect(lastOut1?.overallStatus == lastOut2?.overallStatus)
    }
}
