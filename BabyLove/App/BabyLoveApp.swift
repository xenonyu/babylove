import SwiftUI

@main
struct BabyLoveApp: App {
    @StateObject private var appState = AppState()
    let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}
