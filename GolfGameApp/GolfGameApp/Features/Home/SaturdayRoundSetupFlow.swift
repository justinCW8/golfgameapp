import SwiftUI
import Combine
import PhotosUI
import UIKit

// MARK: - Setup ViewModel

@MainActor
final class SaturdaySetupViewModel: ObservableObject {

    // Screen 1: Players + Course
    @Published var playerCount = 4
    @Published var playerDrafts: [PlayerDraft]
    @Published var courseName = DemoCourseFactory.name
    @Published var holes: [CourseHoleStub] = DemoCourseFactory.holes18()

    // Screen 2: Games
    @Published var selectedGames: [GameType] = []

    // Screen 3: Teams
    @Published var customPairings: [TeamPairing]? = nil  // nil = use auto

    // Screen 4: Settings
    @Published var nassauConfig = NassauGameConfig.default
    @Published var scotchConfig = ScotchGameConfig.default
    @Published var stablefordConfig = StablefordGameConfig.default
    @Published var skinsConfig = SkinsGameConfig.default
    @Published var strokePlayConfig = StrokePlayGameConfig()
    
    // Stroke Play Best Ball Team Assignments
    @Published var bestBallPairings: [BestBallPairing] = []

    init() {
        playerDrafts = (0..<4).map { _ in PlayerDraft() }
    }

    var activePlayers: [PlayerDraft] { Array(playerDrafts.prefix(playerCount)) }

    var hasValidPlayers: Bool {
        activePlayers.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var hasSelectedGames: Bool { !selectedGames.isEmpty }

    // Scotch requires exactly 4 players (2v2)
    var scotchEligible: Bool { playerCount == 4 }

    // Nassau fourball requires exactly 4 players
    var nassauFourballEligible: Bool { playerCount == 4 }
    var stablefordTeamEligible: Bool { playerCount == 4 }

    var requiresTeamScreen: Bool {
        guard playerCount == 4 else { return false }
        let hasScotch = selectedGames.contains(.sixPointScotch)
        let hasFourballNassau = selectedGames.contains(.nassau) && nassauConfig.format == .fourball
        let hasTeamStableford = selectedGames.contains(.stableford) && stablefordConfig.format == .team2v2
        return hasScotch || hasFourballNassau || hasTeamStableford
    }

    var autoPairings: [TeamPairing] {
        let sorted = activePlayers.sorted { $0.handicapIndex < $1.handicapIndex }
        guard sorted.count == 4 else { return [] }
        return [
            TeamPairing(team: .teamA, players: [
                PlayerSnapshot(id: sorted[0].id.uuidString, name: sorted[0].name, handicapIndex: sorted[0].handicapIndex),
                PlayerSnapshot(id: sorted[3].id.uuidString, name: sorted[3].name, handicapIndex: sorted[3].handicapIndex)
            ]),
            TeamPairing(team: .teamB, players: [
                PlayerSnapshot(id: sorted[1].id.uuidString, name: sorted[1].name, handicapIndex: sorted[1].handicapIndex),
                PlayerSnapshot(id: sorted[2].id.uuidString, name: sorted[2].name, handicapIndex: sorted[2].handicapIndex)
            ])
        ]
    }

    var effectivePairings: [TeamPairing] { customPairings ?? autoPairings }

    func toggleGame(_ game: GameType) {
        if selectedGames.contains(game) {
            selectedGames.removeAll { $0 == game }
        } else {
            selectedGames.append(game)
        }
    }

    func swapPlayer(_ playerID: String) {
        var pairings = effectivePairings
        guard pairings.count == 2 else { return }
        // Find which team this player is on and move to other
        if let aIdx = pairings[0].players.firstIndex(where: { $0.id == playerID }),
           let bIdx = pairings.indices.first(where: { pairings[$0].team == .teamB }) {
            let player = pairings[0].players[aIdx]
            pairings[0].players.remove(at: aIdx)
            // Move first player from B to A
            if let bFirst = pairings[bIdx].players.first {
                pairings[0].players.append(bFirst)
                pairings[bIdx].players[0] = player
            }
        } else if let bPairingIdx = pairings.indices.first(where: { pairings[$0].team == .teamB }),
                  let bIdx = pairings[bPairingIdx].players.firstIndex(where: { $0.id == playerID }),
                  let aPairingIdx = pairings.indices.first(where: { pairings[$0].team == .teamA }) {
            let player = pairings[bPairingIdx].players[bIdx]
            pairings[bPairingIdx].players.remove(at: bIdx)
            if let aFirst = pairings[aPairingIdx].players.first {
                pairings[bPairingIdx].players.append(aFirst)
                pairings[aPairingIdx].players[0] = player
            }
        }
        customPairings = pairings
    }

    func resetPairings() { customPairings = nil }

    func activeGameConfigs() -> [SaturdayGameConfig] {
        selectedGames.map { type in
            switch type {
            case .nassau: return .nassau(nassauConfig)
            case .sixPointScotch: return .scotch(scotchConfig)
            case .stableford:
                var config = stablefordConfig
                if !stablefordTeamEligible, config.format == .team2v2 {
                    config.format = .individual
                }
                return .stableford(config)
            case .skins: return .skins(skinsConfig)
            case .strokePlay: 
                var config = strokePlayConfig
                config.bestBallPairings = bestBallPairings
                return .strokePlay(config)
            }
        }
    }

    func commit(into store: AppSessionStore) {
        let snapshots = activePlayers.map {
            PlayerSnapshot(id: $0.id.uuidString, name: $0.name, handicapIndex: $0.handicapIndex)
        }
        store.startSaturdayRound(
            players: snapshots,
            teams: requiresTeamScreen ? effectivePairings : [],
            courseName: courseName,
            holes: holes,
            activeGames: activeGameConfigs()
        )
    }
}

// MARK: - Flow Root

struct SaturdayRoundSetupFlow: View {
    @Binding var path: [SaturdayRoute]
    @StateObject private var vm = SaturdaySetupViewModel()

