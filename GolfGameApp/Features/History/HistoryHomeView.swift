//
//  HistoryHomeView.swift
//  GolfGameApp
//
//  Created by juswaite on 2/27/26.
//

import SwiftUI

struct HistoryHomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Round History")
                    .font(.headline)
                Text("Coming soon")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("History")
        }
    }
}
