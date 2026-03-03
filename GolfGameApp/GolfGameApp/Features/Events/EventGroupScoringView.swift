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

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(.body.weight(.medium))
                    Text("CH \(viewModel.courseHandicap(for: player))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if strokes > 0 {
                    HStack(spacing: 3) {
                        ForEach(0..<min(strokes, 3), id: \.self) { _ in
                            Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                        }
                        if strokes > 3 {
                            Text("+\(strokes - 3)")
                                .font(.caption2)
                                .foregroundStyle(.accentColor)
                        }
                    }
                }

                Spacer()

                Button {
                    viewModel.togglePickup(for: player)
                } label: {
                    Text("Pickup")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isPickup ? Color.orange.opacity(0.15) : Color(.tertiarySystemBackground))
                        .foregroundStyle(isPickup ? .orange : .secondary)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(isPickup ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)

                if isPickup {
                    Text("PU")
                        .frame(width: 56)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else {
                    TextField("Gross", text: Binding(
                        get: { viewModel.grossText(for: player.id) },
                        set: { viewModel.setGrossText($0, for: player.id) }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
                    .padding(.vertical, 7)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack {
                Spacer()
                let net = viewModel.netPreview(for: player)
                let pts = viewModel.pointsPreview(for: player)
                Text("Net: \(net)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·").font(.caption).foregroundStyle(.tertiary)
                Text("\(pts) pts")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(pointsColor(pts))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func pointsColor(_ pts: String) -> Color {
        guard let n = Int(pts) else { return .secondary }
        if n >= 4 { return .purple }
        if n >= 3 { return .green }
        if n >= 2 { return .primary }
        if n >= 1 { return .secondary }
        return .tertiary
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Running Totals")
                .font(.subheadline.weight(.semibold))

            ForEach(viewModel.groupPlayers) { player in
                HStack {
                    Text(player.name)
                        .font(.subheadline)
                    Spacer()
                    Text("\(viewModel.runningTotal(for: player.id)) pts")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom)
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
