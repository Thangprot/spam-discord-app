import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var token = ""
    @Published var me: DiscordUser?
    @Published var guilds: [Guild] = []
    @Published var channels: [Channel] = []
    @Published var isLoading = false
    @Published var loginError: String?
    
    @Published var delaySeconds: Double = 2.0
    @Published var targetUserId = ""
    @Published var messages: [ParsedMessage] = []
    @Published var isSending = false
    @Published var currentIndex = 0
    @Published var logs: [LogEntry] = []
    
    private var client: DiscordClient? { token.isEmpty ? nil : DiscordClient(token: token) }
    private var isCancelled = false
    
    func login() async {
        isLoading = true; loginError = nil
        do {
            guard let client = client else { return }
            self.me = try await client.validateToken()
            KeychainHelper.save(token, key: "token")
            self.guilds = try await client.getAllGuilds().sorted { $0.name < $1.name }
        } catch { loginError = error.localizedDescription }
        isLoading = false
    }
    
    func loadChannels(for guild: Guild) async {
        isLoading = true
        do {
            guard let client = client else { return }
            let all = try await client.getAllChannels(guildId: guild.id)
            self.channels = all.filter { $0.isSendableText || $0.isCategory }.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        } catch { print(error) }
        isLoading = false
    }
    
    func groupedChannels() -> [(category: Channel?, items: [Channel])] {
        var secs: [(Channel?, [Channel])] = []
        let orp = channels.filter { $0.isSendableText && $0.parentId == nil }
        if !orp.isEmpty { secs.append((nil, orp)) }
        for cat in channels where cat.isCategory {
            let kids = channels.filter { $0.isSendableText && $0.parentId == cat.id }
            if !kids.isEmpty { secs.append((cat, kids)) }
        }
        return secs
    }
    
    func parseFile(url: URL) {
        let acc = url.startAccessingSecurityScopedResource()
        defer { if acc { url.stopAccessingSecurityScopedResource() } }
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            messages = content.components(separatedBy: .newlines).compactMap {
                let t = $0.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix(">") && t.hasSuffix("#") else { return nil }
                let body = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                return body.isEmpty ? nil : ParsedMessage(body: body)
            }
        }
    }
    
    func startSending(channel: Channel) {
        guard let client = client, !messages.isEmpty, !targetUserId.isEmpty else { return }
        isSending = true; isCancelled = false; currentIndex = 0; logs.removeAll()
        
        Task {
            for (i, msg) in messages.enumerated() {
                if isCancelled { break }
                do {
                    try await client.sendMessage(channelId: channel.id, content: "\(msg.body) <@\(targetUserId)>")
                    logs.append(LogEntry(text: "✅ [\(i+1)/\(messages.count)] Đã gửi", isSuccess: true))
                } catch { logs.append(LogEntry(text: "❌ [\(i+1)] \(error.localizedDescription)", isSuccess: false)) }
                currentIndex = i + 1
                try? await Task.sleep(nanoseconds: UInt64(max(0.1, delaySeconds + Double.random(in: -0.3...0.3) * delaySeconds) * 1_000_000_000))
            }
            isSending = false
        }
    }
    
    func stopSending() { isCancelled = true }
    func logout() { KeychainHelper.delete(key: "token"); token = ""; me = nil; guilds = []; channels = [] }
}