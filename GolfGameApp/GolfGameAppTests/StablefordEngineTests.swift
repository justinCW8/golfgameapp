import Testing
@testable import GolfGameApp

struct StablefordEngineTests {

    // MARK: - Points Table

    @Test func albatrossOrBetterGivesFivePoints() {
        let out = StablefordEngine.scoreHole(.init(gross: 2, par: 5, handicapStrokes: 0))
        #expect(out.points == 5)
        #expect(out.net == 2)
    }

    @Test func doubleEagleGivesFivePoints() {
        // -3 or better → 5 pts
        let out = StablefordEngine.scoreHole(.init(gross: 1, par: 4, handicapStrokes: 0))
        #expect(out.points == 5)
    }

    @Test func eagleGivesFourPoints() {
        let out = StablefordEngine.scoreHole(.init(gross: 3, par: 5, handicapStrokes: 0))
        #expect(out.points == 4)
        #expect(out.net == 3)
    }

    @Test func birdieGivesThreePoints() {
        let out = StablefordEngine.scoreHole(.init(gross: 4, par: 5, handicapStrokes: 0))
        #expect(out.points == 3)
        #expect(out.net == 4)
    }

    @Test func parGivesTwoPoints() {
        let out = StablefordEngine.scoreHole(.init(gross: 4, par: 4, handicapStrokes: 0))
        #expect(out.points == 2)
        #expect(out.net == 4)
    }

    @Test func bogeyGivesOnePoint() {
        let out = StablefordEngine.scoreHole(.init(gross: 5, par: 4, handicapStrokes: 0))
        #expect(out.points == 1)
        #expect(out.net == 5)
    }

    @Test func doubleGivesZeroPoints() {
        let out = StablefordEngine.scoreHole(.init(gross: 6, par: 4, handicapStrokes: 0))
        #expect(out.points == 0)
    }

    @Test func tripleOrWorseGivesZeroPoints() {
        let out = StablefordEngine.scoreHole(.init(gross: 12, par: 4, handicapStrokes: 0))
        #expect(out.points == 0)
    }

    // MARK: - Handicap Strokes

    @Test func oneHandicapStrokeConvertsBogeyToPar() {
        // Gross 5, par 4, 1 stroke → net 4 → par → 2 pts (not bogey/1 pt)
        let out = StablefordEngine.scoreHole(.init(gross: 5, par: 4, handicapStrokes: 1))
        #expect(out.net == 4)
        #expect(out.points == 2)
    }

    @Test func twoHandicapStrokesConvertDoubleToPar() {
        // Gross 6, par 4, 2 strokes → net 4 → par → 2 pts
        let out = StablefordEngine.scoreHole(.init(gross: 6, par: 4, handicapStrokes: 2))
        #expect(out.net == 4)
        #expect(out.points == 2)
    }

    @Test func handicapStrokeConvertsBogeyToBirdie() {
        // Gross 4, par 4, 1 stroke → net 3 → birdie → 3 pts
        let out = StablefordEngine.scoreHole(.init(gross: 4, par: 4, handicapStrokes: 1))
        #expect(out.net == 3)
        #expect(out.points == 3)
    }

    @Test func zeroHandicapStrokesLeavesNetUnchanged() {
        let out = StablefordEngine.scoreHole(.init(gross: 4, par: 4, handicapStrokes: 0))
        #expect(out.net == 4)
    }

    @Test func multipleStrokesAccumulateCorrectly() {
        // Gross 7, par 4, 3 strokes → net 4 → par → 2 pts
        let out = StablefordEngine.scoreHole(.init(gross: 7, par: 4, handicapStrokes: 3))
        #expect(out.net == 4)
        #expect(out.points == 2)
    }

    // MARK: - Par Variations

    @Test func par3ScoringWorks() {
        // Gross 2, par 3, 0 strokes → net 2, delta -1 → birdie → 3 pts
        let out = StablefordEngine.scoreHole(.init(gross: 2, par: 3, handicapStrokes: 0))
        #expect(out.points == 3)
    }

    @Test func par5WithBirdieAndStroke() {
        // Gross 4, par 5, 1 stroke → net 3, delta -2 → eagle → 4 pts
        let out = StablefordEngine.scoreHole(.init(gross: 4, par: 5, handicapStrokes: 1))
        #expect(out.net == 3)
        #expect(out.points == 4)
    }
}
