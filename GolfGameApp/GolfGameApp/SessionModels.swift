import Foundation
import Combine

enum TeamSide: String, Codable {
    case teamA
    case teamB
}

enum StrokePlayFormat: String, Codable {
    case individual      // Individual leaderboard only
    case bestBall2v2     // Two teams of 2, best ball competition
    case teamBestBall    // All 4 players as one team vs par
}

struct BestBallPairing: Identifiable, Codable, Hashable {
    var id: String
    var teamName: String
    var playerIDs: [String]
    
    init(id: String = UUID().uuidString, teamName: String, playerIDs: [String]) {
        self.id = id
        self.teamName = teamName
        self.playerIDs = playerIDs
    }
}

enum GameScope: String, Codable {
    case round
    case event
}

enum GameType: String, CaseIterable, Codable, Identifiable, Hashable {
    case sixPointScotch
    case nassau
    case stableford
    case skins
    case strokePlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sixPointScotch: return "Six Point Scotch"
        case .nassau: return "Nassau"
        case .stableford: return "Stableford"
        case .skins: return "Skins"
        case .strokePlay: return "Stroke Play"
        }
    }

    var scope: GameScope {
        switch self {
        case .stableford: return .event
        case .sixPointScotch, .nassau, .skins, .strokePlay: return .round
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

struct Buddy: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var handicapIndex: Double
    var lastConfirmedAt: Date = Date()

    var needsHIConfirmation: Bool {
        Date().timeIntervalSince(lastConfirmedAt) > 30 * 24 * 3600  // 30 days
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, handicapIndex, lastConfirmedAt
    }

    init(id: UUID = UUID(), name: String, handicapIndex: Double, lastConfirmedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.handicapIndex = handicapIndex
        self.lastConfirmedAt = lastConfirmedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        handicapIndex = try c.decode(Double.self, forKey: .handicapIndex)
        lastConfirmedAt = try c.decodeIfPresent(Date.self, forKey: .lastConfirmedAt) ?? Date(timeIntervalSinceNow: -31 * 24 * 3600)
    }
}

@MainActor
final class BuddyStore: ObservableObject {
    @Published var buddies: [Buddy] = []
    private static let key = "golf_buddies"

    init() {
        load()
        if buddies.isEmpty { seedDefaults() }
    }

    private func seedDefaults() {
        let defaults: [(String, Double)] = [
            ("DB", 10.0), ("JW", 9.5), ("BC", 14.2), ("JP", 11.1)
        ]
        for (name, hi) in defaults {
            buddies.append(Buddy(name: name, handicapIndex: hi))
        }
        save()
    }

    func add(name: String, handicapIndex: Double) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard !buddies.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return }
        let clampedHI = min(max(handicapIndex, 0), 54)
        buddies.append(Buddy(name: name, handicapIndex: clampedHI))
        save()
    }

    func update(_ buddy: Buddy) {
        if let idx = buddies.firstIndex(where: { $0.id == buddy.id }) {
            buddies[idx] = buddy
            save()
        }
    }

    func confirmHI(id: UUID) {
        if let idx = buddies.firstIndex(where: { $0.id == id }) {
            buddies[idx].lastConfirmedAt = Date()
            save()
        }
    }

    func updateHI(id: UUID, to newHI: Double) {
        if let idx = buddies.firstIndex(where: { $0.id == id }) {
            buddies[idx].handicapIndex = newHI
            buddies[idx].lastConfirmedAt = Date()
            save()
        }
    }

    func remove(at offsets: IndexSet) {
        for i in offsets.sorted().reversed() {
            buddies.remove(at: i)
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(buddies) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([Buddy].self, from: data) else { return }
        buddies = decoded
    }
}

struct CourseHoleStub: Identifiable, Codable, Hashable {
    var id: Int { number }
    var number: Int
    var par: Int
    var strokeIndex: Int
    var yardage: Int

