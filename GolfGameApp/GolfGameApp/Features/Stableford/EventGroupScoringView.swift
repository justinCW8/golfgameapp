import SwiftUI

struct EventGroupScoringView: View {
    @StateObject private var viewModel: EventGroupScoringViewModel

    init(session: SessionModel, groupID: String) {
        _viewModel = StateObject(wrappedValue: EventGroupScoringViewModel(sessionStore: session, groupID: groupID))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                holeHeader

                if !viewModel.isComplete {
                    playerInputSection
                    actionSection
                } else {
                    completedBanner
                }

                if !viewModel.lastScoredResults.isEmpty {
                    lastHoleResultsSection
                }

                runningTotalsSection
            }
            .padding(.vertical)
        }
        .navigationTitle(viewModel.groupName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.seedInputs() }
    }

    // MARK: - Hole Header

    private var holeHeader: some View {
        VStack(spacing: 6) {
            if viewModel.isComplete {
                Text("18 Holes Complete")
                    .font(.title3.weight(.semibold))
            } else {
                Text("Hole \(viewModel.currentHole) of 18")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 20) {
                    Label("Par \(viewModel.currentPar)", systemImage: "flag.fill")
                    Label("SI \(viewModel.currentStrokeIndex)", systemImage: "arrow.up.arrow.down")
                    if viewModel.currentYardage > 0 {
                        Label("\(viewModel.currentYardage) yds", systemImage: "ruler")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Player Input

    private var playerInputSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.groupPlayers.enumerated()), id: \.element.id) { index, player in
                VStack(spacing: 0) {
                    playerRow(player)
                    if index < viewModel.groupPlayers.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .padding(.horizontal)
    }

    private func playerRow(_ player: PlayerSnapshot) -> some View {
        let isPickup = viewModel.isPickup(for: player.id)
        let strokes = viewModel.strokeCount(for: player)
        let par = viewModel.currentPar
        let gross = Int(viewModel.grossText(for: player.id))
        let lo = max(1, par - 2)
        let scores = Array(lo...(par + 2))
        let overflowMin = par + 3
        let overflowSelected = !isPickup && (gross ?? -1) >= overflowMin

        return VStack(alignment: .leading, spacing: 4) {
            // Player info
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name).font(.body.weight(.medium))
                    HStack(spacing: 3) {
                        Text("CH \(viewModel.courseHandicap(for: player))")
                            .font(.caption2).foregroundStyle(.secondary)
                        if strokes > 0 {
                            HStack(spacing: 2) {
                                ForEach(0..<min(strokes, 3), id: \.self) { _ in
                                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                }
                                if strokes > 3 { Text("+\(strokes-3)").font(.caption2).foregroundStyle(Color.accentColor) }
                            }
                        }
                    }
                }
                Spacer()
                Button { viewModel.togglePickup(for: player) } label: {
                    Text("Pickup")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(isPickup ? Color.orange.opacity(0.15) : Color(.tertiarySystemBackground))
                        .foregroundStyle(isPickup ? .orange : .secondary)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(isPickup ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // Score buttons or pickup banner
            if isPickup {
                Text("Picked Up")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 5) {
                    ForEach(scores, id: \.self) { score in
                        let isSelected = gross == score
                        let netDelta = score - strokes - par
                        Button { viewModel.setGrossText(isSelected ? "" : String(score), for: player.id) } label: {
                            Text("\(score)")
                                .font(.callout.weight(isSelected ? .bold : .regular))
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(
                                    isSelected ? stablefordTint(netDelta: netDelta) : Color(.tertiarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                    if overflowSelected {
                        HStack(spacing: 3) {
                            Button {
                                let cur = gross ?? overflowMin
                                viewModel.setGrossText(cur > overflowMin ? String(cur - 1) : "", for: player.id)
                            } label: {
                                Image(systemName: "minus").font(.caption.weight(.bold))
                                    .frame(width: 28, height: 40)
                                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            let g = gross ?? overflowMin
                            Text("\(g)").font(.callout.weight(.bold))
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(stablefordTint(netDelta: g - strokes - par), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                            Button {
                                viewModel.setGrossText(String((gross ?? overflowMin) + 1), for: player.id)
                            } label: {
                                Image(systemName: "plus").font(.caption.weight(.bold))
                                    .frame(width: 28, height: 40)
                                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button { viewModel.setGrossText(String(overflowMin), for: player.id) } label: {
                            Text("\(overflowMin)+")
                                .font(.callout.weight(.regular))
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Result preview
            if !isPickup {
                let net = viewModel.netPreview(for: player)
                let pts = viewModel.pointsPreview(for: player)
                if net != "—" {
                    HStack(spacing: 4) {
                        Spacer()
                        Text("Net: \(net)").font(.caption2).foregroundStyle(.secondary)
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        Text("\(pts) pts").font(.caption2.weight(.semibold)).foregroundStyle(pointsColor(pts))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func stablefordTint(netDelta: Int) -> Color {
        switch netDelta {
        case ...(-2): return Color(red: 0.85, green: 0.65, blue: 0.10)
        case -1: return .green
        case 0: return Color.accentColor
        case 1: return .orange
        default: return .red
        }
    }

    private func pointsColor(_ pts: String) -> Color {
        guard let n = Int(pts) else { return .secondary }
        if n >= 4 { return .purple }
        if n >= 3 { return .green }
        if n >= 2 { return .primary }
        if n >= 1 { return .secondary }
        return Color.secondary.opacity(0.4)
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(spacing: 10) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                viewModel.scoreHole()
            } label: {
                Text("Score Hole \(viewModel.currentHole)")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canScore)

            if viewModel.currentHole > 1 {
                Button {
                    viewModel.editLastHole()
                } label: {
                    Label("Edit Hole \(viewModel.currentHole - 1)", systemImage: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    // MARK: - Last Hole Results

    private var lastHoleResultsSection: some View {
        let holeNum = viewModel.lastScoredResults.first?.holeNumber ?? 0
        let playerByID = Dictionary(
            uniqueKeysWithValues: (viewModel.event?.players ?? []).map { ($0.id, $0) }
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text("Hole \(holeNum) — Results")
                .font(.subheadline.weight(.semibold))

            ForEach(viewModel.lastScoredResults) { result in
                HStack {
                    Text(playerByID[result.playerID]?.name ?? "Player")
                        .font(.subheadline)
                    Spacer()
                    Text("Gross \(result.gross) · Net \(result.net)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(result.points) pts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(result.points >= 3 ? .green : result.points >= 2 ? .primary : .secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Running Totals

    private var runningTotalsSection: some View {
        let rows = viewModel.event.map { EventGroupScoringViewModel.leaderboardRows(from: $0) } ?? []
        let thru = viewModel.event.map { EventGroupScoringViewModel.maxCompletedHole(from: $0) } ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Leaderboard")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if thru > 0 {
                    Text(thru == 18 ? "Final" : "Thru \(thru)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if rows.isEmpty {
                Text("No scores yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    leaderboardRow(rank: idx + 1, row: row)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom)
    }

    private func leaderboardRow(rank: Int, row: StablefordLeaderboardRow) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption.weight(.bold))
                .foregroundStyle(rank == 1 ? Color.accentColor : .secondary)
                .frame(width: 18, alignment: .center)

            Text(row.player.name)
                .font(.subheadline)
                .fontWeight(rank == 1 ? .semibold : .regular)

            Spacer()

            if row.thruHole > 0 {
                Text(row.thruHole == 18 ? "F" : "T\(row.thruHole)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }

            Text("\(row.totalPoints)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
            Text("pts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Completed

    private var completedBanner: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Group Complete")
                .font(.headline)
            Text("All 18 holes scored.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
