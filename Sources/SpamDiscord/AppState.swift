import SwiftUI

@MainActor
class AppState: ObservableObject {
    // Auth & Data
    @Published var token: String = ""
    @Published var me: DiscordUser?
    @Published var guilds: [Guild] = []
    @Published var selectedGuild: Guild?
    @Published var channels: [Channel] = []
    @Published var selectedChannel: Channel?
    
    // UI States
    @Published var isLoading = false
    @Published var loginError: String?
    
    // Sender Config
    @Published var delaySeconds: Double = 2.0
    @Published var targetUserId: String = ""
    @Published var messages: [ParsedMessage] = []
    
    // Sending States
    @Published var isSending = false
    @Published var currentIndex = 0
    @Published var logs: [LogEntry] = []
    private var isCancelled = false
    
    var client: DiscordClient? { token.isEmpty ? nil : DiscordClient(token: token) }
    
    func login() async {
        isLoading = true
        loginError = nil
        do {
            guard let client = client else { return }
            let user = try await client.validateToken()
            self.me = user
            KeychainHelper.save(token, key: "discord_token")
            self.guilds = try await client.getAllGuilds().sorted { $0.name < $1.name }
        } catch {
            loginError = error.localizedDescription
            self.me = nil
        }
        isLoading = false
    }
    
    func loadChannels(for guild: Guild) async {
        isLoading = true
        self.selectedGuild = guild
        self.channels = []
        self.selectedChannel = nil
        do {
            guard let client = client else { return }
            let allChannels = try await client.getAllChannels(guildId: guild.id)
            self.channels = allChannels
                .filter { $0.isSendableText || $0.isCategory }
                .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        } catch {
            logs.append(LogEntry(text: "Lỗi tải kênh: \(error.localizedDescription)", isSuccess: false))
        }
        isLoading = false
    }
    
    func groupedChannels() -> [(category: Channel?, items: [Channel])] {
        var sections: [(Channel?, [Channel])] = []
        let orphans = channels.filter { $0.isSendableText && $0.parentId == nil }
        if !orphans.isEmpty { sections.append((nil, orphans)) }
        for cat in channels where cat.isCategory {
            let kids = channels.filter { $0.isSendableText && $0.parentId == cat.id }
            if !kids.isEmpty { sections.append((cat, kids)) }
        }
        return sections
    }
    
    func parseFile(url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            var parsed: [ParsedMessage] = []
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix(">") && trimmed.hasSuffix("#") {
                    let body = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                    if !body.isEmpty { parsed.append(ParsedMessage(body: body)) }
                }
            }
            self.messages = parsed
        } catch {
            logs.append(LogEntry(text: "Lỗi đọc file: \(error.localizedDescription)", isSuccess: false))
        }
    }
    
    func startSending() {
        guard let client = client, let channel = selectedChannel, !messages.isEmpty, !targetUserId.isEmpty else { return }
        
        isSending = true
        isCancelled = false
        currentIndex = 0
        logs.removeAll()
        
        let mention = "<@\(targetUserId)>"
        let delay = delaySeconds
        let msgs = messages
        
        Task {
            for (index, msg) in msgs.enumerated() {
                if isCancelled { break }
                
                let content = "\(msg.body) \(mention)"
                do {
                    try await client.sendMessage(channelId: channel.id, content: content)
                    logs.append(LogEntry(text: "✅ [\(index+1)/\(msgs.count)] Đã gửi", isSuccess: true))
                } catch {
                    logs.append(LogEntry(text: "❌ [\(index+1)] \(error.localizedDescription)", isSuccess: false))
                }
                
                currentIndex = index + 1
                
                // Random Jitter ±25% để tránh bị Discord phát hiện pattern
                let jitter = Double.random(in: -0.25...0.25) * delay
                let waitTime = max(0.1, delay + jitter)
                
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
            isSending = false
        }
    }
    
    func stopSending() {
        isCancelled = true
    }
    
    func logout() {
        KeychainHelper.delete(key: "discord_token")
        token = ""
        me = nil
        guilds = []
        channels = []
        messages = []
        logs = []
    }
}