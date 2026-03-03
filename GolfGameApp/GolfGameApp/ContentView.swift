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

            EventHomeView()
                .tabItem {
                    Label("Stableford", systemImage: "list.number")
                }
        }
    }
}
