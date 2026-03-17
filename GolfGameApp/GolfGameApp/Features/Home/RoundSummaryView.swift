import SwiftUI
import MessageUI

// MARK: - Round Summary (tabbed settlement)

struct RoundSummaryView: View {
    let round: SaturdayRound
    let store: AppSessionStore
    let onDone: () -> Void

    @EnvironmentObject private var buddyStore: BuddyStore
    @State private var selectedTab = 0
    @State private var showingMessageComposer = false
    @State private var showCannotTextAlert = false
    @State private var showSendConfirmAlert = false

    private var activeTabs: [GameType] {
        round.activeGames.map(\.type)
    }

    private var messageData: RoundTextMessageData {
        RoundTextMessageData(
            recipients: buddyStore.phoneNumbers(forPlayers: round.players.map(\.name)),
            body: RoundTextMessageComposer.messageBody(for: round),
            attachmentData: RoundMessageSnapshotRenderer.pngData(for: round),
            attachmentUTI: "public.png",
            attachmentFilename: "golf-round-summary.png"
        )
    }

    private var recipientEntries: [(name: String, phone: String)] {
        buddyStore.textingRecipients(forPlayers: round.players.map(\.name))
    }

    private var recipientPreviewText: String {
        if recipientEntries.isEmpty {
            return "No saved phone numbers matched this group. You can still review and send from the composer."
        }
        return recipientEntries
            .map { "\($0.name): \($0.phone)" }
            .joined(separator: "\n")
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

            VStack(spacing: 10) {
                Button {
                    if MFMessageComposeViewController.canSendText() {
                        showSendConfirmAlert = true
                    } else {
                        showCannotTextAlert = true
                    }
                } label: {
                    Label("Text Scorecard + Settlement", systemImage: "message.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)

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
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemBackground))
        }
        .navigationTitle("Round Summary")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMessageComposer) {
            RoundMessageComposeView(
                recipients: messageData.recipients,
                body: messageData.body,
                attachmentData: messageData.attachmentData,
                attachmentUTI: messageData.attachmentUTI,
                attachmentFilename: messageData.attachmentFilename
            )
        }
        .alert("Send Scorecard + Settlement?", isPresented: $showSendConfirmAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Open Message") {
                showingMessageComposer = true
            }
        } message: {
            Text(recipientPreviewText)
        }
        .alert("Text Messaging Unavailable", isPresented: $showCannotTextAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This simulator cannot send SMS. Use a real iPhone to text your group.")
        }
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
            if let skinsGame = round.activeGames.first(where: { $0.type == .skins }),
               let config = skinsGame.skinsConfig {
                SkinsSummaryView(round: round, config: config)
            }
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
                    Text("\(loser) owes $\(formattedCurrencyAmount(amount))")
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
                Text("$\(formattedCurrencyAmount(config.pointValue)) per point")
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

// MARK: - Skins Settlement

struct SkinsSummaryView: View {
    let round: SaturdayRound
    let config: SkinsGameConfig

    private struct EngineResult {
        var grossSkinsTotal: [String: Int]
        var netSkinsTotal: [String: Int]
        var grossCarryover: Int
        var netCarryover: Int
    }

    private var engineResult: EngineResult {
        var engine = SkinsEngine()
        var lastOutput: SkinsHoleOutput?
        let entries = round.holeEntries.sorted { $0.holeNumber < $1.holeNumber }
        for entry in entries {
            guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
            let scores = round.players.map { player -> SkinsPlayerScore in
                let gross = entry.grossByPlayerID[player.id] ?? stub.par
                let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                return SkinsPlayerScore(playerID: player.id, gross: gross, handicapStrokes: strokes)
            }
            let input = SkinsHoleInput(
                holeNumber: entry.holeNumber, par: stub.par,
                scores: scores, mode: config.mode, carryoverEnabled: config.carryoverEnabled
            )
            if let output = try? engine.scoreHole(input) { lastOutput = output }
        }
        return EngineResult(
            grossSkinsTotal: lastOutput?.grossSkinsTotal ?? [:],
            netSkinsTotal: lastOutput?.netSkinsTotal ?? [:],
            grossCarryover: lastOutput?.grossCarryover ?? 0,
            netCarryover: lastOutput?.netCarryover ?? 0
        )
    }

