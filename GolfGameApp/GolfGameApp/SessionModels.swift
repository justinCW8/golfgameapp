import Foundation
import Combine

enum TeamSide: String, Codable {
    case teamA
    case teamB
}

enum GameScope: String, Codable {
    case round
    case event
}

enum GameType: String, CaseIterable, Codable, Identifiable, Hashable {
    case sixPointScotch
    case nassau
    case stableford

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sixPointScotch: return "Six Point Scotch"
        case .nassau: return "Nassau"
        case .stableford: return "Stableford"
        }
    }

    var scope: GameScope {
        switch self {
        case .stableford: return .event
        case .sixPointScotch, .nassau: return .round
        }
    }
}

struct EventDraft: Codable, Hashable {
    var name: String
    var date: Date
}

struct PlayerDraft: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var handicapIndex: Double

    init(id: UUID = UUID(), name: String = "", handicapIndex: Double = 0) {
        self.id = id
        self.name = name
        self.handicapIndex = handicapIndex
    }
}

struct CourseHoleStub: Identifiable, Codable, Hashable {
    var id: Int { number }
    var number: Int
    var par: Int
    var strokeIndex: Int
}

struct TeamPairing: Identifiable, Codable, Hashable {
    var id: String { "\(team.rawValue)-\(players.map(\.id).joined(separator: "-"))" }
    var team: TeamSide
    var players: [PlayerSnapshot]
}

struct PlayerSnapshot: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var handicapIndex: Double
}

struct RoundSetupSession: Codable, Hashable {
    var event: EventDraft
    var courseName: String
    var players: [PlayerSnapshot]
    var holes: [CourseHoleStub]
    var pairings: [TeamPairing]

    init(
        event: EventDraft,
        courseName: String,
        players: [PlayerSnapshot],
        holes: [CourseHoleStub],
        pairings: [TeamPairing]
    ) {
        self.event = event
        self.courseName = courseName
        self.players = players
        self.holes = holes
        self.pairings = pairings
    }

    private enum CodingKeys: String, CodingKey {
        case event
        case courseName
        case players
        case holes
        case pairings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(EventDraft.self, forKey: .event)
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName) ?? DemoCourseFactory.name
        players = try container.decode([PlayerSnapshot].self, forKey: .players)
        holes = try container.decode([CourseHoleStub].self, forKey: .holes)
        pairings = try container.decode([TeamPairing].self, forKey: .pairings)
    }
}

struct HoleResult: Codable, Hashable, Identifiable {
    var id: Int { holeNumber }
    var holeNumber: Int
    var grossByPlayerID: [String: Int]
    var netByPlayerID: [String: Int]
}

struct HoleStrokeAllocation: Codable, Hashable, Identifiable {
    var id: Int { holeNumber }
    var holeNumber: Int
    var strokesByPlayerID: [String: Int]
}

struct RoundSession: Codable {
    var id: UUID
    var setup: RoundSetupSession
    var currentHole: Int
    var isCurrentHoleScored: Bool
    var scoredHoleInputs: [SixPointScotchHoleInput]
    var holeResults: [HoleResult]
    var strokesByPlayerByHole: [HoleStrokeAllocation]
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case setup
        case currentHole
        case isCurrentHoleScored
        case scoredHoleInputs
        case holeResults
        case strokesByPlayerByHole
        case updatedAt
    }

    init(
        id: UUID,
        setup: RoundSetupSession,
        currentHole: Int,
        isCurrentHoleScored: Bool,
        scoredHoleInputs: [SixPointScotchHoleInput],
        holeResults: [HoleResult],
        strokesByPlayerByHole: [HoleStrokeAllocation],
        updatedAt: Date
    ) {
        self.id = id
        self.setup = setup
        self.currentHole = currentHole
        self.isCurrentHoleScored = isCurrentHoleScored
        self.scoredHoleInputs = scoredHoleInputs
        self.holeResults = holeResults
        self.strokesByPlayerByHole = strokesByPlayerByHole
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        setup = try container.decode(RoundSetupSession.self, forKey: .setup)
        currentHole = try container.decode(Int.self, forKey: .currentHole)
        isCurrentHoleScored = try container.decode(Bool.self, forKey: .isCurrentHoleScored)
        scoredHoleInputs = try container.decode([SixPointScotchHoleInput].self, forKey: .scoredHoleInputs)
        holeResults = try container.decodeIfPresent([HoleResult].self, forKey: .holeResults) ?? []
        strokesByPlayerByHole = try container.decodeIfPresent([HoleStrokeAllocation].self, forKey: .strokesByPlayerByHole) ?? []
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

private struct AppSessionSnapshot: Codable {
    var gameSelections: [GameType: Bool]
    var activeRoundSession: RoundSession?
}

@MainActor
final class AppSessionStore: ObservableObject {
    @Published var gameSelections: [GameType: Bool] = Dictionary(
        uniqueKeysWithValues: GameType.allCases.map { ($0, $0 == .sixPointScotch) }
    )
    @Published var activeRoundSession: RoundSession?

    var configuredRound: RoundSetupSession? {
        activeRoundSession?.setup
    }

    private let saveURL: URL

    init() {
        self.saveURL = Self.persistenceURL()
        loadFromDisk()
    }

    func startRoundSession(with setup: RoundSetupSession) {
        activeRoundSession = RoundSession(
            id: UUID(),
            setup: setup,
            currentHole: 1,
            isCurrentHoleScored: false,
            scoredHoleInputs: [],
            holeResults: [],
            strokesByPlayerByHole: [],
            updatedAt: Date()
        )
        persist()
    }

    func updateActiveRoundState(
        currentHole: Int,
        isCurrentHoleScored: Bool,
        scoredHoleInputs: [SixPointScotchHoleInput],
        holeResults: [HoleResult],
        strokesByPlayerByHole: [HoleStrokeAllocation]
    ) {
        guard var active = activeRoundSession else { return }
        active.currentHole = currentHole
        active.isCurrentHoleScored = isCurrentHoleScored
        active.scoredHoleInputs = scoredHoleInputs
        active.holeResults = holeResults
        active.strokesByPlayerByHole = strokesByPlayerByHole
        active.updatedAt = Date()
        activeRoundSession = active
        persist()
    }

    func persistSelections() {
        persist()
    }

    private func persist() {
        let snapshot = AppSessionSnapshot(
            gameSelections: gameSelections,
            activeRoundSession: activeRoundSession
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try FileManager.default.createDirectory(
                at: saveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: saveURL, options: .atomic)
        } catch {
            #if DEBUG
            print("AppSessionStore persist failed: \(error)")
            #endif
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(AppSessionSnapshot.self, from: data)
            gameSelections = snapshot.gameSelections
            activeRoundSession = snapshot.activeRoundSession
        } catch {
            #if DEBUG
            print("AppSessionStore load failed: \(error)")
            #endif
        }
    }

    private static func persistenceURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("GolfGameApp", isDirectory: true)
            .appendingPathComponent("round_session.json", isDirectory: false)
    }
}

