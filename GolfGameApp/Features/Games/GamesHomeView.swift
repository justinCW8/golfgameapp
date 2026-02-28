//
//  GamesHomeView.swift
//  GolfGameApp
//
//  Created by juswaite on 2/27/26.
//

import SwiftUI

struct GamesHomeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Active Games") {
                    Text("None yet")
                        .foregroundStyle(.secondary)
                }

                Section("Add a Game") {
                    Text("Six Point Scotch")
                    Text("Nassau")
                    Text("Stableford")
                }
            }
            .navigationTitle("Games")
        }
    }
}