    init(number: Int, par: Int, strokeIndex: Int, yardage: Int = 0) {
        self.number = number
        self.par = par
        self.strokeIndex = strokeIndex
        self.yardage = yardage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        par = try c.decode(Int.self, forKey: .par)
        strokeIndex = try c.decode(Int.self, forKey: .strokeIndex)
        yardage = try c.decodeIfPresent(Int.self, forKey: .yardage) ?? 0
    }
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

struct SavedCourse: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var teeColor: String
    var slope: Int?
    var courseRating: Double?
    var holes: [CourseHoleStub]
    var savedAt: Date = Date()
}

@MainActor
final class CourseStore: ObservableObject {
    @Published var courses: [SavedCourse] = []
    private static let key = "golf_courses"

    init() { load() }

    func save(_ course: SavedCourse) {
        if let idx = courses.firstIndex(where: { $0.name.lowercased() == course.name.lowercased() && $0.teeColor == course.teeColor }) {
            courses[idx] = course
        } else {
            courses.insert(course, at: 0)
        }
        persist()
    }

    func remove(at offsets: IndexSet) {
        for i in offsets.sorted().reversed() {
            courses.remove(at: i)
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(courses) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([SavedCourse].self, from: data) else { return }
        courses = decoded
    }
}

struct RoundSetupSession: Codable, Hashable {
    var event: EventDraft
    var courseName: String
    var teeBoxName: String
    var slope: Int?
    var courseRating: Double?
    var players: [PlayerSnapshot]
    var holes: [CourseHoleStub]
    var pairings: [TeamPairing]

    init(
        event: EventDraft,
        courseName: String,
        teeBoxName: String,
        slope: Int? = nil,
        courseRating: Double? = nil,
        players: [PlayerSnapshot],
        holes: [CourseHoleStub],
        pairings: [TeamPairing]
    ) {
        self.event = event
        self.courseName = courseName
        self.teeBoxName = teeBoxName
        self.slope = slope
        self.courseRating = courseRating
        self.players = players
        self.holes = holes
        self.pairings = pairings
    }

    private enum CodingKeys: String, CodingKey {
        case event, courseName, teeBoxName, slope, courseRating, players, holes, pairings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(EventDraft.self, forKey: .event)
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName) ?? DemoCourseFactory.name
        teeBoxName = try container.decodeIfPresent(String.self, forKey: .teeBoxName) ?? "White"
        slope = try container.decodeIfPresent(Int.self, forKey: .slope)
        courseRating = try container.decodeIfPresent(Double.self, forKey: .courseRating)
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

struct EventGroup: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var playerIDs: [String]
}

struct StablefordHoleResult: Codable, Hashable, Identifiable {
    var id: String { "\(playerID)-\(holeNumber)" }
    var playerID: String
    var holeNumber: Int
    var gross: Int
    var net: Int
    var points: Int
    var strokes: Int
}

struct EventSession: Codable {
    var id: UUID
    var name: String
    var date: Date
    var courseName: String
    var holes: [CourseHoleStub]
    var players: [PlayerSnapshot]
    var groups: [EventGroup]
    var holeResultsByPlayer: [String: [StablefordHoleResult]]
    var currentHoleByGroup: [String: Int]
    var updatedAt: Date
    var isQuickGame: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, date, courseName, holes, players, groups
        case holeResultsByPlayer, currentHoleByGroup, updatedAt, isQuickGame
    }

