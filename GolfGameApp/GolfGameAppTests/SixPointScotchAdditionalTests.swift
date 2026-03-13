import Testing
@testable import GolfGameApp

// MARK: - Helpers

private func scotchInput(
    hole: Int,
    par: Int = 4,
    aNet: [Int],
    bNet: [Int],
    aGross: [Int]? = nil,
    bGross: [Int]? = nil,
    aProx: Double? = nil,
    bProx: Double? = nil,
    pressBy: TeamSide? = nil,
    rollBy: TeamSide? = nil,
    rerollBy: TeamSide? = nil
) -> SixPointScotchHoleInput {
    SixPointScotchHoleInput(
        holeNumber: hole,
        par: par,
        teamANetScores: aNet,
        teamBNetScores: bNet,
        teamAGrossScores: aGross ?? aNet,
        teamBGrossScores: bGross ?? bNet,
        teamAProxFeet: aProx,
        teamBProxFeet: bProx,
        requestPressBy: pressBy,
        requestRollBy: rollBy,
        requestRerollBy: rerollBy
    )
}

/// B always wins (aNet 5/5, bNet 4/4). A is trailing after this hole.
private func bWinsHole(hole: Int, pressBy: TeamSide? = nil, rollBy: TeamSide? = nil) -> SixPointScotchHoleInput {
    scotchInput(hole: hole, aNet: [5, 5], bNet: [4, 4], pressBy: pressBy, rollBy: rollBy)
}

// MARK: - Error Cases

struct SixPointScotchErrorTests {

    @Test func holeZeroThrows() throws {
        var engine = SixPointScotchEngine()
        do {
            _ = try engine.scoreHole(scotchInput(hole: 0, aNet: [4, 4], bNet: [5, 5]))
            #expect(Bool(false), "Expected holeOutOfRange")
        } catch let e as SixPointScotchActionError {
            #expect(e == .holeOutOfRange)
        }
    }

    @Test func hole19Throws() throws {
        var engine = SixPointScotchEngine()
        do {
            _ = try engine.scoreHole(scotchInput(hole: 19, aNet: [4, 4], bNet: [5, 5]))
            #expect(Bool(false), "Expected holeOutOfRange")
        } catch let e as SixPointScotchActionError {
            #expect(e == .holeOutOfRange)
        }
    }

    @Test func invalidPlayerCountThrows() throws {
        var engine = SixPointScotchEngine()
        // Only 1 score on teamA side — requires exactly 2
        let bad = SixPointScotchHoleInput(
            holeNumber: 1, par: 4,
            teamANetScores: [4], teamBNetScores: [5, 5],
            teamAGrossScores: [4], teamBGrossScores: [5, 5],
            teamAProxFeet: nil, teamBProxFeet: nil,
            requestPressBy: nil, requestRollBy: nil, requestRerollBy: nil
        )
        do {
            _ = try engine.scoreHole(bad)
            #expect(Bool(false), "Expected invalidPlayerCount")
        } catch let e as SixPointScotchActionError {
            #expect(e == .invalidPlayerCount)
        }
    }

    @Test func pressWhenLevelThrows() throws {
        var engine = SixPointScotchEngine()
        // Level → no trailing team → press not allowed
        do {
            _ = try engine.scoreHole(scotchInput(hole: 1, aNet: [4, 4], bNet: [4, 4], pressBy: .teamA))
            #expect(Bool(false), "Expected pressRequiresTrailingTeam")
        } catch let e as SixPointScotchActionError {
            #expect(e == .pressRequiresTrailingTeam)
        }
    }

    @Test func rerollRequiresLeadingTeamThrows() throws {
        var engine = SixPointScotchEngine()
        // After hole 1: B leads, A trails
        _ = try engine.scoreHole(bWinsHole(hole: 1))
        // A trails → A may roll; B leads → B may reroll
        // Try re-roll by A (trailing = wrong team for reroll)
        do {
            _ = try engine.scoreHole(scotchInput(hole: 2, aNet: [5, 5], bNet: [4, 4], rollBy: .teamA, rerollBy: .teamA))
            #expect(Bool(false), "Expected rerollRequiresLeadingTeam")
        } catch let e as SixPointScotchActionError {
            #expect(e == .rerollRequiresLeadingTeam)
        }
    }
}

// MARK: - Prox GIR Enforcement

struct SixPointScotchProxTests {

