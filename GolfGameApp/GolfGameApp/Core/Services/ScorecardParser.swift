import Foundation

struct ScannedHole {
    var number: Int
    var par: Int?
    var strokeIndex: Int?
}

struct TeeRating {
    var rating: Double
    var slope: Int
}

struct ScannedCourseData {
    var holes: [ScannedHole]
    var slope: Int?
    var courseRating: Double?
    var teeRatings: [String: TeeRating] = [:]   // "Blue" -> TeeRating(71.6, 131)

    static var empty: ScannedCourseData {
        ScannedCourseData(
            holes: (1...18).map { ScannedHole(number: $0, par: nil, strokeIndex: nil) },
            slope: nil,
            courseRating: nil,
            teeRatings: [:]
        )
    }

    /// Merge another scan result into this one — only fills nil fields.
    mutating func merge(_ other: ScannedCourseData) {
        for idx in holes.indices {
            if holes[idx].par == nil { holes[idx].par = other.holes[idx].par }
            if holes[idx].strokeIndex == nil { holes[idx].strokeIndex = other.holes[idx].strokeIndex }
        }
        if slope == nil { slope = other.slope }
        if courseRating == nil { courseRating = other.courseRating }
        for (tee, rating) in other.teeRatings {
            if teeRatings[tee] == nil { teeRatings[tee] = rating }
        }
    }
}

struct ScorecardParser {
    func parse(_ lines: [String]) -> ScannedCourseData {
        var result = ScannedCourseData.empty

        let normalized = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        result.teeRatings = extractTeeRatings(from: normalized)

        // Use first found rating/slope as the default (overridden per-tee in UI)
        let (rating, slope) = extractRatingAndSlope(from: normalized, teeRatings: result.teeRatings)
        result.slope = slope
        result.courseRating = rating

        let parValues = extractRow(
            labeled: ["par", "Par", "PAR"],
            from: normalized,
            validRange: 3...5
        )
        let siValues = extractRow(
            labeled: ["hcp", "HCP", "hdcp", "Hcp", "HDCP", "Handicap", "handicap",
                      "Men's Handicap", "men's handicap", "SI", "si", "Stroke Index"],
            from: normalized,
            validRange: 1...18
        )

        // When we only extracted 9 values, detect whether this is the back nine (holes 10–18).
        // Full 18-value extractions always start at index 0.
        let holeOffset = parValues.count == 9 ? detectHoleOffset(from: normalized) : 0

        if parValues.count >= 9 {
            for (idx, val) in parValues.prefix(18).enumerated() {
                result.holes[holeOffset + idx].par = val
            }
        }

        if siValues.count >= 9 {
            let values = Array(siValues.prefix(18))
            if isValidSI(values) {
                let siOffset = values.count == 9 ? holeOffset : 0
                for (idx, val) in values.enumerated() {
                    result.holes[siOffset + idx].strokeIndex = val
                }
            }
        }

        return result
    }

    // MARK: - Private

