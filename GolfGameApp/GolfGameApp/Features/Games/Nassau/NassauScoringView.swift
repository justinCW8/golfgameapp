import SwiftUI

struct NassauScoringView: View {
    @StateObject private var viewModel: NassauScoringViewModel
    @State private var showEndConfirmation = false
    @State private var showManualPressConfirmation = false
    @State private var scrollToTopToken = 0

    init(session: SessionModel) {
        _viewModel = StateObject(wrappedValue: NassauScoringViewModel(sessionStore: session))
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Color.clear
                    .frame(height: 0)
                    .id("TOP")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                holeHeaderSection
                matchStatusSection

                if let autoPress = viewModel.pendingAutoPress {
                    autoPressNoticeSection(for: autoPress)
                }

                if viewModel.pressConfig.manualPressEnabled && !viewModel.hasScoredCurrentHole {
                    manualPressSection
                }

                playerInputSection
                actionButtonSection

                if viewModel.hasScoredCurrentHole, let lastOut = viewModel.lastOutput {
                    lastHoleResultSection(output: lastOut)
                }

                if viewModel.holeHistory.count > 0 {
                    playerTotalsSection
                }

                endRoundSection
            }
            .navigationTitle(viewModel.courseName.isEmpty ? "Nassau" : viewModel.courseName)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scrollToTopToken) { _, _ in
                withAnimation { proxy.scrollTo("TOP", anchor: .top) }
            }
        }
        .sheet(isPresented: $viewModel.showSettlement) {
            NassauSettlementView(viewModel: viewModel) {
                viewModel.clearSession()
            }
        }
        .alert("End Game?", isPresented: $showEndConfirmation) {
            Button("End & Settle", role: .destructive) { viewModel.endRound() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will show the final settlement screen.")
        }
        .alert("Manual Press", isPresented: $showManualPressConfirmation) {
            Button("Press") {
                viewModel.pendingManualPress = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let trailing = viewModel.trailingSideLabel
            Text("\(trailing.isEmpty ? "Trailing side" : trailing) presses — new bet starts on hole \(viewModel.currentHole).")
        }
    }

    // MARK: - Hole Header

    private var holeHeaderSection: some View {
        Section {
            VStack(spacing: 6) {
                let hole = viewModel.currentHole
                let holeConfig = viewModel.currentHoleConfig
                let par = holeConfig?.par ?? 4
                let si = holeConfig?.strokeIndex ?? hole
                let yardage = holeConfig?.yardage ?? 0

                if viewModel.isComplete {
                    Text("Round Complete")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.green)
                } else {
                    Text("Hole \(hole)  ·  Par \(par)  ·  \(yardage > 0 ? "\(yardage)yds" : "—")")
                        .font(.title3.weight(.bold))
                    Text("HCP \(si)")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Match Status

    private var matchStatusSection: some View {
        Section("Match Status") {
            matchRow(
                label: viewModel.isCurrentSegment(.front) ? "Front 9 ▶" : "Front 9",
                status: viewModel.frontStatus,
                isActive: viewModel.isCurrentSegment(.front)
            )

            if viewModel.currentHole > 9 || viewModel.isComplete {
                matchRow(
                    label: viewModel.isCurrentSegment(.back) ? "Back 9 ▶" : "Back 9",
                    status: viewModel.backStatus,
                    isActive: viewModel.isCurrentSegment(.back)
                )
            }

            matchRow(
                label: "Overall",
                status: viewModel.overallStatus,
                isActive: false
            )
        }
    }

    private func matchRow(label: String, status: NassauMatchStatus, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(isActive ? .subheadline.weight(.semibold) : .subheadline)
                    .foregroundStyle(isActive ? .primary : .secondary)
                Spacer()
                Text(formattedStatus(status, viewModel: viewModel))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor(status))
            }
            // Sub-rows for presses
            ForEach(Array(status.pressStatuses.enumerated()), id: \.offset) { i, press in
                HStack {
                    Text("  Press \(i + 1) (from hole \(press.startHole))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formattedStatus(press.matchStatus, viewModel: viewModel))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(press.matchStatus))
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Auto-Press Notice

    private func autoPressNoticeSection(for team: TeamSide) -> some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "arrow.trianglehead.2.counterclockwise.rotate.90")
                    .foregroundStyle(.orange)
                Text("Auto-press — \(viewModel.sideLabel(for: team)) was \(viewModel.pressConfig.autoPressTrigger.map { "\($0)-down" } ?? "down"). New bet starts this hole.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Manual Press

    private var manualPressSection: some View {
        Section {
            if viewModel.pendingManualPress {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Manual press set for hole \(viewModel.currentHole)")
                        .font(.subheadline)
                    Spacer()
                    Button("Cancel") {
                        viewModel.pendingManualPress = false
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            } else if viewModel.canManualPress {
                Button {
                    showManualPressConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.trianglehead.2.counterclockwise.rotate.90")
                        Text("Press (\(viewModel.trailingSideLabel))")
                    }
                    .frame(maxWidth: .infinity)
                }
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Wager")
        }
    }

    // MARK: - Player Input

    private var playerInputSection: some View {
        Section("Score Entry") {
            if viewModel.format == .fourball {
                teamInputGroup(team: .teamA)
                teamInputGroup(team: .teamB)
            } else {
                singlesInputRows
            }
        }
    }

    private func teamInputGroup(team: TeamSide) -> some View {
        let teamPlayers = viewModel.players.filter { viewModel.sideFor(playerID: $0.id) == team }
        return Group {
            HStack {
                Text(viewModel.sideLabel(for: team))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(team == .teamA ? .blue : .orange)
                Spacer()
            }
            ForEach(teamPlayers, id: \.id) { player in
                nassauPlayerRow(player: player)
            }
        }
    }

    private var singlesInputRows: some View {
        ForEach(viewModel.players, id: \.id) { player in
            nassauPlayerRow(player: player)
        }
    }

    private func nassauPlayerRow(player: PlayerSnapshot) -> some View {
        let strokes = viewModel.strokeDots(for: player)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 3) {
                    ForEach(0..<strokes, id: \.self) { _ in
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                    }
                    Text(viewModel.netPreview(for: player))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            TextField("Gross", text: Binding(
                get: { viewModel.playerGrossInputs[player.id] ?? "" },
                set: { viewModel.playerGrossInputs[player.id] = $0 }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .frame(width: 60)
            .disabled(viewModel.hasScoredCurrentHole || viewModel.isComplete)
            .padding(6)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 2)
    }

    // MARK: - Action Buttons

    private var actionButtonSection: some View {
        Section {
            if viewModel.isComplete {
                Button("View Settlement") {
                    viewModel.showSettlement = true
                }
                .frame(maxWidth: .infinity)
                .font(.headline)
                .foregroundStyle(.green)
            } else if viewModel.hasScoredCurrentHole {
                Button("Edit Scores") {
                    viewModel.rescoreCurrentHole()
                    scrollToTopToken += 1
                }
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity)

                if viewModel.currentHole < 18 {
                    Button("Next Hole (\(viewModel.currentHole + 1))") {
                        viewModel.goToNextHole()
                        scrollToTopToken += 1
                    }
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                } else {
                    Button("End Round & Settle") {
                        viewModel.endRound()
                    }
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                    .foregroundStyle(.green)
                }
            } else {
                if let err = viewModel.errorMessage {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
                Button("Score Hole \(viewModel.currentHole)") {
                    viewModel.scoreCurrentHole()
                }
                .disabled(!viewModel.canScore)
                .frame(maxWidth: .infinity)
                .font(.headline)
            }
        }
    }

    // MARK: - Last Hole Result

    private func lastHoleResultSection(output: NassauHoleOutput) -> some View {
        Section("Hole \(output.holeNumber) Result") {
            let winnerText: String = {
                switch output.holeWinner {
                case .teamA: return "\(viewModel.sideLabel(for: .teamA)) won"
                case .teamB: return "\(viewModel.sideLabel(for: .teamB)) won"
                case nil: return "Hole halved"
                }
            }()
            Text(winnerText)
                .font(.subheadline)

            if let autoPress = output.autoPressTriggeredFor {
                Text("Auto-press triggered for \(viewModel.sideLabel(for: autoPress))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Show gross scores per player
            ForEach(viewModel.players, id: \.id) { player in
                if let scoreText = viewModel.lastHolePlayerScores(for: player) {
                    HStack {
                        Text(player.name).font(.caption)
                        Spacer()
                        Text(scoreText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Running Totals

    private var playerTotalsSection: some View {
        Section("Running Totals (Gross)") {
            ForEach(viewModel.players, id: \.id) { player in
                HStack {
                    Text(player.name)
                    Spacer()
                    Text("\(viewModel.totalGrossByPlayerID[player.id, default: 0])")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - End Round

    private var endRoundSection: some View {
        Section {
            Button("End Game & Settle") {
                showEndConfirmation = true
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private func formattedStatus(_ status: NassauMatchStatus, viewModel: NassauScoringViewModel) -> String {
        if status.isClosed, let desc = status.closedDescription {
            let winner = status.leadingTeam == .teamA
                ? viewModel.sideLabel(for: .teamA)
                : viewModel.sideLabel(for: .teamB)
            return "\(winner) \(desc)"
        }
        guard let leader = status.leadingTeam else { return "AS" }
        let name = viewModel.sideLabel(for: leader)
        return "\(name) \(status.holesUp)UP"
    }

    private func statusColor(_ status: NassauMatchStatus) -> Color {
        if status.leadingTeam == nil { return .secondary }
        return status.isClosed ? .green : .primary
    }
}

// MARK: - NassauSettlementView

struct NassauSettlementView: View {
    @ObservedObject var viewModel: NassauScoringViewModel
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let settlement = viewModel.settlement()
            List {
                Section("Results") {
                    resultRow(settlement.front, viewModel: viewModel)
                    resultRow(settlement.back, viewModel: viewModel)
                    resultRow(settlement.overall, viewModel: viewModel)
                }

                if !settlement.frontPresses.isEmpty || !settlement.backPresses.isEmpty {
                    Section("Press Results") {
                        ForEach(Array(settlement.frontPresses.enumerated()), id: \.offset) { _, result in
                            resultRow(result, viewModel: viewModel)
                        }
                        ForEach(Array(settlement.backPresses.enumerated()), id: \.offset) { _, result in
                            resultRow(result, viewModel: viewModel)
                        }
                    }
                }

                Section("Net Result") {
                    let net = settlement.totalNetForA
                    let bets = settlement.totalBets
                    if net == 0 {
                        Text("All Square (\(bets) bets halved)")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        let winner = net > 0 ? viewModel.sideLabel(for: .teamA) : viewModel.sideLabel(for: .teamB)
                        Text("\(winner) wins \(abs(net)) of \(bets) bets")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                Section("Player Totals") {
                    ForEach(viewModel.players, id: \.id) { player in
                        HStack {
                            Text(player.name)
                            Spacer()
                            Text("Gross \(viewModel.totalGrossByPlayerID[player.id, default: 0]) · Net \(viewModel.totalNetByPlayerID[player.id, default: 0])")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settlement")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                        dismiss()
                    }
                }
            }
        }
    }

    private func resultRow(_ result: NassauSegmentResult, viewModel: NassauScoringViewModel) -> some View {
        HStack {
            Text(result.name)
                .font(.subheadline)
            Spacer()
            Text(formattedOutcome(result, viewModel: viewModel))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(outcomeColor(result))
        }
    }

    private func formattedOutcome(_ result: NassauSegmentResult, viewModel: NassauScoringViewModel) -> String {
        switch result.outcome {
        case .sideAWon(let desc): return "\(viewModel.sideLabel(for: .teamA)) \(desc)"
        case .sideBWon(let desc): return "\(viewModel.sideLabel(for: .teamB)) \(desc)"
        case .halved: return "Halved"
        }
    }

    private func outcomeColor(_ result: NassauSegmentResult) -> Color {
        switch result.outcome {
        case .halved: return .secondary
        default: return .primary
        }
    }
}