    init(id: UUID, name: String, date: Date, courseName: String,
         holes: [CourseHoleStub], players: [PlayerSnapshot], groups: [EventGroup],
         holeResultsByPlayer: [String: [StablefordHoleResult]],
         currentHoleByGroup: [String: Int], updatedAt: Date, isQuickGame: Bool = false) {
        self.id = id; self.name = name; self.date = date; self.courseName = courseName
        self.holes = holes; self.players = players; self.groups = groups
        self.holeResultsByPlayer = holeResultsByPlayer
        self.currentHoleByGroup = currentHoleByGroup; self.updatedAt = updatedAt
        self.isQuickGame = isQuickGame
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        date = try c.decode(Date.self, forKey: .date)
        courseName = try c.decode(String.self, forKey: .courseName)
        holes = try c.decode([CourseHoleStub].self, forKey: .holes)
        players = try c.decode([PlayerSnapshot].self, forKey: .players)
        groups = try c.decode([EventGroup].self, forKey: .groups)
        holeResultsByPlayer = try c.decode([String: [StablefordHoleResult]].self, forKey: .holeResultsByPlayer)
        currentHoleByGroup = try c.decode([String: Int].self, forKey: .currentHoleByGroup)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        isQuickGame = try c.decodeIfPresent(Bool.self, forKey: .isQuickGame) ?? false
    }
}

