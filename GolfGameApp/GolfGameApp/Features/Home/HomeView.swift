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
            .navigationTitle("Saturday")
            .navigationBarTitleDisplayMode(.large)
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
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)

                VStack(spacing: 6) {
                    Text("Saturday Money Mode")
                        .font(.title2.weight(.bold))
                    Text("Four players. One tee. Zero math disputes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    path.append(.roundSetup)
                } label: {
                    Label("Start Round", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .padding(.horizontal, 24)

                if !buddyStore.buddies.isEmpty {
                    recentPlayersPreview
                }
            }
            .padding(.bottom, 40)
        }
    }

    private var recentPlayersPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Players")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(buddyStore.buddies.prefix(6)) { buddy in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color(.secondarySystemBackground))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(String(buddy.name.prefix(1)))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                )
                            Text(buddy.name.components(separatedBy: " ").first ?? buddy.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
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

// MARK: - Profile placeholder

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Profile",
                systemImage: "person.circle",
                description: Text("Coming soon.")
            )
            .navigationTitle("Profile")
        }
    }
}
