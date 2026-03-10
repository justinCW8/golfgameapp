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

enum CourseSearchError: LocalizedError {
    case missingAPIKey
    case unauthorized
    case serviceUnavailable(statusCode: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Course search is not configured. Add a valid key to Secrets.golfCourseAPIKey."
        case .unauthorized:
            return "Course search authorization failed. Check the GolfCourseAPI key."
        case .serviceUnavailable(let statusCode):
            return "Course search failed (\(statusCode)). Please try again."
        case .invalidResponse:
            return "Course search returned an unexpected response."
        }
    }
}

// MARK: - Service

struct CourseSearchService {
    private static let apiKey  = Secrets.golfCourseAPIKey
    private static let baseURL = "https://api.golfcourseapi.com/v1"

    func search(query: String) async throws -> [CourseAPIResult] {
        let trimmedKey = Self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty || trimmedKey == "YOUR_GOLF_COURSE_API_KEY" {
            throw CourseSearchError.missingAPIKey
        }

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(Self.baseURL)/search?search_query=\(encoded)")
        else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Key \(trimmedKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CourseSearchError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw CourseSearchError.unauthorized
            }
            throw CourseSearchError.serviceUnavailable(statusCode: http.statusCode)
        }

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
                ScannedHole(number: idx + 1, par: hole.par, strokeIndex: hole.handicap, yardage: hole.yardage)
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
    let yardage: Int
    let handicap: Int   // stroke index in the API
}
