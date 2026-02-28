//
//  GolfGameAppApp.swift
//  GolfGameApp
//
//  Created by juswaite on 2/27/26.
//

import SwiftUI

@main
struct GolfGameAppApp: App {
    @StateObject private var session = SessionModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
        }
    }
}
