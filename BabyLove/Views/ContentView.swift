import SwiftUI
import CoreData

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SHOW_SUMMARY"] == "1" {
            SummaryView()
        } else if appState.hasCompletedOnboarding {
            MainTabView()
        } else {
            OnboardingView()
        }
        #else
        if appState.hasCompletedOnboarding {
            MainTabView()
        } else {
            OnboardingView()
        }
        #endif
    }
}

// MARK: - Main Tab
struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    // Track ongoing timers across all tabs so the Home badge stays visible
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "endTime == nil")
    )
    private var ongoingSleeps: FetchedResults<CDSleepRecord>

    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "durationMinutes == 0 AND (feedType == %@ OR feedType == %@)", "breast", "pump")
    )
    private var ongoingFeedings: FetchedResults<CDFeedingRecord>

    /// Number of active timers (sleep + feeding) — shown as a badge on the Home tab
    private var activeTimerCount: Int {
        ongoingSleeps.count + ongoingFeedings.count
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label(String(localized: "tab.today"), systemImage: selectedTab == 0 ? "house.fill" : "house")
                }
                .tag(0)
                .badge(activeTimerCount)

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
