import SwiftUI

@main
struct BabyLoveApp: App {
    @StateObject private var appState: AppState
    let persistence = PersistenceController.shared

    init() {
        let args = ProcessInfo.processInfo.arguments

        let state = AppState()
        // UI 测试中跳过引导页，注入测试 baby
        if args.contains("--uitesting") && args.contains("--skip-onboarding") {
            let testBaby = Baby(
                name: "Test Baby",
                birthDate: Calendar.current.date(byAdding: .month, value: -3, to: Date())!,
                gender: .girl
            )
            state.completeOnboarding(with: testBaby)
        }
        _appState = StateObject(wrappedValue: state)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}
