import SwiftUI
import Combine
import UIKit
import PhotosUI

// MARK: - Shared course-setup types used by Round, Stableford, and Saturday flows.
// ScanViewModel, ImagePicker, and HoleReviewRow are declared once here (internal) so
// each feature file can use them without redeclaring private copies.

enum CourseReviewLayout {
    static let holeColumnWidth: CGFloat = 34
    static let yardageColumnWidth: CGFloat = 72
    static let controlColumnWidth: CGFloat = 126
    static let rowSpacing: CGFloat = 12
}

enum CourseTeePickerLayout {
    static let segmentedThreshold = 4
}

func formattedCurrencyAmount(_ amount: Double) -> String {
    let roundedToCents = (amount * 100).rounded() / 100
    if roundedToCents == roundedToCents.rounded() {
        return String(format: "%.0f", roundedToCents)
    }
    return String(format: "%.2f", roundedToCents)
}

// MARK: - ScanViewModel

@MainActor
final class ScanViewModel: ObservableObject {
    enum Step { case initial, reviewing }

    @Published var step: Step = .initial
    @Published var scannedData: ScannedCourseData = .empty
    @Published var courseName: String = ""
    @Published var teeColor: String = "White"
    @Published var slopeText: String = ""
    @Published var ratingText: String = ""
    @Published var isProcessing: Bool = false
    @Published var showCamera: Bool = false
    @Published var photoPickerItem: PhotosPickerItem? = nil
    @Published var mergePhotoItem: PhotosPickerItem? = nil

    // Course search
    @Published var searchQuery: String = ""
    @Published var apiResults: [CourseAPIResult] = []
    @Published var isSearching: Bool = false
    @Published var searchErrorMessage: String? = nil
    @Published private(set) var hasSearchedCurrentQuery: Bool = false
    private var searchTask: Task<Void, Never>? = nil
    private var apiHolesByTee: [String: [ScannedHole]] = [:]

    private let scanner = ScorecardScanner()
    private let parser = ScorecardParser()
    private let courseSearch = CourseSearchService()

    private static let fallbackTeeOptions = ["Blue", "White", "Gold", "Red"]
    private static let teePreferenceOrder = ["Black", "Purple", "Orange", "Blue", "White +", "White", "Gold", "Teal", "Silver", "Green", "Red"]

