import SwiftUI
import Combine
import UIKit
import PhotosUI

// MARK: - EventHomeView

struct EventHomeView: View {
    @EnvironmentObject private var session: SessionModel
    @State private var path: [EventRoute] = []
    @State private var showEndEventConfirmation = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 20) {
                Spacer()

                if let active = session.activeEventSession, let group = active.groups.first {
                    VStack(spacing: 6) {
                        Text(active.courseName)
                            .font(.headline)
                        Text(active.players.map(\.name).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)

                    let rows = EventGroupScoringViewModel.leaderboardRows(from: active)
                    let thru = EventGroupScoringViewModel.maxCompletedHole(from: active)
                    if thru > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Standings")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(thru == 18 ? "Final" : "Thru \(thru)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                                HStack(spacing: 8) {
                                    Text("\(idx + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(idx == 0 ? Color.accentColor : .secondary)
                                        .frame(width: 16, alignment: .center)
                                    Text(row.player.name)
                                        .font(.subheadline)
                                        .fontWeight(idx == 0 ? .semibold : .regular)
                                    Spacer()
                                    Text("\(row.totalPoints) pts")
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    Button("Continue Scoring") {
                        path = [.groupScoring(group.id)]
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("End Game") {
                        showEndEventConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    .controlSize(.large)
                } else {
                    Button("Quick Game") {
                        path.append(.quickSetup)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Stableford")
            .navigationDestination(for: EventRoute.self) { route in
                switch route {
                case .quickSetup:
                    QuickGameSetupFlowView { groupID in
                        path = [.groupScoring(groupID)]
                    }
                case .groupScoring(let groupID):
                    EventGroupScoringView(session: session, groupID: groupID)
                }
            }
            .alert("End Game?", isPresented: $showEndEventConfirmation) {
                Button("End Game", role: .destructive) {
                    session.clearActiveEventSession()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the current game and all scores. This cannot be undone.")
            }
        }
    }
}

private enum EventRoute: Hashable {
    case quickSetup
    case groupScoring(String)
}

// ScanViewModel, ImagePicker, and HoleReviewRow are defined in CourseSetupShared.swift

// MARK: - BuddiesSheet

private struct BuddiesSheet: View {
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
                Text("It's been a while — confirm or update before adding to this event.")
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

// MARK: - EventSetupViewModel

@MainActor
private final class EventSetupViewModel: ObservableObject {
    @Published var players: [PlayerDraft] = (1...4).map { _ in PlayerDraft() }
    @Published var errorMessage: String?

    // Course data — populated by EventCourseScreen
    @Published var courseName: String = ""
    @Published var teeBoxName: String = "White"
    @Published var holes: [CourseHoleStub] = DemoCourseFactory.holes18()
    @Published var slope: Int? = nil
    @Published var courseRating: Double? = nil

    var namedPlayers: [PlayerDraft] {
        players.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var hasValidPlayerCount: Bool { namedPlayers.count >= 2 }

    func addPlayer() {
        players.append(PlayerDraft())
    }

    func removeLastPlayer() {
        guard players.count > 2 else { return }
        players.removeLast()
    }

    func commitQuickGame(into session: SessionModel, courseStore: CourseStore) -> String {
        let snapshots = namedPlayers.map {
            PlayerSnapshot(
                id: $0.id.uuidString,
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                handicapIndex: $0.handicapIndex
            )
        }
        let groupID = session.startQuickGame(
            players: snapshots,
            holes: holes,
            courseName: courseName.isEmpty ? DemoCourseFactory.name : courseName
        )
        if !courseName.trimmingCharacters(in: .whitespaces).isEmpty {
            let saved = SavedCourse(
                name: courseName, teeColor: teeBoxName,
                slope: slope, courseRating: courseRating, holes: holes
            )
            courseStore.save(saved)
        }
        errorMessage = nil
        return groupID
    }
}

// MARK: - Setup Flow

private struct QuickGameSetupFlowView: View {
    @StateObject private var viewModel = EventSetupViewModel()
    @EnvironmentObject private var session: SessionModel
    @EnvironmentObject private var courseStore: CourseStore
    let onFinish: (String) -> Void

    var body: some View {
        EventPlayersScreen(
            viewModel: viewModel,
            onStartGame: {
                let groupID = viewModel.commitQuickGame(into: session, courseStore: courseStore)
                onFinish(groupID)
            }
        )
        .navigationTitle("Quick Game")
    }
}

// MARK: - Screen 2: Players

private struct EventPlayersScreen: View {
    @ObservedObject var viewModel: EventSetupViewModel
    @EnvironmentObject var buddyStore: BuddyStore
    @State private var showBuddies = false
    var onStartGame: (() -> Void)? = nil

    private var nextEmptyIndex: Int? {
        viewModel.players.indices.first { viewModel.players[$0].name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        Form {
            Section("Players") {
                ForEach(viewModel.players.indices, id: \.self) { index in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading) {
                            TextField("Player \(index + 1) name", text: $viewModel.players[index].name)
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

                HStack {
                    Button("Add Player") { viewModel.addPlayer() }
                        .disabled(onStartGame != nil && viewModel.players.count >= 4)
                    Spacer()
                    Button("Remove Last") { viewModel.removeLastPlayer() }
                        .disabled(viewModel.players.count <= 2)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text(onStartGame != nil ? "2–4 players." : "Add as many players as needed (min 2). Groups of 4 are auto-assigned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NavigationLink("Next: Course") {
                    EventCourseScreen(viewModel: viewModel, onStartGame: onStartGame)
                }
                .disabled(!viewModel.hasValidPlayerCount)
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
                    BuddiesSheet(
                        buddyStore: buddyStore,
                        onSelect: { buddy in
                            if let idx = nextEmptyIndex {
                                viewModel.players[idx].name = buddy.name
                                viewModel.players[idx].handicapIndex = buddy.handicapIndex
                            } else {
                                viewModel.players.append(PlayerDraft(name: buddy.name, handicapIndex: buddy.handicapIndex))
                            }
                            if nextEmptyIndex == nil { showBuddies = false }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Screen 3: Course

private struct EventCourseScreen: View {
    @ObservedObject var viewModel: EventSetupViewModel
    @EnvironmentObject var courseStore: CourseStore
    @EnvironmentObject var session: SessionModel
    @StateObject private var scanVM = ScanViewModel()
    var onStartGame: (() -> Void)? = nil

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
            ImagePicker(sourceType: .camera) { image in
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

    // MARK: Initial

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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type at least 3 characters to search ~30,000 courses.")
                        .font(.caption)
                    if let guidance = scanVM.searchGuidanceMessage {
                        Text(guidance)
                            .font(.caption)
                            .foregroundStyle(scanVM.isSearchGuidanceError ? .red : .secondary)
                    }
                }
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

    // MARK: Review

    private var reviewView: some View {
        Form {
            Section("Course Info") {
                TextField("Course Name", text: $scanVM.courseName)
                TeeSelectionField(selectedTee: $scanVM.teeColor, options: scanVM.availableTeeOptions)
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
                HStack {
                    Text("Yardage").foregroundStyle(.secondary)
                    Text(scanVM.totalYardage > 0 ? "\(scanVM.totalYardage)" : "—")
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                HStack {
                    Text("Hole").frame(width: CourseReviewLayout.holeColumnWidth, alignment: .center).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Yardage").frame(width: CourseReviewLayout.yardageColumnWidth, alignment: .center).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Par").frame(width: CourseReviewLayout.controlColumnWidth, alignment: .center).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Stroke Index").frame(width: CourseReviewLayout.controlColumnWidth, alignment: .center).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

                Button("Start Game") {
                    syncToViewModel()
                    onStartGame?()
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
