import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.hasCompletedOnboarding {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

// MARK: - Main Tab
struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label(String(localized: "tab.today"), systemImage: selectedTab == 0 ? "house.fill" : "house")
                }
                .tag(0)

            TrackView()
                .tabItem {
                    Label(String(localized: "tab.track"), systemImage: selectedTab == 1 ? "plus.circle.fill" : "plus.circle")
                }
                .tag(1)

            GrowthView()
                .tabItem {
                    Label(String(localized: "tab.growth"), systemImage: selectedTab == 2 ? "chart.bar.fill" : "chart.bar")
                }
                .tag(2)

            MemoryView()
                .tabItem {
                    Label(String(localized: "tab.memories"), systemImage: selectedTab == 3 ? "heart.fill" : "heart")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label(String(localized: "tab.more"), systemImage: "ellipsis.circle\(selectedTab == 4 ? ".fill" : "")")
                }
                .tag(4)
        }
        .tint(.blPrimary)
        .blToastOverlay()
    }
}
