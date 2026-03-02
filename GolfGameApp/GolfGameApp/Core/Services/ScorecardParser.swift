import Foundation

struct ScannedHole {
    var number: Int
    var par: Int?
    var strokeIndex: Int?
}

struct ScannedCourseData {
    var holes: [ScannedHole]
    var slope: Int?
    var courseRating: Double?

    static var empty: ScannedCourseData {
        ScannedCourseData(
            holes: (1...18).map { ScannedHole(number: $0, par: nil, strokeIndex: nil) },
            slope: nil,
            courseRating: nil
        )
    }
}

struct ScorecardParser {
    func parse(_ lines: [String]) -> ScannedCourseData {
        var result = ScannedCourseData.empty

        // Flatten all lines into a single searchable string array
        // and extract numbers from each line for table row matching.
        let normalized = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        result.slope = extractSlope(from: normalized)
        result.courseRating = extractRating(from: normalized)

        let parValues = extractRow(labeled: ["par", "Par", "PAR"], from: normalized, validRange: 3...5)
        let siValues  = extractRow(labeled: ["hcp", "HCP", "hdcp", "Hcp", "HDCP", "Handicap", "handicap", "SI", "si", "Stroke Index"], from: normalized, validRange: 1...18)

        if parValues.count >= 9 {
            for (idx, val) in parValues.prefix(18).enumerated() {
                result.holes[idx].par = val
            }
        }

        if siValues.count >= 9 {
            let values = Array(siValues.prefix(18))
            if isValidSI(values) {
                for (idx, val) in values.enumerated() {
                    result.holes[idx].strokeIndex = val
                }
            }
        }

        return result
    }

    // MARK: - Private

    private func extractRow(labeled labels: [String], from lines: [String], validRange: ClosedRange<Int>) -> [Int] {
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            let matchesLabel = labels.contains(where: { lower.contains($0.lowercased()) })
            guard matchesLabel else { continue }

            // Collect integers from this line and subsequent lines until we have 9–18 valid values
            var collected: [Int] = []
            let searchLines = Array(lines[i...].prefix(5))  // look ahead up to 5 lines
            for searchLine in searchLines {
                let nums = extractIntegers(from: searchLine).filter { validRange.contains($0) }
                collected.append(contentsOf: nums)
                if collected.count >= 18 { break }
            }
            if collected.count >= 9 { return collected }
        }
        return []
    }

    private func extractSlope(from lines: [String]) -> Int? {
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("slope") else { continue }
            let nums = extractIntegers(from: line).filter { (55...155).contains($0) }
            if let first = nums.first { return first }
        }
        return nil
    }

    private func extractRating(from lines: [String]) -> Double? {
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("rating") || lower.contains(" cr ") || lower.hasPrefix("cr ") else { continue }
            let decimals = extractDecimals(from: line).filter { (55.0...85.0).contains($0) }
            if let first = decimals.first { return first }
        }
        return nil
    }

    private func extractIntegers(from string: String) -> [Int] {
        // Match standalone integers (not part of decimals)
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
        let expected = values.count == 9 ? Set(1...9) : Set(1...18)
        return Set(values) == expected
    }
}
