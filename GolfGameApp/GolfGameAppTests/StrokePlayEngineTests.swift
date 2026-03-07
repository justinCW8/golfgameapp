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

// MARK: - Best Ball 2v2 Tests

@Suite struct StrokePlayEngineBestBall2v2Tests {
    
    @Test func bestBallSelectsLowerGrossScore() throws {
        let pairings = [
            BestBallPairing(teamName: "Team A", playerIDs: ["A1", "A2"]),
            BestBallPairing(teamName: "Team B", playerIDs: ["B1", "B2"])
        ]
        let config = StrokePlayEngineConfig(format: .bestBall2v2, pairings: pairings)
        var engine = StrokePlayEngine(config: config)
        
        let scores = [
            StrokePlayPlayerScore(playerID: "A1", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "A2", gross: 5, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "B1", gross: 6, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "B2", gross: 4, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        
        #expect(output.bestGrossByTeam?[pairings[0].id] == 4)  // Team A best gross
        #expect(output.bestGrossByTeam?[pairings[1].id] == 4)  // Team B best gross
    }
    
    @Test func bestBallSelectsLowerNetScore() throws {
        let pairings = [
            BestBallPairing(teamName: "Team A", playerIDs: ["A1", "A2"])
        ]
        let config = StrokePlayEngineConfig(format: .bestBall2v2, pairings: pairings)
        var engine = StrokePlayEngine(config: config)
        
        let scores = [
            StrokePlayPlayerScore(playerID: "A1", gross: 5, handicapStrokes: 1),  // net 4
            StrokePlayPlayerScore(playerID: "A2", gross: 5, handicapStrokes: 0)   // net 5
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        
        #expect(output.bestNetByTeam?[pairings[0].id] == 4)  // Best net is 4 (A1)
    }
    
    @Test func bestBallTeamTotalsAccumulate() throws {
        let pairings = [
            BestBallPairing(teamName: "Team A", playerIDs: ["A1", "A2"])
        ]
        let config = StrokePlayEngineConfig(format: .bestBall2v2, pairings: pairings)
        var engine = StrokePlayEngine(config: config)
        
        let hole1Scores = [
            StrokePlayPlayerScore(playerID: "A1", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "A2", gross: 5, handicapStrokes: 0)
        ]
        _ = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: hole1Scores))
        
        let hole2Scores = [
            StrokePlayPlayerScore(playerID: "A1", gross: 3, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "A2", gross: 4, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 2, par: 3, scores: hole2Scores))
        
        let teamStanding = output.bestBallTeamStandings?.first
        #expect(teamStanding?.grossTotal == 7)  // 4 + 3
        #expect(teamStanding?.netTotal == 7)    // 4 + 3
    }
    
    @Test func bestBallTeamLeaderboardSortsByNetTotal() throws {
        let pairings = [
            BestBallPairing(teamName: "Team A", playerIDs: ["A1", "A2"]),
            BestBallPairing(teamName: "Team B", playerIDs: ["B1", "B2"]),
            BestBallPairing(teamName: "Team C", playerIDs: ["C1", "C2"])
        ]
        let config = StrokePlayEngineConfig(format: .bestBall2v2, pairings: pairings)
        var engine = StrokePlayEngine(config: config)
        
        let scores = [
            StrokePlayPlayerScore(playerID: "A1", gross: 5, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "A2", gross: 6, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "B1", gross: 3, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "B2", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "C1", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "C2", gross: 5, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        
        let standings = output.bestBallTeamStandings ?? []
        #expect(standings[0].teamName == "Team B")  // 3 net
        #expect(standings[1].teamName == "Team C")  // 4 net
        #expect(standings[2].teamName == "Team A")  // 5 net
    }
    
    @Test func bestBallTiedTeamsShareRank() throws {
        let pairings = [
            BestBallPairing(teamName: "Team A", playerIDs: ["A1", "A2"]),
            BestBallPairing(teamName: "Team B", playerIDs: ["B1", "B2"])
        ]
        let config = StrokePlayEngineConfig(format: .bestBall2v2, pairings: pairings)
        var engine = StrokePlayEngine(config: config)
        
        let scores = [
            StrokePlayPlayerScore(playerID: "A1", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "A2", gross: 5, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "B1", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "B2", gross: 6, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        
        let standings = output.bestBallTeamStandings ?? []
        #expect(standings[0].rank == 1)
        #expect(standings[1].rank == 1)  // Tied, both rank 1
    }
    
    @Test func bestBallVsParCalculatedCorrectly() throws {
        let pairings = [
            BestBallPairing(teamName: "Team A", playerIDs: ["A1", "A2"])
        ]
        let config = StrokePlayEngineConfig(format: .bestBall2v2, pairings: pairings)
        var engine = StrokePlayEngine(config: config)
        
        let scores = [
            StrokePlayPlayerScore(playerID: "A1", gross: 3, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "A2", gross: 4, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        
        let teamStanding = output.bestBallTeamStandings?.first
        #expect(teamStanding?.vsPar == -1)  // 3 net vs 4 par = -1
    }
    
    @Test func bestBallHandicapStrokesAffectNetSelection() throws {
        let pairings = [
            BestBallPairing(teamName: "Team A", playerIDs: ["A1", "A2"])
        ]
        let config = StrokePlayEngineConfig(format: .bestBall2v2, pairings: pairings)
        var engine = StrokePlayEngine(config: config)
        
        let scores = [
            StrokePlayPlayerScore(playerID: "A1", gross: 6, handicapStrokes: 2),  // net 4
            StrokePlayPlayerScore(playerID: "A2", gross: 5, handicapStrokes: 0)   // net 5
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        
        #expect(output.bestNetByTeam?[pairings[0].id] == 4)  // A1's net 4 is better
    }
}

// MARK: - Team Best Ball Tests

@Suite struct StrokePlayEngineTeamBestBallTests {
    
    @Test func teamBestBallTracksAllFourPlayers() throws {
        let pairings = [
            BestBallPairing(teamName: "The Team", playerIDs: ["P1", "P2", "P3", "P4"])
        ]
        let config = StrokePlayEngineConfig(format: .teamBestBall, pairings: pairings)
        var engine = StrokePlayEngine(config: config)
        
        let scores = [
            StrokePlayPlayerScore(playerID: "P1", gross: 5, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "P2", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "P3", gross: 6, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "P4", gross: 3, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        
        #expect(output.bestGrossByTeam?[pairings[0].id] == 3)  // P4's score
        #expect(output.bestNetByTeam?[pairings[0].id] == 3)
    }
    
    @Test func teamBestBallVsParOnly() throws {
        let pairings = [
            BestBallPairing(teamName: "The Team", playerIDs: ["P1", "P2", "P3", "P4"])
        ]
        let config = StrokePlayEngineConfig(format: .teamBestBall, pairings: pairings)
        var engine = StrokePlayEngine(config: config)
        
        let scores = [
            StrokePlayPlayerScore(playerID: "P1", gross: 3, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "P2", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "P3", gross: 5, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "P4", gross: 6, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        
        let teamStanding = output.bestBallTeamStandings?.first
        #expect(teamStanding?.vsPar == -1)  // 3 vs par 4 = -1
        #expect(teamStanding?.rank == 1)    // Only one team
    }
    
    @Test func teamBestBallAccumulatesAcrossHoles() throws {
        let pairings = [
            BestBallPairing(teamName: "The Team", playerIDs: ["P1", "P2", "P3", "P4"])
        ]
        let config = StrokePlayEngineConfig(format: .teamBestBall, pairings: pairings)
        var engine = StrokePlayEngine(config: config)
        
        let hole1Scores = [
            StrokePlayPlayerScore(playerID: "P1", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "P2", gross: 3, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "P3", gross: 5, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "P4", gross: 6, handicapStrokes: 0)
        ]
        _ = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: hole1Scores))
        
        let hole2Scores = [
            StrokePlayPlayerScore(playerID: "P1", gross: 5, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "P2", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "P3", gross: 3, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "P4", gross: 6, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 2, par: 4, scores: hole2Scores))
        
        let teamStanding = output.bestBallTeamStandings?.first
        #expect(teamStanding?.netTotal == 6)     // 3 + 3
        #expect(teamStanding?.vsPar == -2)       // 6 vs 8 par = -2
    }
}

// MARK: - Individual Format Regression Tests

@Suite struct StrokePlayEngineIndividualFormatTests {
    
    @Test func individualFormatHasNoBestBallData() throws {
        let config = StrokePlayEngineConfig(format: .individual, pairings: [])
        var engine = StrokePlayEngine(config: config)
        
        let scores = [
            StrokePlayPlayerScore(playerID: "A", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "B", gross: 5, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        
        #expect(output.bestBallTeamStandings == nil)
        #expect(output.bestGrossByTeam == nil)
        #expect(output.bestNetByTeam == nil)
    }
    
    @Test func individualFormatStillTracksPlayers() throws {
        let config = StrokePlayEngineConfig(format: .individual, pairings: [])
        var engine = StrokePlayEngine(config: config)
        
        let scores = [
            StrokePlayPlayerScore(playerID: "A", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "B", gross: 5, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        
        #expect(output.grossTotalByPlayer["A"] == 4)
        #expect(output.grossTotalByPlayer["B"] == 5)
        #expect(output.leaderboard.count == 2)
    }
}

// MARK: - Best Ball Audit Log Tests

@Suite struct StrokePlayEngineBestBallAuditTests {
    
    @Test func auditLogIncludesTeamScores() throws {
        let pairings = [
            BestBallPairing(teamName: "Team A", playerIDs: ["A1", "A2"])
        ]
        let config = StrokePlayEngineConfig(format: .bestBall2v2, pairings: pairings)
        var engine = StrokePlayEngine(config: config)
        
        let scores = [
            StrokePlayPlayerScore(playerID: "A1", gross: 4, handicapStrokes: 0),
            StrokePlayPlayerScore(playerID: "A2", gross: 5, handicapStrokes: 0)
        ]
        let output = try engine.scoreHole(StrokePlayHoleInput(holeNumber: 1, par: 4, scores: scores))
        
        let hasTeamEntry = output.auditLog.contains { $0.contains("Team A") }
        #expect(hasTeamEntry == true)
    }
}
