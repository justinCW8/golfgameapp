import Testing
@testable import GolfGameApp

struct HandicapStrokeTests {

    // MARK: - Zero Handicap

    @Test func zeroHandicapGivesZeroStrokesOnEveryHole() {
        for si in 1...18 {
            #expect(strokeCountForHandicapIndex(0, onHoleStrokeIndex: si) == 0,
                    "Expected 0 strokes on SI \(si) for 0 handicap")
        }
    }

    // MARK: - Full Round Coverage

    @Test func handicap18GivesOneStrokeOnEveryHole() {
        for si in 1...18 {
            #expect(strokeCountForHandicapIndex(18, onHoleStrokeIndex: si) == 1,
                    "Expected 1 stroke on SI \(si) for handicap 18")
        }
    }

    @Test func handicap36GivesTwoStrokesOnEveryHole() {
        for si in 1...18 {
            #expect(strokeCountForHandicapIndex(36, onHoleStrokeIndex: si) == 2,
                    "Expected 2 strokes on SI \(si) for handicap 36")
        }
    }

    // MARK: - Partial Coverage

    @Test func handicap9GivesOneStrokeOnSI1Through9() {
        for si in 1...9 {
            #expect(strokeCountForHandicapIndex(9, onHoleStrokeIndex: si) == 1,
                    "Expected 1 stroke on SI \(si) for handicap 9")
        }
        for si in 10...18 {
            #expect(strokeCountForHandicapIndex(9, onHoleStrokeIndex: si) == 0,
                    "Expected 0 strokes on SI \(si) for handicap 9")
        }
    }

    @Test func handicap1GivesOneStrokeOnSI1Only() {
        #expect(strokeCountForHandicapIndex(1, onHoleStrokeIndex: 1) == 1)
        for si in 2...18 {
            #expect(strokeCountForHandicapIndex(1, onHoleStrokeIndex: si) == 0,
                    "Expected 0 strokes on SI \(si) for handicap 1")
        }
    }

    // MARK: - Mixed (base + remainder)

    @Test func handicap27GivesTwoStrokesOnSI1To9OneElsewhere() {
        // courseHandicap = 27, base = 1, remainder = 9
        // SI 1-9 → base + 1 = 2; SI 10-18 → base + 0 = 1
        for si in 1...9 {
            #expect(strokeCountForHandicapIndex(27, onHoleStrokeIndex: si) == 2,
                    "Expected 2 strokes on SI \(si) for handicap 27")
        }
        for si in 10...18 {
            #expect(strokeCountForHandicapIndex(27, onHoleStrokeIndex: si) == 1,
                    "Expected 1 stroke on SI \(si) for handicap 27")
        }
    }

    // MARK: - Decimal Truncation

    @Test func decimalHandicapTruncatedDown() {
        // 9.9 → courseHandicap = 9 (floor) → same as handicap 9
        for si in 1...9 {
            #expect(strokeCountForHandicapIndex(9.9, onHoleStrokeIndex: si) == 1)
        }
        for si in 10...18 {
            #expect(strokeCountForHandicapIndex(9.9, onHoleStrokeIndex: si) == 0)
        }
    }

    @Test func decimalJustBelowWholeNumberTruncates() {
        // 17.99 → courseHandicap = 17 (floor), remainder = 17
        // SI 1-17 → 1 stroke, SI 18 → 0 strokes
        for si in 1...17 {
            #expect(strokeCountForHandicapIndex(17.99, onHoleStrokeIndex: si) == 1)
        }
        #expect(strokeCountForHandicapIndex(17.99, onHoleStrokeIndex: 18) == 0)
    }

    // MARK: - Boundary / Edge Cases

    @Test func negativeHandicapClampedToZero() {
        // max(0, floor(-5)) = 0 → 0 strokes everywhere
        for si in 1...18 {
            #expect(strokeCountForHandicapIndex(-5, onHoleStrokeIndex: si) == 0,
                    "Expected 0 strokes on SI \(si) for negative handicap")
        }
    }

    @Test func strokeIndexOneAlwaysGetsFirstExtraStroke() {
        // Any handicap ≥ 1 gives a stroke on SI 1
        #expect(strokeCountForHandicapIndex(1, onHoleStrokeIndex: 1) == 1)
        #expect(strokeCountForHandicapIndex(5, onHoleStrokeIndex: 1) == 1)
        #expect(strokeCountForHandicapIndex(18, onHoleStrokeIndex: 1) == 1)
    }

    @Test func strokeIndex18IsLastToReceiveStroke() {
        // handicap 17 → remainder = 17 → SI 1-17 get stroke, SI 18 does not
        #expect(strokeCountForHandicapIndex(17, onHoleStrokeIndex: 17) == 1)
        #expect(strokeCountForHandicapIndex(17, onHoleStrokeIndex: 18) == 0)
        // handicap 18 → SI 18 gets stroke too
        #expect(strokeCountForHandicapIndex(18, onHoleStrokeIndex: 18) == 1)
    }
}
