import SwiftUI

@main
struct OSVcopyApp: App {
    @StateObject private var model = OrganizerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 900, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
