//
//  RoundHomeView.swift
//  GolfGameApp
//
//  Created by juswaite on 2/27/26.
//

import SwiftUI

struct RoundHomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("No Active Round")
                    .font(.headline)

                Button("Create Event") {
                    // TODO: Event setup flow
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Round")
        }
    }
}
