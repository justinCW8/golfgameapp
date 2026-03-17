import Foundation
import Testing
@testable import GolfGameApp

@MainActor
struct WorkflowRegressionTests {

    @Test func buddyStoreTextingRecipientsNormalizesPhones() {
        let key = "golf_buddies"
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: key)
        let store = BuddyStore()
        store.buddies = []
        store.add(name: "Alice", handicapIndex: 10.4, phoneNumber: "(312) 555-0101")
        store.add(name: "Bob", handicapIndex: 12.2, phoneNumber: "+1 312 555 0102")

        let recipients = store.textingRecipients(forPlayers: ["Alice", "Missing", "Bob"])

        #expect(recipients.count == 2)
        #expect(recipients[0].name == "Alice")
        #expect(recipients[0].phone == "3125550101")
        #expect(recipients[1].name == "Bob")
        #expect(recipients[1].phone == "+13125550102")
    }

    @Test func clearSaturdayRoundArchivesOnlyCompletedRounds() {
        let store = AppSessionStore()
        store.completedRounds = []

        var unfinished = makeRound(currentHole: 5, isComplete: false)
        unfinished.holeEntries = [holeEntry(holeNumber: 1, players: unfinished.players)]
        store.activeSaturdayRound = unfinished
        store.clearSaturdayRound()

        #expect(store.activeSaturdayRound == nil)
        #expect(store.completedRounds.isEmpty)

        var completed = makeRound(currentHole: 18, isComplete: true)
        completed.holeEntries = [holeEntry(holeNumber: 1, players: completed.players)]
        store.activeSaturdayRound = completed
        store.clearSaturdayRound()

        #expect(store.activeSaturdayRound == nil)
        #expect(store.completedRounds.count == 1)
        #expect(store.completedRounds.first?.id == completed.id)
    }

    @Test func clearSaturdayRoundDoesNotDuplicateSameRoundID() {
        let store = AppSessionStore()
        var completed = makeRound(currentHole: 18, isComplete: true)
        completed.holeEntries = [holeEntry(holeNumber: 1, players: completed.players)]

        store.completedRounds = [completed]
        store.activeSaturdayRound = completed
        store.clearSaturdayRound()

        #expect(store.completedRounds.count == 1)
    }

    @Test func autofillRemainingHolesCompletesRoundForTesting() {
        let store = AppSessionStore()
        var round = makeRound(currentHole: 16, isComplete: false)
        round.holeEntries = [holeEntry(holeNumber: 1, players: round.players)]
        let vm = SaturdayScoringViewModel(round: round, store: store)

        vm.autofillRemainingHolesForTesting()

        #expect(vm.round.isComplete)
        #expect(vm.round.currentHole == 18)

        for hole in [16, 17, 18] {
            let entry = vm.round.holeEntries.first(where: { $0.holeNumber == hole })
            #expect(entry != nil)
            #expect(entry?.grossByPlayerID.count == vm.round.players.count)
        }
    }

    @Test func roundTextMessageComposerIncludesSummarySections() {
        var round = makeRound(currentHole: 2, isComplete: true, activeGames: [.stableford()])
        round.holeEntries = [holeEntry(holeNumber: 1, players: round.players)]

        let message = RoundTextMessageComposer.messageBody(for: round)

        #expect(message.contains("Golf Round Summary"))
        #expect(message.contains("Scorecard Totals"))
        #expect(message.contains("Final Settlement"))
        #expect(message.contains("Alice"))
        #expect(message.contains("Stableford:"))
        #expect(message.contains("Standings:"))
        #expect(message.contains("Alice "))
        #expect(message.contains("Bob "))
        #expect(message.contains("Carol "))
        #expect(message.contains("Dave "))
    }

    private func makeRound(
        currentHole: Int,
        isComplete: Bool,
        activeGames: [SaturdayGameConfig] = [.scotch()]
    ) -> SaturdayRound {
        let players: [PlayerSnapshot] = [
            PlayerSnapshot(id: "p1", name: "Alice", handicapIndex: 10),
            PlayerSnapshot(id: "p2", name: "Bob", handicapIndex: 12),
            PlayerSnapshot(id: "p3", name: "Carol", handicapIndex: 8),
            PlayerSnapshot(id: "p4", name: "Dave", handicapIndex: 14)
        ]
        let teams: [TeamPairing] = [
            TeamPairing(team: .teamA, players: [players[0], players[1]]),
            TeamPairing(team: .teamB, players: [players[2], players[3]])
        ]
        let holes = (1...18).map { CourseHoleStub(number: $0, par: 4, strokeIndex: $0) }
        return SaturdayRound(
            players: players,
            teams: teams,
            courseName: "Test Course",
            holes: holes,
            activeGames: activeGames,
            holeEntries: [],
            currentHole: currentHole,
            isComplete: isComplete
        )
    }

    private func holeEntry(holeNumber: Int, players: [PlayerSnapshot]) -> SaturdayHoleEntry {
        SaturdayHoleEntry(
            holeNumber: holeNumber,
            grossByPlayerID: Dictionary(uniqueKeysWithValues: players.map { ($0.id, 4) })
        )
    }
}
