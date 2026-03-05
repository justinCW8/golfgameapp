import Testing
import Foundation
@testable import GolfGameApp

// MARK: - ScotchHoleFlags

struct ScotchHoleFlagsTests {

    @Test func defaultInitHasEmptyProxAndNilFlags() {
        let flags = ScotchHoleFlags()
        #expect(flags.proxFeetByPlayerID.isEmpty)
        #expect(flags.requestPressBy == nil)
        #expect(flags.requestRollBy == nil)
        #expect(flags.requestRerollBy == nil)
    }

    @Test func codableRoundtripPreservesAllFields() throws {
        let flags = ScotchHoleFlags(
            proxFeetByPlayerID: ["player-1": 12.5, "player-2": 30.0],
            requestPressBy: .teamA,
            requestRollBy: nil,
            requestRerollBy: nil
        )
        let data = try JSONEncoder().encode(flags)
        let decoded = try JSONDecoder().decode(ScotchHoleFlags.self, from: data)
        #expect(decoded == flags)
    }

    @Test func codableRoundtripWithAllFlags() throws {
        let flags = ScotchHoleFlags(
            proxFeetByPlayerID: [:],
            requestPressBy: .teamB,
            requestRollBy: .teamB,
            requestRerollBy: .teamA
        )
        let data = try JSONEncoder().encode(flags)
        let decoded = try JSONDecoder().decode(ScotchHoleFlags.self, from: data)
        #expect(decoded == flags)
    }

    @Test func equalityWhenSame() {
        let a = ScotchHoleFlags(proxFeetByPlayerID: ["p1": 5.0], requestPressBy: .teamA)
        let b = ScotchHoleFlags(proxFeetByPlayerID: ["p1": 5.0], requestPressBy: .teamA)
        #expect(a == b)
    }

    @Test func inequalityWhenDifferent() {
        let a = ScotchHoleFlags(requestPressBy: .teamA)
        let b = ScotchHoleFlags(requestPressBy: .teamB)
        #expect(a != b)
    }
}

// MARK: - SaturdayHoleEntry

struct SaturdayHoleEntryTests {

    @Test func defaultFlagsOnMinimalInit() {
        let entry = SaturdayHoleEntry(holeNumber: 5, grossByPlayerID: ["p1": 4, "p2": 5])
        #expect(entry.holeNumber == 5)
        #expect(entry.grossByPlayerID == ["p1": 4, "p2": 5])
        #expect(entry.scotchFlags == ScotchHoleFlags())
        #expect(entry.nassauManualPressBy == nil)
    }

    @Test func idEqualsHoleNumber() {
        let entry = SaturdayHoleEntry(holeNumber: 7, grossByPlayerID: [:])
        #expect(entry.id == 7)
    }

    @Test func codableRoundtripPreservesAllFields() throws {
        let entry = SaturdayHoleEntry(
            holeNumber: 3,
            grossByPlayerID: ["abc-123": 5, "def-456": 4],
            scotchFlags: ScotchHoleFlags(
                proxFeetByPlayerID: ["abc-123": 8.0],
                requestPressBy: .teamA
            ),
            nassauManualPressBy: .teamB
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(SaturdayHoleEntry.self, from: data)
        #expect(decoded == entry)
    }

    @Test func equalityCheck() {
        let a = SaturdayHoleEntry(holeNumber: 1, grossByPlayerID: ["p": 4])
        let b = SaturdayHoleEntry(holeNumber: 1, grossByPlayerID: ["p": 4])
        #expect(a == b)
    }
}

// MARK: - SaturdayGameConfig

struct SaturdayGameConfigTests {

    @Test func nassauFactoryCreatesCorrectType() {
        let config = SaturdayGameConfig.nassau()
        #expect(config.type == .nassau)
        #expect(config.nassauConfig != nil)
        #expect(config.scotchConfig == nil)
        #expect(config.stablefordConfig == nil)
    }

    @Test func scotchFactoryCreatesCorrectType() {
        let config = SaturdayGameConfig.scotch()
        #expect(config.type == .sixPointScotch)
        #expect(config.scotchConfig != nil)
        #expect(config.nassauConfig == nil)
        #expect(config.stablefordConfig == nil)
    }

    @Test func stablefordFactoryCreatesCorrectType() {
        let config = SaturdayGameConfig.stableford()
        #expect(config.type == .stableford)
        #expect(config.stablefordConfig != nil)
        #expect(config.nassauConfig == nil)
        #expect(config.scotchConfig == nil)
    }

    @Test func idEqualsTypeRawValue() {
        #expect(SaturdayGameConfig.nassau().id == GameType.nassau.rawValue)
        #expect(SaturdayGameConfig.scotch().id == GameType.sixPointScotch.rawValue)
        #expect(SaturdayGameConfig.stableford().id == GameType.stableford.rawValue)
    }

