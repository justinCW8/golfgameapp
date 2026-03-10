import SwiftUI

// MARK: - Route

enum SaturdayRoute: Hashable {
    case roundSetup
    case roundScoring
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject private var store: AppSessionStore
    @EnvironmentObject private var buddyStore: BuddyStore
    @State private var path: [SaturdayRoute] = []
    @State private var showNewRoundAlert = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let round = store.activeSaturdayRound {
                    activeRoundView(round)
                } else {
                    noRoundView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SaturdayRoute.self) { route in
                switch route {
                case .roundSetup:
                    SaturdayRoundSetupFlow(path: $path)
                case .roundScoring:
                    SaturdayScoringView(path: $path)
                }
            }
        }
    }

    // MARK: - State A: No active round

    private var noRoundView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.98, blue: 0.96), Color(red: 0.92, green: 0.95, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.green.opacity(0.12))
                .frame(width: 360, height: 360)
                .offset(x: 150, y: -260)

            Circle()
                .fill(Color.blue.opacity(0.08))
                .frame(width: 280, height: 280)
                .offset(x: -170, y: 260)

            VStack(spacing: 18) {
                heroCard

                Button {
                    path.append(.roundSetup)
                } label: {
                    VStack(spacing: 2) {
                        Label("Start Round", systemImage: "plus.circle.fill")
                            .font(.headline)
                        Text("New setup in about 20 seconds")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.12, green: 0.63, blue: 0.35))
                .controlSize(.large)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                quickUtilityRow

                if !buddyStore.buddies.isEmpty {
                    recentPlayersPreview
                } else {
                    Text("Add buddies in Settings to prefill your Saturday foursome.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 0)
            .padding(.bottom, 12)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                SaturdayBrandMark()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Game Day Golf")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Side rounds with your crew")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                HomeStatPill(label: "Mode", value: "Game Day")
                HomeStatPill(label: "Players", value: "2-4")
                HomeStatPill(label: "Buddies", value: "\(buddyStore.buddies.count)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.45), lineWidth: 1)
        )
    }

    private var quickUtilityRow: some View {
        HStack(spacing: 10) {
            QuickUtilityChip(
                title: "Buddies",
                subtitle: "\(buddyStore.buddies.count) saved",
                systemImage: "person.2.fill"
            )
            QuickUtilityChip(
                title: "Last Round",
                subtitle: store.completedRounds.isEmpty ? "No history" : "View history tab",
                systemImage: "clock.arrow.circlepath"
            )
        }
    }

    private var recentPlayersPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Players")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(buddyStore.buddies.prefix(6)) { buddy in
                        VStack(alignment: .leading, spacing: 8) {
                            Circle()
                                .fill(Color(.systemBackground))
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Text(String(buddy.name.prefix(1)))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.primary)
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(buddy.name.components(separatedBy: " ").first ?? buddy.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(String(format: "HCP %.1f", buddy.handicapIndex))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - State B: Active round

    private func activeRoundView(_ round: SaturdayRound) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                activeRoundCard(round)
                    .padding(20)
            }

            VStack(spacing: 12) {
                Button {
                    path.append(.roundScoring)
                } label: {
                    Label("Resume Round", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)

                Button("Start New Round", role: .destructive) {
                    showNewRoundAlert = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .alert("Start New Round?", isPresented: $showNewRoundAlert) {
            Button("Discard & Start New", role: .destructive) {
                store.clearSaturdayRound()
                path.append(.roundSetup)
            }
            Button("Keep Current", role: .cancel) {}
        } message: {
            Text("Your current round will be discarded.")
        }
    }

    private func activeRoundCard(_ round: SaturdayRound) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Course + progress
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(round.courseName)
                        .font(.headline)
                    Text("Hole \(round.currentHole) of 18")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(round.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Active games as pills
            HStack(spacing: 8) {
                ForEach(round.activeGames) { game in
                    Text(game.type.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12), in: Capsule())
                        .foregroundStyle(.green)
                }
                Spacer()
            }

            Divider()

            // Players / teams
            if round.requiresTeams {
                teamsRow(round)
            } else {
                playersRow(round.players)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func teamsRow(_ round: SaturdayRound) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Team A")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                ForEach(round.teamAPlayers) { p in
                    Text(p.name).font(.subheadline)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Team B")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                ForEach(round.teamBPlayers) { p in
                    Text(p.name).font(.subheadline)
                }
            }
        }
    }

    private func playersRow(_ players: [PlayerSnapshot]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(players.enumerated()), id: \.element.id) { index, p in
                Text(p.name).font(.subheadline)
                if index < players.count - 1 {
                    Text("·").foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

private struct SaturdayBrandMark: View {
    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.06, green: 0.36, blue: 0.22), Color(red: 0.14, green: 0.62, blue: 0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color(red: 0.53, green: 0.82, blue: 0.49))
                .frame(width: 56, height: 56)

            Circle()
                .fill(.white.opacity(0.96))
                .frame(width: 38, height: 38)
                .overlay {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.black.opacity(0.16)).frame(width: 3, height: 3)
                            Circle().fill(Color.black.opacity(0.16)).frame(width: 3, height: 3)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.black.opacity(0.16)).frame(width: 3, height: 3)
                            Circle().fill(Color.black.opacity(0.16)).frame(width: 3, height: 3)
                        }
                    }
                }
                .offset(x: -5, y: 8)

            Rectangle()
                .fill(.white)
                .frame(width: 2.5, height: 24)
                .offset(x: 14, y: -7)

            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 16, y: 5))
                p.addLine(to: CGPoint(x: 0, y: 11))
                p.closeSubpath()
            }
            .fill(Color(red: 1.00, green: 0.90, blue: 0.25))
            .frame(width: 16, height: 11, alignment: .leading)
            .offset(x: 22, y: -12)
        }
        .frame(width: 82, height: 82)
    }
}

