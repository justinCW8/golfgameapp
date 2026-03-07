import SwiftUI

// MARK: - Round Summary (tabbed settlement)

struct RoundSummaryView: View {
    let round: SaturdayRound
    let store: AppSessionStore
    let onDone: () -> Void

    @State private var selectedTab = 0

    private var activeTabs: [GameType] {
        round.activeGames.map(\.type)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            if activeTabs.count > 1 {
                Picker("", selection: $selectedTab) {
                    ForEach(activeTabs.indices, id: \.self) { i in
                        Text(activeTabs[i].title).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
            }

            ScrollView {
                VStack(spacing: 0) {
                    if activeTabs.indices.contains(selectedTab) {
                        summaryContent(for: activeTabs[selectedTab])
                            .padding(16)
                    }
                }
            }

            Divider()

            Button {
                store.clearSaturdayRound()
                onDone()
            } label: {
                Label("Done — Clear Round", systemImage: "checkmark.circle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemBackground))
        }
        .navigationTitle("Round Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Per-game content

    @ViewBuilder
    private func summaryContent(for game: GameType) -> some View {
        switch game {
        case .nassau:
            if let nassauGame = round.activeGames.first(where: { $0.type == .nassau }),
               let config = nassauGame.nassauConfig {
                NassauSummaryView(round: round, config: config)
            }
        case .sixPointScotch:
            if let scotchGame = round.activeGames.first(where: { $0.type == .sixPointScotch }),
               let config = scotchGame.scotchConfig {
                ScotchSummaryView(round: round, config: config)
            }
        case .stableford:
            StablefordSummaryView(round: round)
        case .skins:
            EmptyView()   // SkinsSummaryView added in Swarm 8.4
        case .strokePlay:
            StrokePlaySummaryView(round: round)
        }
    }
}

// MARK: - Nassau Settlement

struct NassauSummaryView: View {
    let round: SaturdayRound
    let config: NassauGameConfig

    private var engine: NassauEngine {
        var e = NassauEngine()
        let entries = round.holeEntries.sorted { $0.holeNumber < $1.holeNumber }
        let format = config.format
        for entry in entries {
            guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
            let sideANet: [Int]
            let sideBNet: [Int]
            if format == .fourball {
                sideANet = round.teamAPlayers.map { p in
                    let g = entry.grossByPlayerID[p.id] ?? (stub.par + 2)
                    let s = strokeCountForHandicapIndex(p.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                    return g - s
                }
                sideBNet = round.teamBPlayers.map { p in
                    let g = entry.grossByPlayerID[p.id] ?? (stub.par + 2)
                    let s = strokeCountForHandicapIndex(p.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                    return g - s
                }
            } else {
                let p1 = round.players.first
                let p2 = round.players.dropFirst().first
                sideANet = [p1].compactMap { p -> Int? in
                    guard let p else { return nil }
                    return (entry.grossByPlayerID[p.id] ?? (stub.par + 2)) - strokeCountForHandicapIndex(p.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                }
                sideBNet = [p2].compactMap { p -> Int? in
                    guard let p else { return nil }
                    return (entry.grossByPlayerID[p.id] ?? (stub.par + 2)) - strokeCountForHandicapIndex(p.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                }
            }
            let input = NassauHoleInput(holeNumber: entry.holeNumber, par: stub.par, sideANetScores: sideANet, sideBNetScores: sideBNet, manualPressBy: entry.nassauManualPressBy)
            _ = try? e.scoreHole(input, config: config.pressConfig)
        }
        return e
    }

    private func teamInitials(_ players: [PlayerSnapshot]) -> String {
        players.map { String($0.name.split(separator: " ").first ?? Substring($0.name)) }.joined(separator: "/")
    }

    private var sideAName: String {
        config.format == .fourball
            ? teamInitials(round.teamAPlayers)
            : round.players.first?.name ?? "Side A"
    }

    private var sideBName: String {
        config.format == .fourball
            ? teamInitials(round.teamBPlayers)
            : round.players.dropFirst().first?.name ?? "Side B"
    }

    var body: some View {
        let settlement = engine.settlement()
        let totalNetA = settlement.totalNetForA

        VStack(spacing: 16) {
            // Winner banner
            settlementBanner(netA: totalNetA, aName: sideAName, bName: sideBName, stake: config.frontStake)

            // Bets breakdown
            VStack(spacing: 0) {
                betRow("Front 9", result: settlement.front, stake: config.frontStake, aName: sideAName, bName: sideBName)
                Divider()
                betRow("Back 9", result: settlement.back, stake: config.backStake, aName: sideAName, bName: sideBName)
                Divider()
                betRow("Overall", result: settlement.overall, stake: config.overallStake, aName: sideAName, bName: sideBName)

                if !settlement.frontPresses.isEmpty || !settlement.backPresses.isEmpty {
                    Divider()
                    ForEach(Array(settlement.frontPresses.enumerated()), id: \.offset) { i, press in
                        betRow("Front Press \(i+1)", result: press, stake: config.frontStake, aName: sideAName, bName: sideBName)
                        Divider()
                    }
                    ForEach(Array(settlement.backPresses.enumerated()), id: \.offset) { i, press in
                        betRow("Back Press \(i+1)", result: press, stake: config.backStake, aName: sideAName, bName: sideBName)
                        if i < settlement.backPresses.count - 1 { Divider() }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func settlementBanner(netA: Int, aName: String, bName: String, stake: Double) -> some View {
        let totalBets = Double(engine.settlement().totalBets)
        let winnerName = netA > 0 ? aName : netA < 0 ? bName : nil
        let loserName = netA > 0 ? bName : netA < 0 ? aName : nil
        let amount = abs(Double(netA)) * stake

        return VStack(spacing: 6) {
            if let winner = winnerName, let loser = loserName {
                Text(winner)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.green)
                Text("wins \(abs(netA)) of \(Int(totalBets)) bets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(loser) owes $\(String(format: "%.0f", amount))")
                    .font(.headline)
            } else {
                Text("All Square")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func betRow(_ label: String, result: NassauSegmentResult, stake: Double, aName: String, bName: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            betOutcomeText(result: result, stake: stake, aName: aName, bName: bName)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func betOutcomeText(result: NassauSegmentResult, stake: Double, aName: String, bName: String) -> some View {
        switch result.outcome {
        case .sideAWon(let desc):
            HStack(spacing: 4) {
                Text("\(aName) \(desc)").font(.subheadline.weight(.semibold)).foregroundStyle(.blue)
                Text("$\(String(format: "%.0f", stake))").font(.caption).foregroundStyle(.secondary)
            }
        case .sideBWon(let desc):
            HStack(spacing: 4) {
                Text("\(bName) \(desc)").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                Text("$\(String(format: "%.0f", stake))").font(.caption).foregroundStyle(.secondary)
            }
        case .halved:
            Text("Halved").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Scotch Settlement

struct ScotchSummaryView: View {
    let round: SaturdayRound
    let config: ScotchGameConfig

    private var finalState: (totalA: Int, totalB: Int, frontA: Int, frontB: Int, backA: Int, backB: Int) {
        var engine = SixPointScotchEngine()
        let entries = round.holeEntries.sorted { $0.holeNumber < $1.holeNumber }
        var lastOutput: SixPointScotchHoleOutput?

        for entry in entries {
            guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
            let teamANet = round.teamAPlayers.map { p in
                let g = entry.grossByPlayerID[p.id] ?? (stub.par + 2)
                return g - strokeCountForHandicapIndex(p.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
            }
            let teamBNet = round.teamBPlayers.map { p in
                let g = entry.grossByPlayerID[p.id] ?? (stub.par + 2)
                return g - strokeCountForHandicapIndex(p.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
            }
            let teamAGross = round.teamAPlayers.compactMap { entry.grossByPlayerID[$0.id] }
            let teamBGross = round.teamBPlayers.compactMap { entry.grossByPlayerID[$0.id] }
            let teamAProx = round.teamAPlayers.compactMap { entry.scotchFlags.proxFeetByPlayerID[$0.id] }.min()
            let teamBProx = round.teamBPlayers.compactMap { entry.scotchFlags.proxFeetByPlayerID[$0.id] }.min()

            let input = SixPointScotchHoleInput(
                holeNumber: entry.holeNumber, par: stub.par,
                teamANetScores: teamANet, teamBNetScores: teamBNet,
                teamAGrossScores: teamAGross, teamBGrossScores: teamBGross,
                teamAProxFeet: teamAProx, teamBProxFeet: teamBProx,
                requestPressBy: entry.scotchFlags.requestPressBy,
                requestRollBy: entry.scotchFlags.requestRollBy,
                requestRerollBy: entry.scotchFlags.requestRerollBy
            )
            lastOutput = try? engine.scoreHole(input)
        }

        return (
            lastOutput?.totalTeamA ?? 0,
            lastOutput?.totalTeamB ?? 0,
            lastOutput?.frontNineTeamA ?? 0,
            lastOutput?.frontNineTeamB ?? 0,
            lastOutput?.backNineTeamA ?? 0,
            lastOutput?.backNineTeamB ?? 0
        )
    }

    private func teamInitials(_ players: [PlayerSnapshot]) -> String {
        players.map { String($0.name.split(separator: " ").first ?? Substring($0.name)) }.joined(separator: "/")
    }

    private var teamAName: String { teamInitials(round.teamAPlayers) }
    private var teamBName: String { teamInitials(round.teamBPlayers) }

    var body: some View {
        let state = finalState
        let diff = state.totalA - state.totalB
        let winnerName = diff > 0 ? teamAName : diff < 0 ? teamBName : nil
        let loserName = diff > 0 ? teamBName : diff < 0 ? teamAName : nil
        let amount = abs(Double(diff)) * config.pointValue

        VStack(spacing: 16) {
            // Banner
            VStack(spacing: 6) {
                if let winner = winnerName, let loser = loserName {
                    Text(winner)
                        .font(.title2.weight(.bold)).foregroundStyle(.green)
                    Text("wins \(abs(diff)) points")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("\(loser) owes $\(String(format: "%.0f", amount))")
                        .font(.headline)
                } else {
                    Text("Tied").font(.title2.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            // Breakdown
            VStack(spacing: 0) {
                scotchRow("Front 9", a: state.frontA, b: state.frontB)
                Divider()
                scotchRow("Back 9", a: state.backA, b: state.backB)
                Divider()
                scotchRow("Total", a: state.totalA, b: state.totalB)
                    .fontWeight(.semibold)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            // Per-point value
            if config.pointValue > 0 {
                Text("$\(String(format: "%.0f", config.pointValue)) per point")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func scotchRow(_ label: String, a: Int, b: Int) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text("\(teamAName): \(a)").font(.subheadline.weight(.medium)).foregroundStyle(.blue)
            Text("·").foregroundStyle(.secondary)
            Text("\(teamBName): \(b)").font(.subheadline.weight(.medium)).foregroundStyle(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Stableford Leaderboard

struct StrokePlaySummaryView: View {
    let round: SaturdayRound
    
    private var config: StrokePlayGameConfig {
        round.activeGames.first(where: { $0.type == .strokePlay })?.strokePlayConfig ?? StrokePlayGameConfig()
    }
    
    private var engineResult: StrokePlayHoleOutput? {
        let engineConfig = StrokePlayEngineConfig(format: config.format, pairings: config.bestBallPairings)
        var engine = StrokePlayEngine(config: engineConfig)
        let entries = round.holeEntries.sorted { $0.holeNumber < $1.holeNumber }
        var lastOutput: StrokePlayHoleOutput?
        for entry in entries {
            guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
            let scores = round.players.map { player -> StrokePlayPlayerScore in
                let gross = entry.grossByPlayerID[player.id] ?? stub.par
                let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                return StrokePlayPlayerScore(playerID: player.id, gross: gross, handicapStrokes: strokes)
            }
            if let output = try? engine.scoreHole(StrokePlayHoleInput(holeNumber: entry.holeNumber, par: stub.par, scores: scores)) {
                lastOutput = output
            }
        }
        return lastOutput
    }

    private var leaderboard: [(player: PlayerSnapshot, grossTotal: Int, netTotal: Int, vsPar: Int)] {
        guard let output = engineResult else { return [] }
        return output.leaderboard.compactMap { standing in
            guard let player = round.players.first(where: { $0.id == standing.playerID }) else { return nil }
            return (player: player, grossTotal: standing.grossTotal, netTotal: standing.netTotal, vsPar: standing.vsPar)
        }
    }
    
    private var teamLeaderboard: [BestBallTeamStanding] {
        engineResult?.bestBallTeamStandings ?? []
    }

    var body: some View {
        VStack(spacing: 16) {
            // Team Best Ball - show only team winner
            if config.format == .teamBestBall, let topTeam = teamLeaderboard.first {
                let vsParStr = topTeam.vsPar == 0 ? "Even" : (topTeam.vsPar > 0 ? "+\(topTeam.vsPar)" : "\(topTeam.vsPar)")
                VStack(spacing: 6) {
                    Text(topTeam.teamName)
                        .font(.title2.weight(.bold)).foregroundStyle(.teal)
                    Text("\(vsParStr) · Net \(topTeam.netTotal)")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            // 2v2 Best Ball - show team winners
            else if config.format == .bestBall2v2, let topTeam = teamLeaderboard.first(where: { $0.rank == 1 }) {
                let vsParStr = topTeam.vsPar == 0 ? "Even" : (topTeam.vsPar > 0 ? "+\(topTeam.vsPar)" : "\(topTeam.vsPar)")
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(.yellow)
                        Text(topTeam.teamName)
                            .font(.title2.weight(.bold)).foregroundStyle(.teal)
                    }
                    Text("\(vsParStr) · Net \(topTeam.netTotal)")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                
                // Team leaderboard
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("").frame(width: 24)
                        Text("Team").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("Gross").font(.caption).foregroundStyle(.secondary).frame(width: 44)
                        Text("Net").font(.caption).foregroundStyle(.secondary).frame(width: 44)
                        Text("+/-").font(.caption).foregroundStyle(.secondary).frame(width: 36)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Divider()
                    ForEach(Array(teamLeaderboard.enumerated()), id: \.element.teamID) { index, team in
                        HStack(spacing: 12) {
                            Text("\(team.rank)")
                                .font(.headline)
                                .foregroundStyle(team.rank == 1 ? .teal : .secondary)
                                .frame(width: 24)
                            Text(team.teamName)
                                .font(.subheadline.weight(team.rank == 1 ? .semibold : .regular))
                            Spacer()
                            Text("\(team.grossTotal)").font(.subheadline).frame(width: 44)
                            Text("\(team.netTotal)").font(.subheadline.weight(.medium)).frame(width: 44)
                            let vsParStr = team.vsPar == 0 ? "E" : (team.vsPar > 0 ? "+\(team.vsPar)" : "\(team.vsPar)")
                            Text(vsParStr)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(team.vsPar < 0 ? .teal : (team.vsPar == 0 ? .primary : .secondary))
                                .frame(width: 36)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        if index < teamLeaderboard.count - 1 { Divider() }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            // Individual - show individual winner
            else if let top = leaderboard.first {
                let vsParStr = top.vsPar == 0 ? "Even" : (top.vsPar > 0 ? "+\(top.vsPar)" : "\(top.vsPar)")
                VStack(spacing: 6) {
                    Text(top.player.name)
                        .font(.title2.weight(.bold)).foregroundStyle(.teal)
                    Text("\(vsParStr) · Net \(top.netTotal)")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            // Individual leaderboard (show for individual and 2v2)
            if config.format != .teamBestBall {
                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 12) {
                        Text("").frame(width: 24)
                        Text("Player").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("Gross").font(.caption).foregroundStyle(.secondary).frame(width: 44)
                        Text("Net").font(.caption).foregroundStyle(.secondary).frame(width: 44)
                        Text("+/-").font(.caption).foregroundStyle(.secondary).frame(width: 36)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Divider()
                    ForEach(Array(leaderboard.enumerated()), id: \.element.player.id) { index, row in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundStyle(index == 0 ? .teal : .secondary)
                                .frame(width: 24)
                            Text(row.player.name)
                                .font(.subheadline.weight(index == 0 ? .semibold : .regular))
                            Spacer()
                            Text("\(row.grossTotal)").font(.subheadline).frame(width: 44)
                            Text("\(row.netTotal)").font(.subheadline.weight(.medium)).frame(width: 44)
                            let vsParStr = row.vsPar == 0 ? "E" : (row.vsPar > 0 ? "+\(row.vsPar)" : "\(row.vsPar)")
                            Text(vsParStr)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(row.vsPar < 0 ? .teal : (row.vsPar == 0 ? .primary : .secondary))
                                .frame(width: 36)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        if index < leaderboard.count - 1 { Divider() }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct StablefordSummaryView: View {
    let round: SaturdayRound

    private var leaderboard: [(player: PlayerSnapshot, points: Int)] {
        var totals: [String: Int] = [:]
        let entries = round.holeEntries.sorted { $0.holeNumber < $1.holeNumber }
        for entry in entries {
            guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
            for player in round.players {
                let gross = entry.grossByPlayerID[player.id] ?? (stub.par + 2)
                let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                let output = StablefordEngine.scoreHole(StablefordHoleScoreInput(gross: gross, par: stub.par, handicapStrokes: strokes))
                totals[player.id, default: 0] += output.points
            }
        }
        return round.players
            .map { (player: $0, points: totals[$0.id] ?? 0) }
            .sorted { $0.points > $1.points }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Winner banner
            if let top = leaderboard.first {
                VStack(spacing: 6) {
                    Text(top.player.name)
                        .font(.title2.weight(.bold)).foregroundStyle(.green)
                    Text("\(top.points) points")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            // Full leaderboard
            VStack(spacing: 0) {
                ForEach(Array(leaderboard.enumerated()), id: \.element.player.id) { index, row in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .foregroundStyle(index == 0 ? .green : .secondary)
                            .frame(width: 24)
                        Text(row.player.name)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(row.points)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(index == 0 ? .green : .primary)
                        Text("pts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    if index < leaderboard.count - 1 { Divider() }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
