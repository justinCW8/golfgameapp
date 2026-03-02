import SwiftUI

struct RoundScoringView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RoundScoringViewModel
    @State private var showEndRoundConfirmation = false
    @State private var showFinalSummary = false
    @State private var scrollToTopToken = 0
    @State private var showLastHoleDetails = false

    init(session: SessionModel) {
        _viewModel = StateObject(wrappedValue: RoundScoringViewModel(sessionStore: session))
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Color.clear
                    .frame(height: 0)
                    .id("TOP")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                // SCOREBOARD — always at top
                Section {
                    VStack(spacing: 10) {
                        // HOLE INFO — prominent at top
                        VStack(spacing: 3) {
                            if !viewModel.courseName.isEmpty {
                                Text(viewModel.courseName)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Text("Hole \(viewModel.currentHole)  ·  Par \(viewModel.currentHolePar)  ·  \(viewModel.currentHoleYardage)yds")
                                .font(.title3.weight(.bold))
                            HStack(spacing: 6) {
                                Text("HCP \(viewModel.currentHoleStrokeIndex)")
                                    .foregroundStyle(.blue)
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Text(viewModel.teeBoxName)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }

                        Divider()

                        // MATCH STATUS — margin-based, leader in green
                        HStack(spacing: 0) {
                            Text(viewModel.teamAName)
                                .font(viewModel.teamALeads ? .title2.weight(.bold) : .subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(
                                    viewModel.teamALeads ? Color.green :
                                    viewModel.teamBLeads ? Color.secondary : Color.primary
                                )
                            VStack(spacing: 2) {
                                Text(viewModel.matchMarginDisplay)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(
                                        viewModel.teamALeads || viewModel.teamBLeads ? Color.green : Color.secondary
                                    )
                                Text("thru \(viewModel.holesThru)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 72)
                            Text(viewModel.teamBName)
                                .font(viewModel.teamBLeads ? .title2.weight(.bold) : .subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(
                                    viewModel.teamBLeads ? Color.green :
                                    viewModel.teamALeads ? Color.secondary : Color.primary
                                )
                        }

                        if viewModel.isRoundEnded {
                            Text("Round ended — read only")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }

                // WAGERS (press / roll / reroll)
                if viewModel.trailingTeam != nil || viewModel.requestRoll || viewModel.requestReroll {
                    Section("Wagers") {
                        if viewModel.canRequestPress || viewModel.requestPress {
                            Button(viewModel.requestPress ? "Press ✓" : "Press") {
                                viewModel.pressTapped()
                            }
                            .disabled(!viewModel.canRequestPress && !viewModel.requestPress)
                        }
                        if viewModel.canRequestRoll || viewModel.requestRoll {
                            Button(viewModel.requestRoll ? "Roll ✓" : "Roll") {
                                viewModel.rollTapped()
                            }
                            .disabled(!viewModel.canRequestRoll && !viewModel.requestRoll)
                        }
                        if viewModel.canRequestReroll || viewModel.requestReroll {
                            Button(viewModel.requestReroll ? "Re-roll ✓" : "Re-roll") {
                                viewModel.rerollTapped()
                            }
                            .disabled(!viewModel.canRequestReroll && !viewModel.requestReroll)
                        }
                        Text(viewModel.pressStatusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(viewModel.isRoundEnded)
                }

                // SCORE ENTRY
                Section("Player Gross / Net") {
                    ForEach(viewModel.playersWithOriginalIndex, id: \.player.id) { originalIndex, player in
                        PlayerScoreRow(
                            player: player,
                            flooredHandicap: viewModel.flooredHandicapDisplay(forPlayerAt: originalIndex),
                            gross: grossBinding(at: originalIndex),
                            netText: viewModel.grossNetStrokeDisplay(forPlayerAt: originalIndex),
                            strokeCount: viewModel.strokesDisplay(forPlayerAt: originalIndex),
                            proxSelected: selectedProxWinner(for: originalIndex) == viewModel.proxWinner,
                            onTapProx: { viewModel.proxWinner = selectedProxWinner(for: originalIndex) },
                            readOnly: viewModel.isRoundEnded
                        )
                    }
                    if viewModel.proxWinner == .none {
                        Button("None / No GIR ✓") { viewModel.proxWinner = .none }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("None / No GIR") { viewModel.proxWinner = .none }
                            .buttonStyle(.bordered)
                    }
                }
                .disabled(viewModel.isRoundEnded)

                // SCORE HOLE + NEXT HOLE together
                Section {
                    Button("Score Hole") {
                        viewModel.scoreCurrentHole()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(viewModel.isRoundEnded || viewModel.isRoundComplete || viewModel.hasScoredCurrentHole || !viewModel.canScore)

                    if viewModel.hasScoredCurrentHole, let output = viewModel.lastOutput {
                        HStack {
                            Text(viewModel.lastHolePointsWinnerDisplay)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if output.multiplier > 1 {
                                Text("×\(output.multiplier)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button("Edit Scores") {
                            viewModel.rescoreCurrentHole()
                        }
                        .foregroundStyle(.orange)
                    }

                    Button("Next Hole") {
                        viewModel.goToNextHole()
                        scrollToTopToken += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(viewModel.isRoundEnded || !viewModel.hasScoredCurrentHole || viewModel.currentHole >= 18)

                    if viewModel.isRoundComplete {
                        Text("Round complete — 18 holes done.")
                            .foregroundStyle(.secondary)
                    }
                }

                // AUDIT LOG (collapsible, for debugging)
                if !viewModel.latestAuditLines.isEmpty {
                    Section {
                        DisclosureGroup(
                            isExpanded: $showLastHoleDetails,
                            content: {
                                ForEach(viewModel.latestAuditLines, id: \.self) { line in
                                    Text(line).font(.footnote).foregroundStyle(.secondary)
                                }
                            },
                            label: { Text("Audit log").font(.footnote) }
                        )
                    }
                }

                // SCORECARD + END ROUND
                Section {
                    NavigationLink("View Scorecard") {
                        RoundScorecardView(viewModel: viewModel)
                    }
                    .disabled(viewModel.holeResults.isEmpty)
                }

                Section {
                    Button(role: .destructive) {
                        showEndRoundConfirmation = true
                    } label: {
                        Text("End Round")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                if viewModel.isRoundComplete {
                    roundSummarySection
                }

                if let error = viewModel.errorMessage {
                    Section("Error") {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .onChange(of: scrollToTopToken) { _, _ in
                withAnimation {
                    proxy.scrollTo("TOP", anchor: .top)
                }
            }
        }
        .navigationTitle("Scotch Scoring")
        .confirmationDialog("End round?", isPresented: $showEndRoundConfirmation, titleVisibility: .visible) {
            Button("End Round", role: .destructive) {
                viewModel.endRound()
                showFinalSummary = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will end the round and clear the current session.")
        }
        .sheet(isPresented: $showFinalSummary) {
            FinalRoundSummaryView(viewModel: viewModel) {
                viewModel.endRoundAndClearSession()
                dismiss()
            }
        }
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
    let flooredHandicap: Int
    @Binding var gross: String
    let netText: String
    let strokeCount: Int
    let proxSelected: Bool
    let onTapProx: () -> Void
    let readOnly: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text("Index \(flooredHandicap)")
                        .foregroundStyle(.secondary)
                    if strokeCount > 0 {
                        Text("+\(strokeCount)")
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }
                .font(.caption)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                TextField("Gross", text: $gross)
                    .keyboardType(.numberPad)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .disabled(readOnly)
                Text(netText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if proxSelected {
                Button("PROX ✓", action: onTapProx)
                    .buttonStyle(.borderedProminent)
                    .disabled(readOnly)
            } else {
                Button("PROX", action: onTapProx)
                    .buttonStyle(.bordered)
                    .disabled(readOnly)
            }
        }
    }
}

private struct RoundScorecardView: View {
    @ObservedObject var viewModel: RoundScoringViewModel

    private let cellW: CGFloat = 30
    private let nameW: CGFloat = 52
    private let totalW: CGFloat = 36

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(viewModel.teamAName) vs \(viewModel.teamBName)")
                            .font(.headline)
                        Text(viewModel.matchStatusDisplay)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()

                nineSection(holes: Array(1...9), totalLabel: "Out")
                    .padding(.horizontal)

                Spacer().frame(height: 16)

                nineSection(holes: Array(10...18), totalLabel: "In")
                    .padding(.horizontal)

                Spacer().frame(height: 16)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Totals")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                    ForEach(viewModel.players) { player in
                        HStack {
                            Text(player.name).font(.subheadline.weight(.medium))
                            Spacer()
                            let g = viewModel.totalGrossByPlayerID[player.id, default: 0]
                            let n = viewModel.totalNetByPlayerID[player.id, default: 0]
                            Text("Gross \(g)  ·  Net \(n)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Scorecard")
    }

    private func nineSection(holes: [Int], totalLabel: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Hole numbers
                gridRow(
                    label: "Hole",
                    cells: holes.map { String($0) },
                    total: totalLabel,
                    font: .caption.weight(.semibold),
                    cellColor: .primary
                )
                .background(Color(UIColor.secondarySystemBackground))

                Divider()

                // Par
                gridRow(
                    label: "Par",
                    cells: holes.map { String(viewModel.par(for: $0)) },
                    total: String(holes.map { viewModel.par(for: $0) }.reduce(0, +)),
                    font: .caption,
                    cellColor: .secondary
                )

                // SI
                gridRow(
                    label: "SI",
                    cells: holes.map { String(viewModel.strokeIndex(for: $0)) },
                    total: "",
                    font: .caption,
                    cellColor: .secondary
                )

                Divider()

                ForEach(viewModel.players) { player in
                    playerGridRow(player: player, holes: holes)
                    Divider()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(UIColor.separator), lineWidth: 0.5))
        }
    }

    private func gridRow(label: String, cells: [String], total: String, font: Font, cellColor: Color) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .frame(width: nameW, alignment: .leading)
                .padding(.leading, 8)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, val in
                Text(val).frame(width: cellW).multilineTextAlignment(.center).foregroundStyle(cellColor)
            }
            Text(total).frame(width: totalW).fontWeight(.semibold).foregroundStyle(cellColor).padding(.trailing, 8)
        }
        .font(font)
        .padding(.vertical, 5)
    }

    private func playerGridRow(player: PlayerSnapshot, holes: [Int]) -> some View {
        let hi = Int(player.handicapIndex.rounded(.down))
        let scored = holes.compactMap { hole -> Int? in
            viewModel.holeResults.first(where: { $0.holeNumber == hole })?.grossByPlayerID[player.id]
        }
        let nineTotal = scored.count == 9 ? String(scored.reduce(0, +)) : ""

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(player.name).font(.caption.weight(.medium))
                Text("Index \(hi)").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .frame(width: nameW, alignment: .leading)
            .padding(.leading, 8)

            ForEach(holes, id: \.self) { hole in
                scoreCell(player: player, hole: hole).frame(width: cellW)
            }

            Text(nineTotal)
                .font(.caption.weight(.semibold))
                .frame(width: totalW)
                .padding(.trailing, 8)
        }
        .padding(.vertical, 4)
    }

    private func scoreCell(player: PlayerSnapshot, hole: Int) -> some View {
        let gross = viewModel.holeResults.first(where: { $0.holeNumber == hole })?.grossByPlayerID[player.id]
        let si = viewModel.strokeIndex(for: hole)
        let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: si)
        let holePar = viewModel.par(for: hole)

        return VStack(spacing: 1) {
            Circle()
                .fill(strokes > 0 ? Color.green : Color.clear)
                .frame(width: 4, height: 4)
            if let g = gross {
                scoreBadge(gross: g, par: holePar)
            } else {
                Text("–").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func scoreBadge(gross: Int, par: Int) -> some View {
        let diff = gross - par
        let label = Text("\(gross)").font(.system(size: 10, weight: .medium))
        switch diff {
        case ...(-2):
            // Eagle or better: double circle
            label
                .padding(2)
                .overlay(Circle().stroke(Color.orange, lineWidth: 1))
                .padding(1.5)
                .overlay(Circle().stroke(Color.orange, lineWidth: 1))
        case -1:
            // Birdie: single circle
            label
                .padding(2)
                .overlay(Circle().stroke(Color.red, lineWidth: 1))
        case 0:
            // Par: plain
            label.foregroundStyle(.primary)
        case 1:
            // Bogey: single square
            label
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(Color.primary, lineWidth: 1))
        default:
            // Double bogey or worse: double square
            label
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(Color.secondary, lineWidth: 1))
                .padding(1.5)
                .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.secondary, lineWidth: 1))
        }
    }
}

private struct FinalRoundSummaryView: View {
    @ObservedObject var viewModel: RoundScoringViewModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(viewModel.matchStatusDisplay)
                        .font(.title2.weight(.bold))
                    Text("\(viewModel.teamAName) vs \(viewModel.teamBName)")
                        .foregroundStyle(.secondary)
                }

                if let output = viewModel.lastOutput {
                    Section("Team Points") {
                        HStack {
                            Text(viewModel.teamAName)
                            Spacer()
                            Text("\(output.totalTeamA) pts")
                                .monospacedDigit()
                        }
                        HStack {
                            Text(viewModel.teamBName)
                            Spacer()
                            Text("\(output.totalTeamB) pts")
                                .monospacedDigit()
                        }
                    }
                }

                Section("Holes Played") {
                    Text("\(viewModel.holeResults.count) of 18")
                        .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink("View Scorecard") {
                        RoundScorecardView(viewModel: viewModel)
                    }
                    .disabled(viewModel.holeResults.isEmpty)
                }

                Section("Player Totals") {
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
            .navigationTitle("Final Summary")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}
