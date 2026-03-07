import Testing
@testable import GolfGameApp

// MARK: - Helpers

private func skinsInput(
    hole: Int,
    par: Int = 4,
    mode: SkinsMode = .gross,
    carryover: Bool = true,
    scores: [(id: String, gross: Int, strokes: Int)]
) -> SkinsHoleInput {
    SkinsHoleInput(
        holeNumber: hole,
        par: par,
        scores: scores.map { SkinsPlayerScore(playerID: $0.id, gross: $0.gross, handicapStrokes: $0.strokes) },
        mode: mode,
        carryoverEnabled: carryover
    )
}

// MARK: - Error Cases

struct SkinsEngineErrorTests {

    @Test func holeZeroThrows() throws {
        var engine = SkinsEngine()
        do {
            _ = try engine.scoreHole(skinsInput(hole: 0, scores: [("A", 4, 0), ("B", 5, 0)]))
            #expect(Bool(false), "Expected holeOutOfRange")
        } catch let e as SkinsActionError {
            #expect(e == .holeOutOfRange)
        }
    }

    @Test func hole19Throws() throws {
        var engine = SkinsEngine()
        do {
            _ = try engine.scoreHole(skinsInput(hole: 19, scores: [("A", 4, 0), ("B", 5, 0)]))
            #expect(Bool(false), "Expected holeOutOfRange")
        } catch let e as SkinsActionError {
            #expect(e == .holeOutOfRange)
        }
    }

    @Test func onePlayerThrows() throws {
        var engine = SkinsEngine()
        do {
            _ = try engine.scoreHole(skinsInput(hole: 1, scores: [("A", 4, 0)]))
            #expect(Bool(false), "Expected notEnoughPlayers")
        } catch let e as SkinsActionError {
            #expect(e == .notEnoughPlayers)
        }
    }

    @Test func duplicatePlayerIDThrows() throws {
        var engine = SkinsEngine()
        do {
            _ = try engine.scoreHole(skinsInput(hole: 1, scores: [("A", 4, 0), ("A", 5, 0)]))
            #expect(Bool(false), "Expected duplicatePlayerID")
        } catch let e as SkinsActionError {
            #expect(e == .duplicatePlayerID)
        }
    }
}

// MARK: - Gross Mode

struct SkinsEngineGrossTests {

    @Test func outrightWinnerGetsOneSkin() throws {
        var engine = SkinsEngine()
        let out = try engine.scoreHole(skinsInput(hole: 1, scores: [
            ("A", 3, 0), ("B", 4, 0), ("C", 5, 0)
        ]))
        #expect(out.grossResult.winnerID == "A")
        #expect(out.grossResult.skinsAwarded == 1)
        #expect(out.grossResult.isTie == false)
        #expect(out.grossSkinsTotal["A"] == 1)
        #expect(out.grossCarryover == 0)
    }

    @Test func tieWithCarryoverIncrementsCarryover() throws {
        var engine = SkinsEngine()
        let out = try engine.scoreHole(skinsInput(hole: 1, carryover: true, scores: [
            ("A", 4, 0), ("B", 4, 0)
        ]))
        #expect(out.grossResult.winnerID == nil)
        #expect(out.grossResult.isTie == true)
        #expect(out.grossCarryover == 1)
        #expect(out.grossSkinsTotal["A"] == 0)
        #expect(out.grossSkinsTotal["B"] == 0)
    }

    @Test func tieWithCarryoverOffVoidsSkin() throws {
        var engine = SkinsEngine()
        let out = try engine.scoreHole(skinsInput(hole: 1, carryover: false, scores: [
            ("A", 4, 0), ("B", 4, 0)
        ]))
        #expect(out.grossResult.winnerID == nil)
        #expect(out.grossCarryover == 0)   // no accumulation
    }

