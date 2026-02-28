//
//  GolfGameAppTests.swift
//  GolfGameAppTests
//
//  Created by juswaite on 2/27/26.
//

import Testing
@testable import GolfGameApp

struct GolfGameAppTests {

    @Test func tieWipesOutBucket() async throws {
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
                requestRerollBy: nil,
                leaderTeedOff: false,
                trailerTeedOff: false
            )
        )

        #expect(output.rawTeamAPoints == 0)
        #expect(output.rawTeamBPoints == 0)
    }

    @Test func umbrellaDoublesToTwelveRaw() async throws {
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
                requestRerollBy: nil,
                leaderTeedOff: false,
                trailerTeedOff: false
            )
        )

        #expect(output.rawTeamAPoints == 12)
        #expect(output.multipliedTeamAPoints == 12)
    }

    @Test func pressMaximumTwoPerNine() async throws {
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

    @Test func pressEligibilityEnforcedForTrailingTeam() async throws {
        var engine = SixPointScotchEngine()
        _ = try engine.scoreHole(trailingHole(hole: 1))

        do {
            _ = try engine.scoreHole(trailingHole(hole: 2, requestPressBy: .teamB))
            #expect(Bool(false), "Expected trailing team enforcement error")
        } catch let error as SixPointScotchActionError {
            #expect(error == .pressRequiresTrailingTeam)
        }
    }

    @Test func rollAndRerollStackMultiplier() async throws {
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
                requestRerollBy: .teamB,
                leaderTeedOff: true,
                trailerTeedOff: false
            )
        )

        #expect(output.rawTeamBPoints == 5)
        #expect(output.multiplier == 16)
        #expect(output.multipliedTeamBPoints == 80)
    }

    @Test func naturalBirdieUsesParReference() async throws {
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
                requestRerollBy: nil,
                leaderTeedOff: false,
                trailerTeedOff: false
            )
        )

        #expect(output.rawTeamAPoints == 1)
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
        requestRerollBy: nil,
        leaderTeedOff: false,
        trailerTeedOff: false
    )
}
