import Testing
@testable import GolfGameApp

// MARK: - Error Tests

@Suite struct StrokePlayEngineErrorTests {

    @Test func holeZeroThrows() {
        var engine = StrokePlayEngine()
        let score = StrokePlayPlayerScore(playerID: "A", gross: 4, handicapStrokes: 0)
        #expect(throws: StrokePlayActionError.holeOutOfRange) {
            try engine.scoreHole(StrokePlayHoleInput(holeNumber: 0, par: 4, scores: [score]))
        }
    }

    @Test func hole19Throws() {
        var engine = StrokePlayEngine()
        let score = StrokePlayPlayerScore(playerID: "A", gross: 4, handicapStrokes: 0)
        #expect(throws: StrokePlayActionError.holeOutOfRange) {
            try engine.scoreHole(StrokePlayHoleInput(holeNumber: 19, par: 4, scores: [score]))
        }
    }

    @Test func duplicatePlayerIDThrows() {
        var engine = StrokePlayEngine()
        let s1 = StrokePlayPlayerScore(playerID: "A", gross: 4, handicapStrokes: 0)
        let s2 = StrokePlayPlayerScore(playerID: "A", gross: 5, handicapStrokes: 0)
        #expect(throws: StrokePlayActionError.duplicatePlayerID) {
            try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: [s1, s2]))
        }
    }
}

// MARK: - Gross Totals

@Suite struct StrokePlayEngineGrossTests {

    @Test func singleHoleGrossTotalsCorrect() throws {
        var engine = StrokePlayEngine()
        let scores = [
            StrokePlayPlayerScore(playerID: "A", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "B", gross: 5, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        #expect(output.grossTotalByPlayer["A"] == 4)
        #expect(output.grossTotalByPlayer["B"] == 5)
    }

    @Test func multiHoleGrossTotalsAccumulate() throws {
        var engine = StrokePlayEngine()
        let make = { (id: String, gross: Int) in StrokePlayPlayerScore(playerID: id, gross: gross, handicapStrokes: 0) }
        _ = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: [make("A", 4), make("B", 5)]))
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 2, par: 3, scores: [make("A", 3), make("B", 4)]))
        #expect(output.grossTotalByPlayer["A"] == 7)
        #expect(output.grossTotalByPlayer["B"] == 9)
    }

    @Test func singlePlayerAllowed() throws {
        var engine = StrokePlayEngine()
        let score = StrokePlayPlayerScore(playerID: "A", gross: 5, handicapStrokes: 0)
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: [score]))
        #expect(output.grossTotalByPlayer["A"] == 5)
    }
}

// MARK: - Net Totals & Handicap Strokes

@Suite struct StrokePlayEngineNetTests {

    @Test func handicapStrokesReduceNetScore() throws {
        var engine = StrokePlayEngine()
        let scores = [
            StrokePlayPlayerScore(playerID: "A", gross: 5, handicapStrokes: 1),
            StrokePlayPlayerScore(playerID: "B", gross: 5, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        #expect(output.netTotalByPlayer["A"] == 4)
        #expect(output.netTotalByPlayer["B"] == 5)
    }

    @Test func netTotalAccumulatesAcrossHoles() throws {
        var engine = StrokePlayEngine()
        let make = { (id: String, gross: Int, strokes: Int) in
            StrokePlayPlayerScore(playerID: id, gross: gross, handicapStrokes: strokes)
        }
        _ = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: [make("A", 5, 1), make("B", 5, 0)]))
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 2, par: 4, scores: [make("A", 4, 0), make("B", 4, 1)]))
        // A: (5-1) + (4-0) = 4 + 4 = 8; B: (5-0) + (4-1) = 5 + 3 = 8
        #expect(output.netTotalByPlayer["A"] == 8)
        #expect(output.netTotalByPlayer["B"] == 8)
    }
}

// MARK: - Vs Par

@Suite struct StrokePlayEngineVsParTests {

    @Test func underParIsNegative() throws {
        var engine = StrokePlayEngine()
        let scores = [StrokePlayPlayerScore(playerID: "A", gross: 3, handicapStrokes: 0)]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        #expect(output.vsParByPlayer["A"] == -1)
    }

