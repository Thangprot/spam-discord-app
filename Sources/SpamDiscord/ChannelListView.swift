import SwiftUI

struct ChannelListView: View {
    @EnvironmentObject var app: AppState
    let guild: Guild
    @State private var searchText = ""
    
    var filteredSections: [(category: Channel?, items: [Channel])] {
        let sections = app.groupedChannels()
        if searchText.isEmpty { return sections }
        
        return sections.compactMap { section in
            let filteredItems = section.items.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
            if filteredItems.isEmpty { return nil }
            return (section.category, filteredItems)
        }
    }
    
    var body: some View {
        Group {
            if app.isLoading { ProgressView() }
            else {
                List {
                    ForEach(filteredSections, id: \.category?.id) { sec in
                        Section(header: Text(sec.category?.displayName.uppercased() ?? "KHÁC").font(.caption).bold()) {
                            ForEach(sec.items) { c in
                                NavigationLink(value: c) {
                                    HStack { 
                                        Image(systemName: c.type == 5 ? "megaphone" : "number")
                                            .foregroundStyle(.secondary)
                                        Text(c.displayName) 
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Tìm kênh...")
        .navigationTitle(guild.name)
        .task { await app.loadChannels(for: guild) }
        .navigationDestination(for: Channel.self) { SendView(channel: $0) }
    }
}