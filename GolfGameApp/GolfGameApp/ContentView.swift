import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            HistoryHomeView()
                .tabItem { Label("History", systemImage: "clock.fill") }
                .tag(1)

            ProfileView(selectedTab: $selectedTab)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(2)
        }
    }
}