    @Test func proxIgnoredWhenNeitherTeamHasGIR() throws {
        var engine = SixPointScotchEngine()
        // Par 4, all nets = 5 → no GIR (net > par). Prox distances present but irrelevant.
        let out = try engine.scoreHole(scotchInput(
            hole: 1, par: 4,
            aNet: [5, 6], bNet: [5, 6],
            aProx: 2.0, bProx: 10.0
        ))
        // Ties on everything → 0/0
        #expect(out.rawTeamAPoints == 0)
        #expect(out.rawTeamBPoints == 0)
        let proxEntry = out.auditLog.first(where: { $0.hasPrefix("Prox:") })
        #expect(proxEntry == nil)
    }

    @Test func proxAwardedToGIREligibleTeamEvenWhenFurtherAway() throws {
        var engine = SixPointScotchEngine()
        // Par 4: A gross [4, 5] → 4 ≤ 4 → natural GIR eligible
        //        B gross [5, 6] → none ≤ 4 → NOT eligible
        // B is closer in feet but ineligible → A wins prox
        let out = try engine.scoreHole(scotchInput(
            hole: 1, par: 4,
            aNet: [4, 5], bNet: [5, 6],
            aProx: 30.0, bProx: 2.0
        ))
        let proxEntry = out.auditLog.first(where: { $0.hasPrefix("Prox:") })
        #expect(proxEntry == "Prox: teamA (1)")
    }

    @Test func proxWonByCloserTeamWhenBothHaveGIR() throws {
        var engine = SixPointScotchEngine()
        // Both teams have natural GIR (gross ≤ par), B closer → B wins prox
        let out = try engine.scoreHole(scotchInput(
            hole: 1, par: 4,
            aNet: [4, 5], bNet: [4, 5],
            aProx: 20.0, bProx: 5.0
        ))
        let proxEntry = out.auditLog.first(where: { $0.hasPrefix("Prox:") })
        #expect(proxEntry == "Prox: teamB (1)")
    }

    @Test func proxIneligibleWhenGrossBogeyButNetPar() throws {
        var engine = SixPointScotchEngine()
        // Par 4: A gross [5, 6] (bogey + worse) but net [4, 5] via handicap stroke.
        // Natural GIR requires gross ≤ par — a handicap-assisted net par does NOT qualify.
        // Old net-based rule would award prox to A; gross-based rule must not.
        let out = try engine.scoreHole(scotchInput(
            hole: 1, par: 4,
            aNet: [4, 5], bNet: [5, 6],
            aGross: [5, 6], bGross: [6, 7],
            aProx: 3.0
        ))
        let proxEntry = out.auditLog.first(where: { $0.hasPrefix("Prox:") })
        #expect(proxEntry == nil, "Gross bogey with handicap stroke should not qualify for prox")
    }
}

// MARK: - Running Totals

struct SixPointScotchRunningTotalsTests {

    @Test func frontNineTotalsAccumulateCorrectly() throws {
        var engine = SixPointScotchEngine()
        // Hole 1: A wins low man + low team = 4 raw pts (no birdie: gross [4,5] on par 4)
        let out1 = try engine.scoreHole(scotchInput(hole: 1, aNet: [4, 5], bNet: [6, 7]))
        #expect(out1.frontNineTeamA == 4)
        #expect(out1.frontNineTeamB == 0)
        #expect(out1.totalTeamA == 4)

        // Hole 2: B wins low man + low team = 4 raw pts (no birdie: gross [6,7] on par 4)
        let out2 = try engine.scoreHole(scotchInput(hole: 2, aNet: [6, 7], bNet: [4, 5]))
        #expect(out2.frontNineTeamA == 4)   // A's front unchanged
        #expect(out2.frontNineTeamB == 4)   // B adds 4
        #expect(out2.totalTeamA == 4)
        #expect(out2.totalTeamB == 4)
    }

    @Test func backNineTotalsTrackedSeparatelyFromFront() throws {
        var engine = SixPointScotchEngine()
        // A wins front hole 1 (4 raw pts — no birdie)
        _ = try engine.scoreHole(scotchInput(hole: 1, aNet: [4, 5], bNet: [6, 7]))
        // B wins back hole 10 (4 raw pts — no birdie)
        let out = try engine.scoreHole(scotchInput(hole: 10, aNet: [6, 7], bNet: [4, 5]))
        #expect(out.frontNineTeamA == 4)
        #expect(out.frontNineTeamB == 0)
        #expect(out.backNineTeamA == 0)
        #expect(out.backNineTeamB == 4)
        #expect(out.totalTeamA == 4)
        #expect(out.totalTeamB == 4)
    }