struct RoundSession: Codable {
    var id: UUID
    var setup: RoundSetupSession
    var teeTossFirst: TeamSide?
    var isRoundEnded: Bool
    var currentHole: Int
    var isCurrentHoleScored: Bool
    var scoredHoleInputs: [SixPointScotchHoleInput]
    var holeResults: [HoleResult]
    var strokesByPlayerByHole: [HoleStrokeAllocation]
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case setup
        case teeTossFirst
        case isRoundEnded
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
        teeTossFirst: TeamSide?,
        isRoundEnded: Bool,
        currentHole: Int,
        isCurrentHoleScored: Bool,
        scoredHoleInputs: [SixPointScotchHoleInput],
        holeResults: [HoleResult],
        strokesByPlayerByHole: [HoleStrokeAllocation],
        updatedAt: Date
    ) {
        self.id = id
        self.setup = setup
        self.teeTossFirst = teeTossFirst
        self.isRoundEnded = isRoundEnded
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
        teeTossFirst = try container.decodeIfPresent(TeamSide.self, forKey: .teeTossFirst)
        isRoundEnded = try container.decodeIfPresent(Bool.self, forKey: .isRoundEnded) ?? false
        currentHole = try container.decode(Int.self, forKey: .currentHole)
        isCurrentHoleScored = try container.decode(Bool.self, forKey: .isCurrentHoleScored)
        scoredHoleInputs = try container.decode([SixPointScotchHoleInput].self, forKey: .scoredHoleInputs)
        holeResults = try container.decodeIfPresent([HoleResult].self, forKey: .holeResults) ?? []
        strokesByPlayerByHole = try container.decodeIfPresent([HoleStrokeAllocation].self, forKey: .strokesByPlayerByHole) ?? []
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Nassau Session Models

struct NassauHoleResult: Codable, Hashable {
    var holeNumber: Int
    var grossByPlayerID: [String: Int]
    var netByPlayerID: [String: Int]
    var holeWinner: TeamSide?
}

struct NassauSession: Codable {
    var id: UUID
    var format: NassauFormat
    var players: [PlayerSnapshot]       // 2 for singles, 4 for fourball
    var pairings: [TeamPairing]         // empty for singles; 2 TeamPairing for fourball
    var courseName: String
    var teeBoxName: String
    var holes: [CourseHoleStub]
    var pressConfig: NassauPressConfig
    var currentHole: Int
    var isComplete: Bool
    var holeInputs: [NassauHoleInput]   // Replayed on app restore to rebuild engine
    var holeResults: [NassauHoleResult]
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, format, players, pairings, courseName, teeBoxName
        case holes, pressConfig, currentHole, isComplete
        case holeInputs, holeResults, updatedAt
    }

    init(
        id: UUID, format: NassauFormat, players: [PlayerSnapshot], pairings: [TeamPairing],
        courseName: String, teeBoxName: String, holes: [CourseHoleStub],
        pressConfig: NassauPressConfig, currentHole: Int = 1, isComplete: Bool = false,
        holeInputs: [NassauHoleInput] = [], holeResults: [NassauHoleResult] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id; self.format = format; self.players = players; self.pairings = pairings
        self.courseName = courseName; self.teeBoxName = teeBoxName; self.holes = holes
        self.pressConfig = pressConfig; self.currentHole = currentHole; self.isComplete = isComplete
        self.holeInputs = holeInputs; self.holeResults = holeResults; self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        format = try c.decode(NassauFormat.self, forKey: .format)
        players = try c.decode([PlayerSnapshot].self, forKey: .players)
        pairings = try c.decodeIfPresent([TeamPairing].self, forKey: .pairings) ?? []
        courseName = try c.decode(String.self, forKey: .courseName)
        teeBoxName = try c.decodeIfPresent(String.self, forKey: .teeBoxName) ?? "White"
        holes = try c.decode([CourseHoleStub].self, forKey: .holes)
        pressConfig = try c.decode(NassauPressConfig.self, forKey: .pressConfig)
        currentHole = try c.decodeIfPresent(Int.self, forKey: .currentHole) ?? 1
        isComplete = try c.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
        holeInputs = try c.decodeIfPresent([NassauHoleInput].self, forKey: .holeInputs) ?? []
        holeResults = try c.decodeIfPresent([NassauHoleResult].self, forKey: .holeResults) ?? []
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

private struct AppSessionSnapshot: Codable {
    var gameSelections: [GameType: Bool]
    var activeRoundSession: RoundSession?
    var activeEventSession: EventSession?
    var activeNassauSession: NassauSession?
    var activeSaturdayRound: SaturdayRound?
    var completedRounds: [SaturdayRound]

    private enum CodingKeys: String, CodingKey {
        case gameSelections
        case activeRoundSession
        case activeEventSession
        case activeNassauSession
        case activeSaturdayRound
        case completedRounds
    }

    init(
        gameSelections: [GameType: Bool],
        activeRoundSession: RoundSession?,
        activeEventSession: EventSession?,
        activeNassauSession: NassauSession?,
        activeSaturdayRound: SaturdayRound?,
        completedRounds: [SaturdayRound]
    ) {
        self.gameSelections = gameSelections
        self.activeRoundSession = activeRoundSession
        self.activeEventSession = activeEventSession
        self.activeNassauSession = activeNassauSession
        self.activeSaturdayRound = activeSaturdayRound
        self.completedRounds = completedRounds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameSelections = try container.decode([GameType: Bool].self, forKey: .gameSelections)
        activeRoundSession = try container.decodeIfPresent(RoundSession.self, forKey: .activeRoundSession)
        activeEventSession = try container.decodeIfPresent(EventSession.self, forKey: .activeEventSession)
        activeNassauSession = try container.decodeIfPresent(NassauSession.self, forKey: .activeNassauSession)
        activeSaturdayRound = try container.decodeIfPresent(SaturdayRound.self, forKey: .activeSaturdayRound)
        completedRounds = try container.decodeIfPresent([SaturdayRound].self, forKey: .completedRounds) ?? []
    }
}

@MainActor
final class AppSessionStore: ObservableObject {
    @Published var gameSelections: [GameType: Bool] = Dictionary(
        uniqueKeysWithValues: GameType.allCases.map { ($0, $0 == .sixPointScotch) }
    )
    @Published var activeRoundSession: RoundSession?
    @Published var activeEventSession: EventSession?
    @Published var activeNassauSession: NassauSession?
    @Published var activeSaturdayRound: SaturdayRound?
    @Published var completedRounds: [SaturdayRound] = []

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
            teeTossFirst: nil,
            isRoundEnded: false,
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
        isRoundEnded: Bool,
        currentHole: Int,
        isCurrentHoleScored: Bool,
        scoredHoleInputs: [SixPointScotchHoleInput],
        holeResults: [HoleResult],
        strokesByPlayerByHole: [HoleStrokeAllocation]
    ) {
        guard var active = activeRoundSession else { return }
        active.isRoundEnded = isRoundEnded
        active.currentHole = currentHole
        active.isCurrentHoleScored = isCurrentHoleScored
        active.scoredHoleInputs = scoredHoleInputs
        active.holeResults = holeResults
        active.strokesByPlayerByHole = strokesByPlayerByHole
        active.updatedAt = Date()
        activeRoundSession = active
        persist()
    }

    func startEventSession(
        name: String,
        date: Date,
        courseName: String,
        holes: [CourseHoleStub],
        players: [PlayerSnapshot],
        groups: [EventGroup]
    ) {
        let currentHoleByGroup = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, 1) })
        activeEventSession = EventSession(
            id: UUID(),
            name: name,
            date: date,
            courseName: courseName,
            holes: holes,
            players: players,
            groups: groups,
            holeResultsByPlayer: [:],
            currentHoleByGroup: currentHoleByGroup,
            updatedAt: Date()
        )
        persist()
    }

    @discardableResult
    func startQuickGame(players: [PlayerSnapshot], holes: [CourseHoleStub], courseName: String) -> String {
        let groupID = "group-quick"
        let group = EventGroup(id: groupID, name: "Group 1", playerIDs: players.map(\.id))
        activeEventSession = EventSession(
            id: UUID(),
            name: "Quick Game",
            date: Date(),
            courseName: courseName.isEmpty ? DemoCourseFactory.name : courseName,
            holes: holes,
            players: players,
            groups: [group],
            holeResultsByPlayer: [:],
            currentHoleByGroup: [groupID: 1],
            updatedAt: Date(),
            isQuickGame: true
        )
        persist()
        return groupID
    }

    func updateActiveEventSession(_ session: EventSession) {
        activeEventSession = session
        persist()
    }

    func clearActiveRoundSession() {
        activeRoundSession = nil
        persist()
    }

    func clearActiveEventSession() {
        activeEventSession = nil
        persist()
    }

    func startNassauSession(
        format: NassauFormat,
        players: [PlayerSnapshot],
        pairings: [TeamPairing],
        courseName: String,
        teeBoxName: String,
        holes: [CourseHoleStub],
        pressConfig: NassauPressConfig
    ) {
        activeNassauSession = NassauSession(
            id: UUID(),
            format: format,
            players: players,
            pairings: pairings,
            courseName: courseName.isEmpty ? DemoCourseFactory.name : courseName,
            teeBoxName: teeBoxName,
            holes: holes,
            pressConfig: pressConfig
        )
        persist()
    }

    func updateActiveNassauState(
        currentHole: Int,
        isComplete: Bool,
        holeInputs: [NassauHoleInput],
        holeResults: [NassauHoleResult]
    ) {
        guard var active = activeNassauSession else { return }
        active.currentHole = currentHole
        active.isComplete = isComplete
        active.holeInputs = holeInputs
        active.holeResults = holeResults
        active.updatedAt = Date()
        activeNassauSession = active
        persist()
    }

    func clearActiveNassauSession() {
        activeNassauSession = nil
        persist()
    }

    func persistSelections() {
        persist()
    }

    func startSaturdayRound(
        players: [PlayerSnapshot],
        teams: [TeamPairing],
        courseName: String,
        holes: [CourseHoleStub],
        activeGames: [SaturdayGameConfig]
    ) {
        activeSaturdayRound = SaturdayRound(
            players: players,
            teams: teams,
            courseName: courseName,
            holes: holes,
            activeGames: activeGames
        )
        persist()
    }

    func updateSaturdayRound(_ round: SaturdayRound) {
        var updated = round
        updated.updatedAt = Date()
        activeSaturdayRound = updated
        persist()
    }

    func clearSaturdayRound() {
        if let round = activeSaturdayRound, !round.holeEntries.isEmpty {
            completedRounds.insert(round, at: 0)
        }
        activeSaturdayRound = nil
        persist()
    }

    func persistCompletedRounds() {
        persist()
    }

    private func persist() {
        let snapshot = AppSessionSnapshot(
            gameSelections: gameSelections,
            activeRoundSession: activeRoundSession,
            activeEventSession: activeEventSession,
            activeNassauSession: activeNassauSession,
            activeSaturdayRound: activeSaturdayRound,
            completedRounds: completedRounds
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
            activeEventSession = snapshot.activeEventSession
            activeNassauSession = snapshot.activeNassauSession
            activeSaturdayRound = snapshot.activeSaturdayRound
            completedRounds = snapshot.completedRounds
        } catch {
            #if DEBUG
            print("AppSessionStore load failed: \(error)")
            #endif
        }
    }

    private static func persistenceURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("GolfGameApp", isDirectory: true)
            .appendingPathComponent("round_session.json", isDirectory: false)
    }
}

