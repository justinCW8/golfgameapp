import SwiftUI

struct RoundScoringView: View {
    @StateObject private var viewModel = RoundScoringViewModel()

    var body: some View {
        Form {
            Section("Current Hole") {
                Text("Hole \(viewModel.currentHole)")
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

            Section("Prox (optional)") {
                TextField("Team A prox (feet)", text: $viewModel.teamAProxInput)
                    .keyboardType(.decimalPad)
                TextField("Team B prox (feet)", text: $viewModel.teamBProxInput)
                    .keyboardType(.decimalPad)
            }

            Section("Actions") {
                Toggle("Press", isOn: $viewModel.usePress)
                Toggle("Roll", isOn: $viewModel.useRoll)
                Toggle("Re-roll", isOn: $viewModel.useReroll)
            }

            Section {
                Button("Score Hole") {
                    viewModel.scoreCurrentHole()
                }
                .disabled(viewModel.isRoundComplete || viewModel.hasScoredCurrentHole || !viewModel.isRequiredInputValid)
            }

            if let output = viewModel.lastOutput {
                Section("Last Scored Hole") {
                    Text("Raw Team A / Team B: \(output.rawTeamAPoints) / \(output.rawTeamBPoints)")
                    Text("Multiplier: x\(output.multiplier)")
                    Text("Multiplied Team A / Team B: \(output.multipliedTeamAPoints) / \(output.multipliedTeamBPoints)")
                }

                Section("Running Totals") {
                    Text("Front Nine A/B: \(output.frontNineTeamA) / \(output.frontNineTeamB)")
                    Text("Back Nine A/B: \(output.backNineTeamA) / \(output.backNineTeamB)")
                    Text("Overall A/B: \(output.totalTeamA) / \(output.totalTeamB)")
                }

                Section("Audit Log") {
                    ForEach(Array(viewModel.latestAuditLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.footnote)
                    }
                }
            }

            Section {
                Button("Next Hole") {
                    viewModel.goToNextHole()
                }
                .disabled(!viewModel.hasScoredCurrentHole)

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
}