private struct HomeStatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct QuickUtilityChip: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.08, green: 0.47, blue: 0.29))
                .padding(7)
                .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Profile placeholder

struct ProfileView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject private var store: AppSessionStore
    @EnvironmentObject private var buddyStore: BuddyStore
    @AppStorage("useStepperScoring") private var useStepperScoring = true

    var body: some View {
        NavigationStack {
            Form {
                if store.activeSaturdayRound != nil {
                    Section {
                        Button {
                            selectedTab = 0
                        } label: {
                            Label("Return to Game", systemImage: "flag.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.green)
                    }
                }

                Section {
                    Toggle(isOn: $useStepperScoring) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stepper Input")
                            Text(useStepperScoring ? "− score +" : "Tap a score button")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Score Entry Style")
                } footer: {
                    Text("Stepper uses + / − buttons — one row per player, works at any text size. Button grid shows all scores at once.")
                }

                Section {
                    NavigationLink {
                        BuddyManagerView()
                            .environmentObject(buddyStore)
                    } label: {
                        HStack {
                            Label("Manage Buddies", systemImage: "person.2.fill")
                            Spacer()
                            Text("\(buddyStore.buddies.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Buddies")
                } footer: {
                    Text("Add a phone number for each buddy to pre-fill recipients when texting scorecards and settlements.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct BuddyManagerView: View {
    @EnvironmentObject private var buddyStore: BuddyStore
    @State private var editingBuddy: Buddy?
    @State private var showAdd = false

    var body: some View {
        List {
            ForEach(buddyStore.buddies) { buddy in
                Button {
                    editingBuddy = buddy
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(buddy.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            Text(String(format: "HCP %.1f", buddy.handicapIndex))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let phone = buddy.phoneNumber, !phone.isEmpty {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(phone)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { buddyStore.remove(at: $0) }
        }
        .navigationTitle("Manage Buddies")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Label("Add Buddy", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            BuddyEditorView()
                .environmentObject(buddyStore)
        }
        .sheet(item: $editingBuddy) { buddy in
            BuddyEditorView(existingBuddy: buddy)
                .environmentObject(buddyStore)
        }
    }
}

private struct BuddyEditorView: View {
    @EnvironmentObject private var buddyStore: BuddyStore
    @Environment(\.dismiss) private var dismiss

    let existingBuddy: Buddy?

    @State private var name: String
    @State private var handicapText: String
    @State private var phoneNumber: String
    @State private var showDuplicateAlert = false

    init(existingBuddy: Buddy? = nil) {
        self.existingBuddy = existingBuddy
        _name = State(initialValue: existingBuddy?.name ?? "")
        if let handicap = existingBuddy?.handicapIndex {
            _handicapText = State(initialValue: String(format: "%.1f", handicap))
        } else {
            _handicapText = State(initialValue: "0.0")
        }
        _phoneNumber = State(initialValue: existingBuddy?.phoneNumber ?? "")
    }

    private var title: String {
        existingBuddy == nil ? "Add Buddy" : "Edit Buddy"
    }

    private var saveLabel: String {
        existingBuddy == nil ? "Add" : "Save"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Buddy") {
                    TextField("Name", text: $name)
                    TextField("Handicap Index", text: $handicapText)
                        .keyboardType(.decimalPad)
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) { saveBuddy() }
                }
            }
            .alert("Buddy Name Exists", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Use a unique name for each buddy.")
            }
        }
    }

    private func saveBuddy() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let existingNameConflict = buddyStore.buddies.contains {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame && $0.id != existingBuddy?.id
        }
        guard !existingNameConflict else {
            showDuplicateAlert = true
            return
        }

        let handicap = min(max(Double(handicapText) ?? 0, 0), 54)
        let normalizedPhone = BuddyStore.normalizedPhoneNumber(phoneNumber)

        if var buddy = existingBuddy {
            buddy.name = trimmedName
            buddy.handicapIndex = handicap
            buddy.phoneNumber = normalizedPhone
            buddyStore.update(buddy)
        } else {
            buddyStore.add(name: trimmedName, handicapIndex: handicap, phoneNumber: normalizedPhone)
        }
        dismiss()
    }
}