    @Test func multipliedPointsAddedToRunningTotal() throws {
        var engine = SixPointScotchEngine()
        // Hole 1: B wins → A trails
        _ = try engine.scoreHole(bWinsHole(hole: 1))
        // Hole 2: A presses (×2), A wins low man + low team = 4 raw → 8 multiplied
        // No birdie: gross [4,4] on par 4
        let out = try engine.scoreHole(scotchInput(hole: 2, aNet: [4, 4], bNet: [6, 7], pressBy: .teamA))
        #expect(out.multiplier == 2)
        #expect(out.multipliedTeamAPoints == 8)
        #expect(out.frontNineTeamA == out.multipliedTeamAPoints)
    }
}

// MARK: - Low Man Tie Rules

struct SixPointScotchLowManTieTests {

    @Test func lowManTieAcrossTeamsAwardsNoLowManPoints() throws {
        var engine = SixPointScotchEngine()
        // Low net ties at 4 (A1 and B1) -> no low-man points.
        // Team A still wins low-team 2 points (4+5 vs 4+6).
        let out = try engine.scoreHole(scotchInput(
            hole: 1, par: 4,
            aNet: [4, 5], bNet: [4, 6],
            aGross: [4, 5], bGross: [4, 6]
        ))
        #expect(out.rawTeamAPoints == 2)
        #expect(out.rawTeamBPoints == 0)
        let lowManEntry = out.auditLog.first(where: { $0.hasPrefix("Low Man:") })
        #expect(lowManEntry == nil)
    }

    @Test func lowManTieWithinSameTeamAwardsNoLowManPoints() throws {
        var engine = SixPointScotchEngine()
        // Team A players tie for lowest net at 4 -> no low-man points.
        // Team A still wins low-team 2 points (4+4 vs 5+6).
        let out = try engine.scoreHole(scotchInput(
            hole: 1, par: 4,
            aNet: [4, 4], bNet: [5, 6],
            aGross: [4, 4], bGross: [5, 6]
        ))
        #expect(out.rawTeamAPoints == 2)
        #expect(out.rawTeamBPoints == 0)
        let lowManEntry = out.auditLog.first(where: { $0.hasPrefix("Low Man:") })
        #expect(lowManEntry == nil)
    }
}

// MARK: - Bucket Tie Rules

struct SixPointScotchBucketRuleTests {

    @Test func lowTeamTieAwardsNoLowTeamPoints() throws {
        var engine = SixPointScotchEngine()
        // Team totals tie (4+5 vs 3+6 -> 9/9), so no low-team points.
        // Team B has unique low man (3), so B gets only 2.
        let out = try engine.scoreHole(scotchInput(
            hole: 1, par: 4,
            aNet: [4, 5], bNet: [3, 6],
            aGross: [4, 5], bGross: [3, 6]
        ))
        #expect(out.rawTeamAPoints == 0)
        #expect(out.rawTeamBPoints == 2)
        let lowTeamEntry = out.auditLog.first(where: { $0.hasPrefix("Low Team:") })
        #expect(lowTeamEntry == nil)
    }

    @Test func proxTieAwardsNoProxPoints() throws {
        var engine = SixPointScotchEngine()
        // Both teams GIR-eligible and exact same prox distance -> no prox point.
        let out = try engine.scoreHole(scotchInput(
            hole: 1, par: 3,
            aNet: [3, 4], bNet: [4, 5],
            aGross: [3, 4], bGross: [4, 5],
            aProx: 6.0, bProx: 6.0
        ))
        let proxEntry = out.auditLog.first(where: { $0.hasPrefix("Prox:") })
        #expect(proxEntry == nil)
    }

    @Test func naturalBirdiePushWhenBothTeamsHaveBirdie() throws {
        var engine = SixPointScotchEngine()
        // Both teams make natural birdie (3 on par 4): birdie bucket pushes (0 points).
        // Low man ties at 3, low team ties at 7 -> no low-man/low-team points.
        let out = try engine.scoreHole(scotchInput(
            hole: 1, par: 4,
            aNet: [3, 4], bNet: [3, 4],
            aGross: [3, 4], bGross: [3, 4]
        ))
        #expect(out.rawTeamAPoints == 0)
        #expect(out.rawTeamBPoints == 0)
        let birdieEntry = out.auditLog.first(where: { $0.hasPrefix("Birdie:") })
        #expect(birdieEntry == nil)
    }
}

// MARK: - Back Nine Press Independence

struct SixPointScotchBackNineTests {

