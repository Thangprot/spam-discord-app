import SwiftUI
import UIKit

@MainActor
class AppState: ObservableObject {
    @Published var token = ""
    @Published var me: DiscordUser?
    @Published var guilds: [Guild] = []
    @Published var channels: [Channel] = []
    @Published var isLoading = false
    @Published var loginError: String?
    
    @Published var delaySeconds: Double = 2.0
    @Published var useTag: Bool = true 
    @Published var targetUserId = ""
    @Published var inputText = "" 
    
    @Published var messages: [ParsedMessage] = []
    @Published var isSending = false
    @Published var totalSent = 0 // Đổi thành tổng số tin đã gửi
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
            self.inputText = content 
            parseDirectInput()
        }
    }
    
    func parseDirectInput() {
        messages = inputText.components(separatedBy: .newlines).compactMap {
            var t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix(">") { t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if t.hasSuffix("#") { t = String(t.dropLast()).trimmingCharacters(in: .whitespaces) }
            return t.isEmpty ? nil : ParsedMessage(body: t)
        }
    }
    
    func startSending(channel: Channel) {
        guard let client = client, !messages.isEmpty else { return }
        if useTag && targetUserId.isEmpty { return }
        
        isSending = true; isCancelled = false; totalSent = 0; logs.removeAll()
        
        let mentionText = useTag ? " <@\(targetUserId)>" : ""
        
        Task {
            var currentIndex = 0
            
            // VÒNG LẶP VÔ HẠN CHO ĐẾN KHI BẤM DỪNG
            while !isCancelled {
                let msg = messages[currentIndex]
                
                // Cập nhật trạng thái đang gửi
                let sendingLog = LogEntry(text: "Đang gửi: \(msg.body.prefix(20))...", isSuccess: true, isSendingState: true)
                logs.append(sendingLog)
                
                do {
                    try await client.sendMessage(channelId: channel.id, content: "\(msg.body)\(mentionText)")
                    // Xóa log tạm, thêm log thành công
                    if let idx = logs.firstIndex(where: { $0.id == sendingLog.id }) { logs.remove(at: idx) }
                    logs.append(LogEntry(text: "Đã gửi: \(msg.body.prefix(20))...", isSuccess: true))
                    totalSent += 1
                } catch { 
                    if let idx = logs.firstIndex(where: { $0.id == sendingLog.id }) { logs.remove(at: idx) }
                    logs.append(LogEntry(text: "Lỗi: \(error.localizedDescription)", isSuccess: false)) 
                }
                
                // Chuyển sang tin tiếp theo, nếu hết thì quay lại từ đầu
                currentIndex = (currentIndex + 1) % messages.count
                
                // Delay có yếu tố ngẫu nhiên (jitter)
                let actualDelay = max(0.1, delaySeconds + Double.random(in: -0.3...0.3) * delaySeconds)
                try? await Task.sleep(nanoseconds: UInt64(actualDelay * 1_000_000_000))
            }
            
            isSending = false
        }
    }
    
    func stopSending() { 
        isCancelled = true 
        isSending = false
    }
    
    func logout() { 
        KeychainHelper.delete(key: "token")
        token = ""; me = nil; guilds = []; channels = [] 
    }
    
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}