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

    init() { load() }

    func add(name: String, handicapIndex: Double) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard !buddies.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return }
        buddies.append(Buddy(name: name, handicapIndex: handicapIndex))
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

private struct AppSessionSnapshot: Codable {
    var gameSelections: [GameType: Bool]
    var activeRoundSession: RoundSession?
    var activeEventSession: EventSession?

    private enum CodingKeys: String, CodingKey {
        case gameSelections
        case activeRoundSession
        case activeEventSession
    }

    init(
        gameSelections: [GameType: Bool],
        activeRoundSession: RoundSession?,
        activeEventSession: EventSession?
    ) {
        self.gameSelections = gameSelections
        self.activeRoundSession = activeRoundSession
        self.activeEventSession = activeEventSession
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameSelections = try container.decode([GameType: Bool].self, forKey: .gameSelections)
        activeRoundSession = try container.decodeIfPresent(RoundSession.self, forKey: .activeRoundSession)
        activeEventSession = try container.decodeIfPresent(EventSession.self, forKey: .activeEventSession)
    }
}

@MainActor
final class AppSessionStore: ObservableObject {
    @Published var gameSelections: [GameType: Bool] = Dictionary(
        uniqueKeysWithValues: GameType.allCases.map { ($0, $0 == .sixPointScotch) }
    )
    @Published var activeRoundSession: RoundSession?
    @Published var activeEventSession: EventSession?

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

    func updateActiveEventSession(_ session: EventSession) {
        activeEventSession = session
        persist()
    }

    func clearActiveRoundSession() {
        activeRoundSession = nil
        persist()
    }

    func persistSelections() {
        persist()
    }

    private func persist() {
        let snapshot = AppSessionSnapshot(
            gameSelections: gameSelections,
            activeRoundSession: activeRoundSession,
            activeEventSession: activeEventSession
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

func strokeCountForHandicapIndex(_ handicapIndex: Double, onHoleStrokeIndex si: Int) -> Int {
    let courseHandicap = max(0, Int(handicapIndex.rounded(.down)))
    let base = courseHandicap / 18
    let remainder = courseHandicap % 18
    return base + (si <= remainder ? 1 : 0)
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
