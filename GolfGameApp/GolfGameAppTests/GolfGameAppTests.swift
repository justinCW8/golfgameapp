//
//  GolfGameAppTests.swift
//  GolfGameAppTests
//
//  Created by juswaite on 2/27/26.
//

import Testing
@testable import GolfGameApp

struct GolfGameAppTests {

    @Test func tieWipesOutBucket() throws {
        var engine = SixPointScotchEngine()
        let output = try engine.scoreHole(
            .init(
                holeNumber: 1,
                par: 4,
                teamANetScores: [4, 5],
                teamBNetScores: [4, 5],
                teamAGrossScores: [4, 5],
                teamBGrossScores: [4, 5],
                teamAProxFeet: nil,
                teamBProxFeet: nil,
                requestPressBy: nil,
                requestRollBy: nil,
                requestRerollBy: nil
            )
        )

        #expect(output.rawTeamAPoints == 0)
        #expect(output.rawTeamBPoints == 0)
    }

    @Test func umbrellaDoublesToTwelveRaw() throws {
        var engine = SixPointScotchEngine()
        let output = try engine.scoreHole(
            .init(
                holeNumber: 1,
                par: 4,
                teamANetScores: [3, 4],
                teamBNetScores: [5, 6],
                teamAGrossScores: [3, 4],
                teamBGrossScores: [5, 6],
                teamAProxFeet: 6,
                teamBProxFeet: 20,
                requestPressBy: nil,
                requestRollBy: nil,
                requestRerollBy: nil
            )
        )

        #expect(output.rawTeamAPoints == 12)
        #expect(output.multipliedTeamAPoints == 12)
    }

    @Test func pressMaximumTwoPerNine() throws {
        var engine = SixPointScotchEngine()

        _ = try engine.scoreHole(trailingHole(hole: 1))
        _ = try engine.scoreHole(trailingHole(hole: 2, requestPressBy: .teamA))
        _ = try engine.scoreHole(trailingHole(hole: 3, requestPressBy: .teamA))

        do {
            _ = try engine.scoreHole(trailingHole(hole: 4, requestPressBy: .teamA))
            #expect(Bool(false), "Expected press limit error")
        } catch let error as SixPointScotchActionError {
            #expect(error == .pressLimitReached)
        }
    }

    @Test func pressEligibilityEnforcedForTrailingTeam() throws {
        var engine = SixPointScotchEngine()
        _ = try engine.scoreHole(trailingHole(hole: 1))

        do {
            _ = try engine.scoreHole(trailingHole(hole: 2, requestPressBy: .teamB))
            #expect(Bool(false), "Expected trailing team enforcement error")
        } catch let error as SixPointScotchActionError {
            #expect(error == .pressRequiresTrailingTeam)
        }
    }

    @Test func rollAndRerollStackMultiplier() throws {
        var engine = SixPointScotchEngine()
        _ = try engine.scoreHole(trailingHole(hole: 1))
        _ = try engine.scoreHole(trailingHole(hole: 2, requestPressBy: .teamA))
        _ = try engine.scoreHole(trailingHole(hole: 3, requestPressBy: .teamA))

        let output = try engine.scoreHole(
            .init(
                holeNumber: 4,
                par: 4,
                teamANetScores: [4, 4],
                teamBNetScores: [3, 4],
                teamAGrossScores: [4, 4],
                teamBGrossScores: [3, 4],
                teamAProxFeet: nil,
                teamBProxFeet: nil,
                requestPressBy: nil,
                requestRollBy: .teamA,
                requestRerollBy: .teamB
            )
        )

        #expect(output.rawTeamBPoints == 5)
        #expect(output.multiplier == 16)
        #expect(output.multipliedTeamBPoints == 80)
    }

    @Test func naturalBirdieUsesParReference() throws {
        var engine = SixPointScotchEngine()
        let output = try engine.scoreHole(
            .init(
                holeNumber: 1,
                par: 5,
                teamANetScores: [5, 5],
                teamBNetScores: [5, 5],
                teamAGrossScores: [4, 6],
                teamBGrossScores: [5, 6],
                teamAProxFeet: nil,
                teamBProxFeet: nil,
                requestPressBy: nil,
                requestRollBy: nil,
                requestRerollBy: nil
            )
        )

        #expect(output.rawTeamAPoints == 1)
        #expect(output.rawTeamBPoints == 0)
    }

