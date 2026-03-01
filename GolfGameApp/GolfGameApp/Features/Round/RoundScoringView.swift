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
                if let trailing = viewModel.trailingTeam {
                    Text("Trailing: \(teamTitle(trailing))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Teams are tied on this nine")
                        .foregroundStyle(.secondary)
                }
                if let leading = viewModel.leadingTeam {
                    Text("Leading: \(teamTitle(leading))")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(viewModel.leaderTeedOff ? "Leader Teed Off ✓" : "Leader Teed Off") {
                        viewModel.leaderTeedOffTapped()
                    }
                    .disabled(viewModel.leaderTeedOff || viewModel.hasScoredCurrentHole)

                    Button(viewModel.trailerTeedOff ? "Trailer Teed Off ✓" : "Trailer Teed Off") {
                        viewModel.trailerTeedOffTapped()
                    }
                    .disabled(viewModel.trailerTeedOff || !viewModel.leaderTeedOff || viewModel.hasScoredCurrentHole)
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
                    HStack {
                        VStack(alignment: .leading) {
                            Text(player.name)
                            Text("HI \(player.handicapIndex, specifier: "%.1f")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("Gross", text: grossBinding(at: index))
                            .keyboardType(.numberPad)
                            .frame(maxWidth: 80)
                            .multilineTextAlignment(.trailing)
                        Text("Net \(viewModel.netDisplay(forPlayerAt: index))")
                            .frame(width: 80, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Prox") {
                Picker("Prox Winner", selection: $viewModel.proxWinner) {
                    ForEach(ProxWinner.allCases) { winner in
                        Text(winner.title).tag(winner)
                    }
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
                    Text("Raw Team A / Team B: \(output.rawTeamAPoints) / \(output.rawTeamBPoints)")
                    Text("Multiplier: x\(output.multiplier)")
                    Text("Multiplied Team A / Team B: \(output.multipliedTeamAPoints) / \(output.multipliedTeamBPoints)")
                }

                Section("Running Totals") {
                    Text("Front Nine A/B: \(output.frontNineTeamA) / \(output.frontNineTeamB)")
                    Text("Back Nine A/B: \(output.backNineTeamA) / \(output.backNineTeamB)")
                    Text("Overall A/B: \(output.totalTeamA) / \(output.totalTeamB)")
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
                Text("Scotch Total Team A/B: \(output.totalTeamA) / \(output.totalTeamB)")
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

    private func teamTitle(_ team: TeamSide) -> String {
        team == .teamA ? "Team A" : "Team B"
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
