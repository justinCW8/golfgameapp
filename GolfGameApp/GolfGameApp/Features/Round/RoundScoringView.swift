import SwiftUI

struct RoundScoringView: View {
    @StateObject private var viewModel: RoundScoringViewModel

    init(session: SessionModel) {
        _viewModel = StateObject(wrappedValue: RoundScoringViewModel(sessionStore: session))
    }

    var body: some View {
        Form {
            Section("Tee Box") {
                Text("Hole \(viewModel.currentHole) • Par \(viewModel.currentHolePar) • SI \(viewModel.currentHoleStrokeIndex)")
                Text("Status: \(viewModel.nineStatusText)")
                    .font(.headline)
                if let teesFirst = viewModel.teesFirstTeam {
                    Text("Tee order: \(teamName(teesFirst)) tees first")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tee order: Set tee toss to start round")
                        .foregroundStyle(.secondary)
                }
                if let leading = viewModel.leadingTeam, let trailing = viewModel.trailingTeam {
                    Text("Lead: \(teamName(leading)) over \(teamName(trailing))")
                        .foregroundStyle(.secondary)
                }

                if viewModel.requiresTeeTossChoice {
                    Text("Select tee toss before scoring Hole 1")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("\(viewModel.teamAName) tees first") {
                            viewModel.setTeeTossFirst(.teamA)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("\(viewModel.teamBName) tees first") {
                            viewModel.setTeeTossFirst(.teamB)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack {
                    Button(
                        viewModel.leaderTeedOff
                        ? "\(teamName(viewModel.teesFirstTeam ?? .teamA)) Teed Off ✓"
                        : "\(teamName(viewModel.teesFirstTeam ?? .teamA)) Teed Off"
                    ) {
                        viewModel.leaderTeedOffTapped()
                    }
                    .disabled(
                        viewModel.requiresTeeTossChoice ||
                        viewModel.leaderTeedOff ||
                        viewModel.hasScoredCurrentHole
                    )

                    Button(
                        viewModel.trailerTeedOff
                        ? "\(teamName(viewModel.teesSecondTeam ?? .teamB)) Teed Off ✓"
                        : "\(teamName(viewModel.teesSecondTeam ?? .teamB)) Teed Off"
                    ) {
                        viewModel.trailerTeedOffTapped()
                    }
                    .disabled(
                        viewModel.requiresTeeTossChoice ||
                        viewModel.trailerTeedOff ||
                        !viewModel.leaderTeedOff ||
                        viewModel.hasScoredCurrentHole
                    )
                }

                if viewModel.canRequestPress || viewModel.requestPress {
                    Button(viewModel.requestPress ? "Press Selected ✓" : "Press") {
                        viewModel.pressTapped()
                    }
                    .disabled(!viewModel.canRequestPress && !viewModel.requestPress)
                }

                if viewModel.canRequestRoll || viewModel.requestRoll {
                    Button(viewModel.requestRoll ? "Roll Selected ✓" : "Roll") {
                        viewModel.rollTapped()
                    }
                    .disabled(!viewModel.canRequestRoll && !viewModel.requestRoll)
                }

                if viewModel.canRequestReroll || viewModel.requestReroll {
                    Button(viewModel.requestReroll ? "Re-roll Selected ✓" : "Re-roll") {
                        viewModel.rerollTapped()
                    }
                    .disabled(!viewModel.canRequestReroll && !viewModel.requestReroll)
                }

                Text("Presses remaining this nine: \(viewModel.pressesRemainingThisNine)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Player Gross / Net") {
                ForEach(Array(viewModel.players.enumerated()), id: \.element.id) { index, player in
                    PlayerScoreRow(
                        player: player,
                        gross: grossBinding(at: index),
                        grossNetStrokeText: viewModel.grossNetStrokeDisplay(forPlayerAt: index),
                        strokeCount: viewModel.strokesDisplay(forPlayerAt: index),
                        proxSelected: selectedProxWinner(for: index) == viewModel.proxWinner,
                        onTapProx: { viewModel.proxWinner = selectedProxWinner(for: index) }
                    )
                }
                Text(viewModel.teamHoleSummaryDisplay(for: .teamA))
                    .font(.subheadline)
                Text(viewModel.teamHoleSummaryDisplay(for: .teamB))
                    .font(.subheadline)
                if viewModel.proxWinner == .none {
                    Button("None / No GIR ✓") {
                        viewModel.proxWinner = .none
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("None / No GIR") {
                        viewModel.proxWinner = .none
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section {
                Button("Score Hole") {
                    viewModel.scoreCurrentHole()
                }
                .disabled(viewModel.isRoundComplete || viewModel.hasScoredCurrentHole || !viewModel.canScore)
            }

            if let output = viewModel.lastOutput {
                Section("Hole Results (Hole \(output.holeNumber))") {
                    Text("Raw \(viewModel.teamAName) / \(viewModel.teamBName): \(output.rawTeamAPoints) / \(output.rawTeamBPoints)")
                    Text("Multiplier: x\(output.multiplier)")
                    Text("Multiplied \(viewModel.teamAName) / \(viewModel.teamBName): \(output.multipliedTeamAPoints) / \(output.multipliedTeamBPoints)")
                }

                Section("Running Totals") {
                    Text("Status: \(viewModel.overallStatusText)")
                        .font(.headline)
                    if let leading = viewModel.overallLeadingTeamName {
                        Text("Leader: \(leading)")
                            .foregroundStyle(.secondary)
                    }
                    Text("Front Nine \(viewModel.teamAName) / \(viewModel.teamBName): \(output.frontNineTeamA) / \(output.frontNineTeamB)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Back Nine \(viewModel.teamAName) / \(viewModel.teamBName): \(output.backNineTeamA) / \(output.backNineTeamB)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Overall \(viewModel.teamAName) / \(viewModel.teamBName): \(output.totalTeamA) / \(output.totalTeamB)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !viewModel.latestAuditLines.isEmpty {
                    Section("Audit Log") {
                        ForEach(viewModel.latestAuditLines, id: \.self) { line in
                            Text(line)
                                .font(.footnote)
                        }
                    }
                }
            }

            Section {
                NavigationLink("View Scorecard") {
                    RoundScorecardView(viewModel: viewModel)
                }
                .disabled(viewModel.holeResults.isEmpty)
            }

            Section {
                Button("Next Hole") {
                    viewModel.goToNextHole()
                }
                .disabled(!viewModel.hasScoredCurrentHole || viewModel.currentHole >= 18)

                if viewModel.isRoundComplete {
                    Text("Round complete at 18 holes.")
                }
            }

            if viewModel.isRoundComplete {
                roundSummarySection
            }

            if let error = viewModel.errorMessage {
                Section("Error") {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Scotch Scoring")
    }

    private var roundSummarySection: some View {
        Section("Round Summary") {
            if let output = viewModel.lastOutput {
                Text("Scotch Total \(viewModel.teamAName) / \(viewModel.teamBName): \(output.totalTeamA) / \(output.totalTeamB)")
            }
            ForEach(viewModel.players) { player in
                let gross = viewModel.totalGrossByPlayerID[player.id, default: 0]
                let net = viewModel.totalNetByPlayerID[player.id, default: 0]
                Text("\(player.name): Gross \(gross), Net \(net)")
            }
        }
    }

    private func grossBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.playerGrossInputs.indices.contains(index) else { return "" }
                return viewModel.playerGrossInputs[index]
            },
            set: { newValue in
                guard viewModel.playerGrossInputs.indices.contains(index) else { return }
                viewModel.playerGrossInputs[index] = newValue
            }
        )
    }

    private func teamName(_ team: TeamSide) -> String {
        viewModel.teamDisplayName(for: team)
    }

    private func selectedProxWinner(for index: Int) -> ProxWinner {
        switch index {
        case 0: return .player1
        case 1: return .player2
        case 2: return .player3
        case 3: return .player4
        default: return .none
        }
    }
}

private struct PlayerScoreRow: View {
    let player: PlayerSnapshot
    @Binding var gross: String
    let grossNetStrokeText: String
    let strokeCount: Int
    let proxSelected: Bool
    let onTapProx: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(player.name)
                Text("HI \(player.handicapIndex, specifier: "%.1f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(grossNetStrokeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Gross", text: $gross)
                .keyboardType(.numberPad)
                .frame(maxWidth: 80)
                .multilineTextAlignment(.trailing)
            if strokeCount > 0 {
                Text("+\(strokeCount)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.18), in: Capsule())
            }
            if proxSelected {
                Button("PRO ✓", action: onTapProx)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("PRO", action: onTapProx)
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct RoundScorecardView: View {
    @ObservedObject var viewModel: RoundScoringViewModel

    var body: some View {
        List {
            Section("Holes") {
                ForEach(viewModel.sortedHoleResults) { result in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hole \(result.holeNumber)")
                            .font(.headline)

                        ForEach(viewModel.players) { player in
                            let gross = result.grossByPlayerID[player.id, default: 0]
                            let net = result.netByPlayerID[player.id, default: 0]
                            let strokes = viewModel.strokesByPlayerByHole
                                .first(where: { $0.holeNumber == result.holeNumber })?
                                .strokesByPlayerID[player.id, default: 0] ?? 0

                            HStack {
                                Text(player.name)
                                Spacer()
                                Text("G \(gross)")
                                Text("N \(net)")
                                Text("St \(strokes)")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.footnote)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Totals") {
                ForEach(viewModel.players) { player in
                    let gross = viewModel.totalGrossByPlayerID[player.id, default: 0]
                    let net = viewModel.totalNetByPlayerID[player.id, default: 0]
                    HStack {
                        Text(player.name)
                        Spacer()
                        Text("Gross \(gross)")
                        Text("Net \(net)")
                    }
                }
            }
        }
        .navigationTitle("Round Scorecard")
    }
}
