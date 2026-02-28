import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RoundHomeView()
                .tabItem {
                    Label("Round", systemImage: "flag.fill")
                }

            GamesHomeView()
                .tabItem {
                    Label("Games", systemImage: "gamecontroller.fill")
                }

            HistoryHomeView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
        }
    }
}