    @Test func backNinePressLimitIsIndependentOfFrontNine() throws {
        var engine = SixPointScotchEngine()
        // Exhaust front nine press limit (2 presses)
        _ = try engine.scoreHole(bWinsHole(hole: 1))
        _ = try engine.scoreHole(bWinsHole(hole: 2, pressBy: .teamA))
        _ = try engine.scoreHole(bWinsHole(hole: 3, pressBy: .teamA))
        for hole in 4...9 { _ = try engine.scoreHole(bWinsHole(hole: hole)) }

        // Back nine starts fresh — score one hole to make A trail on back 9
        _ = try engine.scoreHole(bWinsHole(hole: 10))

        // A can now press on back nine (back nine usedPresses = 0)
        let out = try engine.scoreHole(bWinsHole(hole: 11, pressBy: .teamA))
        #expect(out.multiplier == 2)   // Press took effect
    }

    @Test func frontNinePressDoesNotCarryToBackNine() throws {
        var engine = SixPointScotchEngine()
        // A presses on front nine
        _ = try engine.scoreHole(bWinsHole(hole: 1))
        _ = try engine.scoreHole(bWinsHole(hole: 2, pressBy: .teamA))
        for hole in 3...9 { _ = try engine.scoreHole(bWinsHole(hole: hole)) }

        // Back nine: no press yet → multiplier should be ×1
        let out = try engine.scoreHole(bWinsHole(hole: 10))
        #expect(out.multiplier == 1)
    }
}

// MARK: - Umbrella + Multiplier

struct SixPointScotchUmbrellaTests {

    @Test func umbrellaWithPressMultipliesToTwentyFour() throws {
        var engine = SixPointScotchEngine()
        // Hole 1: B wins → A trails
        _ = try engine.scoreHole(bWinsHole(hole: 1))
        // Hole 2: A presses (×2), A sweeps all buckets (umbrella = 12 raw) → 24 final
        // par 5: A gross [4, 5] → birdie (4 on par 5). A net lowest. A has prox.
        let out = try engine.scoreHole(scotchInput(
            hole: 2, par: 5,
            aNet: [3, 4], bNet: [6, 7],
            aGross: [4, 5], bGross: [6, 7],
            aProx: 5.0, bProx: nil,
            pressBy: .teamA
        ))
        #expect(out.rawTeamAPoints == 12)      // umbrella
        #expect(out.multiplier == 2)            // 1 press
        #expect(out.multipliedTeamAPoints == 24)
    }

    @Test func umbrellaNotTriggeredWhenTeamWinsFivePoints() throws {
        // Umbrella requires exactly all 6 raw points (both low man + low team + birdie + prox)
        // If only 5 (no prox, win other 3) → not umbrella
        var engine = SixPointScotchEngine()
        let out = try engine.scoreHole(scotchInput(
            hole: 1, par: 5,
            aNet: [3, 4], bNet: [6, 7],
            aGross: [4, 5], bGross: [6, 7],
            aProx: nil, bProx: nil   // no prox → A gets 5 raw (low man 2 + low team 2 + birdie 1)
        ))
        #expect(out.rawTeamAPoints == 5)   // no umbrella
        #expect(out.multipliedTeamAPoints == 5)
    }
}

// MARK: - Audit Log

struct SixPointScotchAuditLogTests {

    @Test func auditLogContainsHoleMarkerForEachHole() throws {
        var engine = SixPointScotchEngine()
        _ = try engine.scoreHole(bWinsHole(hole: 1))
        let out = try engine.scoreHole(bWinsHole(hole: 2))
        #expect(out.auditLog.contains("Hole 1"))
        #expect(out.auditLog.contains("Hole 2"))
    }

    @Test func auditLogContainsPressEntry() throws {
        var engine = SixPointScotchEngine()
        _ = try engine.scoreHole(bWinsHole(hole: 1))
        let out = try engine.scoreHole(bWinsHole(hole: 2, pressBy: .teamA))
        let pressEntry = out.auditLog.first(where: { $0.hasPrefix("Press by") })
        #expect(pressEntry != nil)
        #expect(pressEntry?.contains("teamA") == true)
    }

    @Test func auditLogContainsMultiplierLine() throws {
        var engine = SixPointScotchEngine()
        let out = try engine.scoreHole(bWinsHole(hole: 1))
        let multiplierEntry = out.auditLog.first(where: { $0.hasPrefix("Multiplier=") })
        #expect(multiplierEntry != nil)
    }

    @Test func auditLogContainsUmbrellaEntry() throws {
        var engine = SixPointScotchEngine()
        // A sweeps all (par 5, A has birdie + prox + low man + low team)
        let out = try engine.scoreHole(scotchInput(
            hole: 1, par: 5,
            aNet: [3, 4], bNet: [6, 7],
            aGross: [4, 5], bGross: [6, 7],
            aProx: 5.0
        ))
        let umbrellaEntry = out.auditLog.first(where: { $0.hasPrefix("Umbrella:") })
        #expect(umbrellaEntry != nil)
    }
}