typealias SessionModel = AppSessionStore

enum DemoCourseFactory {
    static let name = "Demo Course"

    static func holes18() -> [CourseHoleStub] {
        let pars = [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4]
        return (1...18).map {
            CourseHoleStub(number: $0, par: pars[$0 - 1], strokeIndex: $0)
        }
    }
}

extension SixPointScotchHoleInput: Codable {
    private enum CodingKeys: String, CodingKey {
        case holeNumber
        case par
        case teamANetScores
        case teamBNetScores
        case teamAGrossScores
        case teamBGrossScores
        case teamAProxFeet
        case teamBProxFeet
        case requestPressBy
        case requestRollBy
        case requestRerollBy
        case leaderTeedOff
        case trailerTeedOff
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holeNumber = try container.decode(Int.self, forKey: .holeNumber)
        par = try container.decode(Int.self, forKey: .par)
        teamANetScores = try container.decode([Int].self, forKey: .teamANetScores)
        teamBNetScores = try container.decode([Int].self, forKey: .teamBNetScores)
        teamAGrossScores = try container.decode([Int].self, forKey: .teamAGrossScores)
        teamBGrossScores = try container.decode([Int].self, forKey: .teamBGrossScores)
        teamAProxFeet = try container.decodeIfPresent(Double.self, forKey: .teamAProxFeet)
        teamBProxFeet = try container.decodeIfPresent(Double.self, forKey: .teamBProxFeet)
        requestPressBy = try container.decodeIfPresent(TeamSide.self, forKey: .requestPressBy)
        requestRollBy = try container.decodeIfPresent(TeamSide.self, forKey: .requestRollBy)
        requestRerollBy = try container.decodeIfPresent(TeamSide.self, forKey: .requestRerollBy)
        leaderTeedOff = try container.decode(Bool.self, forKey: .leaderTeedOff)
        trailerTeedOff = try container.decode(Bool.self, forKey: .trailerTeedOff)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(holeNumber, forKey: .holeNumber)
        try container.encode(par, forKey: .par)
        try container.encode(teamANetScores, forKey: .teamANetScores)
        try container.encode(teamBNetScores, forKey: .teamBNetScores)
        try container.encode(teamAGrossScores, forKey: .teamAGrossScores)
        try container.encode(teamBGrossScores, forKey: .teamBGrossScores)
        try container.encodeIfPresent(teamAProxFeet, forKey: .teamAProxFeet)
        try container.encodeIfPresent(teamBProxFeet, forKey: .teamBProxFeet)
        try container.encodeIfPresent(requestPressBy, forKey: .requestPressBy)
        try container.encodeIfPresent(requestRollBy, forKey: .requestRollBy)
        try container.encodeIfPresent(requestRerollBy, forKey: .requestRerollBy)
        try container.encode(leaderTeedOff, forKey: .leaderTeedOff)
        try container.encode(trailerTeedOff, forKey: .trailerTeedOff)
    }
}