    @Test func scotchCodeableRoundtripPreservesPointValue() throws {
        let config = SaturdayGameConfig.scotch(.init(pointValue: 2.5))
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SaturdayGameConfig.self, from: data)
        #expect(decoded == config)
        #expect(decoded.scotchConfig?.pointValue == 2.5)
    }

    @Test func nassauCodableRoundtripPreservesStake() throws {
        let nassauConfig = NassauGameConfig(
            frontStake: 10,
            backStake: 10,
            overallStake: 10,
            format: .fourball,
            pressConfig: .default
        )
        let config = SaturdayGameConfig.nassau(nassauConfig)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SaturdayGameConfig.self, from: data)
        #expect(decoded.nassauConfig?.frontStake == 10)
        #expect(decoded.nassauConfig?.backStake == 10)
    }
}

// MARK: - SaturdayRound

struct SaturdayRoundTests {

    private func makeRound(
        games: [SaturdayGameConfig] = [.scotch()],
        holeEntries: [SaturdayHoleEntry] = [],
        currentHole: Int = 1,
        isComplete: Bool = false
    ) -> SaturdayRound {
        let players: [PlayerSnapshot] = [
            PlayerSnapshot(id: "p1", name: "Alice", handicapIndex: 10),
            PlayerSnapshot(id: "p2", name: "Bob", handicapIndex: 15),
            PlayerSnapshot(id: "p3", name: "Carol", handicapIndex: 8),
            PlayerSnapshot(id: "p4", name: "Dave", handicapIndex: 12)
        ]
        let teams: [TeamPairing] = [
            TeamPairing(team: .teamA, players: [players[0], players[1]]),
            TeamPairing(team: .teamB, players: [players[2], players[3]])
        ]
        let holes: [CourseHoleStub] = (1...18).map {
            CourseHoleStub(number: $0, par: 4, strokeIndex: $0)
        }
        return SaturdayRound(
            players: players,
            teams: teams,
            courseName: "Test Course",
            holes: holes,
            activeGames: games,
            holeEntries: holeEntries,
            currentHole: currentHole,
            isComplete: isComplete
        )
    }

    @Test func defaultCurrentHoleIsOne() {
        let round = makeRound()
        #expect(round.currentHole == 1)
    }

    @Test func defaultIsNotComplete() {
        let round = makeRound()
        #expect(round.isComplete == false)
    }

    @Test func codableRoundtripPreservesAllFields() throws {
        let entry = SaturdayHoleEntry(
            holeNumber: 1,
            grossByPlayerID: ["p1": 4, "p2": 5, "p3": 3, "p4": 4],
            scotchFlags: ScotchHoleFlags(requestPressBy: .teamA)
        )
        let round = makeRound(
            games: [.scotch(), .nassau()],
            holeEntries: [entry],
            currentHole: 2,
            isComplete: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(round)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SaturdayRound.self, from: data)

        #expect(decoded.courseName == round.courseName)
        #expect(decoded.currentHole == 2)
        #expect(decoded.isComplete == false)
        #expect(decoded.players.count == round.players.count)
        #expect(decoded.teams.count == round.teams.count)
        #expect(decoded.activeGames.count == 2)
        #expect(decoded.holeEntries.count == 1)
        #expect(decoded.holeEntries[0].scotchFlags.requestPressBy == .teamA)
    }

    @Test func roundWithAllThreeGames() throws {
        let round = makeRound(games: [.scotch(), .nassau(), .stableford()])
        #expect(round.activeGames.count == 3)
        #expect(round.activeGames.map(\.type).contains(.sixPointScotch))
        #expect(round.activeGames.map(\.type).contains(.nassau))
        #expect(round.activeGames.map(\.type).contains(.stableford))
    }

    @Test func roundPreservesPlayersAndTeams() {
        let round = makeRound()
        #expect(round.players.count == 4)
        #expect(round.teams.count == 2)
        #expect(round.teams.first(where: { $0.team == .teamA })?.players.count == 2)
        #expect(round.teams.first(where: { $0.team == .teamB })?.players.count == 2)
    }
}

// MARK: - Game Config Defaults

struct GameConfigDefaultTests {

    @Test func nassauDefaultHasFivePerSegmentStakes() {
        let config = NassauGameConfig.default
        #expect(config.frontStake == 5)
        #expect(config.backStake == 5)
        #expect(config.overallStake == 5)
    }

    @Test func scotchDefaultHasOnePointValue() {
        let config = ScotchGameConfig.default
        #expect(config.pointValue == 1)
    }

    @Test func stablefordDefaultIsStandardScoring() {
        let config = StablefordGameConfig.default
        #expect(config.scoringType == .standard)
    }
}