    @Test func winAfterCarryoverGetsBonusSkins() throws {
        var engine = SkinsEngine()
        // Hole 1: tie → carryover = 1
        _ = try engine.scoreHole(skinsInput(hole: 1, carryover: true, scores: [
            ("A", 4, 0), ("B", 4, 0)
        ]))
        // Hole 2: A wins outright → gets 1 + 1 = 2 skins
        let out = try engine.scoreHole(skinsInput(hole: 2, carryover: true, scores: [
            ("A", 3, 0), ("B", 5, 0)
        ]))
        #expect(out.grossResult.winnerID == "A")
        #expect(out.grossResult.skinsAwarded == 2)
        #expect(out.grossCarryover == 0)
        #expect(out.grossSkinsTotal["A"] == 2)
    }

    @Test func multiHoleCarryoverAccumulatesCorrectly() throws {
        var engine = SkinsEngine()
        // Two ties in a row → carryover = 2
        _ = try engine.scoreHole(skinsInput(hole: 1, carryover: true, scores: [("A", 4, 0), ("B", 4, 0)]))
        _ = try engine.scoreHole(skinsInput(hole: 2, carryover: true, scores: [("A", 5, 0), ("B", 5, 0)]))
        // Hole 3: B wins → gets 3 skins
        let out = try engine.scoreHole(skinsInput(hole: 3, carryover: true, scores: [("A", 5, 0), ("B", 4, 0)]))
        #expect(out.grossResult.skinsAwarded == 3)
        #expect(out.grossSkinsTotal["B"] == 3)
        #expect(out.grossCarryover == 0)
    }

    @Test func carryoverResetsAfterWin() throws {
        var engine = SkinsEngine()
        _ = try engine.scoreHole(skinsInput(hole: 1, carryover: true, scores: [("A", 4, 0), ("B", 4, 0)]))
        _ = try engine.scoreHole(skinsInput(hole: 2, carryover: true, scores: [("A", 3, 0), ("B", 5, 0)]))
        // Hole 3: next hole carryover starts at 0
        let out = try engine.scoreHole(skinsInput(hole: 3, carryover: true, scores: [("A", 4, 0), ("B", 5, 0)]))
        #expect(out.grossResult.skinsAwarded == 1)
    }

    @Test func runningTotalsAccumulateAcrossHoles() throws {
        var engine = SkinsEngine()
        _ = try engine.scoreHole(skinsInput(hole: 1, scores: [("A", 3, 0), ("B", 5, 0)]))
        let out = try engine.scoreHole(skinsInput(hole: 2, scores: [("A", 5, 0), ("B", 3, 0)]))
        #expect(out.grossSkinsTotal["A"] == 1)
        #expect(out.grossSkinsTotal["B"] == 1)
    }

    @Test func fourPlayerOutrightWinner() throws {
        var engine = SkinsEngine()
        let out = try engine.scoreHole(skinsInput(hole: 1, scores: [
            ("A", 3, 0), ("B", 4, 0), ("C", 4, 0), ("D", 5, 0)
        ]))
        #expect(out.grossResult.winnerID == "A")
        #expect(out.grossResult.skinsAwarded == 1)
    }

    @Test func twoPlayersLowestScoreTies() throws {
        var engine = SkinsEngine()
        let out = try engine.scoreHole(skinsInput(hole: 1, scores: [
            ("A", 3, 0), ("B", 3, 0), ("C", 5, 0), ("D", 5, 0)
        ]))
        // A and B tie the low score → no winner even though C and D are higher
        #expect(out.grossResult.winnerID == nil)
        #expect(out.grossResult.isTie == true)
    }
}

// MARK: - Net Mode

struct SkinsEngineNetTests {

    @Test func netWinnerDifferentFromGrossWinner() throws {
        var engine = SkinsEngine()
        // A gross 5 - 2 strokes = net 3; B gross 4 - 0 strokes = net 4
        // Gross winner: B (4 < 5). Net winner: A (3 < 4).
        let out = try engine.scoreHole(skinsInput(hole: 1, mode: .net, scores: [
            ("A", 5, 2), ("B", 4, 0)
        ]))
        // Net mode: gross track not evaluated
        #expect(out.grossResult.winnerID == nil)
        #expect(out.grossResult.skinsAwarded == 0)
        // Net track: A wins
        #expect(out.netResult.winnerID == "A")
        #expect(out.netResult.skinsAwarded == 1)
        #expect(out.netSkinsTotal["A"] == 1)
    }

