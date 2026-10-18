import SwiftUI

@main
struct EQKeyboardApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                SetupView().tabItem { Label("tab.setup", systemImage: "keyboard") }
                ImportView().tabItem { Label("tab.import", systemImage: "photo.on.rectangle") }
                ProfileView().tabItem { Label("tab.profile", systemImage: "person.crop.circle") }
                AccountView().tabItem { Label("tab.account", systemImage: "crown") }
            }
        }
    }
}
