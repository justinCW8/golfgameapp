//
//  RoundHomeView.swift
//  GolfGameApp
//
//  Created by juswaite on 2/27/26.
//

import SwiftUI
import Combine
import UIKit
import PhotosUI

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
    @State private var showBuddies = false
    let onFinish: (RoundSetupSession) -> Void

    private var nextEmptyIndex: Int? {
        viewModel.players.indices.first { viewModel.players[$0].name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        Form {
            Section("Players (exactly 4)") {
                ForEach(0..<4, id: \.self) { index in
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
            }

            Section {
                NavigationLink("Next: Course") {
                    CourseSetupScreen(viewModel: viewModel, onFinish: onFinish)
                }
                .disabled(!viewModel.hasFourNamedPlayers)
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
                            }
                            if nextEmptyIndex == nil { showBuddies = false }
                        }
                    )
                }
            }
        }
    }
}

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
                Text("It's been a while — confirm or update before adding to this round.")
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

// ScanViewModel, ImagePicker, and HoleReviewRow are defined in CourseSetupShared.swift

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
            // Search
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
                    if let searchError = scanVM.searchErrorMessage {
                        Text(searchError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            // Search results
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

            // Saved courses
            if !courseStore.courses.isEmpty {
                Section {
                    ForEach(courseStore.courses) { saved in
                        Button { applysaved(saved) } label: {
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

            // Scan fallback
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
                    Text("Stroke Index").frame(maxWidth: .infinity, alignment: .center).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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

                NavigationLink("Next: Teams") {
                    TeamAssignmentScreen(viewModel: viewModel, onFinish: onFinish)
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

    private func applysaved(_ saved: SavedCourse) {
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


private struct TeamAssignmentScreen: View {
    @EnvironmentObject private var session: SessionModel
    @ObservedObject var viewModel: RoundSetupViewModel
    let onFinish: (RoundSetupSession) -> Void

    var body: some View {
        List {
            Section("Auto Pairing (Low Index + High Index)") {
                ForEach(viewModel.pairings) { pairing in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pairing.team == .teamA ? "Team A" : "Team B")
                            .font(.headline)
                        ForEach(pairing.players) { player in
                            HStack {
                                Text(player.name)
                                Spacer()
                                Text(String(format: "Index %.1f", player.handicapIndex))
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
                    Text(String(format: "Index %.1f", player.handicapIndex))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