    @Test func netTieCarriesOver() throws {
        var engine = SkinsEngine()
        // Both net 4 (A: 5-1, B: 4-0)
        let out = try engine.scoreHole(skinsInput(hole: 1, mode: .net, carryover: true, scores: [
            ("A", 5, 1), ("B", 4, 0)
        ]))
        #expect(out.netResult.isTie == true)
        #expect(out.netCarryover == 1)
    }
}

// MARK: - Both Mode

struct SkinsEngineBothModeTests {

    @Test func bothModeRunsIndependentTracks() throws {
        var engine = SkinsEngine()
        // A gross 4 (wins gross: 4 < 5), B net 3 (gross 5 - 2 = 3, wins net vs A net 4)
        let out = try engine.scoreHole(skinsInput(hole: 1, mode: .both, scores: [
            ("A", 4, 0), ("B", 5, 2)
        ]))
        #expect(out.grossResult.winnerID == "A")
        #expect(out.netResult.winnerID == "B")
        #expect(out.grossSkinsTotal["A"] == 1)
        #expect(out.netSkinsTotal["B"] == 1)
    }

    @Test func bothModeIndependentCarryovers() throws {
        var engine = SkinsEngine()
        // Hole 1: gross tie (both 4, strokes 0) but net A wins (A: 4-1=3, B: 4-0=4)
        _ = try engine.scoreHole(skinsInput(hole: 1, mode: .both, carryover: true, scores: [
            ("A", 4, 1), ("B", 4, 0)
        ]))
        // grossCarryover should be 1; netCarryover 0
        let out = try engine.scoreHole(skinsInput(hole: 2, mode: .both, carryover: true, scores: [
            ("A", 3, 0), ("B", 5, 0)
        ]))
        // Gross: A wins, picks up carryover → 2 skins
        #expect(out.grossResult.winnerID == "A")
        #expect(out.grossResult.skinsAwarded == 2)
        // Net: A wins outright → 1 skin (no net carryover was pending)
        #expect(out.netResult.winnerID == "A")
        #expect(out.netResult.skinsAwarded == 1)
    }
}

// MARK: - Audit Log

struct SkinsEngineAuditLogTests {

    @Test func auditLogContainsHoleMarker() throws {
        var engine = SkinsEngine()
        let out = try engine.scoreHole(skinsInput(hole: 5, scores: [("A", 3, 0), ("B", 4, 0)]))
        #expect(out.auditLog.contains("Hole 5"))
    }

    @Test func auditLogRecordsGrossWin() throws {
        var engine = SkinsEngine()
        let out = try engine.scoreHole(skinsInput(hole: 1, scores: [("A", 3, 0), ("B", 4, 0)]))
        let entry = out.auditLog.first(where: { $0.hasPrefix("Gross:") })
        #expect(entry == "Gross: A wins 1 skin(s)")
    }

    @Test func auditLogRecordsTieWithCarryover() throws {
        var engine = SkinsEngine()
        let out = try engine.scoreHole(skinsInput(hole: 1, carryover: true, scores: [("A", 4, 0), ("B", 4, 0)]))
        let entry = out.auditLog.first(where: { $0.hasPrefix("Gross: tie") })
        #expect(entry == "Gross: tie · carryover now 1")
    }

    @Test func auditLogRecordsTieVoidedWhenCarryoverOff() throws {
        var engine = SkinsEngine()
        let out = try engine.scoreHole(skinsInput(hole: 1, carryover: false, scores: [("A", 4, 0), ("B", 4, 0)]))
        let entry = out.auditLog.first(where: { $0.hasPrefix("Gross: tie") })
        #expect(entry == "Gross: tie · skin void")
    }

    @Test func auditLogAccumulatesAcrossHoles() throws {
        var engine = SkinsEngine()
        _ = try engine.scoreHole(skinsInput(hole: 1, scores: [("A", 3, 0), ("B", 4, 0)]))
        let out = try engine.scoreHole(skinsInput(hole: 2, scores: [("A", 5, 0), ("B", 3, 0)]))
        #expect(out.auditLog.contains("Hole 1"))
        #expect(out.auditLog.contains("Hole 2"))
    }
}