typealias SessionModel = AppSessionStore

func strokeCountForHandicapIndex(_ handicapIndex: Double, onHoleStrokeIndex si: Int) -> Int {
    let courseHandicap = max(0, Int(handicapIndex.rounded(.down)))
    let base = courseHandicap / 18
    let remainder = courseHandicap % 18
    return base + (si <= remainder ? 1 : 0)
}

// MARK: - Saturday Round (Unified Multi-Game Session)

struct NassauGameConfig: Codable, Equatable {
    var frontStake: Double
    var backStake: Double
    var overallStake: Double
    var format: NassauFormat
    var pressConfig: NassauPressConfig

    static let `default` = NassauGameConfig(
        frontStake: 5,
        backStake: 5,
        overallStake: 5,
        format: .fourball,
        pressConfig: .default
    )
}

struct ScotchGameConfig: Codable, Equatable {
    var pointValue: Double  // $ per point

    static let `default` = ScotchGameConfig(pointValue: 1)
}

struct StablefordGameConfig: Codable, Equatable {
    enum ScoringType: String, Codable {
        case standard
        case modified
    }
    var scoringType: ScoringType

    static let `default` = StablefordGameConfig(scoringType: .standard)
}

struct SkinsGameConfig: Codable, Equatable {
    var mode: SkinsMode
    var carryoverEnabled: Bool
    /// Dollar value per skin (used in settlement).
    var skinValue: Double
    static let `default` = SkinsGameConfig(mode: .gross, carryoverEnabled: true, skinValue: 5)
}

