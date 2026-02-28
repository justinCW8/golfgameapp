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
    var players: [PlayerSnapshot]
    var holes: [CourseHoleStub]
    var pairings: [TeamPairing]
}

@MainActor
final class SessionModel: ObservableObject {
    @Published var gameSelections: [GameType: Bool] = Dictionary(
        uniqueKeysWithValues: GameType.allCases.map { ($0, $0 == .sixPointScotch) }
    )
    @Published var configuredRound: RoundSetupSession?
}

enum CourseStubFactory {
    static func default18() -> [CourseHoleStub] {
        let pars = [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4]
        return (1...18).map {
            CourseHoleStub(number: $0, par: pars[$0 - 1], strokeIndex: $0)
        }
    }
}
