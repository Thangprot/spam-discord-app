import SwiftUI

struct GuildListView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        NavigationStack {
            List(app.guilds) { g in
                NavigationLink(value: g) { Text(g.name) }
            }
            .navigationTitle("Chọn Server")
            .toolbar { Button("Đăng xuất", role: .destructive) { app.logout() } }
            .navigationDestination(for: Guild.self) { ChannelListView(guild: $0) }
        }
    }
}