struct StrokePlayGameConfig: Codable, Equatable {
    var format: StrokePlayFormat
    var bestBallPairings: [BestBallPairing]
    
    init(format: StrokePlayFormat = .individual, bestBallPairings: [BestBallPairing] = []) {
        self.format = format
        self.bestBallPairings = bestBallPairings
    }
    
    static let `default` = StrokePlayGameConfig()
}

struct SaturdayGameConfig: Codable, Identifiable, Equatable {
    var type: GameType
    var nassauConfig: NassauGameConfig?
    var scotchConfig: ScotchGameConfig?
    var stablefordConfig: StablefordGameConfig?
    var skinsConfig: SkinsGameConfig?
    var strokePlayConfig: StrokePlayGameConfig?

    var id: String { type.rawValue }

    static func nassau(_ config: NassauGameConfig = .default) -> SaturdayGameConfig {
        SaturdayGameConfig(type: .nassau, nassauConfig: config)
    }

    static func scotch(_ config: ScotchGameConfig = .default) -> SaturdayGameConfig {
        SaturdayGameConfig(type: .sixPointScotch, scotchConfig: config)
    }

    static func stableford(_ config: StablefordGameConfig = .default) -> SaturdayGameConfig {
        SaturdayGameConfig(type: .stableford, stablefordConfig: config)
    }

    static func skins(_ config: SkinsGameConfig = .default) -> SaturdayGameConfig {
        SaturdayGameConfig(type: .skins, skinsConfig: config)
    }

