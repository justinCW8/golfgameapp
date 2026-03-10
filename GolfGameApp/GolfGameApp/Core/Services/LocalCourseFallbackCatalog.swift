import Foundation

/// Local fallback catalog for courses that may be absent in the upstream API.
/// Keep entries minimal and sourced from publicly available scorecard data.
enum LocalCourseFallbackCatalog {
    static func search(query: String) -> [CourseAPIResult] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }
        let tokens = normalizedQuery.split(separator: " ").map(String.init)

        return allCourses.filter { course in
            let aliases = aliasesByCourseID[course.id, default: []].joined(separator: " ")
            let haystack = normalize("\(course.clubName) \(course.courseName) \(course.city) \(course.state) \(aliases)")
            if haystack.contains(normalizedQuery) { return true }
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    private static let allCourses: [CourseAPIResult] = [
        laGrangeCountryClub
    ]

    private static let aliasesByCourseID: [Int: [String]] = [
        9_000_001: [
            "la grange country club",
            "lagrange country club",
            "la grange cc",
            "60525"
        ]
    ]

    // Source notes (March 2026):
    // - Public scorecard/rating listing for La Grange Country Club (La Grange, IL)
    private static let laGrangeCountryClub = CourseAPIResult(
        id: 9_000_001,
        clubName: "La Grange Country Club",
        courseName: "La Grange",
        city: "La Grange",
        state: "IL",
        teeRatings: [
            "Blue": TeeRating(rating: 72.4, slope: 127),
            "White": TeeRating(rating: 71.1, slope: 124),
            "Red": TeeRating(rating: 68.9, slope: 120)
        ],
        holesByTee: [
            "Blue": makeHoles(yardages: [379, 537, 431, 193, 573, 432, 571, 229, 143, 513, 413, 315, 364, 182, 392, 400, 166, 452]),
            "White": makeHoles(yardages: [370, 525, 416, 176, 560, 417, 554, 188, 126, 500, 404, 305, 361, 173, 369, 391, 152, 436]),
            "Red": makeHoles(yardages: [353, 506, 407, 141, 457, 409, 497, 152, 104, 478, 337, 291, 351, 128, 363, 348, 101, 428])
        ]
    )

    private static func makeHoles(yardages: [Int]) -> [ScannedHole] {
        let pars = [4, 5, 4, 3, 5, 4, 5, 3, 3, 5, 4, 4, 4, 3, 4, 4, 3, 4]
        let strokeIndexes = [1, 3, 5, 7, 9, 11, 13, 15, 17, 2, 4, 6, 8, 10, 12, 14, 16, 18]
        return yardages.enumerated().map { idx, yardage in
            ScannedHole(number: idx + 1, par: pars[idx], strokeIndex: strokeIndexes[idx], yardage: yardage)
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
