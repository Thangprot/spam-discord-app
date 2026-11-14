import SwiftUI

struct ChannelListView: View {
    @EnvironmentObject var app: AppState
    let guild: Guild
    
    var body: some View {
        Group {
            if app.isLoading { ProgressView() }
            else {
                List {
                    ForEach(app.groupedChannels(), id: \.category?.id) { sec in
                        Section(header: Text(sec.category?.displayName.uppercased() ?? "KHÁC")) {
                            ForEach(sec.items) { c in
                                NavigationLink(value: c) {
                                    HStack { Image(systemName: c.type == 5 ? "megaphone" : "number"); Text(c.displayName) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(guild.name)
        .task { await app.loadChannels(for: guild) }
        .navigationDestination(for: Channel.self) { SendView(channel: $0) }
    }
}