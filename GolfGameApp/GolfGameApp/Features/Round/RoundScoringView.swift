import SwiftUI

struct RoundScoringView: View {
    @StateObject private var viewModel: RoundScoringViewModel

    init(session: SessionModel) {
        _viewModel = StateObject(wrappedValue: RoundScoringViewModel(sessionStore: session))
    }

    var body: some View {
        Form {
            Section("Tee Box") {
                Text("Hole \(viewModel.currentHole)")
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

            if !viewModel.playerNames.isEmpty {
                Section("Players") {
                    ForEach(viewModel.playerNames, id: \.self) { name in
                        Text(name)
                    }
                }
            }

            Section("Team A Net") {
                scorePairFields(inputs: $viewModel.teamANetInputs, prefix: "A Net")
            }

            Section("Team B Net") {
                scorePairFields(inputs: $viewModel.teamBNetInputs, prefix: "B Net")
            }

            Section("Team A Gross") {
                scorePairFields(inputs: $viewModel.teamAGrossInputs, prefix: "A Gross")
            }

            Section("Team B Gross") {
                scorePairFields(inputs: $viewModel.teamBGrossInputs, prefix: "B Gross")
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
                Button("Next Hole") {
                    viewModel.goToNextHole()
                }
                .disabled(!viewModel.hasScoredCurrentHole || viewModel.currentHole >= 18)

                if viewModel.isRoundComplete {
                    Text("Round complete at 18 holes.")
                }
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

    @ViewBuilder
    private func scorePairFields(inputs: Binding<[String]>, prefix: String) -> some View {
        ForEach(0..<2, id: \.self) { index in
            TextField("\(prefix) \(index + 1)", text: inputs[index])
                .keyboardType(.numberPad)
        }
    }

    private func teamTitle(_ team: TeamSide) -> String {
        team == .teamA ? "Team A" : "Team B"
    }
}
