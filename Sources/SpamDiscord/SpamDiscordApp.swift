import SwiftUI

@main
struct SpamDiscordApp: App {
    @StateObject private var app = AppState()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .task {
                    // Tự động đăng nhập nếu có token trong Keychain
                    if let savedToken = KeychainHelper.read(key: "discord_token"), !savedToken.isEmpty {
                        app.token = savedToken
                        await app.login()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    
    var body: some View {
        if app.me != nil {
            GuildListView()
        } else {
            LoginView()
        }
    }
}