    var isValid: Bool {
        let allFilled = scannedData.holes.allSatisfy { $0.par != nil && $0.strokeIndex != nil }
        let siValues = scannedData.holes.compactMap { $0.strokeIndex }
        let noDuplicates = siValues.count == Set(siValues).count
        return allFilled && noDuplicates && !courseName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var duplicateSI: Set<Int> {
        let siValues = scannedData.holes.compactMap { $0.strokeIndex }
        var seen = Set<Int>()
        var dupes = Set<Int>()
        for v in siValues { if !seen.insert(v).inserted { dupes.insert(v) } }
        return dupes
    }

    var slope: Int? { Int(slopeText) }
    var courseRating: Double? { Double(ratingText) }
    var totalYardage: Int {
        scannedData.holes.compactMap(\.yardage).reduce(0, +)
    }
    var availableTeeOptions: [String] {
        let teeKeys = Array(scannedData.teeRatings.keys)
        guard !teeKeys.isEmpty else { return Self.fallbackTeeOptions }
        return Self.sortedTeeOptions(teeKeys)
    }

    func processImage(_ image: UIImage) async {
        apiHolesByTee = [:]
        isProcessing = true
        let lines = await scanner.recognizeText(in: image)
        let parsed = parser.parse(lines)
        scannedData = parsed
        applyRatingForCurrentTee(from: parsed)
        isProcessing = false
        step = .reviewing
    }

    func mergeImage(_ image: UIImage) async {
        isProcessing = true
        let lines = await scanner.recognizeText(in: image)
        let parsed = parser.parse(lines)
        scannedData.merge(parsed)
        applyRatingForCurrentTee(from: scannedData)
        isProcessing = false
    }

    func updateRatingForTee(_ newTee: String) {
        if let tr = scannedData.teeRatings[newTee] {
            slopeText = String(tr.slope)
            ratingText = String(format: "%.1f", tr.rating)
        }
        if let holes = apiHolesByTee[newTee] {
            scannedData.holes = holes
        }
    }

    func triggerSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard query.count >= 3 else {
            apiResults = []
            isSearching = false
            searchErrorMessage = nil
            hasSearchedCurrentQuery = false
            return
        }
        isSearching = true
        searchErrorMessage = nil
        hasSearchedCurrentQuery = false
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 s debounce
            guard !Task.isCancelled else { return }
            do {
                apiResults = try await courseSearch.search(query: query)
                searchErrorMessage = nil
                hasSearchedCurrentQuery = true
            } catch is CancellationError {
                return
            } catch {
                apiResults = []
                searchErrorMessage = error.localizedDescription
                hasSearchedCurrentQuery = true
            }
            isSearching = false
        }
    }

    var searchGuidanceMessage: String? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { return nil }
        if let searchErrorMessage { return searchErrorMessage }
        guard hasSearchedCurrentQuery, !isSearching, apiResults.isEmpty else { return nil }
        return "No courses found. Try adding city/state (e.g. \"Ross Bridge Birmingham AL\")."
    }

    var isSearchGuidanceError: Bool {
        searchErrorMessage != nil
    }

    func applyAPIResult(_ result: CourseAPIResult) {
        apiHolesByTee = result.holesByTee
        courseName = result.displayName
        let defaultTee = Self.sortedTeeOptions(Array(result.teeRatings.keys)).first
            ?? result.teeRatings.keys.sorted().first
            ?? "White"
        teeColor = defaultTee
        scannedData = ScannedCourseData(
            holes: result.holes(forTee: defaultTee),
            slope: result.teeRatings[defaultTee]?.slope,
            courseRating: result.teeRatings[defaultTee]?.rating,
            teeRatings: result.teeRatings
        )
        applyRatingForCurrentTee(from: scannedData)
        apiResults = []
        searchErrorMessage = nil
        hasSearchedCurrentQuery = false
        searchQuery = ""
        step = .reviewing
    }

    private func applyRatingForCurrentTee(from data: ScannedCourseData) {
        if let tr = data.teeRatings[teeColor] {
            slopeText = String(tr.slope)
            ratingText = String(format: "%.1f", tr.rating)
        } else {
            slopeText = data.slope.map { String($0) } ?? ""
            ratingText = data.courseRating.map { String(format: "%.1f", $0) } ?? ""
        }
    }

    private static func sortedTeeOptions(_ teeKeys: [String]) -> [String] {
        teeKeys.sorted { lhs, rhs in
            let lIndex = teePreferenceOrder.firstIndex(of: lhs) ?? .max
            let rIndex = teePreferenceOrder.firstIndex(of: rhs) ?? .max
            if lIndex != rIndex { return lIndex < rIndex }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    func setPar(hole: Int, par: Int) {
        guard let idx = scannedData.holes.firstIndex(where: { $0.number == hole }) else { return }
        scannedData.holes[idx].par = par
    }

    func setSI(hole: Int, si: Int) {
        guard let idx = scannedData.holes.firstIndex(where: { $0.number == hole }) else { return }
        scannedData.holes[idx].strokeIndex = si
    }

    func toHoleStubs() -> [CourseHoleStub] {
        scannedData.holes.map {
            CourseHoleStub(number: $0.number, par: $0.par ?? 4, strokeIndex: $0.strokeIndex ?? $0.number, yardage: $0.yardage ?? 0)
        }
    }

    func applyDemoCourse() {
        apiHolesByTee = [:]
        courseName = DemoCourseFactory.name
        teeColor = "White"
        slopeText = ""
        ratingText = ""
        scannedData = ScannedCourseData(
            holes: DemoCourseFactory.holes18().map { ScannedHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex, yardage: $0.yardage) },
            slope: nil,
            courseRating: nil
        )
        step = .reviewing
    }
}

// MARK: - ImagePicker

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPick: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onPick: (UIImage) -> Void
        init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onPick(image) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

struct TeeSelectionField: View {
    @Binding var selectedTee: String
    let options: [String]

    var body: some View {
        if options.count <= CourseTeePickerLayout.segmentedThreshold {
            Picker("Tee", selection: $selectedTee) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
        } else {
            Menu {
                Picker("Tee", selection: $selectedTee) {
                    ForEach(options, id: \.self) { tee in
                        Text(tee).tag(tee)
                    }
                }
            } label: {
                HStack {
                    Text("Tee")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(selectedTee)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - HoleReviewRow

struct HoleReviewRow: View {
    let hole: ScannedHole
    let isDuplicateSI: Bool
    let onParChange: (Int) -> Void
    let onSIChange: (Int) -> Void

    var body: some View {
        HStack(spacing: CourseReviewLayout.rowSpacing) {
            Text("\(hole.number)")
                .frame(width: CourseReviewLayout.holeColumnWidth, alignment: .center)
                .foregroundStyle(.secondary)

            Text(hole.yardage.map { "\($0)" } ?? "—")
                .frame(width: CourseReviewLayout.yardageColumnWidth, alignment: .center)
                .foregroundStyle(hole.yardage == nil ? .secondary : .primary)

            Stepper(value: Binding(
                get: { hole.par ?? 4 },
                set: { onParChange($0) }
            ), in: 3...5) {
                Text(hole.par.map { "\($0)" } ?? "–")
                    .frame(width: 30, alignment: .center)
                    .foregroundStyle(hole.par == nil ? .orange : .primary)
            }
            .frame(width: CourseReviewLayout.controlColumnWidth)

            Stepper(value: Binding(
                get: { hole.strokeIndex ?? 1 },
                set: { onSIChange($0) }
            ), in: 1...18) {
                Text(hole.strokeIndex.map { "\($0)" } ?? "–")
                    .frame(width: 30, alignment: .center)
                    .foregroundStyle(
                        isDuplicateSI ? .red :
                        hole.strokeIndex == nil ? .orange : .primary
                    )
            }
            .frame(width: CourseReviewLayout.controlColumnWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
