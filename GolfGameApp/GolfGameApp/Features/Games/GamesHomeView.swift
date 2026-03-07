//
//  GamesHomeView.swift
//  GolfGameApp
//
//  Created by juswaite on 2/27/26.
//

import SwiftUI

struct GamesHomeView: View {
    @EnvironmentObject private var session: SessionModel

    var body: some View {
        NavigationStack {
            List {
                Section("Games Catalog") {
                    ForEach(GameType.allCases) { game in
                        HStack {
                            GameCatalogRow(game: game)
                            Spacer(minLength: 12)
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { session.gameSelections[game, default: false] },
                                    set: {
                                        session.gameSelections[game] = $0
                                        session.persistSelections()
                                    }
                                )
                            )
                            .labelsHidden()
                        }
                    }
                }

                Section("Selection Summary") {
                    ForEach(GameType.allCases.filter { session.gameSelections[$0, default: false] }) { selectedGame in
                        Text(selectedGame.title)
                    }
                }
            }
            .navigationTitle("Games")
        }
    }
}

private struct GameCatalogRow: View {
    let game: GameType

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
            }
            Spacer()
            Text(game.scope == .round ? "Round" : "Event")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    game.scope == .round ? Color.blue.opacity(0.15) : Color.indigo.opacity(0.15),
                    in: Capsule()
                )
        }
        .padding(.vertical, 4)
    }
}
