import Foundation
import Testing
@testable import GolfGameApp

struct CourseSearchServiceTests {

    @Test func resolvedStrokeIndexesPreservesKnownValuesAndFillsMissingSlots() {
        let strokeIndexes = CourseSearchService.resolvedStrokeIndexes(
            from: [3, nil, 1, nil, 5, nil]
        )

        #expect(strokeIndexes == [3, 2, 1, 4, 5, 6])
    }

    @Test func resolvedStrokeIndexesTreatsDuplicateOrInvalidValuesAsMissing() {
        let strokeIndexes = CourseSearchService.resolvedStrokeIndexes(
            from: [1, 1, 9, nil, 3, 0]
        )

        #expect(strokeIndexes == [1, 2, 4, 5, 3, 6])
    }
}