    var body: some View {
        SetupScreen1_Players(vm: vm, path: $path)
            .navigationTitle("New Round")
    }
}

// MARK: - Screen 1: Players + Course

private struct SetupScreen1_Players: View {
    @ObservedObject var vm: SaturdaySetupViewModel
    @Binding var path: [SaturdayRoute]
    @EnvironmentObject private var store: AppSessionStore
    @EnvironmentObject private var buddyStore: BuddyStore
    @EnvironmentObject private var courseStore: CourseStore
    @State private var showBuddies = false

    private var nextEmptyIndex: Int? {
        (0..<vm.playerCount).first { vm.playerDrafts[$0].name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        Form {
            // Course section
            Section {
                NavigationLink {
                    SaturdayCourseSetupScreen(vm: vm)
                        .navigationTitle("Course")
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.courseName)
                                .foregroundStyle(.primary)
                            Text("Tap to change course")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } header: {
                Text("Course")
            }

            // Player count
            Section {
                Picker("Number of Players", selection: $vm.playerCount) {
                    Text("2 Players").tag(2)
                    Text("3 Players").tag(3)
                    Text("4 Players").tag(4)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Players")
            }

            // Player rows
            Section {
                ForEach(0..<vm.playerCount, id: \.self) { index in
                    PlayerDraftRow(
                        draft: $vm.playerDrafts[index],
                        label: "Player \(index + 1)",
                        buddyStore: buddyStore
                    )
                }
            }

            // Continue
            Section {
                NavigationLink {
                    SetupScreen2_Games(vm: vm, path: $path)
                        .navigationTitle("Select Games")
                } label: {
                    HStack {
                        Spacer()
                        Text("Continue")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(vm.hasValidPlayers ? Color.green : Color(.systemGray3))
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
                .disabled(!vm.hasValidPlayers)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showBuddies = true
                } label: {
                    Label("Buddies", systemImage: "person.2.fill")
                }
            }
        }
        .sheet(isPresented: $showBuddies) {
            SetupBuddiesSheet(buddyStore: buddyStore) { buddy in
                if let idx = nextEmptyIndex {
                    vm.playerDrafts[idx].name = buddy.name
                    vm.playerDrafts[idx].handicapIndex = buddy.handicapIndex
                }
                if nextEmptyIndex == nil { showBuddies = false }
            }
        }
        .onChange(of: vm.playerCount) { _, count in
            if count < 4, vm.stablefordConfig.format == .team2v2 {
                vm.stablefordConfig.format = .individual
            }
        }
    }
}

private struct PlayerDraftRow: View {
    @Binding var draft: PlayerDraft
    let label: String
    let buddyStore: BuddyStore

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                TextField(label, text: $draft.name)
                HStack(spacing: 6) {
                    Text("HCP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("0.0", value: $draft.handicapIndex, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 48)
                }
            }
            Spacer()
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                let isSaved = buddyStore.buddies.contains(where: { $0.name.lowercased() == name.lowercased() })
                Button {
                    buddyStore.add(name: name, handicapIndex: draft.handicapIndex)
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(isSaved)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                draft.name = ""
                draft.handicapIndex = 0.0
            } label: {
                Label("Clear", systemImage: "xmark")
            }
        }
    }
}

// MARK: - Saturday Course Setup Screen

private struct SaturdayCourseSetupScreen: View {
    @ObservedObject var vm: SaturdaySetupViewModel
    @EnvironmentObject var courseStore: CourseStore
    @StateObject private var scanVM = ScanViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if scanVM.step == .initial {
                initialView
            } else {
                reviewView
            }
        }
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
                        ProgressView().scaleEffect(1.4).tint(.white)
                        Text("Reading scorecard...")
                            .foregroundStyle(.white).font(.subheadline)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: Initial view

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
                                Text(result.location).font(.caption).foregroundStyle(.secondary)
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
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
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