    @Test func pressAppliesStartingOnCurrentHole() throws {
        var engine = SixPointScotchEngine()
        for hole in 1...6 {
            _ = try engine.scoreHole(trailingHole(hole: hole))
        }

        let output = try engine.scoreHole(
            trailingHole(hole: 7, requestPressBy: .teamA)
        )

        #expect(output.multiplier == 2)
        #expect(output.multipliedTeamBPoints == 8)
    }

    @Test func rerollRequiresRoll() throws {
        var engine = SixPointScotchEngine()

        do {
            _ = try engine.scoreHole(
                .init(
                    holeNumber: 1,
                    par: 4,
                    teamANetScores: [4, 4],
                    teamBNetScores: [5, 5],
                    teamAGrossScores: [4, 4],
                    teamBGrossScores: [5, 5],
                    teamAProxFeet: nil,
                    teamBProxFeet: nil,
                    requestPressBy: nil,
                    requestRollBy: nil,
                    requestRerollBy: .teamA
                )
            )
            #expect(Bool(false), "Expected rerollRequiresRoll")
        } catch let error as SixPointScotchActionError {
            #expect(error == .rerollRequiresRoll)
        }
    }

    @Test func rollRequiresTrailingTeam() throws {
        var engine = SixPointScotchEngine()
        // After hole 1, B leads (A is trailing)
        _ = try engine.scoreHole(trailingHole(hole: 1))

        // B is leading — B cannot roll
        do {
            _ = try engine.scoreHole(
                .init(
                    holeNumber: 2,
                    par: 4,
                    teamANetScores: [5, 5],
                    teamBNetScores: [4, 4],
                    teamAGrossScores: [5, 5],
                    teamBGrossScores: [4, 4],
                    teamAProxFeet: nil,
                    teamBProxFeet: nil,
                    requestPressBy: nil,
                    requestRollBy: .teamB,
                    requestRerollBy: nil
                )
            )
            #expect(Bool(false), "Expected rollRequiresTrailingTeam")
        } catch let error as SixPointScotchActionError {
            #expect(error == .rollRequiresTrailingTeam)
        }
    }

    @Test func proxWinnerWithSingleEntry() throws {
        var engine = SixPointScotchEngine()
        let output = try engine.scoreHole(
            .init(
                holeNumber: 1,
                par: 4,
                teamANetScores: [4, 5],
                teamBNetScores: [4, 5],
                teamAGrossScores: [4, 5],
                teamBGrossScores: [4, 5],
                teamAProxFeet: 8.2,
                teamBProxFeet: nil,
                requestPressBy: nil,
                requestRollBy: nil,
                requestRerollBy: nil
            )
        )

        #expect(output.rawTeamAPoints == 1)
        #expect(output.rawTeamBPoints == 0)
    }

    @Test func birdieBucketTieWipesOut() throws {
        var engine = SixPointScotchEngine()
        let output = try engine.scoreHole(
            .init(
                holeNumber: 1,
                par: 5,
                teamANetScores: [5, 6],
                teamBNetScores: [5, 6],
                teamAGrossScores: [4, 6],
                teamBGrossScores: [4, 7],
                teamAProxFeet: nil,
                teamBProxFeet: nil,
                requestPressBy: nil,
                requestRollBy: nil,
                requestRerollBy: nil
            )
        )

        #expect(output.rawTeamAPoints == 0)
        #expect(output.rawTeamBPoints == 0)
    }
}

private func trailingHole(hole: Int, requestPressBy: TeamSide? = nil) -> SixPointScotchHoleInput {
    .init(
        holeNumber: hole,
        par: 4,
        teamANetScores: [5, 5],
        teamBNetScores: [4, 4],
        teamAGrossScores: [5, 5],
        teamBGrossScores: [4, 4],
        teamAProxFeet: nil,
        teamBProxFeet: nil,
        requestPressBy: requestPressBy,
        requestRollBy: nil,
        requestRerollBy: nil
    )
}
