import SwiftUI

struct GuildListView: View {
    @EnvironmentObject var app: AppState
    
    var body: some View {
        NavigationStack {
            List(app.guilds) { guild in
                NavigationLink(value: guild) {
                    Text(guild.name)
                }
            }
            .navigationTitle("Chọn Server")
            .toolbar {
                Button("Đăng xuất", role: .destructive) { app.logout() }
            }
            .navigationDestination(for: Guild.self) { guild in
                ChannelListView(guild: guild)
            }
        }
    }
}