    // MARK: Review view

    private var reviewView: some View {
        Form {
            Section("Course Info") {
                TextField("Course Name", text: $scanVM.courseName)
                TeeSelectionField(selectedTee: $scanVM.teeColor, options: scanVM.availableTeeOptions)
                HStack {
                    Text("Slope").foregroundStyle(.secondary)
                    TextField("—", text: $scanVM.slopeText)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Rating").foregroundStyle(.secondary)
                    TextField("—", text: $scanVM.ratingText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Yardage").foregroundStyle(.secondary)
                    Text(scanVM.totalYardage > 0 ? "\(scanVM.totalYardage)" : "—")
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                HStack {
                    Text("Hole").frame(width: CourseReviewLayout.holeColumnWidth, alignment: .center)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Yardage").frame(width: CourseReviewLayout.yardageColumnWidth, alignment: .center)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Par").frame(width: CourseReviewLayout.controlColumnWidth, alignment: .center)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Stroke Index").frame(width: CourseReviewLayout.controlColumnWidth, alignment: .center)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                        .foregroundStyle(.red).font(.caption)
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

                Button("Rescan (Start Over)") { scanVM.step = .initial }
                    .foregroundStyle(.orange)

                Button {
                    vm.courseName = scanVM.courseName
                    vm.holes = scanVM.toHoleStubs()
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text("Confirm Course")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(scanVM.isValid ? Color.green : Color(.systemGray3))
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
                .disabled(!scanVM.isValid)
            } footer: {
                let missingPar = scanVM.scannedData.holes.filter { $0.par == nil }.count
                let missingSI = scanVM.scannedData.holes.filter { $0.strokeIndex == nil }.count
                if missingPar > 0 || missingSI > 0 {
                    Text("Missing data on \(max(missingPar, missingSI)) hole(s). Scan the front of the card to import par and stroke index.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .onChange(of: scanVM.teeColor) { _, newTee in scanVM.updateRatingForTee(newTee) }
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

// MARK: - Buddies Sheet (setup-specific)

private struct SetupBuddiesSheet: View {
    @ObservedObject var buddyStore: BuddyStore
    let onSelect: (Buddy) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pendingBuddy: Buddy?
    @State private var updatedHIText = ""
    @State private var showHIUpdate = false
    @State private var addedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if buddyStore.buddies.isEmpty {
                    ContentUnavailableView(
                        "No Buddies Saved",
                        systemImage: "person.2",
                        description: Text("Enter players and tap the bookmark icon to save them.")
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
                                    addedIDs.insert(buddy.id.uuidString)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(buddy.name).foregroundStyle(.primary)
                                        HStack(spacing: 4) {
                                            Text(String(format: "HCP %.1f", buddy.handicapIndex))
                                                .font(.caption).foregroundStyle(.secondary)
                                            if buddy.needsHIConfirmation {
                                                Image(systemName: "exclamationmark.circle.fill")
                                                    .font(.caption).foregroundStyle(.orange)
                                            }
                                        }
                                    }
                                    Spacer()
                                    let added = addedIDs.contains(buddy.id.uuidString)
                                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                        .foregroundStyle(added ? .green : .blue)
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
                pendingBuddy.map { "Still HCP \(String(format: "%.1f", $0.handicapIndex)), \($0.name)?" } ?? "",
                isPresented: Binding(
                    get: { pendingBuddy != nil && !showHIUpdate },
                    set: { if !$0 { pendingBuddy = nil } }
                )
            ) {
                Button("Yes, same HCP") {
                    if let b = pendingBuddy {
                        buddyStore.confirmHI(id: b.id)
                        onSelect(b)
                        addedIDs.insert(b.id.uuidString)
                    }
                    pendingBuddy = nil
                }
                Button("Update HCP") { showHIUpdate = true }
                Button("Cancel", role: .cancel) { pendingBuddy = nil }
            } message: {
                Text("It's been a while — confirm or update before adding.")
            }
            .alert("Update HCP for \(pendingBuddy?.name ?? "")", isPresented: $showHIUpdate) {
                TextField("New HCP (e.g. 14)", text: $updatedHIText).keyboardType(.decimalPad)
                Button("Save & Add") {
                    if let b = pendingBuddy, let newHI = Double(updatedHIText) {
                        buddyStore.updateHI(id: b.id, to: newHI)
                        if let updated = buddyStore.buddies.first(where: { $0.id == b.id }) {
                            onSelect(updated)
                            addedIDs.insert(b.id.uuidString)
                        }
                    }
                    pendingBuddy = nil; showHIUpdate = false
                }
                Button("Cancel", role: .cancel) { pendingBuddy = nil; showHIUpdate = false }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Screen 2: Select Games

private struct SetupScreen2_Games: View {
    @ObservedObject var vm: SaturdaySetupViewModel
    @Binding var path: [SaturdayRoute]

    private let allGames: [GameType] = [.nassau, .sixPointScotch, .stableford, .skins, .strokePlay]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(allGames, id: \.self) { game in
                    GameSelectCard(
                        game: game,
                        isSelected: vm.selectedGames.contains(game),
                        isDisabled: gameDisabled(game),
                        disabledReason: disabledReason(game)
                    ) {
                        vm.toggleGame(game)
                    }
                }

                if !vm.selectedGames.isEmpty {
                    continueButton
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func gameDisabled(_ game: GameType) -> Bool {
        switch game {
        case .sixPointScotch: return !vm.scotchEligible
        case .nassau, .stableford, .skins, .strokePlay: return false
        }
    }

    private func disabledReason(_ game: GameType) -> String? {
        switch game {
        case .sixPointScotch: return vm.scotchEligible ? nil : "Requires 4 players"
        default: return nil
        }
    }

    private var continueButton: some View {
        NavigationLink {
            nextScreen
        } label: {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var nextScreen: some View {
        if vm.requiresTeamScreen {
            SetupScreen3_Teams(vm: vm, path: $path)
                .navigationTitle("Teams")
        } else {
            SetupScreen4_Settings(vm: vm, path: $path)
                .navigationTitle("Game Settings")
        }
    }
}

private struct GameSelectCard: View {
    let game: GameType
    let isSelected: Bool
    let isDisabled: Bool
    let disabledReason: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(isDisabled ? .secondary : cardColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(game.title)
                        .font(.headline)
                        .foregroundStyle(isDisabled ? .secondary : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let reason = disabledReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                if !isDisabled {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? .green : .secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.green.opacity(0.08) : Color(.secondarySystemGroupedBackground))
                    .stroke(isSelected ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
        .disabled(isDisabled)
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch game {
        case .nassau: return "trophy.fill"
        case .sixPointScotch: return "flame.fill"
        case .stableford: return "list.number"
        case .skins: return "dollarsign.circle.fill"
        case .strokePlay: return "figure.golf"
        }
    }

    private var cardColor: Color {
        switch game {
        case .nassau: return .yellow
        case .sixPointScotch: return .orange
        case .stableford: return .blue
        case .skins: return .green
        case .strokePlay: return .teal
        }
    }

    private var subtitle: String {
        switch game {
        case .nassau: return "Front · Back · Overall match play"
        case .sixPointScotch: return "Points per hole · 2v2 teams required"
        case .stableford: return "Points scoring · individual or team 2v2"
        case .skins: return "Hole-by-hole individual skins"
        case .strokePlay: return "Gross & net leaderboard"
        }
    }
}

// MARK: - Screen 3: Teams

private struct SetupScreen3_Teams: View {
    @ObservedObject var vm: SaturdaySetupViewModel
    @Binding var path: [SaturdayRoute]

    var body: some View {
        Form {
            // Auto-pairing banner
            Section {
                if vm.customPairings == nil {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.green)
                        Text("Balanced teams based on handicap")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            // Teams display
            let pairings = vm.effectivePairings
            ForEach(pairings) { pairing in
                Section {
                    let teamColor: Color = pairing.team == .teamA ? .blue : .orange
                    let teamLabel = pairing.team == .teamA ? "Team A" : "Team B"
                    let totalHCP = pairing.players.reduce(0.0) { $0 + $1.handicapIndex }

                    HStack {
                        Text(teamLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(teamColor)
                        Spacer()
                        Text(String(format: "Total HCP %.0f", totalHCP))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                    ForEach(pairing.players) { player in
                        HStack {
                            Text(player.name)
                            Spacer()
                            Text(String(format: "%.0f", player.handicapIndex))
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
            }

            // Reset to auto
            if vm.customPairings != nil {
                Section {
                    Button("Reset to Auto-Pairing") {
                        vm.resetPairings()
                    }
                    .foregroundStyle(.orange)
                }
            }

            // Continue
            Section {
                NavigationLink {
                    SetupScreen4_Settings(vm: vm, path: $path)
                        .navigationTitle("Game Settings")
                } label: {
                    HStack {
                        Spacer()
                        Text("Continue")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green)
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
        }
    }
}

// MARK: - Screen 4: Game Settings

private struct SetupScreen4_Settings: View {
    @ObservedObject var vm: SaturdaySetupViewModel
    @Binding var path: [SaturdayRoute]
    @EnvironmentObject private var store: AppSessionStore
    @State private var rulesGame: SaturdayGameConfig?

    var body: some View {
        Form {
            // Nassau settings
            if vm.selectedGames.contains(.nassau) {
                Section {
                    if vm.nassauFourballEligible {
                        Picker("Format", selection: $vm.nassauConfig.format) {
                            Text("2v2 Fourball").tag(NassauFormat.fourball)
                            Text("1v1 Singles").tag(NassauFormat.singles)
                        }
                    }

                    StakeRow(label: "Front Stake", value: $vm.nassauConfig.frontStake)
                    StakeRow(label: "Back Stake", value: $vm.nassauConfig.backStake)
                    StakeRow(label: "Overall Stake", value: $vm.nassauConfig.overallStake)

                    Toggle("Auto Press", isOn: Binding(
                        get: { vm.nassauConfig.pressConfig.autoPressTrigger != nil },
                        set: { vm.nassauConfig.pressConfig.autoPressTrigger = $0 ? 2 : nil }
                    ))

                    if vm.nassauConfig.pressConfig.autoPressTrigger != nil {
                        Stepper(
                            "Trigger: \(vm.nassauConfig.pressConfig.autoPressTrigger ?? 2) down",
                            value: Binding(
                                get: { vm.nassauConfig.pressConfig.autoPressTrigger ?? 2 },
                                set: { vm.nassauConfig.pressConfig.autoPressTrigger = $0 }
                            ),
                            in: 1...4
                        )
                    }
                } header: {
                    sectionHeader(title: "Nassau") {
                        rulesGame = .nassau(vm.nassauConfig)
                    }
                } footer: {
                    Text("Stake = amount per bet. Nassau has 3 bets: front, back, overall.")
                        .font(.caption)
                }
            }

            // Scotch settings
            if vm.selectedGames.contains(.sixPointScotch) {
                Section {
                    HStack {
                        Text("$ per Point")
                        Spacer()
                        TextField("1", value: $vm.scotchConfig.pointValue, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                } header: {
                    sectionHeader(title: "Six Point Scotch") {
                        rulesGame = .scotch(vm.scotchConfig)
                    }
                } footer: {
                    Text("Points per hole × multiplier. Umbrella sweep = 12 pts.")
                        .font(.caption)
                }
            }

            // Stableford settings
            if vm.selectedGames.contains(.stableford) {
                Section {
                    Picker("Scoring", selection: $vm.stablefordConfig.scoringType) {
                        Text("Standard").tag(StablefordGameConfig.ScoringType.standard)
                        Text("Modified").tag(StablefordGameConfig.ScoringType.modified)
                    }
                    .pickerStyle(.segmented)

                    Picker("Mode", selection: $vm.stablefordConfig.format) {
                        Text("Individual").tag(StablefordGameConfig.Format.individual)
                        Text("Team 2v2").tag(StablefordGameConfig.Format.team2v2)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!vm.stablefordTeamEligible)
                } header: {
                    sectionHeader(title: "Stableford") {
                        rulesGame = .stableford(vm.stablefordConfig)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Standard: Eagle=4, Birdie=3, Par=2, Bogey=1, Double+=0")
                        if !vm.stablefordTeamEligible {
                            Text("Team 2v2 requires 4 players.")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                }
            }
            
            // Skins settings
            if vm.selectedGames.contains(.skins) {
                Section {
                    Picker("Mode", selection: $vm.skinsConfig.mode) {
                        Text("Gross").tag(SkinsMode.gross)
                        Text("Net").tag(SkinsMode.net)
                        Text("Both").tag(SkinsMode.both)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Carryover", isOn: $vm.skinsConfig.carryoverEnabled)

                    StakeRow(label: "$ per Skin", value: $vm.skinsConfig.skinValue)
                } header: {
                    sectionHeader(title: "Skins") {
                        rulesGame = .skins(vm.skinsConfig)
                    }
                } footer: {
                    Text(vm.skinsConfig.carryoverEnabled
                        ? "Tied holes carry the skin to the next hole."
                        : "Tied holes void the skin — no carryover.")
                        .font(.caption)
                }
            }

            // Stroke Play settings
            if vm.selectedGames.contains(.strokePlay) {
                Section {
                    Picker("Format", selection: $vm.strokePlayConfig.format) {
                        Text("Individual").tag(StrokePlayFormat.individual)
                        Text("2v2 Best Ball").tag(StrokePlayFormat.bestBall2v2)
                        Text("Team Best Ball").tag(StrokePlayFormat.teamBestBall)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: vm.strokePlayConfig.format) { _, _ in
                        // Clear pairings when format changes
                        vm.bestBallPairings = []
                    }
                    
                    if vm.strokePlayConfig.format != .individual && vm.playerCount == 4 {
                        NavigationLink {
                            StrokePlayTeamSetupView(vm: vm)
                                .navigationTitle("Best Ball Teams")
                        } label: {
                            HStack {
                                Text("Configure Teams")
                                Spacer()
                                if vm.bestBallPairings.isEmpty {
                                    Text("Not Set")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(vm.bestBallPairings.count) teams")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    sectionHeader(title: "Stroke Play") {
                        rulesGame = .strokePlay(vm.strokePlayConfig)
                    }
                } footer: {
                    if vm.strokePlayConfig.format == .individual {
                        Text("Individual leaderboard tracking gross and net scores.")
                            .font(.caption)
                    } else if vm.strokePlayConfig.format == .bestBall2v2 {
                        Text("Two teams of 2 players. Best ball score per hole.")
                            .font(.caption)
                    } else {
                        Text("All 4 players on one team. Best ball vs par.")
                            .font(.caption)
                    }
                }
            }

            // Start Round
            Section {
                Button {
                    vm.commit(into: store)
                    path.append(.roundScoring)
                } label: {
                    Label("Start Round", systemImage: "flag.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
        }
        .sheet(item: $rulesGame) { game in
            SetupGameRulesSheet(game: game)
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, onRulesTap: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button("Rules", action: onRulesTap)
                .font(.caption.weight(.semibold))
                .textCase(.none)
        }
    }
}

private struct SetupGameRulesSheet: View {
    let game: SaturdayGameConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rules(for: game), id: \.self) { rule in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(rule)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("\(game.type.title) Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func rules(for game: SaturdayGameConfig) -> [String] {
        switch game.type {
        case .sixPointScotch:
            return [
                "Per-hole buckets: Low Man 2, Low Team 2, Birdie 1, Prox 1.",
                "Low Man pays the team if the lowest score ties within the same side; across-team ties pay 0. Low Team ties pay 0.",
                "Birdie bucket follows natural birdies. A stroke-assisted birdie does not take away an umbrella earned by a natural birdie.",
                "Prox awards one winner only and requires natural GIR eligibility.",
                "Umbrella pays 12 raw points when one team sweeps all buckets.",
                "Press, roll, and re-roll adjust the per-hole multiplier."
            ]
        case .nassau:
            return [
                "Three bets run at once: Front, Back, and Overall.",
                "Each segment is match play (net scores).",
                "Auto press can trigger when a side goes a set number down.",
                "Manual presses are allowed for the trailing side."
            ]
        case .stableford:
            let mode = game.stablefordConfig?.format == .team2v2 ? "Team 2v2" : "Individual"
            let scoring = game.stablefordConfig?.scoringType == .modified ? "Modified" : "Standard"
            return [
                "Current mode: \(mode).",
                "Current scoring table: \(scoring).",
                "Standard table: Eagle=4, Birdie=3, Par=2, Bogey=1, Double or worse=0.",
                "Modified table (if selected): Eagle=5, Birdie=2, Par=0, Bogey=-1, Double=-3.",
                "Higher total points wins."
            ]
        case .skins:
            let mode: String
            switch game.skinsConfig?.mode {
            case .gross: mode = "Gross"
            case .net: mode = "Net"
            case .both: mode = "Both"
            case .none: mode = "Gross"
            }
            let carry = game.skinsConfig?.carryoverEnabled == true
                ? "Carryover is ON (ties roll to next hole)."
                : "Carryover is OFF (ties void the skin)."
            return [
                "Current mode: \(mode).",
                "Gross: lowest raw score on the hole wins the skin.",
                "Net: lowest handicap-adjusted score on the hole wins the skin.",
                "Both: gross and net skins are tracked side-by-side.",
                carry,
                "A skin is won by the unique lowest score on a hole.",
                "Most skins at round end wins."
            ]
        case .strokePlay:
            let format: String
            switch game.strokePlayConfig?.format {
            case .individual: format = "Individual"
            case .bestBall2v2: format = "2v2 Best Ball"
            case .teamBestBall: format = "Team Best Ball"
            case .none: format = "Individual"
            }
            return [
                "Current format: \(format).",
                "Scores track gross and net performance.",
                "Best-ball formats use the best score on each hole for the side/team."
            ]
        }
    }
}

private struct StakeRow: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("$")
                .foregroundStyle(.secondary)
            TextField("5", value: $value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
        }
    }
}

// MARK: - Stroke Play Team Setup

private struct StrokePlayTeamSetupView: View {
    @ObservedObject var vm: SaturdaySetupViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            if vm.strokePlayConfig.format == .bestBall2v2 {
                bestBall2v2View
            } else if vm.strokePlayConfig.format == .teamBestBall {
                teamBestBallView
            }
            
            Section {
                Button("Done") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            initializePairingsIfNeeded()
        }
    }
    
    private var bestBall2v2View: some View {
        Group {
            Section {
                ForEach(0..<2) { teamIndex in
                    let teamLetter = teamIndex == 0 ? "A" : "B"
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Team \(teamLetter)")
                            .font(.headline)
                        
                        if teamIndex < vm.bestBallPairings.count {
                            ForEach(vm.bestBallPairings[teamIndex].playerIDs, id: \.self) { playerID in
                                if let player = vm.activePlayers.first(where: { $0.id.uuidString == playerID }) {
                                    HStack {
                                        Text(player.name)
                                        Spacer()
                                        Text("HI: \(player.handicapIndex, specifier: "%.1f")")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Team Assignments")
            } footer: {
                Text("Tap 'Shuffle Teams' to randomize, or manually assign players.")
                    .font(.caption)
            }
            
            Section {
                Button("Shuffle Teams") {
                    shuffleTeams()
                }
                Button("Balance by Handicap") {
                    balanceByHandicap()
                }
            }
        }
    }
    
    private var teamBestBallView: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("The Team")
                    .font(.headline)
                
                ForEach(vm.activePlayers) { player in
                    HStack {
                        Text(player.name)
                        Spacer()
                        Text("HI: \(player.handicapIndex, specifier: "%.1f")")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("All Players on One Team")
        } footer: {
            Text("Best ball score vs par for all 4 players.")
                .font(.caption)
        }
    }
    
    private func initializePairingsIfNeeded() {
        if vm.bestBallPairings.isEmpty {
            if vm.strokePlayConfig.format == .bestBall2v2 {
                balanceByHandicap()
            } else if vm.strokePlayConfig.format == .teamBestBall {
                let allPlayerIDs = vm.activePlayers.map { $0.id.uuidString }
                vm.bestBallPairings = [
                    BestBallPairing(teamName: "The Team", playerIDs: allPlayerIDs)
                ]
            }
        }
    }
    
    private func shuffleTeams() {
        let shuffled = vm.activePlayers.shuffled()
        vm.bestBallPairings = [
            BestBallPairing(
                teamName: "Team A",
                playerIDs: [shuffled[0].id.uuidString, shuffled[1].id.uuidString]
            ),
            BestBallPairing(
                teamName: "Team B",
                playerIDs: [shuffled[2].id.uuidString, shuffled[3].id.uuidString]
            )
        ]
    }
    
    private func balanceByHandicap() {
        let sorted = vm.activePlayers.sorted { $0.handicapIndex < $1.handicapIndex }
        guard sorted.count == 4 else { return }
        
        vm.bestBallPairings = [
            BestBallPairing(
                teamName: "Team A",
                playerIDs: [sorted[0].id.uuidString, sorted[3].id.uuidString]
            ),
            BestBallPairing(
                teamName: "Team B",
                playerIDs: [sorted[1].id.uuidString, sorted[2].id.uuidString]
            )
        ]
    }
}