    private struct PlayerRow {
        var player: PlayerSnapshot
        var grossSkins: Int
        var netSkins: Int
        var totalSkins: Int
        var winnings: Double
    }

    private var leaderboard: [PlayerRow] {
        let result = engineResult
        return round.players.map { player in
            let gross = result.grossSkinsTotal[player.id] ?? 0
            let net = result.netSkinsTotal[player.id] ?? 0
            let total: Int
            switch config.mode {
            case .gross: total = gross
            case .net:   total = net
            case .both:  total = gross + net
            }
            return PlayerRow(player: player, grossSkins: gross, netSkins: net,
                             totalSkins: total, winnings: Double(total) * config.skinValue)
        }
        .sorted { $0.totalSkins > $1.totalSkins }
    }

    var body: some View {
        let board = leaderboard
        let result = engineResult
        let unresolvedGross = config.mode != .net ? result.grossCarryover : 0
        let unresolvedNet   = config.mode != .gross ? result.netCarryover : 0

        VStack(spacing: 16) {
            // Winner banner
            if let top = board.first, top.totalSkins > 0 {
                VStack(spacing: 6) {
                    Text(top.player.name)
                        .font(.title2.weight(.bold)).foregroundStyle(.green)
                    Text("\(top.totalSkins) skin\(top.totalSkins == 1 ? "" : "s") · $\(String(format: "%.0f", top.winnings))")
                        .font(.headline)
                    Text("$\(String(format: "%.0f", config.skinValue)) per skin")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 6) {
                    Text("No Skins Won")
                        .font(.title2.weight(.bold)).foregroundStyle(.secondary)
                    Text("All holes tied")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            // Unresolved carryover warning
            if unresolvedGross > 0 || unresolvedNet > 0 {
                let carries = [
                    unresolvedGross > 0 ? "\(unresolvedGross) gross" : nil,
                    unresolvedNet   > 0 ? "\(unresolvedNet) net"     : nil
                ].compactMap { $0 }.joined(separator: " · ")
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("\(carries) skin(s) unresolved — round ended mid-carryover")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Leaderboard table
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("").frame(width: 24)
                    Text("Player").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if config.mode == .both {
                        Text("Gross").font(.caption).foregroundStyle(.secondary).frame(width: 44)
                        Text("Net").font(.caption).foregroundStyle(.secondary).frame(width: 44)
                    }
                    Text("Skins").font(.caption).foregroundStyle(.secondary).frame(width: 40)
                    Text("$").font(.caption).foregroundStyle(.secondary).frame(width: 44)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
                ForEach(Array(board.enumerated()), id: \.element.player.id) { index, row in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .foregroundStyle(row.totalSkins > 0 ? .green : .secondary)
                            .frame(width: 24)
                        Text(row.player.name)
                            .font(.subheadline.weight(row.totalSkins > 0 ? .semibold : .regular))
                        Spacer()
                        if config.mode == .both {
                            Text("\(row.grossSkins)").font(.subheadline).foregroundStyle(.secondary).frame(width: 44)
                            Text("\(row.netSkins)").font(.subheadline).foregroundStyle(.secondary).frame(width: 44)
                        }
                        Text("\(row.totalSkins)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(row.totalSkins > 0 ? .green : .secondary)
                            .frame(width: 40)
                        Text(row.winnings > 0 ? "$\(String(format: "%.0f", row.winnings))" : "—")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(row.winnings > 0 ? .primary : .secondary)
                            .frame(width: 44)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    if index < board.count - 1 { Divider() }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
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

struct RoundTextMessageData {
    var recipients: [String]
    var body: String
    var attachmentData: Data?
    var attachmentUTI: String?
    var attachmentFilename: String?
}

struct RoundMessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let attachmentData: Data?
    let attachmentUTI: String?
    let attachmentFilename: String?

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var parent: RoundMessageComposeView

        init(parent: RoundMessageComposeView) {
            self.parent = parent
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = context.coordinator
        vc.recipients = recipients.isEmpty ? nil : recipients
        vc.body = body
        if let attachmentData, let attachmentUTI, let attachmentFilename {
            vc.addAttachmentData(attachmentData, typeIdentifier: attachmentUTI, filename: attachmentFilename)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
}

enum RoundTextMessageComposer {
    static func messageBody(for round: SaturdayRound) -> String {
        var lines: [String] = []
        lines.append("Golf Round Summary")
        lines.append("\(round.courseName)")
        lines.append(round.createdAt.formatted(date: .abbreviated, time: .shortened))
        lines.append("Players: \(round.players.map(\.name).joined(separator: ", "))")
        lines.append("")
        lines.append("Scorecard Totals")
        lines.append(contentsOf: scorecardLines(for: round))
        lines.append("")
        lines.append("Final Settlement")
        lines.append(contentsOf: settlementLines(for: round))
        return lines.joined(separator: "\n")
    }

    static func scorecardLines(for round: SaturdayRound) -> [String] {
        let entries = round.holeEntries.sorted { $0.holeNumber < $1.holeNumber }
        let holesPlayed = entries.count
        return round.players.map { player in
            var grossTotal = 0
            var netTotal = 0
            for entry in entries {
                guard let gross = entry.grossByPlayerID[player.id] else { continue }
                grossTotal += gross
                let strokeIndex = round.holes.first(where: { $0.number == entry.holeNumber })?.strokeIndex ?? entry.holeNumber
                let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: strokeIndex)
                netTotal += gross - strokes
            }
            return "- \(player.name): Gross \(grossTotal), Net \(netTotal) (\(holesPlayed) holes)"
        }
    }

    static func settlementLines(for round: SaturdayRound) -> [String] {
        var lines: [String] = []
        for game in round.activeGames {
            switch game.type {
            case .nassau:
                if let config = game.nassauConfig {
                    lines.append(nassauSummary(round: round, config: config))
                }
            case .sixPointScotch:
                if let config = game.scotchConfig {
                    lines.append(scotchSummary(round: round, config: config))
                }
            case .stableford:
                lines.append(stablefordSummary(round: round))
            case .skins:
                if let config = game.skinsConfig {
                    lines.append(skinsSummary(round: round, config: config))
                }
            case .strokePlay:
                if let config = game.strokePlayConfig {
                    lines.append(strokePlaySummary(round: round, config: config))
                }
            }
        }
        return lines.isEmpty ? ["- No active games configured."] : lines
    }

    private static func nassauSummary(round: SaturdayRound, config: NassauGameConfig) -> String {
        var engine = NassauEngine()
        let entries = round.holeEntries.sorted { $0.holeNumber < $1.holeNumber }
        for entry in entries {
            guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
            let sideANet: [Int]
            let sideBNet: [Int]
            if config.format == .fourball {
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
                sideANet = round.players.prefix(1).map { p in
                    let g = entry.grossByPlayerID[p.id] ?? (stub.par + 2)
                    let s = strokeCountForHandicapIndex(p.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                    return g - s
                }
                sideBNet = round.players.dropFirst().prefix(1).map { p in
                    let g = entry.grossByPlayerID[p.id] ?? (stub.par + 2)
                    let s = strokeCountForHandicapIndex(p.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                    return g - s
                }
            }
            _ = try? engine.scoreHole(
                NassauHoleInput(
                    holeNumber: entry.holeNumber,
                    par: stub.par,
                    sideANetScores: sideANet,
                    sideBNetScores: sideBNet,
                    manualPressBy: entry.nassauManualPressBy
                ),
                config: config.pressConfig
            )
        }

        let settlement = engine.settlement()
        let net = settlement.totalNetForA
        let sideAName = shortTeamName(round.teamAPlayers, fallback: round.players.first?.name ?? "Side A")
        let sideBName = shortTeamName(round.teamBPlayers, fallback: round.players.dropFirst().first?.name ?? "Side B")
        if net == 0 {
            return "- Nassau: All square."
        }
        let winner = net > 0 ? sideAName : sideBName
        let loser = net > 0 ? sideBName : sideAName
        let amount = abs(Double(net)) * config.frontStake
        return "- Nassau: \(winner) won \(abs(net)) bets. \(loser) owes $\(Int(amount.rounded()))."
    }

    private static func scotchSummary(round: SaturdayRound, config: ScotchGameConfig) -> String {
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
            lastOutput = try? engine.scoreHole(
                SixPointScotchHoleInput(
                    holeNumber: entry.holeNumber,
                    par: stub.par,
                    teamANetScores: teamANet,
                    teamBNetScores: teamBNet,
                    teamAGrossScores: teamAGross,
                    teamBGrossScores: teamBGross,
                    teamAProxFeet: teamAProx,
                    teamBProxFeet: teamBProx,
                    requestPressBy: entry.scotchFlags.requestPressBy,
                    requestRollBy: entry.scotchFlags.requestRollBy,
                    requestRerollBy: entry.scotchFlags.requestRerollBy
                )
            )
        }
        let totalA = lastOutput?.totalTeamA ?? 0
        let totalB = lastOutput?.totalTeamB ?? 0
        let diff = totalA - totalB
        if diff == 0 {
            return "- Six Point Scotch: Tied."
        }
        let teamAName = shortTeamName(round.teamAPlayers, fallback: "Team A")
        let teamBName = shortTeamName(round.teamBPlayers, fallback: "Team B")
        let winner = diff > 0 ? teamAName : teamBName
        let loser = diff > 0 ? teamBName : teamAName
        let amount = abs(Double(diff)) * config.pointValue
        return "- Six Point Scotch: \(winner) +\(abs(diff)) pts. \(loser) owes $\(formattedCurrencyAmount(amount))."
    }

    private static func stablefordSummary(round: SaturdayRound) -> String {
        var totals: [String: Int] = [:]
        let entries = round.holeEntries.sorted { $0.holeNumber < $1.holeNumber }
        for entry in entries {
            guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
            for player in round.players {
                let gross = entry.grossByPlayerID[player.id] ?? (stub.par + 2)
                let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                let output = StablefordEngine.scoreHole(
                    StablefordHoleScoreInput(gross: gross, par: stub.par, handicapStrokes: strokes)
                )
                totals[player.id, default: 0] += output.points
            }
        }
        let rankedPlayers = round.players.sorted { lhs, rhs in
            let lhsPoints = totals[lhs.id, default: 0]
            let rhsPoints = totals[rhs.id, default: 0]
            if lhsPoints != rhsPoints { return lhsPoints > rhsPoints }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        guard let winner = rankedPlayers.first else {
            return "- Stableford: No result."
        }
        let standings = rankedPlayers
            .map { "\($0.name) \(totals[$0.id, default: 0])" }
            .joined(separator: ", ")
        return "- Stableford: \(winner.name) won with \(totals[winner.id, default: 0]) points. Standings: \(standings)."
    }

    private static func skinsSummary(round: SaturdayRound, config: SkinsGameConfig) -> String {
        var engine = SkinsEngine()
        let entries = round.holeEntries.sorted { $0.holeNumber < $1.holeNumber }
        var lastOutput: SkinsHoleOutput?
        for entry in entries {
            guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
            let scores = round.players.map { player -> SkinsPlayerScore in
                let gross = entry.grossByPlayerID[player.id] ?? stub.par
                let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                return SkinsPlayerScore(playerID: player.id, gross: gross, handicapStrokes: strokes)
            }
            lastOutput = try? engine.scoreHole(
                SkinsHoleInput(
                    holeNumber: entry.holeNumber,
                    par: stub.par,
                    scores: scores,
                    mode: config.mode,
                    carryoverEnabled: config.carryoverEnabled
                )
            )
        }
        let grossTotals = lastOutput?.grossSkinsTotal ?? [:]
        let netTotals = lastOutput?.netSkinsTotal ?? [:]
        let top = round.players.max { lhs, rhs in
            let lhsTotal = totalSkins(for: lhs.id, gross: grossTotals, net: netTotals, mode: config.mode)
            let rhsTotal = totalSkins(for: rhs.id, gross: grossTotals, net: netTotals, mode: config.mode)
            return lhsTotal < rhsTotal
        }
        guard let top else { return "- Skins: No result." }
        let skins = totalSkins(for: top.id, gross: grossTotals, net: netTotals, mode: config.mode)
        return "- Skins: \(top.name) won \(skins) skin\(skins == 1 ? "" : "s")."
    }

    private static func strokePlaySummary(round: SaturdayRound, config: StrokePlayGameConfig) -> String {
        var engine = StrokePlayEngine(
            config: StrokePlayEngineConfig(format: config.format, pairings: config.bestBallPairings)
        )
        let entries = round.holeEntries.sorted { $0.holeNumber < $1.holeNumber }
        var lastOutput: StrokePlayHoleOutput?
        for entry in entries {
            guard let stub = round.holes.first(where: { $0.number == entry.holeNumber }) else { continue }
            let scores = round.players.map { player -> StrokePlayPlayerScore in
                let gross = entry.grossByPlayerID[player.id] ?? stub.par
                let strokes = strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: stub.strokeIndex)
                return StrokePlayPlayerScore(playerID: player.id, gross: gross, handicapStrokes: strokes)
            }
            lastOutput = try? engine.scoreHole(
                StrokePlayHoleInput(holeNumber: entry.holeNumber, par: stub.par, scores: scores)
            )
        }
        guard let lastOutput else { return "- Stroke Play: No result." }
        if config.format == .teamBestBall || config.format == .bestBall2v2 {
            guard let topTeam = lastOutput.bestBallTeamStandings?.first else { return "- Stroke Play: No team result." }
            let vsPar = topTeam.vsPar == 0 ? "E" : (topTeam.vsPar > 0 ? "+\(topTeam.vsPar)" : "\(topTeam.vsPar)")
            return "- Stroke Play: \(topTeam.teamName) won at \(vsPar)."
        }
        guard let topPlayer = lastOutput.leaderboard.first,
              let player = round.players.first(where: { $0.id == topPlayer.playerID }) else {
            return "- Stroke Play: No result."
        }
        let vsPar = topPlayer.vsPar == 0 ? "E" : (topPlayer.vsPar > 0 ? "+\(topPlayer.vsPar)" : "\(topPlayer.vsPar)")
        return "- Stroke Play: \(player.name) won at \(vsPar)."
    }

    private static func shortTeamName(_ players: [PlayerSnapshot], fallback: String) -> String {
        guard !players.isEmpty else { return fallback }
        return players
            .map { String($0.name.split(separator: " ").first ?? Substring($0.name)) }
            .joined(separator: "/")
    }

    private static func totalSkins(
        for playerID: String,
        gross: [String: Int],
        net: [String: Int],
        mode: SkinsMode
    ) -> Int {
        switch mode {
        case .gross: return gross[playerID] ?? 0
        case .net: return net[playerID] ?? 0
        case .both: return (gross[playerID] ?? 0) + (net[playerID] ?? 0)
        }
    }
}

enum RoundMessageSnapshotRenderer {
    @MainActor
    static func pngData(for round: SaturdayRound) -> Data? {
        let renderer = ImageRenderer(content: RoundMessageSnapshotView(round: round))
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage?.pngData()
    }
}

private struct RoundMessageSnapshotView: View {
    let round: SaturdayRound

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

    private func handicapStrokes(for player: PlayerSnapshot, on stub: CourseHoleStub?, holeNumber: Int) -> Int {
        let si = stub?.strokeIndex ?? holeNumber
        return strokeCountForHandicapIndex(player.handicapIndex, onHoleStrokeIndex: si)
    }

    private func strokeMarker(_ count: Int) -> String {
        if count <= 0 { return "" }
        if count == 1 { return "•" }
        if count == 2 { return "••" }
        return "•x\(count)"
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
        let netTotal = filtered.compactMap { entry -> Int? in
            guard let gross = entry.grossByPlayerID[player.id] else { return nil }
            let stub = round.holes.first(where: { $0.number == entry.holeNumber })
            return netScore(for: player, on: stub, holeNumber: entry.holeNumber, gross: gross)
        }.reduce(0, +)
        return (grossTotal, netTotal)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Scorecard")
                    .font(.title.weight(.bold))
                Spacer()
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("H").frame(width: 32, alignment: .center)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Par").frame(width: 36, alignment: .center)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("SI").frame(width: 32, alignment: .center)
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

                ForEach(entries) { entry in
                    let stub = round.holes.first(where: { $0.number == entry.holeNumber })
                    let par = stub?.par ?? 4
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("\(entry.holeNumber)").frame(width: 32, alignment: .center)
                                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            Text("\(par)").frame(width: 36, alignment: .center)
                                .font(.caption2).foregroundStyle(.secondary)
                            Text("\(stub?.strokeIndex ?? entry.holeNumber)").frame(width: 32, alignment: .center)
                                .font(.caption2).foregroundStyle(.secondary)
                            ForEach(round.players) { player in
                                VStack(spacing: 1) {
                                    PGAScoreCell(gross: entry.grossByPlayerID[player.id], par: par)
                                    if let gross = entry.grossByPlayerID[player.id] {
                                        let net = netScore(for: player, on: stub, holeNumber: entry.holeNumber, gross: gross)
                                        let strokes = handicapStrokes(for: player, on: stub, holeNumber: entry.holeNumber)
                                        HStack(spacing: 2) {
                                            if strokes > 0 {
                                                Text(strokeMarker(strokes))
                                                    .font(.system(size: 8).weight(.bold))
                                                    .foregroundStyle(.blue)
                                            }
                                            Text("\(net)")
                                                .font(.system(size: 9).weight(.medium))
                                                .foregroundStyle(netColor(net - par))
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)

                        if entry.holeNumber == 9 {
                            nineTotalsRow(label: "Out", parTotal: round.holes.filter { $0.number <= 9 }.map(\.par).reduce(0, +)) { $0.holeNumber <= 9 }
                        }

                        if entry.holeNumber != entries.last?.holeNumber && entry.holeNumber != 9 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }

                Divider()
                nineTotalsRow(label: "In", parTotal: round.holes.filter { $0.number > 9 }.map(\.par).reduce(0, +)) { $0.holeNumber > 9 }

                Divider()
                HStack(spacing: 0) {
                    Text("Tot").frame(width: 32, alignment: .center)
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text("—").frame(width: 36, alignment: .center)
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("—").frame(width: 32, alignment: .center)
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
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .padding(16)
        }
        .frame(width: 900, alignment: .top)
        .background(Color(.systemGroupedBackground))
    }

    private func nineTotalsRow(label: String, parTotal: Int, filter: @escaping (SaturdayHoleEntry) -> Bool) -> some View {
        HStack(spacing: 0) {
            Text(label).frame(width: 32, alignment: .center)
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text("\(parTotal)")
                .frame(width: 36, alignment: .center)
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text("—").frame(width: 32, alignment: .center)
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(round.players) { player in
                if let totals = netTotals(for: player, filter: filter) {
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
}
