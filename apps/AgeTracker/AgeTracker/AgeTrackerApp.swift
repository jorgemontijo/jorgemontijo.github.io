import SwiftUI

@main
struct AgeTrackerApp: App {
    @StateObject private var store = PersonStore()

    var body: some Scene {
        WindowGroup("Age Tracker") {
            ContentView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
