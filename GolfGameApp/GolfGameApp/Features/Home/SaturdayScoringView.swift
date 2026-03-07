import SwiftUI

// MARK: - Scoring View Entry Point

struct SaturdayScoringView: View {
    @Binding var path: [SaturdayRoute]
    @EnvironmentObject private var store: AppSessionStore

    var body: some View {
        Group {
            if let round = store.activeSaturdayRound {
                SaturdayScoringContent(round: round, store: store, path: $path)
            } else {
                ContentUnavailableView("No Active Round", systemImage: "flag")
            }
        }
        .navigationTitle(holeTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var holeTitle: String {
        guard let round = store.activeSaturdayRound else { return "Round" }
        if round.isComplete { return "Round Complete" }
        return "Hole \(round.currentHole)"
    }
}

// MARK: - Main Content

private struct SaturdayScoringContent: View {
    let round: SaturdayRound
    let store: AppSessionStore
    @Binding var path: [SaturdayRoute]
    @StateObject private var vm: SaturdayScoringViewModel
    @State private var showEndRoundAlert = false
    @State private var showScorecard = false
    @State private var showScotchAudit = false

    init(round: SaturdayRound, store: AppSessionStore, path: Binding<[SaturdayRoute]>) {
        self.round = round
        self.store = store
        self._path = path
        self._vm = StateObject(wrappedValue: SaturdayScoringViewModel(round: round, store: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    holeHeader.id("scrollTop")
                    currentStandings
                    scotchActions
                    nassauActions
                    scoreEntryGrid
                    actionButtons
                    matchDecidedBanner
                    scotchAudit
                    stablefordStandings
                    scorecardButton
                }
                .padding(16)
            }
            .onChange(of: vm.currentHole) {
                withAnimation { proxy.scrollTo("scrollTop", anchor: .top) }
            }
            .onChange(of: vm.isComplete) {
                withAnimation { proxy.scrollTo("scrollTop", anchor: .top) }
            }
        }

            Divider()
            gameStrip
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showScorecard) {
            ScorecardSheet(round: vm.round)
        }
        .alert("End Round?", isPresented: $showEndRoundAlert) {
            Button("End Round", role: .destructive) {
                var completed = vm.round
                completed.isComplete = true
                store.updateSaturdayRound(completed)
                path.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mark this round as complete and return home.")
        }
    }

    // MARK: - Hole Header

    @ViewBuilder
    private var holeHeader: some View {
        if vm.isComplete {
            completeBanner
        } else if let stub = vm.currentHoleStub {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text("Hole \(stub.number)")
                        .font(.title3.weight(.bold))
                    Text("·").foregroundStyle(.secondary)
                    Text("Par \(stub.par)")
                        .font(.title3.weight(.semibold))
                    Text("·").foregroundStyle(.secondary)
                    Text("Hdcp \(stub.strokeIndex)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if stub.yardage > 0 {
                        Text("·").foregroundStyle(.secondary)
                        Text("\(stub.yardage)y")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Text(vm.round.courseName)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var completeBanner: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle).foregroundStyle(.green)
            Text("Round Complete")
                .font(.title2.weight(.bold))
            Text(vm.round.courseName)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Current Standings

    @ViewBuilder
    private var currentStandings: some View {
        if !vm.round.holeEntries.isEmpty, !vm.isComplete {
            VStack(spacing: 0) {
                ForEach(Array(vm.round.activeGames.enumerated()), id: \.element.id) { idx, game in
                    if idx > 0 { Divider().padding(.leading, 16) }
                    HStack(alignment: .center) {
                        Text(game.type.title)
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            standingLabel(for: game)
                            if game.type == .sixPointScotch, let last = vm.scotchState.lastOutput {
                                let aMult = last.multipliedTeamAPoints
                                let bMult = last.multipliedTeamBPoints
                                let pts = max(aMult, bMult)
                                let isA = aMult > bMult
                                let isB = bMult > aMult
                                Text(pts > 0 ? "Last +\(pts)" : "Last push")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(isA ? Color.blue : isB ? Color.orange : Color.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func standingLabel(for game: SaturdayGameConfig) -> some View {
        switch game.type {
        case .sixPointScotch:
            let diff = vm.scotchState.totalA - vm.scotchState.totalB
            if diff == 0 {
                Text("AS").font(.headline.weight(.bold)).foregroundStyle(.secondary)
            } else {
                let leader = diff > 0 ? teamInitials(.teamA) : teamInitials(.teamB)
                Text("\(leader) +\(abs(diff))")
                    .font(.headline.weight(.bold)).foregroundStyle(.green)
            }
        case .nassau:
            let s = vm.nassauState.overallStatus
            Text(nassauDisplayString(s))
                .font(.headline.weight(.bold))
                .foregroundStyle(s.leadingTeam == nil ? Color.secondary : Color.green)
        case .stableford:
            if let top = vm.stablefordState.pointsByPlayerID.max(by: { $0.value < $1.value }) {
                Text("\(vm.playerName(for: top.key)) +\(top.value)")
                    .font(.headline.weight(.bold)).foregroundStyle(.green)
            }
        }
    }

    // MARK: - Score Entry Grid

    @ViewBuilder
    private var scoreEntryGrid: some View {
        if !vm.isComplete, let stub = vm.currentHoleStub {
            VStack(spacing: 0) {
                if vm.round.requiresTeams && !vm.round.teamAPlayers.isEmpty {
                    teamLabelRow(teamInitials(.teamA), color: .blue)
                    ForEach(vm.round.teamAPlayers) { player in
                        playerRow(player: player, stub: stub)
                        if player.id != vm.round.teamAPlayers.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                    teamLabelRow(teamInitials(.teamB), color: .orange)
                    ForEach(vm.round.teamBPlayers) { player in
                        playerRow(player: player, stub: stub)
                        if player.id != vm.round.teamBPlayers.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                } else {
                    ForEach(vm.round.players) { player in
                        playerRow(player: player, stub: stub)
                        if player.id != vm.round.players.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                if vm.isScotchActive {
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: vm.proxWinnerID == nil ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(vm.proxWinnerID == nil ? Color.green : Color.secondary)
                        Text("No Prox this hole")
                            .font(.caption)
                            .foregroundStyle(vm.proxWinnerID == nil ? Color.primary : Color.secondary)
                        Spacer()
                        Text("Scotch").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.proxWinnerID = nil }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func teamLabelRow(_ label: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(color.opacity(0.06))
    }

    private func playerRow(player: PlayerSnapshot, stub: CourseHoleStub) -> some View {
        let strokes = vm.handicapStrokes(for: player, on: stub)
        let grossText = vm.grossInputs[player.id] ?? ""
        let gross = Int(grossText)
        let hasGIR = gross.map { $0 <= stub.par } ?? false  // natural GIR: gross ≤ par, no strokes
        let isProxSelected = vm.proxWinnerID == player.id
        let par = stub.par
        let lo = max(1, par - 2)
        let scores = Array(lo...(par + 2))
        let overflowMin = par + 3
        let overflowSelected = (gross ?? -1) >= overflowMin

        return VStack(alignment: .leading, spacing: 4) {
            // Player info row
            HStack(spacing: 6) {
                Text(player.name)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 3) {
                    Text(String(format: "HCP %.0f", player.handicapIndex))
                        .font(.caption2).foregroundStyle(.secondary)
                    if strokes > 0 {
                        HStack(spacing: 2) {
                            ForEach(0..<min(strokes, 3), id: \.self) { _ in
                                Circle().fill(Color.green).frame(width: 5, height: 5)
                            }
                            if strokes > 3 { Text("+\(strokes-3)").font(.caption2).foregroundStyle(.green) }
                        }
                    }
                }
                Spacer()
                if vm.isScotchActive {
                    Button { vm.proxWinnerID = isProxSelected ? nil : player.id } label: {
                        Text("Prox").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(isProxSelected ? .orange : .gray)
                    .controlSize(.small)
                    .disabled(!hasGIR)
                }
            }

            // Score buttons
            HStack(spacing: 5) {
                ForEach(scores, id: \.self) { score in
                    let isSelected = gross == score
                    let netDelta = score - strokes - par
                    Button { vm.grossInputs[player.id] = isSelected ? "" : String(score) } label: {
                        Text("\(score)")
                            .font(.callout.weight(isSelected ? .bold : .regular))
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(
                                isSelected ? scoreTint(netDelta: netDelta) : Color(.tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
                // Overflow (par+3+): shows stepper when active
                if overflowSelected {
                    HStack(spacing: 3) {
                        Button {
                            let cur = gross ?? overflowMin
                            vm.grossInputs[player.id] = cur > overflowMin ? String(cur - 1) : ""
                        } label: {
                            Image(systemName: "minus").font(.caption.weight(.bold))
                                .frame(width: 28, height: 40)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        let g = gross ?? overflowMin
                        Text("\(g)").font(.callout.weight(.bold))
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(scoreTint(netDelta: g - strokes - par), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                        Button {
                            vm.grossInputs[player.id] = String((gross ?? overflowMin) + 1)
                        } label: {
                            Image(systemName: "plus").font(.caption.weight(.bold))
                                .frame(width: 28, height: 40)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button { vm.grossInputs[player.id] = String(overflowMin) } label: {
                        Text("\(overflowMin)+")
                            .font(.callout.weight(.regular))
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Result label
            if let g = gross, g > 0 {
                let net = g - strokes
                let delta = net - par
                let isStablefordActive = vm.round.activeGames.contains(where: { $0.type == .stableford })
                HStack(spacing: 4) {
                    Spacer()
                    if isStablefordActive {
                        let pts = StablefordEngine.scoreHole(.init(gross: g, par: par, handicapStrokes: strokes)).points
                        Text(scoreName(delta)).font(.caption2.weight(.semibold)).foregroundStyle(scoreColor(delta))
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        Text("\(pts) pts").font(.caption2.weight(.semibold)).foregroundStyle(scoreColor(delta))
                    } else {
                        Text("Net \(net)").font(.caption2).foregroundStyle(.secondary)
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        Text(scoreName(delta)).font(.caption2.weight(.medium)).foregroundStyle(scoreColor(delta))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func scoreTint(netDelta: Int) -> Color {
        switch netDelta {
        case ...(-2): return Color(red: 0.85, green: 0.65, blue: 0.10)
        case -1: return .green
        case 0: return Color.accentColor
        case 1: return .orange
        default: return .red
        }
    }

    private func scoreName(_ delta: Int) -> String {
        switch delta {
        case ...(-3): return "Albatross"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double"
        case 3: return "Triple"
        default: return "+\(delta)"
        }
    }

    private func scoreColor(_ delta: Int) -> Color {
        switch delta {
        case ...(-2): return Color(red: 0.7, green: 0.5, blue: 0.0)
        case -1: return .green
        case 0: return .primary
        case 1: return .orange
        default: return .red
        }
    }

    // MARK: - Scotch Actions (Press / Roll / Re-roll)

    @ViewBuilder
    private var scotchActions: some View {
        if vm.isScotchActive, !vm.isComplete {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Scotch Actions")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Spacer()
                    Text("\(vm.scotchPressesRemaining) press\(vm.scotchPressesRemaining == 1 ? "" : "es") left")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.orange.opacity(0.06))

                scotchTeamRow(
                    label: "Press", note: "trailing team · doubles nine",
                    tint: .orange,
                    eligibleTeam: vm.canScotchPress ? vm.scotchTrailingTeam : nil,
                    current: vm.scotchPressBy,
                    set: { vm.scotchPressBy = $0 }
                )
                Divider().padding(.leading, 16)
                scotchTeamRow(
                    label: "Roll", note: "trailing team · doubles this hole",
                    tint: .red,
                    eligibleTeam: vm.scotchTrailingTeam,
                    current: vm.scotchRollBy,
                    set: { vm.scotchRollBy = $0; if $0 == nil { vm.scotchRerollBy = nil } }
                )
                if vm.scotchRollBy != nil {
                    Divider().padding(.leading, 16)
                    scotchTeamRow(
                        label: "Re-roll", note: "leading team · counters roll",
                        tint: .purple,
                        eligibleTeam: vm.scotchLeadingTeam,
                        current: vm.scotchRerollBy,
                        set: { vm.scotchRerollBy = $0 }
                    )
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Nassau Actions

    @ViewBuilder
    private var nassauActions: some View {
        if vm.isNassauActive, vm.canNassauPress, !vm.isComplete {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Nassau")
                        .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                    Spacer()
                    Text("trailing team presses")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.blue.opacity(0.06))

                scotchTeamRow(
                    label: "Press",
                    note: "new bet to end of nine",
                    tint: .blue,
                    eligibleTeam: vm.nassauTrailingTeam,
                    current: vm.nassauManualPressBy,
                    set: { vm.nassauManualPressBy = $0 }
                )
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func teamInitials(_ side: TeamSide) -> String {
        let players = side == .teamA ? vm.round.teamAPlayers : vm.round.teamBPlayers
        return players.map { firstName($0.name) }.joined(separator: "/")
    }

    private func nassauDisplayString(_ status: NassauMatchStatus) -> String {
        if status.isClosed, let desc = status.closedDescription {
            let winner = status.leadingTeam == .teamA ? teamInitials(.teamA) : teamInitials(.teamB)
            return "\(winner) won \(desc)"
        }
        guard let leader = status.leadingTeam else { return "AS" }
        let name = leader == .teamA ? teamInitials(.teamA) : teamInitials(.teamB)
        return "\(name) \(status.holesUp)UP"
    }

    private func scotchTeamRow(
        label: String, note: String, tint: Color,
        eligibleTeam: TeamSide?,
        current: TeamSide?,
        set: @escaping (TeamSide?) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.medium))
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let eligible = eligibleTeam {
                let isOn = current == eligible
                Button { set(isOn ? nil : eligible) } label: {
                    Text(teamInitials(eligible))
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(isOn ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(isOn ? Color.white : tint)
                }
                .buttonStyle(.plain)
            } else {
                Text("Level · N/A")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Scotch Audit (collapsible multiplier chain + last hole)

    @ViewBuilder
    private var scotchAudit: some View {
        if vm.isScotchActive, !vm.isComplete {
            VStack(spacing: 0) {
                // Tappable header (always visible)
                Button {
                    withAnimation(.spring(response: 0.3)) { showScotchAudit.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Last Hole")
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        if let last = vm.scotchState.lastOutput {
                            Text("·").font(.caption2).foregroundStyle(.secondary)
                            Text(scotchAuditSummary(last))
                                .font(.caption.weight(.medium)).foregroundStyle(.primary)
                        }
                        Spacer()
                        Image(systemName: showScotchAudit ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.orange.opacity(0.06))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Expanded: active press/roll/reroll status + hole breakdown
                if showScotchAudit {
                    let activeActions: [String] = [
                        vm.scotchPressBy != nil ? "Press" : nil,
                        vm.scotchRollBy != nil ? "Roll" : nil,
                        vm.scotchRerollBy != nil ? "Re-roll" : nil
                    ].compactMap { $0 }
                    if !activeActions.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(activeActions, id: \.self) { action in
                                Text(action)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }

                    if let last = vm.scotchState.lastOutput {
                        let buckets = lastHoleBuckets(last)
                        Divider()
                        // Bucket rows
                        if buckets.isEmpty {
                            HStack {
                                Text("No buckets won this hole")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                        } else {
                            ForEach(Array(buckets.enumerated()), id: \.offset) { idx, bucket in
                                HStack {
                                    Text(bucket.0)
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("\(bucket.1)")
                                        .font(.caption.weight(.semibold)).foregroundStyle(.primary)
                                    Spacer()
                                    Text(teamInitials(bucket.2))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(bucket.2 == .teamA ? Color.blue : Color.orange)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                if idx < buckets.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        Divider()
                        // Winning team total
                        HStack(spacing: 6) {
                            Text("Hole \(last.holeNumber):")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            if last.multipliedTeamAPoints > last.multipliedTeamBPoints {
                                Text("\(teamInitials(.teamA)) +\(last.multipliedTeamAPoints)")
                                    .font(.caption.weight(.bold)).foregroundStyle(.blue)
                            } else if last.multipliedTeamBPoints > last.multipliedTeamAPoints {
                                Text("\(teamInitials(.teamB)) +\(last.multipliedTeamBPoints)")
                                    .font(.caption.weight(.bold)).foregroundStyle(.orange)
                            } else {
                                Text("Push").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            }
                            if last.multiplier > 1 {
                                Text("(×\(last.multiplier))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // Returns (bucketName, points, winningSide) for the last scored hole
    private func lastHoleBuckets(_ last: SixPointScotchHoleOutput) -> [(String, Int, TeamSide)] {
        let log = last.auditLog
        guard let startIdx = log.lastIndex(where: { $0 == "Hole \(last.holeNumber)" }) else { return [] }
        var result: [(String, Int, TeamSide)] = []
        for entry in log[(startIdx + 1)...] {
            for (marker, side) in [(": teamA (", TeamSide.teamA), (": teamB (", TeamSide.teamB)] {
                if entry.contains(marker) {
                    let parts = entry.components(separatedBy: marker)
                    let name = parts.first ?? ""
                    let pts = Int(parts.last?.dropLast() ?? "") ?? 0
                    result.append((name, pts, side))
                    break
                }
            }
        }
        return result
    }

    private func scotchAuditSummary(_ last: SixPointScotchHoleOutput) -> String {
        let aMult = last.multipliedTeamAPoints
        let bMult = last.multipliedTeamBPoints
        guard aMult != 0 || bMult != 0 else { return "Push" }
        if aMult > bMult {
            return "\(teamInitials(.teamA)) +\(aMult)"
        } else {
            return "\(teamInitials(.teamB)) +\(bMult)"
        }
    }

    // MARK: - Stableford Standings

    @ViewBuilder
    private var stablefordStandings: some View {
        let isStablefordActive = vm.round.activeGames.contains(where: { $0.type == .stableford })
        if isStablefordActive, !vm.round.holeEntries.isEmpty {
            let sorted = vm.round.players.sorted {
                (vm.stablefordState.pointsByPlayerID[$0.id] ?? 0) >
                (vm.stablefordState.pointsByPlayerID[$1.id] ?? 0)
            }
            VStack(spacing: 0) {
                HStack {
                    Text("Stableford")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                    Spacer()
                    let thru = vm.round.holeEntries.count
                    Text(thru == 18 ? "Final" : "Thru \(thru)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.purple.opacity(0.06))

                ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, player in
                    if idx > 0 { Divider().padding(.leading, 44) }
                    HStack(spacing: 10) {
                        Text("\(idx + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(idx == 0 ? .purple : .secondary)
                            .frame(width: 18, alignment: .center)
                        Text(player.name)
                            .font(.subheadline)
                            .fontWeight(idx == 0 ? .semibold : .regular)
                        Spacer()
                        Text("\(vm.stablefordState.pointsByPlayerID[player.id] ?? 0)")
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(idx == 0 ? .purple : .primary)
                        Text("pts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Scorecard Button

    @ViewBuilder
    private var scorecardButton: some View {
        if !vm.round.holeEntries.isEmpty {
            Button { showScorecard = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scorecard")
                            .font(.subheadline.weight(.semibold))
                        let count = vm.round.holeEntries.count
                        Text("\(count) of 18 holes")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "tablecells.fill")
                        .foregroundStyle(.blue)
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func firstName(_ name: String) -> String {
        String(name.split(separator: " ").first ?? Substring(name))
    }

    // MARK: - Match Decided Banner

    @ViewBuilder
    private var matchDecidedBanner: some View {
        let nassauActive = vm.round.activeGames.contains(where: { $0.type == .nassau })
        let overallClosed = vm.nassauState.overallStatus.isClosed
        if nassauActive && overallClosed && !vm.isComplete {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered.2.crossed")
                        .font(.title3)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Match Decided")
                            .font(.subheadline.weight(.semibold))
                        Text(nassauDisplayString(vm.nassauState.overallStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                NavigationLink {
                    RoundSummaryView(round: vm.round, store: store) {
                        path.removeAll()
                    }
                } label: {
                    Text("Settle Up Now")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(14)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.25), lineWidth: 1))
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if !vm.isComplete {
                Button {
                    vm.scoreHole()
                } label: {
                    Text("Score Hole")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .disabled(!vm.canScoreHole)
            }

            if !vm.round.holeEntries.isEmpty {
                Button {
                    vm.editPreviousHole()
                } label: {
                    Text(vm.isComplete ? "Edit Last Hole" : "Edit Previous Hole")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            if vm.isComplete {
                NavigationLink {
                    RoundSummaryView(round: vm.round, store: store) {
                        path.removeAll()
                    }
                } label: {
                    Label("View Settlement", systemImage: "dollarsign.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
            } else {
                Button("End Round Early") {
                    showEndRoundAlert = true
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Game Strip

    private var gameStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(vm.round.activeGames) { game in
                    GameStripPill(
                        game: game,
                        vm: vm,
                        isExpanded: vm.expandedGame == game.type
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            vm.expandedGame = vm.expandedGame == game.type ? nil : game.type
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Scorecard Sheet

struct ScorecardSheet: View {
    let round: SaturdayRound
    @Environment(\.dismiss) private var dismiss

    private var entries: [SaturdayHoleEntry] {
        round.holeEntries.sorted { $0.holeNumber < $1.holeNumber }
    }

    private func firstName(_ name: String) -> String {
        String(name.split(separator: " ").first ?? Substring(name))
    }

    private func netScore(for player: PlayerSnapshot, on stub: CourseHoleStub?, holeNumber: Int, gross: Int) -> Int {
        let si = stub?.strokeIndex ?? holeNumber
        let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: si)
        return gross - strokes
    }

    private func netColor(_ delta: Int) -> Color {
        switch delta {
        case ...(-2): return Color(red: 0.85, green: 0.65, blue: 0.10)
        case -1: return .green
        case 0: return .secondary
        case 1: return .orange
        default: return .red
        }
    }

    private func netTotals(for player: PlayerSnapshot, filter: (SaturdayHoleEntry) -> Bool) -> (gross: Int, net: Int)? {
        let filtered = entries.filter(filter)
        let grossValues = filtered.compactMap { $0.grossByPlayerID[player.id] }
        guard !grossValues.isEmpty else { return nil }
        let grossTotal = grossValues.reduce(0, +)
        let netTotal = filtered.compactMap { e -> Int? in
            guard let g = e.grossByPlayerID[player.id] else { return nil }
            let stub = round.holes.first(where: { $0.number == e.holeNumber })
            return netScore(for: player, on: stub, holeNumber: e.holeNumber, gross: g)
        }.reduce(0, +)
        return (grossTotal, netTotal)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("H").frame(width: 32, alignment: .center)
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Par").frame(width: 36, alignment: .center)
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(round.players) { player in
                            Text(firstName(player.name))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color(.tertiarySystemGroupedBackground))

                    // Hole rows
                    ForEach(entries) { entry in
                        let stub = round.holes.first(where: { $0.number == entry.holeNumber })
                        let par = stub?.par ?? 4
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                Text("\(entry.holeNumber)").frame(width: 32, alignment: .center)
                                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                                Text("\(par)").frame(width: 36, alignment: .center)
                                    .font(.caption2).foregroundStyle(.secondary)
                                ForEach(round.players) { player in
                                    VStack(spacing: 1) {
                                        PGAScoreCell(gross: entry.grossByPlayerID[player.id], par: par)
                                        if let g = entry.grossByPlayerID[player.id] {
                                            let net = netScore(for: player, on: stub, holeNumber: entry.holeNumber, gross: g)
                                            Text("\(net)")
                                                .font(.system(size: 9).weight(.medium))
                                                .foregroundStyle(netColor(net - par))
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 6)
                            // Front/back nine divider
                            if entry.holeNumber == 9 {
                                HStack(spacing: 0) {
                                    Text("Out").frame(width: 32, alignment: .center)
                                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    Text("\(round.holes.filter { $0.number <= 9 }.map(\.par).reduce(0,+))")
                                        .frame(width: 36, alignment: .center)
                                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    ForEach(round.players) { player in
                                        if let totals = netTotals(for: player, filter: { $0.holeNumber <= 9 }) {
                                            VStack(spacing: 1) {
                                                Text("\(totals.gross)").font(.caption.weight(.bold))
                                                Text("\(totals.net)").font(.system(size: 9).weight(.medium)).foregroundStyle(.secondary)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .center)
                                        } else {
                                            Text("—").frame(maxWidth: .infinity, alignment: .center).font(.caption.weight(.bold))
                                        }
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 6)
                                .background(Color(.tertiarySystemGroupedBackground))
                            }
                            if entry.holeNumber != entries.last?.holeNumber && entry.holeNumber != 9 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }

                    // Totals row
                    Divider()
                    HStack(spacing: 0) {
                        Text("In").frame(width: 32, alignment: .center)
                            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Text("\(round.holes.filter { $0.number > 9 }.map(\.par).reduce(0,+))")
                            .frame(width: 36, alignment: .center)
                            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        ForEach(round.players) { player in
                            if let totals = netTotals(for: player, filter: { $0.holeNumber > 9 }) {
                                VStack(spacing: 1) {
                                    Text("\(totals.gross)").font(.caption.weight(.bold))
                                    Text("\(totals.net)").font(.system(size: 9).weight(.medium)).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                Text("—").frame(maxWidth: .infinity, alignment: .center).font(.caption.weight(.bold))
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Color(.tertiarySystemGroupedBackground))

                    Divider()
                    HStack(spacing: 0) {
                        Text("Tot").frame(width: 32, alignment: .center)
                            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Text("—").frame(width: 36, alignment: .center)
                            .font(.caption2).foregroundStyle(.secondary)
                        ForEach(round.players) { player in
                            if let totals = netTotals(for: player, filter: { _ in true }) {
                                VStack(spacing: 1) {
                                    Text("\(totals.gross)").font(.caption.weight(.bold))
                                    Text("\(totals.net)").font(.system(size: 9).weight(.medium)).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                Text("—").frame(maxWidth: .infinity, alignment: .center).font(.caption.weight(.bold))
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color(.tertiarySystemGroupedBackground))

                    // Legend
                    legendRow
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var legendRow: some View {
        HStack(spacing: 16) {
            legendItem(label: "Eagle", toPar: -2)
            legendItem(label: "Birdie", toPar: -1)
            legendItem(label: "Bogey", toPar: 1)
            legendItem(label: "Dbl", toPar: 2)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private func legendItem(label: String, toPar: Int) -> some View {
        HStack(spacing: 4) {
            PGAScoreCell(gross: 4 + toPar, par: 4)
                .frame(width: 28, height: 28)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - PGA Score Cell

struct PGAScoreCell: View {
    let gross: Int?
    let par: Int

    var body: some View {
        Group {
            if let g = gross {
                let tp = g - par
                ZStack {
                    // Filled bg for eagle
                    if tp <= -2 {
                        Circle().fill(Color.yellow.opacity(0.85))
                    }
                    // Number
                    Text("\(g)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tp <= -2 ? Color.black : Color.primary)
                    // Border overlays
                    scoreOverlay(toPar: tp)
                }
                .frame(width: 28, height: 28)
            } else {
                Text("—").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func scoreOverlay(toPar: Int) -> some View {
        switch toPar {
        case ...(-2):
            // Eagle: double circle
            Circle().stroke(Color.primary, lineWidth: 1.5)
            Circle().stroke(Color.primary, lineWidth: 1.5).frame(width: 20, height: 20)
        case -1:
            // Birdie: single red circle
            Circle().stroke(Color.red, lineWidth: 2)
        case 0:
            EmptyView()
        case 1:
            // Bogey: single square
            RoundedRectangle(cornerRadius: 3).stroke(Color.primary, lineWidth: 1.5)
        default:
            // Double bogey+: double square
            RoundedRectangle(cornerRadius: 3).stroke(Color.primary, lineWidth: 1.5)
            RoundedRectangle(cornerRadius: 2).stroke(Color.primary, lineWidth: 1.5)
                .frame(width: 20, height: 20)
        }
    }
}

// MARK: - Game Strip Pill

private struct GameStripPill: View {
    let game: SaturdayGameConfig
    @ObservedObject var vm: SaturdayScoringViewModel
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(game.type.title)
                        .font(.caption.weight(.semibold))
                    Text(pillText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(pillColor)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if isExpanded {
                    Divider()
                    expandedContent
                        .padding(10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            )
        }
        .buttonStyle(.plain)
        .frame(minWidth: isExpanded ? 200 : nil, alignment: .leading)
    }

    private var pillText: String {
        switch game.type {
        case .nassau: return nassauDisplayString(vm.nassauState.overallStatus)
        case .sixPointScotch: return vm.scotchState.pillText
        case .stableford: return vm.stablefordState.pillText
        }
    }

    private var pillColor: Color {
        switch game.type {
        case .nassau: return .blue
        case .sixPointScotch: return .orange
        case .stableford: return .purple
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch game.type {
        case .nassau:
            VStack(alignment: .leading, spacing: 4) {
                nassauRow("Front", vm.nassauState.frontStatus)
                nassauRow("Back", vm.nassauState.backStatus)
                nassauRow("Overall", vm.nassauState.overallStatus)
            }
        case .sixPointScotch:
            let s = vm.scotchState
            VStack(alignment: .leading, spacing: 4) {
                if let last = s.lastOutput {
                    let buckets = pillLastHoleBuckets(last)
                    Divider().padding(.vertical, 2)
                    HStack {
                        Text("Hole \(last.holeNumber) Audit")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                        Spacer()
                        if last.multiplier > 1 {
                            Text("×\(last.multiplier)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if buckets.isEmpty {
                        Text("Push").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                            HStack {
                                Text(bucket.0).font(.caption2).foregroundStyle(.secondary)
                                Text("\(bucket.1)").font(.caption2.weight(.semibold))
                                Spacer()
                                Text(teamInitials(bucket.2))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(bucket.2 == .teamA ? Color.blue : Color.orange)
                            }
                        }
                    }
                    // Press/Roll/Re-roll actions + walking total
                    let actions = pillHoleActions(last)
                    let isA = last.multipliedTeamAPoints > last.multipliedTeamBPoints
                    let winnerRaw = isA ? last.rawTeamAPoints : last.rawTeamBPoints
                    let walkText = walkingTotalString(raw: winnerRaw, multiplier: last.multiplier)
                    if !actions.isEmpty || !walkText.isEmpty {
                        Divider().padding(.vertical, 2)
                        if !actions.isEmpty {
                            Text(actions.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if !walkText.isEmpty {
                            Text(walkText)
                                .font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                        }
                    }
                    HStack {
                        Spacer()
                        if last.multipliedTeamAPoints > last.multipliedTeamBPoints {
                            Text("\(teamInitials(.teamA)) +\(last.multipliedTeamAPoints)")
                                .font(.caption.weight(.bold)).foregroundStyle(.blue)
                        } else if last.multipliedTeamBPoints > last.multipliedTeamAPoints {
                            Text("\(teamInitials(.teamB)) +\(last.multipliedTeamBPoints)")
                                .font(.caption.weight(.bold)).foregroundStyle(.orange)
                        } else {
                            Text("Push").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        case .stableford:
            let sorted = vm.round.players.sorted {
                (vm.stablefordState.pointsByPlayerID[$0.id] ?? 0) >
                (vm.stablefordState.pointsByPlayerID[$1.id] ?? 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, player in
                    HStack(spacing: 6) {
                        Text("\(idx + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(idx == 0 ? .purple : .secondary)
                            .frame(width: 14)
                        Text(player.name).font(.caption)
                            .fontWeight(idx == 0 ? .semibold : .regular)
                        Spacer()
                        Text("\(vm.stablefordState.pointsByPlayerID[player.id] ?? 0) pts")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(idx == 0 ? .purple : .primary)
                    }
                }
            }
        }
    }

    private func nassauRow(_ label: String, _ status: NassauMatchStatus) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(nassauDisplayString(status)).font(.caption.weight(.semibold))
        }
    }

    private func scotchRow(_ label: String, a: Int, b: Int) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("\(teamInitials(.teamA)) \(a)").font(.caption.weight(.semibold)).foregroundStyle(.blue)
            Text("·").font(.caption).foregroundStyle(.secondary)
            Text("\(teamInitials(.teamB)) \(b)").font(.caption.weight(.semibold)).foregroundStyle(.orange)
        }
    }

    private func teamInitials(_ side: TeamSide) -> String {
        let players = side == .teamA ? vm.round.teamAPlayers : vm.round.teamBPlayers
        return players.map { String($0.name.split(separator: " ").first ?? Substring($0.name)) }.joined(separator: "/")
    }

    private func nassauDisplayString(_ status: NassauMatchStatus) -> String {
        if status.isClosed, let desc = status.closedDescription {
            let winner = status.leadingTeam == .teamA ? teamInitials(.teamA) : teamInitials(.teamB)
            return "\(winner) won \(desc)"
        }
        guard let leader = status.leadingTeam else { return "AS" }
        let name = leader == .teamA ? teamInitials(.teamA) : teamInitials(.teamB)
        return "\(name) \(status.holesUp)UP"
    }

    private func pillLastHoleBuckets(_ last: SixPointScotchHoleOutput) -> [(String, Int, TeamSide)] {
        let log = last.auditLog
        guard let startIdx = log.lastIndex(where: { $0 == "Hole \(last.holeNumber)" }) else { return [] }
        var result: [(String, Int, TeamSide)] = []
        for entry in log[(startIdx + 1)...] {
            for (marker, side) in [(": teamA (", TeamSide.teamA), (": teamB (", TeamSide.teamB)] {
                if entry.contains(marker) {
                    let parts = entry.components(separatedBy: marker)
                    let name = parts.first ?? ""
                    let pts = Int(parts.last?.dropLast() ?? "") ?? 0
                    result.append((name, pts, side))
                    break
                }
            }
        }
        return result
    }

    private func pillHoleActions(_ last: SixPointScotchHoleOutput) -> [String] {
        let log = last.auditLog
        guard let startIdx = log.lastIndex(where: { $0 == "Hole \(last.holeNumber)" }) else { return [] }
        return log[(startIdx + 1)...].compactMap { entry in
            if entry.hasPrefix("Press by") { return "Press" }
            if entry.hasPrefix("Roll by") { return "Roll" }
            if entry.hasPrefix("Re-roll by") { return "Re-roll" }
            return nil
        }
    }

    private func walkingTotalString(raw: Int, multiplier: Int) -> String {
        guard raw > 0, multiplier > 1 else { return "" }
        let exponent = Int(log2(Double(multiplier)))
        var steps = [raw]
        for _ in 0..<exponent { steps.append(steps.last! * 2) }
        return steps.map { "\($0)" }.joined(separator: " for ")
    }
}
