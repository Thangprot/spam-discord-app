import SwiftUI

struct GuildListView: View {
    @EnvironmentObject var app: AppState
    @State private var searchText = ""
    
    var filteredGuilds: [Guild] {
        if searchText.isEmpty { return app.guilds }
        return app.guilds.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredGuilds) { guild in
                NavigationLink(value: guild) { 
                    Text(guild.name)
                        .fontWeight(.medium)
                }
            }
            .searchable(text: $searchText, prompt: "Tìm tên Server...")
            .navigationTitle("Chọn Server")
            .toolbar { Button("Đăng xuất", role: .destructive) { app.logout() } }
            .navigationDestination(for: Guild.self) { ChannelListView(guild: $0) }
        }
    }
}