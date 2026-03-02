import Foundation

// MARK: - Public result type

struct CourseAPIResult: Identifiable {
    var id: Int
    var clubName: String
    var courseName: String
    var city: String
    var state: String
    var teeRatings: [String: TeeRating]       // "Blue" -> TeeRating
    var holesByTee: [String: [ScannedHole]]   // "Blue" -> 18 ScannedHoles

    var displayName: String {
        if courseName.isEmpty || courseName.caseInsensitiveCompare(clubName) == .orderedSame {
            return clubName
        }
        return "\(clubName) — \(courseName)"
    }

    var location: String { "\(city), \(state)" }

    /// Returns holes for the requested tee, falling back to any available tee.
    func holes(forTee tee: String) -> [ScannedHole] {
        holesByTee[tee] ?? holesByTee.values.first ?? ScannedCourseData.empty.holes
    }
}

// MARK: - Service

struct CourseSearchService {
    private static let apiKey  = "44NKISNQ3O6TN72ANO62K5KDOM"
    private static let baseURL = "https://api.golfcourseapi.com/v1"

    func search(query: String) async throws -> [CourseAPIResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(Self.baseURL)/search?search_query=\(encoded)")
        else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Key \(Self.apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }

        let decoded = try JSONDecoder().decode(GolfAPIResponse.self, from: data)
        return decoded.courses.map { convert($0) }
    }

    private func convert(_ course: GolfAPICourse) -> CourseAPIResult {
        // Prefer men's tees; fall back to women's tees.
        let teeSets = course.tees.male ?? course.tees.female ?? []

        var teeRatings: [String: TeeRating] = [:]
        var holesByTee: [String: [ScannedHole]] = [:]

        for teeSet in teeSets where teeSet.holes.count == 18 {
            let key = teeSet.teeName
            teeRatings[key] = TeeRating(rating: teeSet.courseRating, slope: teeSet.slopeRating)
            holesByTee[key] = teeSet.holes.enumerated().map { idx, hole in
                ScannedHole(number: idx + 1, par: hole.par, strokeIndex: hole.handicap)
            }
        }

        return CourseAPIResult(
            id: course.id,
            clubName: course.clubName,
            courseName: course.courseName,
            city: course.location.city,
            state: course.location.state,
            teeRatings: teeRatings,
            holesByTee: holesByTee
        )
    }
}

// MARK: - Private Decodable types

private struct GolfAPIResponse: Decodable {
    let courses: [GolfAPICourse]
}

private struct GolfAPICourse: Decodable {
    let id: Int
    let clubName: String
    let courseName: String
    let location: GolfAPILocation
    let tees: GolfAPITees

    enum CodingKeys: String, CodingKey {
        case id, location, tees
        case clubName  = "club_name"
        case courseName = "course_name"
    }
}

private struct GolfAPILocation: Decodable {
    let city: String
    let state: String
}

private struct GolfAPITees: Decodable {
    let male: [GolfAPITeeSet]?
    let female: [GolfAPITeeSet]?
}

private struct GolfAPITeeSet: Decodable {
    let teeName: String
    let courseRating: Double
    let slopeRating: Int
    let holes: [GolfAPIHole]

    enum CodingKeys: String, CodingKey {
        case holes
        case teeName     = "tee_name"
        case courseRating = "course_rating"
        case slopeRating  = "slope_rating"
    }
}

private struct GolfAPIHole: Decodable {
    let par: Int
    let handicap: Int   // stroke index in the API
}
