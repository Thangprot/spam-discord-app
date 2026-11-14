import SwiftUI

struct ChannelListView: View {
    @EnvironmentObject var app: AppState
    let guild: Guild
    
    var body: some View {
        Group {
            if app.isLoading { ProgressView() }
            else {
                List {
                    ForEach(app.groupedChannels(), id: \.category?.id) { section in
                        Section(header: Text(section.category?.displayName.uppercased() ?? "KHÔNG PHÂN LOẠI")) {
                            ForEach(section.items) { channel in
                                NavigationLink(value: channel) {
                                    HStack {
                                        Image(systemName: channel.type == 5 ? "megaphone" : "number")
                                        Text(channel.displayName)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(guild.name)
        .task { await app.loadChannels(for: guild) }
        .navigationDestination(for: Channel.self) { channel in
            SendView(channel: channel)
        }
    }
}