    private func extractRow(labeled labels: [String], from lines: [String], validRange: ClosedRange<Int>) -> [Int] {
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard labels.contains(where: { lower.contains($0.lowercased()) }) else { continue }

            var collected: [Int] = []
            for searchLine in lines[i...].prefix(30) {
                let nums = extractIntegers(from: searchLine).filter { validRange.contains($0) }
                collected.append(contentsOf: nums)
                if collected.count >= 18 { break }
            }
            if collected.count >= 9 { return Array(collected.prefix(18)) }
        }
        return []
    }

    /// Returns 0 (front 9, holes 1–9) or 9 (back 9, holes 10–18).
    /// Looks for a "Hole" / "No." header row; if the first hole number found is ≥ 10, it's back nine.
    private func detectHoleOffset(from lines: [String]) -> Int {
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard lower.contains("hole") || lower.hasPrefix("no") else { continue }
            var collected: [Int] = []
            for searchLine in lines[i...].prefix(15) {
                let nums = extractIntegers(from: searchLine).filter { (1...18).contains($0) }
                collected.append(contentsOf: nums)
                if collected.count >= 3 { break }
            }
            if let first = collected.first {
                return first >= 10 ? 9 : 0
            }
        }
        return 0  // default: assume front nine
    }

    /// Parse all tee-specific rating/slope pairs from lines like:
    ///   "Blue  71.6/131"  or  "White 70.2/128"
    /// Also handles Vision splitting them across adjacent lines.
    func extractTeeRatings(from lines: [String]) -> [String: TeeRating] {
        var map: [String: TeeRating] = [:]
        let teeNames = ["blue", "white", "gold", "red", "green", "silver", "black"]
        let ratingPattern = #"(\d{2}\.\d)\s*/\s*(\d{2,3})"#
        guard let regex = try? NSRegularExpression(pattern: ratingPattern) else { return map }

        for (i, line) in lines.enumerated() {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            guard let match = regex.firstMatch(in: line, range: range),
                  let rRange = Range(match.range(at: 1), in: line),
                  let sRange = Range(match.range(at: 2), in: line),
                  let rating = Double(line[rRange]),
                  let slope = Int(line[sRange]),
                  (55.0...85.0).contains(rating),
                  (55...155).contains(slope)
            else { continue }

            // Check current line and adjacent lines for a tee name
            let context = [
                line,
                i > 0 ? lines[i - 1] : "",
                i + 1 < lines.count ? lines[i + 1] : ""
            ].map { $0.lowercased() }

            for teeName in teeNames {
                if context.contains(where: { $0.contains(teeName) }) {
                    let key = teeName.capitalized
                    if map[key] == nil {
                        map[key] = TeeRating(rating: rating, slope: slope)
                    }
                    break
                }
            }
        }
        return map
    }

    private func extractRatingAndSlope(
        from lines: [String],
        teeRatings: [String: TeeRating]
    ) -> (rating: Double?, slope: Int?) {
        // Prefer Blue → White → Gold → Red → Green order for the default
        let preferenceOrder = ["Blue", "White", "Gold", "Red", "Green"]
        for tee in preferenceOrder {
            if let tr = teeRatings[tee] { return (tr.rating, tr.slope) }
        }

        // Fallback: keyword-based search
        var rating: Double? = nil
        var slope: Int? = nil
        for line in lines {
            let lower = line.lowercased()
            if rating == nil && (lower.contains("rating") || lower.contains(" cr ")) {
                let decimals = extractDecimals(from: line).filter { (55.0...85.0).contains($0) }
                rating = decimals.first
            }
            if slope == nil && lower.contains("slope") {
                let nums = extractIntegers(from: line).filter { (55...155).contains($0) }
                slope = nums.first
            }
            if rating != nil && slope != nil { break }
        }
        return (rating, slope)
    }

    private func extractIntegers(from string: String) -> [Int] {
        let pattern = #"(?<!\d\.)\b(\d{1,3})\b(?!\.\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        return regex.matches(in: string, range: range).compactMap {
            guard let r = Range($0.range(at: 1), in: string) else { return nil }
            return Int(string[r])
        }
    }

    private func extractDecimals(from string: String) -> [Double] {
        let pattern = #"\d{2}\.\d"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        return regex.matches(in: string, range: range).compactMap {
            guard let r = Range($0.range, in: string) else { return nil }
            return Double(string[r])
        }
    }

    private func isValidSI(_ values: [Int]) -> Bool {
        guard values.count == 9 || values.count == 18 else { return false }
        // All values must be in 1...18 and all unique.
        // Front-9 scans have SI values drawn from the full 1...18 range (e.g. 11, 3, 7, 15...),
        // so we do NOT require the set to equal exactly {1...9} when count == 9.
        return values.allSatisfy({ (1...18).contains($0) }) && Set(values).count == values.count
    }
}