    @Test func overParIsPositive() throws {
        var engine = StrokePlayEngine()
        let scores = [StrokePlayPlayerScore(playerID: "A", gross: 6, handicapStrokes: 0)]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        #expect(output.vsParByPlayer["A"] == 2)
    }

    @Test func evenParIsZero() throws {
        var engine = StrokePlayEngine()
        let scores = [StrokePlayPlayerScore(playerID: "A", gross: 4, handicapStrokes: 0)]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        #expect(output.vsParByPlayer["A"] == 0)
    }

    @Test func vsParAccumulatesAcrossHoles() throws {
        var engine = StrokePlayEngine()
        let make = { (gross: Int) in StrokePlayPlayerScore(playerID: "A", gross: gross, handicapStrokes: 0) }
        _ = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: [make(3)]))  // -1
        _ = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 2, par: 4, scores: [make(5)]))  // +1 → 0
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 3, par: 5, scores: [make(4)]))  // -1 → -1
        #expect(output.vsParByPlayer["A"] == -1)
    }

    @Test func netVsParUsesNetScore() throws {
        var engine = StrokePlayEngine()
        // Gross 5 on par 4, 1 stroke = net 4 = par = 0
        let scores = [StrokePlayPlayerScore(playerID: "A", gross: 5, handicapStrokes: 1)]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        #expect(output.vsParByPlayer["A"] == 0)
    }
}

// MARK: - Leaderboard

@Suite struct StrokePlayEngineLeaderboardTests {

    @Test func leaderboardSortedByNetAscending() throws {
        var engine = StrokePlayEngine()
        let scores = [
            StrokePlayPlayerScore(playerID: "A", gross: 5, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "B", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "C", gross: 3, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        #expect(output.leaderboard[0].playerID == "C")
        #expect(output.leaderboard[1].playerID == "B")
        #expect(output.leaderboard[2].playerID == "A")
    }

    @Test func tiedPlayersShareRank() throws {
        var engine = StrokePlayEngine()
        let scores = [
            StrokePlayPlayerScore(playerID: "A", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "B", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "C", gross: 5, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        let aRank = output.leaderboard.first(where: { $0.playerID == "A" })?.rank
        let bRank = output.leaderboard.first(where: { $0.playerID == "B" })?.rank
        let cRank = output.leaderboard.first(where: { $0.playerID == "C" })?.rank
        #expect(aRank == bRank)
        #expect(cRank == 3)
    }

    @Test func leaderboardRank1HasLowestNetTotal() throws {
        var engine = StrokePlayEngine()
        let make = { (id: String, gross: Int) in StrokePlayPlayerScore(playerID: id, gross: gross, handicapStrokes: 0) }
        _ = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: [make("A", 4), make("B", 5)]))
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 2, par: 4, scores: [make("A", 4), make("B", 3)]))
        // A: 8 net, B: 8 net — tied
        let rank1Players = output.leaderboard.filter { $0.rank == 1 }
        #expect(rank1Players.count == 2)
    }
}

// MARK: - Audit Log

@Suite struct StrokePlayEngineAuditLogTests {

    @Test func auditLogContainsHoleMarker() throws {
        var engine = StrokePlayEngine()
        let score = StrokePlayPlayerScore(playerID: "A", gross: 4, handicapStrokes: 0)
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 7, par: 4, scores: [score]))
        #expect(output.auditLog.contains("Hole 7"))
    }

    @Test func auditLogContainsPlayerEntry() throws {
        var engine = StrokePlayEngine()
        let score = StrokePlayPlayerScore(playerID: "JW", gross: 3, handicapStrokes: 1)
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: [score]))
        // Net = 3 - 1 = 2, vs par = 2 - 4 = -2
        let entry = output.auditLog.first(where: { $0.contains("JW") })
        #expect(entry != nil)
        #expect(entry?.contains("3 gross") == true)
        #expect(entry?.contains("2 net") == true)
    }

    @Test func auditLogGrowsAcrossHoles() throws {
        var engine = StrokePlayEngine()
        let score = StrokePlayPlayerScore(playerID: "A", gross: 4, handicapStrokes: 0)
        _ = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: [score]))
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 2, par: 4, scores: [score]))
        #expect(output.auditLog.contains("Hole 1"))
        #expect(output.auditLog.contains("Hole 2"))
    }
}
