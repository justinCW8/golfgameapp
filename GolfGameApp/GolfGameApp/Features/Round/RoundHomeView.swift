//
//  RoundHomeView.swift
//  GolfGameApp
//
//  Created by juswaite on 2/27/26.
//

import SwiftUI
import Combine
import UIKit

struct RoundHomeView: View {
    @EnvironmentObject private var session: SessionModel
    @State private var path: [RoundRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 20) {
                Spacer()

                if let configuredRound = session.configuredRound {
                    ConfiguredRoundCard(round: configuredRound)

                    Button("Resume Round") {
                        path.append(.scoring)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(session.activeRoundSession == nil)
                }

                if session.configuredRound != nil {
                    Button("New Round") { path.append(.setup) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                } else {
                    Button("Start New Round") { path.append(.setup) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Round")
            .navigationDestination(for: RoundRoute.self) { route in
                switch route {
                case .setup:
                    RoundSetupFlowView { _ in
                        path.append(.scoring)
                    }
                case .scoring:
                    RoundScoringView(session: session)
                }
            }
        }
    }
}

private enum RoundRoute: Hashable {
    case setup
    case scoring
}

@MainActor
final class RoundSetupViewModel: ObservableObject {
    static let teeBoxOptions = ["Blue", "White", "Gold", "Red"]

    @Published var eventName = ""
    @Published var eventDate = Date()
    @Published var players = [
        PlayerDraft(),
        PlayerDraft(),
        PlayerDraft(),
        PlayerDraft()
    ]
    @Published var courseName = DemoCourseFactory.name
    @Published var teeBoxName = "White"
    @Published var holes = DemoCourseFactory.holes18()
    @Published var slope: Int? = nil
    @Published var courseRating: Double? = nil

    var hasValidEventName: Bool {
        !eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasFourNamedPlayers: Bool {
        players.count == 4 && players.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var sortedPlayersByHandicap: [PlayerDraft] {
        players.sorted { $0.handicapIndex < $1.handicapIndex }
    }

    var pairings: [TeamPairing] {
        let ordered = sortedPlayersByHandicap
        guard ordered.count == 4 else { return [] }

        let teamA = [
            PlayerSnapshot(id: ordered[0].id.uuidString, name: ordered[0].name, handicapIndex: ordered[0].handicapIndex),
            PlayerSnapshot(id: ordered[3].id.uuidString, name: ordered[3].name, handicapIndex: ordered[3].handicapIndex)
        ]
        let teamB = [
            PlayerSnapshot(id: ordered[1].id.uuidString, name: ordered[1].name, handicapIndex: ordered[1].handicapIndex),
            PlayerSnapshot(id: ordered[2].id.uuidString, name: ordered[2].name, handicapIndex: ordered[2].handicapIndex)
        ]

        return [
            TeamPairing(team: .teamA, players: teamA),
            TeamPairing(team: .teamB, players: teamB)
        ]
    }

    func commit(into session: SessionModel) {
        let snapshots = players.map {
            PlayerSnapshot(id: $0.id.uuidString, name: $0.name, handicapIndex: $0.handicapIndex)
        }

        let setup = RoundSetupSession(
            event: EventDraft(name: eventName, date: eventDate),
            courseName: courseName,
            teeBoxName: teeBoxName,
            slope: slope,
            courseRating: courseRating,
            players: snapshots,
            holes: holes,
            pairings: pairings
        )
        session.startRoundSession(with: setup)
    }
}

private struct RoundSetupFlowView: View {
    @StateObject private var viewModel = RoundSetupViewModel()
    let onFinish: (RoundSetupSession) -> Void

    var body: some View {
        EventCreationScreen(viewModel: viewModel, onFinish: onFinish)
    }
}

private struct EventCreationScreen: View {
    @ObservedObject var viewModel: RoundSetupViewModel
    let onFinish: (RoundSetupSession) -> Void

    var body: some View {
        Form {
            Section("Event Creation") {
                TextField("Event name", text: $viewModel.eventName)
                DatePicker("Date", selection: $viewModel.eventDate, displayedComponents: .date)
            }
            Section {
                NavigationLink("Next: Players") {
                    PlayerEntryScreen(viewModel: viewModel, onFinish: onFinish)
                }
                .disabled(!viewModel.hasValidEventName)
            }
        }
        .navigationTitle("Event")
    }
}

private struct PlayerEntryScreen: View {
    @ObservedObject var viewModel: RoundSetupViewModel
    @EnvironmentObject var buddyStore: BuddyStore
    let onFinish: (RoundSetupSession) -> Void

    private var nextEmptyIndex: Int? {
        viewModel.players.indices.first { viewModel.players[$0].name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        Form {
            // SAVED BUDDIES
            Section {
                if buddyStore.buddies.isEmpty {
                    Text("No buddies saved yet — enter players below and tap the bookmark to save them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(buddyStore.buddies) { buddy in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(buddy.name)
                                    .font(.subheadline)
                                Text(String(format: "HI %.1f", buddy.handicapIndex))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                if let idx = nextEmptyIndex {
                                    viewModel.players[idx].name = buddy.name
                                    viewModel.players[idx].handicapIndex = buddy.handicapIndex
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(nextEmptyIndex != nil ? .blue : .secondary)
                            }
                            .disabled(nextEmptyIndex == nil)
                            .buttonStyle(.plain)
                        }
                    }
                    .onDelete { offsets in
                        buddyStore.remove(at: offsets)
                    }
                }
            } header: {
                Text("Saved Buddies")
            } footer: {
                if !buddyStore.buddies.isEmpty {
                    Text("Tap + to fill the next open slot. Swipe to remove.")
                        .font(.caption)
                }
            }

            // PLAYER SLOTS
            Section("Players (exactly 4)") {
                ForEach(0..<4, id: \.self) { index in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading) {
                            TextField("Player \(index + 1) name", text: $viewModel.players[index].name)
                            HStack {
                                Text("HI")
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
                }
            }

            Section {
                NavigationLink("Next: Course") {
                    CourseSetupScreen(viewModel: viewModel, onFinish: onFinish)
                }
                .disabled(!viewModel.hasFourNamedPlayers)
            }
        }
        .navigationTitle("Players")
    }
}

// MARK: - ScanViewModel

@MainActor
private final class ScanViewModel: ObservableObject {
    enum Step { case initial, reviewing }

    @Published var step: Step = .initial
    @Published var scannedData: ScannedCourseData = .empty
    @Published var courseName: String = ""
    @Published var teeColor: String = "White"
    @Published var slopeText: String = ""
    @Published var ratingText: String = ""
    @Published var isProcessing: Bool = false
    @Published var showCamera: Bool = false

    private let scanner = ScorecardScanner()
    private let parser = ScorecardParser()

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
        isProcessing = true
        let lines = await scanner.recognizeText(in: image)
        let parsed = parser.parse(lines)
        scannedData = parsed
        slopeText = parsed.slope.map { String($0) } ?? ""
        ratingText = parsed.courseRating.map { String(format: "%.1f", $0) } ?? ""
        isProcessing = false
        step = .reviewing
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
            CourseHoleStub(number: $0.number, par: $0.par ?? 4, strokeIndex: $0.strokeIndex ?? $0.number)
        }
    }

    func applyDemoCourse() {
        courseName = DemoCourseFactory.name
        teeColor = "White"
        slopeText = ""
        ratingText = ""
        scannedData = ScannedCourseData(
            holes: DemoCourseFactory.holes18().map { ScannedHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex) },
            slope: nil,
            courseRating: nil
        )
        step = .reviewing
    }
}

// MARK: - ImagePicker

private struct ImagePicker: UIViewControllerRepresentable {
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

// MARK: - CourseSetupScreen

private struct CourseSetupScreen: View {
    @ObservedObject var viewModel: RoundSetupViewModel
    @EnvironmentObject var courseStore: CourseStore
    @StateObject private var scanVM = ScanViewModel()
    let onFinish: (RoundSetupSession) -> Void

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
            let source: UIImagePickerController.SourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
            ImagePicker(sourceType: source) { image in
                scanVM.showCamera = false
                Task { await scanVM.processImage(image) }
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

    // MARK: Initial

    private var initialView: some View {
        Form {
            if !courseStore.courses.isEmpty {
                Section {
                    ForEach(courseStore.courses) { saved in
                        Button {
                            applysaved(saved)
                        } label: {
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
                    Text("Tap to use · Swipe to delete")
                        .font(.caption)
                }
            }

            Section {
                Button {
                    scanVM.showCamera = true
                } label: {
                    Label("Scan Scorecard", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
            } footer: {
                Text("Photograph the front and back of the scorecard. Works best in good light with the card held flat.")
                    .font(.caption)
            }

            Section {
                Button("Use Demo Course (Dev)") {
                    scanVM.applyDemoCourse()
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Review

    private var reviewView: some View {
        Form {
            Section("Course Info") {
                TextField("Course Name", text: $scanVM.courseName)
                Picker("Tee", selection: $scanVM.teeColor) {
                    ForEach(ScanViewModel.teeOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Slope")
                        .foregroundStyle(.secondary)
                    TextField("—", text: $scanVM.slopeText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Rating")
                        .foregroundStyle(.secondary)
                    TextField("—", text: $scanVM.ratingText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                HStack {
                    Text("Hole").frame(width: 36, alignment: .center).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Par").frame(width: 44, alignment: .center).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("SI").frame(maxWidth: .infinity, alignment: .center).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(scanVM.scannedData.holes, id: \.number) { hole in
                    HoleReviewRow(
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
                Button("Rescan") {
                    scanVM.step = .initial
                }
                .foregroundStyle(.orange)

                NavigationLink("Next: Teams") {
                    TeamAssignmentScreen(viewModel: viewModel, onFinish: onFinish)
                }
                .disabled(!scanVM.isValid)
            }
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

    private func applysaved(_ saved: SavedCourse) {
        scanVM.courseName = saved.name
        scanVM.teeColor = saved.teeColor
        scanVM.slopeText = saved.slope.map { String($0) } ?? ""
        scanVM.ratingText = saved.courseRating.map { String(format: "%.1f", $0) } ?? ""
        scanVM.scannedData = ScannedCourseData(
            holes: saved.holes.map { ScannedHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex) },
            slope: saved.slope,
            courseRating: saved.courseRating
        )
        scanVM.step = .reviewing
    }
}

// MARK: - HoleReviewRow

private struct HoleReviewRow: View {
    let hole: ScannedHole
    let isDuplicateSI: Bool
    let onParChange: (Int) -> Void
    let onSIChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(hole.number)")
                .frame(width: 36, alignment: .center)
                .foregroundStyle(.secondary)

            Stepper(value: Binding(
                get: { hole.par ?? 4 },
                set: { onParChange($0) }
            ), in: 3...5) {
                Text(hole.par.map { "\($0)" } ?? "–")
                    .frame(width: 28, alignment: .center)
                    .foregroundStyle(hole.par == nil ? .orange : .primary)
            }
            .frame(width: 110)

            Stepper(value: Binding(
                get: { hole.strokeIndex ?? 1 },
                set: { onSIChange($0) }
            ), in: 1...18) {
                Text(hole.strokeIndex.map { "\($0)" } ?? "–")
                    .frame(width: 28, alignment: .center)
                    .foregroundStyle(
                        isDuplicateSI ? .red :
                        hole.strokeIndex == nil ? .orange : .primary
                    )
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct TeamAssignmentScreen: View {
    @EnvironmentObject private var session: SessionModel
    @ObservedObject var viewModel: RoundSetupViewModel
    let onFinish: (RoundSetupSession) -> Void

    var body: some View {
        List {
            Section("Auto Pairing (Low HI + High HI)") {
                ForEach(viewModel.pairings) { pairing in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pairing.team == .teamA ? "Team A" : "Team B")
                            .font(.headline)
                        ForEach(pairing.players) { player in
                            HStack {
                                Text(player.name)
                                Spacer()
                                Text(String(format: "HI %.1f", player.handicapIndex))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Teams")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Start Round") {
                    viewModel.commit(into: session)
                    if let configured = session.configuredRound {
                        onFinish(configured)
                    }
                }
            }
        }
    }
}

private struct ConfiguredRoundCard: View {
    let round: RoundSetupSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(round.event.name)
                .font(.headline)
            Text(round.event.date, style: .date)
                .foregroundStyle(.secondary)
            Text(round.courseName)
                .foregroundStyle(.secondary)
            Text("Tee Box: \(round.teeBoxName)")
                .foregroundStyle(.secondary)
            Divider()
            Text("Players")
                .font(.subheadline.weight(.medium))
            ForEach(round.players) { player in
                HStack {
                    Text(player.name)
                    Spacer()
                    Text(String(format: "HI %.1f", player.handicapIndex))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