    static func strokePlay(_ config: StrokePlayGameConfig = .default) -> SaturdayGameConfig {
        SaturdayGameConfig(type: .strokePlay, strokePlayConfig: config)
    }
}

struct ScotchHoleFlags: Codable, Equatable {
    var proxFeetByPlayerID: [String: Double]
    var requestPressBy: TeamSide?
    var requestRollBy: TeamSide?
    var requestRerollBy: TeamSide?

    init(
        proxFeetByPlayerID: [String: Double] = [:],
        requestPressBy: TeamSide? = nil,
        requestRollBy: TeamSide? = nil,
        requestRerollBy: TeamSide? = nil
    ) {
        self.proxFeetByPlayerID = proxFeetByPlayerID
        self.requestPressBy = requestPressBy
        self.requestRollBy = requestRollBy
        self.requestRerollBy = requestRerollBy
    }
}

struct SaturdayHoleEntry: Codable, Identifiable, Equatable {
    var holeNumber: Int
    var grossByPlayerID: [String: Int]
    var scotchFlags: ScotchHoleFlags
    var nassauManualPressBy: TeamSide?

    var id: Int { holeNumber }

    init(
        holeNumber: Int,
        grossByPlayerID: [String: Int],
        scotchFlags: ScotchHoleFlags = ScotchHoleFlags(),
        nassauManualPressBy: TeamSide? = nil
    ) {
        self.holeNumber = holeNumber
        self.grossByPlayerID = grossByPlayerID
        self.scotchFlags = scotchFlags
        self.nassauManualPressBy = nassauManualPressBy
    }
}

struct SaturdayRound: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var players: [PlayerSnapshot]
    var teams: [TeamPairing]
    var courseName: String
    var holes: [CourseHoleStub]
    var activeGames: [SaturdayGameConfig]
    var holeEntries: [SaturdayHoleEntry]
    var currentHole: Int
    var isComplete: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        players: [PlayerSnapshot],
        teams: [TeamPairing],
        courseName: String,
        holes: [CourseHoleStub],
        activeGames: [SaturdayGameConfig],
        holeEntries: [SaturdayHoleEntry] = [],
        currentHole: Int = 1,
        isComplete: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.players = players
        self.teams = teams
        self.courseName = courseName
        self.holes = holes
        self.activeGames = activeGames
        self.holeEntries = holeEntries
        self.currentHole = currentHole
        self.isComplete = isComplete
        self.updatedAt = updatedAt
    }

    /// True if any selected game requires teams (Scotch or Nassau fourball)
    var requiresTeams: Bool {
        activeGames.contains { game in
            switch game.type {
            case .sixPointScotch: return true
            case .nassau: return game.nassauConfig?.format == .fourball
            case .stableford, .skins, .strokePlay: return false
            }
        }
    }

    var teamAPlayers: [PlayerSnapshot] {
        let ids = teams.first(where: { $0.team == .teamA })?.players.map(\.id) ?? []
        return players.filter { ids.contains($0.id) }
    }

    var teamBPlayers: [PlayerSnapshot] {
        let ids = teams.first(where: { $0.team == .teamB })?.players.map(\.id) ?? []
        return players.filter { ids.contains($0.id) }
    }
}

enum DemoCourseFactory {
    static let name = "Demo Course"

    static func holes18() -> [CourseHoleStub] {
        let pars =      [4,   4,   3,   5,   4,   4,   3,   5,   4,   4,   3,   5,   4,   4,   3,   5,   4,   4]
        let yardages =  [385, 420, 155, 535, 395, 370, 165, 520, 410, 400, 145, 545, 375, 430, 170, 510, 385, 450]
        return (1...18).map {
            CourseHoleStub(number: $0, par: pars[$0 - 1], strokeIndex: $0, yardage: yardages[$0 - 1])
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
    }
}
