import SwiftUI

@main
struct SpamDiscordApp: App {
    @StateObject private var app = AppState()
    
    var body: some Scene {
        WindowGroup {
            if app.me != nil {
                GuildListView().environmentObject(app)
            } else {
                LoginView().environmentObject(app)
            }
        }
    }
}