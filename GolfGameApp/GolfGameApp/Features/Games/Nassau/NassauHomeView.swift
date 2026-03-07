import SwiftUI
import Combine
import PhotosUI
import UIKit

// MARK: - NassauHomeView

struct NassauHomeView: View {
    @EnvironmentObject private var session: SessionModel
    @State private var path: [NassauRoute] = []
    @State private var showEndConfirmation = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 20) {
                Spacer()

                if let active = session.activeNassauSession {
                    VStack(spacing: 6) {
                        Text(active.courseName)
                            .font(.headline)
                        Text(active.format == .singles ? "Singles" : "Fourball")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(active.players.map(\.name).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)

                    Button("Continue Game") {
                        path = [.scoring]
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("End Game") {
                        showEndConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    .controlSize(.large)
                } else {
                    Button("New Game") {
                        path.append(.setup)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Nassau")
            .navigationDestination(for: NassauRoute.self) { route in
                switch route {
                case .setup:
                    NassauSetupFlowView {
                        path = [.scoring]
                    }
                case .scoring:
                    NassauScoringView(session: session)
                }
            }
            .alert("End Game?", isPresented: $showEndConfirmation) {
                Button("End Game", role: .destructive) {
                    session.clearActiveNassauSession()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the current game and all scores. This cannot be undone.")
            }
        }
    }
}

private enum NassauRoute: Hashable {
    case setup
    case scoring
}

// MARK: - NassauSetupViewModel

@MainActor
private final class NassauSetupViewModel: ObservableObject {
    @Published var format: NassauFormat = .fourball
    @Published var players: [PlayerDraft] = [PlayerDraft(), PlayerDraft(), PlayerDraft(), PlayerDraft()]

    // Course — populated by NassauCourseScreen
    @Published var courseName: String = ""
    @Published var teeBoxName: String = "White"
    @Published var holes: [CourseHoleStub] = DemoCourseFactory.holes18()
    @Published var slope: Int? = nil
    @Published var courseRating: Double? = nil

    // Press config
    @Published var pressConfig: NassauPressConfig = .default

    var namedPlayers: [PlayerDraft] {
        players.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var requiredPlayerCount: Int { format == .singles ? 2 : 4 }

    var hasValidPlayers: Bool {
        namedPlayers.count >= requiredPlayerCount
    }

    var hasValidCourse: Bool { !holes.isEmpty }

    /// Auto-pair 4 players for fourball: sort by HI, Team A = lowest+highest, Team B = middle two
    var pairings: [TeamPairing] {
        guard format == .fourball else { return [] }
        let named = namedPlayers.prefix(4)
        guard named.count == 4 else { return [] }
        let snapshots = named.map { d in
            PlayerSnapshot(
                id: d.id.uuidString,
                name: d.name.trimmingCharacters(in: .whitespacesAndNewlines),
                handicapIndex: d.handicapIndex
            )
        }
        let sorted = snapshots.sorted { $0.handicapIndex < $1.handicapIndex }
        let teamA = TeamPairing(team: .teamA, players: [sorted[0], sorted[3]])
        let teamB = TeamPairing(team: .teamB, players: [sorted[1], sorted[2]])
        return [teamA, teamB]
    }

    func commit(into session: SessionModel, courseStore: CourseStore) {
        let namedSnapshots = namedPlayers.prefix(requiredPlayerCount).map { d in
            PlayerSnapshot(
                id: d.id.uuidString,
                name: d.name.trimmingCharacters(in: .whitespacesAndNewlines),
                handicapIndex: d.handicapIndex
            )
        }
        let finalPairings = format == .singles ? [] : pairings
        session.startNassauSession(
            format: format,
            players: Array(namedSnapshots),
            pairings: finalPairings,
            courseName: courseName.isEmpty ? DemoCourseFactory.name : courseName,
            teeBoxName: teeBoxName,
            holes: holes,
            pressConfig: pressConfig
        )
        if !courseName.trimmingCharacters(in: .whitespaces).isEmpty {
            let saved = SavedCourse(
                name: courseName, teeColor: teeBoxName,
                slope: slope, courseRating: courseRating, holes: holes
            )
            courseStore.save(saved)
        }
    }
}

// MARK: - NassauSetupFlowView

private struct NassauSetupFlowView: View {
    @StateObject private var viewModel = NassauSetupViewModel()
    @EnvironmentObject private var session: SessionModel
    @EnvironmentObject private var courseStore: CourseStore
    let onFinish: () -> Void

    var body: some View {
        NassauFormatScreen(viewModel: viewModel, onFinish: onFinish)
            .navigationTitle("Nassau")
    }
}

// MARK: - Screen 1: Format

private struct NassauFormatScreen: View {
    @ObservedObject var viewModel: NassauSetupViewModel
    let onFinish: () -> Void

    var body: some View {
        Form {
            Section {
                Text("Choose how many players are in your game.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                FormatOptionRow(
                    title: "2v2 Fourball",
                    subtitle: "4 players · best ball per team per hole",
                    isSelected: viewModel.format == .fourball
                ) {
                    viewModel.format = .fourball
                    while viewModel.players.count < 4 { viewModel.players.append(PlayerDraft()) }
                }

                FormatOptionRow(
                    title: "1v1 Singles",
                    subtitle: "2 players · head-to-head",
                    isSelected: viewModel.format == .singles
                ) {
                    viewModel.format = .singles
                    while viewModel.players.count > 2 { viewModel.players.removeLast() }
                }
            } header: {
                Text("Format")
            }

            Section {
                NavigationLink("Next: Players") {
                    NassauPlayersScreen(viewModel: viewModel, onFinish: onFinish)
                }
            }
        }
        .navigationTitle("Format")
    }
}

private struct FormatOptionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Screen 2: Players

private struct NassauPlayersScreen: View {
    @ObservedObject var viewModel: NassauSetupViewModel
    @EnvironmentObject var buddyStore: BuddyStore
    @State private var showBuddies = false
    let onFinish: () -> Void

    private var nextEmptyIndex: Int? {
        viewModel.players.indices.first { viewModel.players[$0].name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var playerLabel: String {
        viewModel.format == .singles ? "players" : "players (4 required)"
    }

    var body: some View {
        Form {
            Section("Players") {
                ForEach(viewModel.players.indices, id: \.self) { index in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading) {
                            let label = viewModel.format == .singles
                                ? (index == 0 ? "Player A" : "Player B")
                                : "Player \(index + 1)"
                            TextField(label, text: $viewModel.players[index].name)
                            HStack {
                                Text("Index")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                TextField("0.0", value: $viewModel.players[index].handicapIndex, format: .number.precision(.fractionLength(1)))
                                    .keyboardType(.decimalPad)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: 50)
                            }
                        }
                        Spacer()
                        let name = viewModel.players[index].name.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            Button {
                                buddyStore.add(name: name, handicapIndex: viewModel.players[index].handicapIndex)
                            } label: {
                                Image(systemName: buddyStore.buddies.contains(where: { $0.name.lowercased() == name.lowercased() }) ? "bookmark.fill" : "bookmark")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.players[index].name = ""
                            viewModel.players[index].handicapIndex = 0.0
                        } label: {
                            Label("Clear", systemImage: "xmark")
                        }
                    }
                }
            }

            // Show projected team pairing for fourball
            if viewModel.format == .fourball, viewModel.namedPlayers.count == 4 {
                let pairs = viewModel.pairings
                if pairs.count == 2 {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Team A").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                                Text(pairs[0].players.map(\.name).joined(separator: " & "))
                                    .font(.caption)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Team B").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                                Text(pairs[1].players.map(\.name).joined(separator: " & "))
                                    .font(.caption)
                            }
                        }
                    } header: {
                        Text("Auto-Paired Teams")
                    } footer: {
                        Text("Pairs lowest and highest handicap together. Reorder players to change teams.")
                            .font(.caption)
                    }
                }
            }

            Section {
                Text(viewModel.format == .singles
                     ? "Enter 2 players for a head-to-head game."
                     : "Enter 4 players. Teams are auto-paired by handicap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NavigationLink("Next: Course") {
                    NassauCourseScreen(viewModel: viewModel, onFinish: onFinish)
                }
                .disabled(!viewModel.hasValidPlayers)
            }
        }
        .navigationTitle("Players")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showBuddies = true
                } label: {
                    Label("Buddies", systemImage: "person.2.fill")
                }
                .sheet(isPresented: $showBuddies) {
                    NassauBuddiesSheet(
                        buddyStore: buddyStore,
                        onSelect: { buddy in
                            if let idx = nextEmptyIndex {
                                viewModel.players[idx].name = buddy.name
                                viewModel.players[idx].handicapIndex = buddy.handicapIndex
                            } else if viewModel.format == .fourball, viewModel.players.count < 4 {
                                viewModel.players.append(PlayerDraft(name: buddy.name, handicapIndex: buddy.handicapIndex))
                            }
                            let maxCount = viewModel.requiredPlayerCount
                            if viewModel.namedPlayers.count >= maxCount { showBuddies = false }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Screen 3: Course

private struct NassauCourseScreen: View {
    @ObservedObject var viewModel: NassauSetupViewModel
    @EnvironmentObject var courseStore: CourseStore
    @StateObject private var scanVM = NassauScanViewModel()
    let onFinish: () -> Void

    var body: some View {
        Group {
            if scanVM.step == .initial {
                initialView
            } else {
                reviewView
            }
        }
        .navigationTitle("Course")
        .sheet(isPresented: $scanVM.showCamera) {
            NassauImagePicker(sourceType: .camera) { image in
                scanVM.showCamera = false
                Task { await scanVM.processImage(image) }
            }
        }
        .onChange(of: scanVM.photoPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await scanVM.processImage(image)
                }
                scanVM.photoPickerItem = nil
            }
        }
        .onChange(of: scanVM.mergePhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await scanVM.mergeImage(image)
                }
                scanVM.mergePhotoItem = nil
            }
        }
        .overlay {
            if scanVM.isProcessing {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.4)
                            .tint(.white)
                        Text("Reading scorecard...")
                            .foregroundStyle(.white)
                            .font(.subheadline)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private var initialView: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search course name…", text: $scanVM.searchQuery)
                        .autocorrectionDisabled()
                        .onChange(of: scanVM.searchQuery) { _, _ in scanVM.triggerSearch() }
                    if scanVM.isSearching {
                        ProgressView().scaleEffect(0.75)
                    } else if !scanVM.searchQuery.isEmpty {
                        Button { scanVM.searchQuery = ""; scanVM.apiResults = [] } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } footer: {
                Text("Type at least 3 characters to search ~30,000 courses.")
                    .font(.caption)
            }

            if !scanVM.apiResults.isEmpty {
                Section("Results") {
                    ForEach(scanVM.apiResults) { result in
                        Button { scanVM.applyAPIResult(result) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.displayName).foregroundStyle(.primary)
                                Text(result.location)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            if !courseStore.courses.isEmpty {
                Section {
                    ForEach(courseStore.courses) { saved in
                        Button { applySaved(saved) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(saved.name).foregroundStyle(.primary)
                                    Text("\(saved.teeColor) tee" + (saved.slope.map { " · Slope \($0)" } ?? ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { courseStore.remove(at: $0) }
                } header: {
                    Text("Saved Courses")
                } footer: {
                    Text("Tap to use · Swipe to delete").font(.caption)
                }
            }

            Section {
                PhotosPicker(selection: $scanVM.photoPickerItem, matching: .images) {
                    Label("Scan Scorecard from Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 8, leading: 0, bottom: 4, trailing: 0))

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { scanVM.showCamera = true } label: {
                        Label("Use Camera", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 4, leading: 0, bottom: 8, trailing: 0))
                }
            } header: {
                Text("Scan Scorecard")
            } footer: {
                Text("Use when the course isn't found in search.").font(.caption)
            }

            Section {
                Button("Use Demo Course (Dev)") { scanVM.applyDemoCourse() }
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reviewView: some View {
        Form {
            Section("Course Info") {
                TextField("Course Name", text: $scanVM.courseName)
                Picker("Tee", selection: $scanVM.teeColor) {
                    ForEach(NassauScanViewModel.teeOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Slope").foregroundStyle(.secondary)
                    TextField("—", text: $scanVM.slopeText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Rating").foregroundStyle(.secondary)
                    TextField("—", text: $scanVM.ratingText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                HStack {
                    Text("Hole").frame(width: 36, alignment: .center).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Par").frame(width: 44, alignment: .center).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Stroke Index").frame(maxWidth: .infinity, alignment: .center).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(scanVM.scannedData.holes, id: \.number) { hole in
                    NassauHoleReviewRow(
                        hole: hole,
                        isDuplicateSI: scanVM.duplicateSI.contains(hole.strokeIndex ?? -1),
                        onParChange: { scanVM.setPar(hole: hole.number, par: $0) },
                        onSIChange: { scanVM.setSI(hole: hole.number, si: $0) }
                    )
                }
            } header: {
                Text("Hole Data")
            } footer: {
                if !scanVM.duplicateSI.isEmpty {
                    Text("Duplicate stroke indexes detected (shown in red). Each SI must be unique.")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section {
                PhotosPicker(selection: $scanVM.mergePhotoItem, matching: .images) {
                    Label("Scan Another Page", systemImage: "doc.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))

                Button("Rescan (Start Over)") {
                    scanVM.step = .initial
                }
                .foregroundStyle(.orange)

                NavigationLink("Next: Press Rules") {
                    NassauPressConfigScreen(viewModel: viewModel, onFinish: onFinish)
                }
                .disabled(!scanVM.isValid)
            } footer: {
                let missingPar = scanVM.scannedData.holes.filter { $0.par == nil }.count
                let missingSI = scanVM.scannedData.holes.filter { $0.strokeIndex == nil }.count
                if missingPar > 0 || missingSI > 0 {
                    Text("Missing data on \(max(missingPar, missingSI)) hole(s). Scan the front of the card to import par and stroke index.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onChange(of: scanVM.teeColor) { _, newTee in
            scanVM.updateRatingForTee(newTee)
        }
        .onChange(of: scanVM.step) { _, _ in syncToViewModel() }
        .onAppear { syncToViewModel() }
    }

    private func syncToViewModel() {
        guard scanVM.isValid else { return }
        viewModel.courseName = scanVM.courseName
        viewModel.teeBoxName = scanVM.teeColor
        viewModel.holes = scanVM.toHoleStubs()
        viewModel.slope = scanVM.slope
        viewModel.courseRating = scanVM.courseRating
    }

    private func applySaved(_ saved: SavedCourse) {
        scanVM.courseName = saved.name
        scanVM.teeColor = saved.teeColor
        scanVM.slopeText = saved.slope.map { String($0) } ?? ""
        scanVM.ratingText = saved.courseRating.map { String(format: "%.1f", $0) } ?? ""
        scanVM.scannedData = ScannedCourseData(
            holes: saved.holes.map { ScannedHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex, yardage: $0.yardage) },
            slope: saved.slope,
            courseRating: saved.courseRating
        )
        scanVM.step = .reviewing
    }
}

// MARK: - Screen 4: Press Config

private struct NassauPressConfigScreen: View {
    @ObservedObject var viewModel: NassauSetupViewModel
    @EnvironmentObject private var session: SessionModel
    @EnvironmentObject private var courseStore: CourseStore
    let onFinish: () -> Void

    private let autoPressTriggerOptions: [(label: String, value: Int?)] = [
        ("Off", nil), ("1 Down", 1), ("2 Down", 2), ("3 Down", 3)
    ]
    private let maxPressOptions: [(label: String, value: Int?)] = [
        ("Unlimited", nil), ("1 per segment", 1), ("2 per segment", 2)
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Manual Press", isOn: $viewModel.pressConfig.manualPressEnabled)
            } header: {
                Text("Manual Press")
            } footer: {
                Text("Trailing side can press before any hole. Confirmation required.")
                    .font(.caption)
            }

            Section {
                Picker("Auto-Press Trigger", selection: Binding(
                    get: { viewModel.pressConfig.autoPressTrigger ?? -1 },
                    set: { viewModel.pressConfig.autoPressTrigger = $0 == -1 ? nil : $0 }
                )) {
                    ForEach(autoPressTriggerOptions, id: \.label) { opt in
                        Text(opt.label).tag(opt.value ?? -1)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Auto-Press")
            } footer: {
                Text("Trailing side auto-presses when they fall behind by the selected amount.")
                    .font(.caption)
            }

            Section {
                Picker("Press Limit", selection: Binding(
                    get: { viewModel.pressConfig.maxPressesPerSegment ?? 0 },
                    set: { viewModel.pressConfig.maxPressesPerSegment = $0 == 0 ? nil : $0 }
                )) {
                    ForEach(maxPressOptions, id: \.label) { opt in
                        Text(opt.label).tag(opt.value ?? 0)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Press Limit")
            } footer: {
                Text("Maximum presses per segment (Front 9 or Back 9).")
                    .font(.caption)
            }

            Section {
                Button("Start Game") {
                    viewModel.commit(into: session, courseStore: courseStore)
                    onFinish()
                }
                .disabled(!viewModel.hasValidPlayers || !viewModel.hasValidCourse)
                .frame(maxWidth: .infinity)
                .font(.headline)
            }
        }
        .navigationTitle("Press Rules")
    }
}

// MARK: - NassauScanViewModel (mirrors ScanViewModel in EventHomeView)

@MainActor
private final class NassauScanViewModel: ObservableObject {
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

    @Published var searchQuery: String = ""
    @Published var apiResults: [CourseAPIResult] = []
    @Published var isSearching: Bool = false
    private var searchTask: Task<Void, Never>? = nil
    private var apiHolesByTee: [String: [ScannedHole]] = [:]

    private let scanner = ScorecardScanner()
    private let parser = ScorecardParser()
    private let courseSearch = CourseSearchService()

    static let teeOptions = ["Blue", "White", "Gold", "Red"]

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
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            apiResults = (try? await courseSearch.search(query: query)) ?? []
            isSearching = false
        }
    }

    func applyAPIResult(_ result: CourseAPIResult) {
        apiHolesByTee = result.holesByTee
        courseName = result.displayName
        let preferredTees = ["Blue", "White", "Gold", "Red"]
        let defaultTee = preferredTees.first { result.teeRatings[$0] != nil }
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

// MARK: - NassauImagePicker

private struct NassauImagePicker: UIViewControllerRepresentable {
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

// MARK: - NassauHoleReviewRow

private struct NassauHoleReviewRow: View {
    let hole: ScannedHole
    let isDuplicateSI: Bool
    let onParChange: (Int) -> Void
    let onSIChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(hole.number)")
                .frame(width: 36, alignment: .center)
                .foregroundStyle(.secondary)

            Stepper(
                value: Binding(
                    get: { hole.par ?? 4 },
                    set: { onParChange($0) }
                ),
                in: 3...5
            ) {
                Text(hole.par.map { "\($0)" } ?? "–")
                    .frame(width: 24, alignment: .center)
                    .foregroundStyle(hole.par == nil ? .orange : .primary)
            }
            .frame(width: 100)

            Stepper(
                value: Binding(
                    get: { hole.strokeIndex ?? hole.number },
                    set: { onSIChange($0) }
                ),
                in: 1...18
            ) {
                Text(hole.strokeIndex.map { "\($0)" } ?? "–")
                    .frame(width: 24, alignment: .center)
                    .foregroundStyle(
                        isDuplicateSI ? .red : hole.strokeIndex == nil ? .orange : .primary
                    )
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - NassauBuddiesSheet

private struct NassauBuddiesSheet: View {
    @ObservedObject var buddyStore: BuddyStore
    let onSelect: (Buddy) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var pendingBuddy: Buddy? = nil
    @State private var updatedHIText: String = ""
    @State private var showHIUpdate = false

    var body: some View {
        NavigationStack {
            Group {
                if buddyStore.buddies.isEmpty {
                    ContentUnavailableView(
                        "No Buddies Saved",
                        systemImage: "person.2",
                        description: Text("Enter players and tap the bookmark icon to save them here.")
                    )
                } else {
                    List {
                        ForEach(buddyStore.buddies) { buddy in
                            Button {
                                if buddy.needsHIConfirmation {
                                    pendingBuddy = buddy
                                    updatedHIText = String(format: "%.1f", buddy.handicapIndex)
                                } else {
                                    onSelect(buddy)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(buddy.name)
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 4) {
                                            Text(String(format: "Index %.1f", buddy.handicapIndex))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if buddy.needsHIConfirmation {
                                                Image(systemName: "exclamationmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .onDelete { buddyStore.remove(at: $0) }
                    }
                }
            }
            .navigationTitle("Saved Buddies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                pendingBuddy.map { "Still Index \(String(format: "%.1f", $0.handicapIndex)), \($0.name)?" } ?? "",
                isPresented: Binding(get: { pendingBuddy != nil && !showHIUpdate },
                                     set: { if !$0 { pendingBuddy = nil } })
            ) {
                Button("Yes, same HI") {
                    if let b = pendingBuddy {
                        buddyStore.confirmHI(id: b.id)
                        onSelect(b)
                    }
                    pendingBuddy = nil
                }
                Button("Update HI") { showHIUpdate = true }
                Button("Cancel", role: .cancel) { pendingBuddy = nil }
            } message: {
                Text("It's been a while — confirm or update before adding to this game.")
            }
            .alert(
                "Update Index for \(pendingBuddy?.name ?? "")",
                isPresented: $showHIUpdate
            ) {
                TextField("New Index (e.g. 8.4)", text: $updatedHIText)
                    .keyboardType(.decimalPad)
                Button("Save & Add") {
                    if let b = pendingBuddy, let newHI = Double(updatedHIText) {
                        buddyStore.updateHI(id: b.id, to: newHI)
                        if let updated = buddyStore.buddies.first(where: { $0.id == b.id }) {
                            onSelect(updated)
                        }
                    }
                    pendingBuddy = nil
                    showHIUpdate = false
                }
                Button("Cancel", role: .cancel) {
                    pendingBuddy = nil
                    showHIUpdate = false
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
