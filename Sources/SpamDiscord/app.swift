import SwiftUI
import Foundation
import Security
import AVFoundation
import UniformTypeIdentifiers
import UIKit

// ==========================================
// MARK: - DOCUMENT PICKER (FIX iOS FILE PICKER)
// ==========================================
// Dùng UIDocumentPickerViewController thay .fileImporter để tránh bug
// "bấm vào file không phản hồi" trên iOS 16/17/18 khi trộn .item với UTType con.
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
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel?()
        }
    }
}

// ==========================================
// MARK: - MODELS (SPAM)
// ==========================================
struct DiscordUser: Codable {
    let id: String
    let username: String
    let globalName: String?
    let avatar: String?
}

struct TokenInfo: Identifiable, Codable, Equatable {
    var id = UUID()
    let token: String
    var userId: String
    var username: String
    var avatarHash: String?
    var isValid: Bool

    var avatarURL: URL? {
        guard let hash = avatarHash else { return nil }
        return URL(string: "https://cdn.discordapp.com/avatars/\(userId)/\(hash).png?size=128")
    }
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

// ==========================================
// MARK: - MODELS (BOT NUKE)
// ==========================================
struct BotInfo: Codable {
    let id: String
    let username: String
    let discriminator: String?
    let avatar: String?
    let bot: Bool?
}

struct BotConfig: Codable {
    var token: String
    var username: String
    var userId: String
    var avatarHash: String?
    var discriminator: String?

    var displayName: String {
        if let d = discriminator, d != "0" { return "\(username)#\(d)" }
        return username
    }
    var avatarURL: URL? {
        guard let h = avatarHash else { return nil }
        return URL(string: "https://cdn.discordapp.com/avatars/\(userId)/\(h).png?size=128")
    }
}

struct GuildRole: Codable {
    let id: String
    let name: String
    let position: Int
}

struct BotMember: Codable {
    let user: BotMemberUser?
    let roles: [String]?
}
struct BotMemberUser: Codable {
    let id: String
    let username: String?
    let bot: Bool?
}

struct NukeConfig {
    var doMassBan = false
    var doDeleteChannels = false
    var doCreateRoles = false
    var doCreateChannels = true
    var doRenameGuild = false

    var roleName = "Ceker Cute"
    var roleCount = 50

    var channelName = "nuked-by-tool"
    var channelCount = 50
    var messageContent = ""
    var tagEveryone = true

    var newGuildName = ""
}

// ==========================================
// MARK: - SILENT AUDIO (CHẠY NGẦM)
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

            let sampleRate = 8000, duration = 1, numSamples = sampleRate * duration, dataSize = numSamples * 2
            var header = Data()
            header.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
            var chunkSize = UInt32(36 + dataSize).littleEndian
            header.append(Data(bytes: &chunkSize, count: 4))
            header.append(contentsOf: [0x57, 0x41, 0x56, 0x45, 0x66, 0x6d, 0x74, 0x20])
            var subchunk1Size = UInt32(16).littleEndian
            header.append(Data(bytes: &subchunk1Size, count: 4))
            var audioFormat = UInt16(1).littleEndian
            header.append(Data(bytes: &audioFormat, count: 2))
            var numChannels = UInt16(1).littleEndian
            header.append(Data(bytes: &numChannels, count: 2))
            var sampleRateL = UInt32(sampleRate).littleEndian
            header.append(Data(bytes: &sampleRateL, count: 4))
            var byteRate = UInt32(sampleRate * 2).littleEndian
            header.append(Data(bytes: &byteRate, count: 4))
            var blockAlign = UInt16(2).littleEndian
            header.append(Data(bytes: &blockAlign, count: 2))
            var bitsPerSample = UInt16(16).littleEndian
            header.append(Data(bytes: &bitsPerSample, count: 2))
            header.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
            var dataChunkSize = UInt32(dataSize).littleEndian
            header.append(Data(bytes: &dataChunkSize, count: 4))

            audioPlayer = try AVAudioPlayer(data: header + Data(repeating: 0, count: dataSize))
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
// MARK: - DISCORD CLIENT (SPAM, user token)
// ==========================================
class DiscordClient {
    let token: String
    let session: URLSession

    init(token: String) {
        self.token = token
        let config = URLSessionConfiguration.default
        let superProps = """
        {"os":"Mac OS X","browser":"Chrome","device":"","system_locale":"en-US","browser_user_agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36","browser_version":"126.0.0.0","os_version":"10.15.7","referrer":"","referring_domain":"","referrer_current":"","referring_domain_current":"","release_channel":"stable","client_build_number":305000,"client_event_source":null}
        """
        config.httpAdditionalHeaders = [
            "Authorization": token, "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            "X-Super-Properties": Data(superProps.utf8).base64EncodedString(), "X-Discord-Locale": "en-US"
        ]
        self.session = URLSession(configuration: config)
    }

    private func check(_ res: URLResponse, _ data: Data) throws {
        guard let http = res as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
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
// MARK: - APP STATE (SPAM)
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
    @Published var addPrefix: Bool = false
    @Published var addSuffix: Bool = false

    @Published var inputText = ""
    @Published var messages: [ParsedMessage] = []

    @Published var isSending = false
    @Published var totalSent = 0
    @Published var currentMessageStr = ""
    @Published var lastError: String?

    private var client: DiscordClient? {
        activeToken != nil ? DiscordClient(token: activeToken!.token) : nil
    }
    private var isCancelled = false
    private var sendTask: Task<Void, Never>?

    init() { loadTokens() }

    private func saveTokens() {
        if let encoded = try? JSONEncoder().encode(tokens) {
            UserDefaults.standard.set(encoded, forKey: "SavedTokens")
        }
    }

    private func loadTokens() {
        if let data = UserDefaults.standard.data(forKey: "SavedTokens"),
           let saved = try? JSONDecoder().decode([TokenInfo].self, from: data) {
            self.tokens = saved
            if let active = saved.first(where: { $0.isValid }) {
                self.activeToken = active
                Task { await loadGuilds() }
            }
        }
    }

    func addToken(_ tokenStr: String) async {
        let cleanToken = tokenStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty, !tokens.contains(where: { $0.token == cleanToken }) else { return }

        isCheckingToken = true
        let tempClient = DiscordClient(token: cleanToken)
        do {
            let user = try await tempClient.validateToken()
            let newToken = TokenInfo(token: cleanToken, userId: user.id,
                                     username: user.globalName ?? user.username,
                                     avatarHash: user.avatar, isValid: true)
            tokens.append(newToken)
            if activeToken == nil { setActiveToken(newToken) }
        } catch {
            let deadToken = TokenInfo(token: cleanToken, userId: "0",
                                      username: "Token Chết",
                                      avatarHash: nil, isValid: false)
            tokens.append(deadToken)
        }
        isCheckingToken = false
    }

    func addTokensFromFile(url: URL) async {
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        var fileData: Data?
        let coordinator = NSFileCoordinator()
        var coordErr: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordErr) { newURL in
            fileData = try? Data(contentsOf: newURL)
        }
        if fileData == nil { fileData = try? Data(contentsOf: url) }

        guard let data = fileData else {
            lastError = "Không thể đọc file token."
            return
        }

        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian,
                                            .windowsCP1252, .isoLatin1, .ascii]
        var content: String?
        for enc in encodings {
            if let s = String(data: data, encoding: enc), !s.isEmpty {
                content = s
                break
            }
        }
        if content == nil { content = String(decoding: data, as: UTF8.self) }

        guard let text = content, !text.isEmpty else {
            lastError = "File token rỗng hoặc sai định dạng."
            return
        }

        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        let lines = cleaned.components(separatedBy: .newlines)
        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await addToken(line)
        }
        lastError = nil
    }

    func setActiveToken(_ token: TokenInfo) {
        guard token.isValid else { return }
        activeToken = token
        Task { await loadGuilds() }
    }

    func deleteToken(at offsets: IndexSet) {
        if let active = activeToken, offsets.map({ tokens[$0] }).contains(where: { $0.id == active.id }) {
            activeToken = nil; guilds = []
        }
        tokens.remove(atOffsets: offsets)
    }

    func loadGuilds() async {
        guard let client = client else { return }
        isLoading = true
        do {
            self.guilds = try await client.getAllGuilds().sorted { $0.name < $1.name }
        } catch { lastError = error.localizedDescription }
        isLoading = false
    }

    func loadChannels(for guild: Guild) async {
        guard let client = client else { return }
        isLoading = true
        do {
            let all = try await client.getAllChannels(guildId: guild.id)
            self.channels = all.filter { $0.isSendableText || $0.isCategory }
                .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
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
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        var fileData: Data?
        var readErr: String?

        let coordinator = NSFileCoordinator()
        var coordErr: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordErr) { newURL in
            do { fileData = try Data(contentsOf: newURL) }
            catch { readErr = error.localizedDescription }
        }

        if fileData == nil {
            do { fileData = try Data(contentsOf: url) }
            catch { readErr = error.localizedDescription }
        }

        guard let data = fileData else {
            self.lastError = "Không thể đọc file: \(readErr ?? coordErr?.localizedDescription ?? "Lỗi không xác định")"
            return
        }

        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian,
                                            .windowsCP1252, .isoLatin1, .ascii, .nonLossyASCII]
        var content: String?
        for enc in encodings {
            if let s = String(data: data, encoding: enc), !s.isEmpty {
                content = s
                break
            }
        }
        if content == nil || content!.isEmpty {
            content = String(decoding: data, as: UTF8.self)
        }

        guard let finalContent = content, !finalContent.isEmpty else {
            self.lastError = "File rỗng hoặc không đúng định dạng."
            return
        }

        let cleaned = finalContent.replacingOccurrences(of: "\u{FEFF}", with: "")
        self.inputText = cleaned
        self.parseDirectInput()
        self.lastError = nil
    }

    func parseDirectInput() {
        messages = inputText.components(separatedBy: .newlines).compactMap {
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : ParsedMessage(body: t)
        }
    }

    func startSending(channel: Channel) {
        guard let client = client, !messages.isEmpty else { return }
        if useTag && targetUserId.isEmpty { return }

        isSending = true; isCancelled = false; totalSent = 0; lastError = nil
        BackgroundManager.shared.start()

        sendTask = Task { [weak self] in
            guard let self = self else { return }
            var currentIndex = 0
            while !self.isCancelled && !Task.isCancelled {
                let msg = self.messages[currentIndex]

                var prefix = ""
                if self.addPrefix { prefix += "> " }
                if self.addSuffix { prefix += "# " }

                var finalContent = prefix + msg.body
                if self.useTag { finalContent += " <@\(self.targetUserId)>" }

                self.currentMessageStr = finalContent

                do {
                    try await client.sendMessage(channelId: channel.id, content: finalContent)
                    self.totalSent += 1
                } catch {
                    self.lastError = error.localizedDescription
                }

                currentIndex = (currentIndex + 1) % self.messages.count
                let actualDelay = max(0.1, self.delaySeconds + Double.random(in: -0.3...0.3) * self.delaySeconds)
                do {
                    try await Task.sleep(nanoseconds: UInt64(actualDelay * 1_000_000_000))
                } catch { break }
            }
            self.isSending = false
            self.currentMessageStr = ""
        }
    }

    func stopSending() {
        isCancelled = true
        sendTask?.cancel()
        sendTask = nil
        isSending = false
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

    static let EVERYONE_ALLOW: UInt64 =
        (1<<10) | (1<<11) | (1<<16) | (1<<15) | (1<<14) | (1<<6) | (1<<17)

    init(token: String) {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.auth = clean.lowercased().hasPrefix("bot ") ? clean : "Bot \(clean)"
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.httpAdditionalHeaders = [
            "Authorization": auth,
            "Content-Type": "application/json",
            "User-Agent": "DiscordBot (https://example.com, 1.0)"
        ]
        self.session = URLSession(configuration: cfg)
    }

    private func check(_ res: URLResponse, _ data: Data) throws {
        guard let http = res as? HTTPURLResponse else {
            throw NSError(domain: "Bot", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Bot", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body.prefix(200))"])
        }
    }

    func validate() async throws -> BotInfo {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/users/@me")!)
        try check(r, d)
        return try JSONDecoder().decode(BotInfo.self, from: d)
    }

    func getGuilds() async throws -> [Guild] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/users/@me/guilds")!)
        try check(r, d)
        return try JSONDecoder().decode([Guild].self, from: d)
    }

    func getGuildDetail(_ gid: String) async throws -> [String: Any] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)")!)
        try check(r, d)
        return (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }

    func getRoles(_ gid: String) async throws -> [GuildRole] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)/roles")!)
        try check(r, d)
        return try JSONDecoder().decode([GuildRole].self, from: d)
    }

    func getMember(_ gid: String, userId: String) async throws -> BotMember {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)/members/\(userId)")!)
        try check(r, d)
        return try JSONDecoder().decode(BotMember.self, from: d)
    }

    func getMembers(_ gid: String, after: String = "0") async throws -> [BotMember] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)/members?limit=1000&after=\(after)")!)
        try check(r, d)
        return try JSONDecoder().decode([BotMember].self, from: d)
    }

    func getChannels(_ gid: String) async throws -> [Channel] {
        let (d, r) = try await session.data(from: URL(string: "https://discord.com/api/v10/guilds/\(gid)/channels")!)
        try check(r, d)
        return try JSONDecoder().decode([Channel].self, from: d)
    }

    func deleteChannel(_ cid: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(cid)")!)
        req.httpMethod = "DELETE"
        let (d, r) = try await session.data(for: req)
        try check(r, d)
    }

    func createChannel(_ gid: String, name: String, openEveryone: Bool) async throws -> String? {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(gid)/channels")!)
        req.httpMethod = "POST"
        var payload: [String: Any] = ["name": name, "type": 0]
        if openEveryone {
            payload["permission_overwrites"] = [[
                "id": gid, "type": 0,
                "allow": String(BotClient.EVERYONE_ALLOW),
                "deny": "0"
            ]]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (d, r) = try await session.data(for: req)
        try check(r, d)
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["id"] as? String
    }

    func sendMessage(_ cid: String, content: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/channels/\(cid)/messages")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        let (d, r) = try await session.data(for: req)
        try check(r, d)
    }

    func createRole(_ gid: String, name: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(gid)/roles")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (d, r) = try await session.data(for: req)
        try check(r, d)
    }

    func renameGuild(_ gid: String, newName: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(gid)")!)
        req.httpMethod = "PATCH"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let (d, r) = try await session.data(for: req)
        try check(r, d)
    }

    func banMember(_ gid: String, userId: String) async throws {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/guilds/\(gid)/bans/\(userId)")!)
        req.httpMethod = "PUT"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["delete_message_seconds": 0])
        let (d, r) = try await session.data(for: req)
        try check(r, d)
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

    private var isCancelled = false
    private let configKey = "BotConfigV1"

    private var client: BotClient? {
        guard let c = config else { return nil }
        return BotClient(token: c.token)
    }

    init() { loadConfig() }

    private func saveConfig() {
        if let c = config, let data = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(data, forKey: configKey)
        } else {
            UserDefaults.standard.removeObject(forKey: configKey)
        }
    }

    private func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let c = try? JSONDecoder().decode(BotConfig.self, from: data) {
            self.config = c
            Task { await loadGuilds() }
        }
    }

    func setToken(_ token: String) async {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        isCheckingToken = true
        tokenError = nil
        let c = BotClient(token: clean)
        do {
            let info = try await c.validate()
            guard info.bot == true else {
                tokenError = "Token này không phải Bot token!"
                isCheckingToken = false
                return
            }
            let rawToken = clean.replacingOccurrences(of: "Bot ", with: "", options: .caseInsensitive)
            config = BotConfig(token: rawToken, username: info.username,
                               userId: info.id, avatarHash: info.avatar,
                               discriminator: info.discriminator)
            await loadGuilds()
        } catch {
            tokenError = "Token không hợp lệ: \(error.localizedDescription)"
        }
        isCheckingToken = false
    }

    func removeConfig() {
        config = nil
        botGuilds = []
        nukeLog = []
    }

    func loadGuilds() async {
        guard let c = client else { return }
        isLoadingGuilds = true
        do {
            botGuilds = try await c.getGuilds().sorted { $0.name < $1.name }
            tokenError = nil
        } catch {
            tokenError = error.localizedDescription
        }
        isLoadingGuilds = false
    }

    func stopNuke() { isCancelled = true }

    private func appendLog(_ msg: String) {
        nukeLog.append(msg)
        if nukeLog.count > 800 { nukeLog.removeFirst(nukeLog.count - 800) }
    }

    private func resetCounters() {
        banSuccess = 0; banFailed = 0
        channelsDeleted = 0; channelsCreated = 0
        messagesSent = 0; rolesCreated = 0
    }

    func runNuke(guild: Guild, options: NukeConfig) async {
        guard let c = client else { return }
        isNuking = true
        isCancelled = false
        nukeLog = []
        resetCounters()
        BackgroundManager.shared.start()

        let gid = guild.id
        appendLog("🚀 Bắt đầu nuke: \(guild.name)")

        if options.doMassBan && !isCancelled {
            appendLog("⚔️ [1/5] Mass Ban...")
            await doMassBan(client: c, guildId: gid)
        }

        if options.doDeleteChannels && !isCancelled {
            appendLog("🗑️ [2/5] Xóa toàn bộ kênh...")
            await doDeleteChannels(client: c, guildId: gid)
        }

        if options.doRenameGuild && !options.newGuildName.isEmpty && !isCancelled {
            appendLog("✏️ [3/5] Đổi tên server...")
            do {
                try await c.renameGuild(gid, newName: options.newGuildName)
                appendLog("  ✓ Đã đổi tên: \(options.newGuildName)")
            } catch {
                appendLog("  ✗ Lỗi đổi tên: \(error.localizedDescription)")
            }
        }

        if !isCancelled && (options.doCreateRoles || options.doCreateChannels) {
            appendLog("⚡ [4/5] Song song tạo Role + Kênh...")
            if options.doCreateRoles && options.doCreateChannels {
                async let r = doCreateRoles(client: c, guildId: gid, options: options)
                async let ch = doCreateChannels(client: c, guildId: gid, options: options)
                let (rr, cc) = await (r, ch)
                rolesCreated = rr
                channelsCreated = cc.0
                messagesSent = cc.1
            } else if options.doCreateRoles {
                rolesCreated = await doCreateRoles(client: c, guildId: gid, options: options)
            } else {
                let cc = await doCreateChannels(client: c, guildId: gid, options: options)
                channelsCreated = cc.0
                messagesSent = cc.1
            }
            appendLog("  ✓ Role: \(rolesCreated) | Kênh: \(channelsCreated) | Tin: \(messagesSent)")
        }

        appendLog(isCancelled ? "🛑 Đã dừng." : "✅ NUKE HOÀN TẤT!")
        appendLog("━━━ TỔNG KẾT ━━━")
        appendLog("Ban: \(banSuccess) ✓ / \(banFailed) ✗")
        appendLog("Xóa kênh: \(channelsDeleted)")
        appendLog("Tạo kênh: \(channelsCreated)")
        appendLog("Tin nhắn: \(messagesSent)")
        appendLog("Role: \(rolesCreated)")

        isNuking = false
        BackgroundManager.shared.stop()
    }

    private func doMassBan(client: BotClient, guildId: String) async {
        guard let cfg = config else { return }
        do {
            let detail = try await client.getGuildDetail(guildId)
            let ownerId = detail["owner_id"] as? String

            let botMember = try await client.getMember(guildId: guildId, userId: cfg.userId)
            let roles = try await client.getRoles(guildId)
            let roleMap = Dictionary(uniqueKeysWithValues: roles.map { ($0.id, $0) })

            let botMaxPos = (botMember.roles ?? []).compactMap { roleMap[$0]?.position }.max() ?? 0
            appendLog("  Bot role position: \(botMaxPos)")

            if botMaxPos == 0 {
                appendLog("  ⚠️ Bot không có role đủ cao — không ban được ai!")
                appendLog("  💡 Kéo role của bot LÊN CAO hơn member cần ban")
                return
            }

            var after = "0"
            var totalFetched = 0

            while !isCancelled {
                let members: [BotMember]
                do {
                    members = try await client.getMembers(guildId: guildId, after: after)
                } catch {
                    let msg = error.localizedDescription
                    appendLog("  ✗ Không lấy được member list: \(msg)")
                    if msg.contains("403") {
                        appendLog("  💡 Bật 'SERVER MEMBERS INTENT' tại Developer Portal → Bot → Privileged Gateway Intents")
                    }
                    return
                }
                if members.isEmpty { break }
                totalFetched += members.count

                for m in members {
                    if isCancelled { break }
                    guard let uid = m.user?.id else { continue }
                    if uid == cfg.userId { continue }
                    if uid == ownerId { continue }
                    if m.user?.bot == true { continue }

                    let pos = (m.roles ?? []).compactMap { roleMap[$0]?.position }.max() ?? 0
                    if pos >= botMaxPos { continue }

                    do {
                        try await client.banMember(guildId: guildId, userId: uid)
                        banSuccess += 1
                    } catch {
                        banFailed += 1
                    }
                    if (banSuccess + banFailed) % 10 == 0 {
                        appendLog("  Ban: \(banSuccess) ✓ / \(banFailed) ✗")
                    }
                }

                if members.count < 1000 { break }
                after = members.last?.user?.id ?? after
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            appendLog("  ✓ Ban xong: \(banSuccess) ok / \(banFailed) fail (đã quét \(totalFetched) members)")
        } catch {
            appendLog("  ✗ Lỗi mass ban: \(error.localizedDescription)")
        }
    }

    private func doDeleteChannels(client: BotClient, guildId: String) async {
        do {
            let chans = try await client.getChannels(guildId)
            appendLog("  Tìm thấy \(chans.count) kênh")
            var count = 0

            await withTaskGroup(of: Bool.self) { group in
                var inFlight = 0
                let maxConc = 10
                for ch in chans {
                    if isCancelled { break }
                    group.addTask {
                        do {
                            try await client.deleteChannel(ch.id)
                            return true
                        } catch { return false }
                    }
                    inFlight += 1
                    if inFlight >= maxConc {
                        if let r = await group.next(), r { count += 1 }
                        inFlight -= 1
                    }
                }
                for await r in group { if r { count += 1 } }
            }
            channelsDeleted = count
            appendLog("  ✓ Đã xóa \(count) kênh")
        } catch {
            appendLog("  ✗ Lỗi xóa kênh: \(error.localizedDescription)")
        }
    }

    private func doCreateRoles(client: BotClient, guildId: String, options: NukeConfig) async -> Int {
        var count = 0
        await withTaskGroup(of: Bool.self) { group in
            var inFlight = 0
            let maxConc = 10
            for _ in 0..<options.roleCount {
                if isCancelled { break }
                group.addTask {
                    do {
                        try await client.createRole(guildId, name: options.roleName)
                        return true
                    } catch { return false }
                }
                inFlight += 1
                if inFlight >= maxConc {
                    if let r = await group.next(), r { count += 1 }
                    inFlight -= 1
                }
            }
            for await r in group { if r { count += 1 } }
        }
        return count
    }

    private func doCreateChannels(client: BotClient, guildId: String, options: NukeConfig) async -> (Int, Int) {
        var created = 0
        var sent = 0

        var content = options.messageContent
        if options.tagEveryone && !content.contains("@everyone") {
            content += "\n\n@everyone"
        }

        await withTaskGroup(of: (Bool, Bool).self) { group in
            var inFlight = 0
            let maxConc = 8
            for _ in 0..<options.channelCount {
                if isCancelled { break }
                group.addTask {
                    do {
                        guard let chId = try await client.createChannel(guildId, name: options.channelName, openEveryone: true) else {
                            return (false, false)
                        }
                        if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                            do {
                                try await client.sendMessage(chId, content: content)
                                return (true, true)
                            } catch { return (true, false) }
                        }
                        return (true, false)
                    } catch { return (false, false) }
                }
                inFlight += 1
                if inFlight >= maxConc {
                    if let (c, s) = await group.next() {
                        if c { created += 1 }
                        if s { sent += 1 }
                    }
                    inFlight -= 1
                }
            }
            for await (c, s) in group {
                if c { created += 1 }
                if s { sent += 1 }
            }
        }
        return (created, sent)
    }
}

// ==========================================
// MARK: - APP ENTRY POINT
// ==========================================
@main
struct SpamDiscordApp: App {
    @StateObject private var app = AppState()
    @StateObject private var bot = BotManager()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(app)
                .environmentObject(bot)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            SpamView()
                .tabItem { Label("Spam", systemImage: "paperplane.fill") }
            TokenListView()
                .tabItem { Label("Tokens", systemImage: "person.2.fill") }
            BotNukeView()
                .tabItem { Label("Bot Nuke", systemImage: "server.rack") }
        }
        .tint(.indigo)
    }
}

// ==========================================
// MARK: - EMPTY STATE VIEW
// ==========================================
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: systemImage)
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text(title).font(.title2).bold()
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// ==========================================
// MARK: - TOKEN VIEWS
// ==========================================
struct TokenListView: View {
    @EnvironmentObject var app: AppState
    @State private var showAddSheet = false
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            Group {
                if app.tokens.isEmpty {
                    EmptyStateView(title: "Chưa có Token",
                                   systemImage: "key.slash",
                                   description: "Vui lòng thêm token để sử dụng app.")
                } else {
                    List {
                        Section(header: Text("Danh sách tài khoản")) {
                            ForEach(app.tokens) { token in
                                Button {
                                    app.setActiveToken(token)
                                } label: {
                                    HStack(spacing: 12) {
                                        if let url = token.avatarURL {
                                            AsyncImage(url: url) { img in
                                                img.resizable().scaledToFill()
                                            } placeholder: {
                                                Circle().fill(Color.gray.opacity(0.3))
                                            }
                                            .frame(width: 45, height: 45)
                                            .clipShape(Circle())
                                        } else {
                                            Image(systemName: "person.circle.fill")
                                                .resizable().frame(width: 45, height: 45)
                                                .foregroundStyle(.gray)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(token.username).font(.headline)
                                            Text(token.isValid ? "Live" : "Die")
                                                .font(.caption).bold()
                                                .foregroundStyle(token.isValid ? .green : .red)
                                        }
                                        Spacer()
                                        if app.activeToken?.id == token.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.indigo)
                                                .font(.title3)
                                        }
                                    }
                                    .padding(.vertical, 4)
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
                        Button("Thêm bằng tay", systemImage: "keyboard") { showAddSheet = true }
                        Button("Nhập từ File .txt", systemImage: "doc.text") { showImport = true }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
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
                    ProgressView("Đang check Token...")
                        .padding()
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
                Section(header: Text("Nhập Token"),
                        footer: Text("Hệ thống sẽ tự động kiểm tra token sống hay chết trước khi lưu.")) {
                    TextField("Dán token...", text: $tokenInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Thêm Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        Task {
                            await app.addToken(tokenInput)
                            dismiss()
                        }
                    }
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

    var filteredGuilds: [Guild] {
        searchText.isEmpty ? app.guilds :
            app.guilds.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if app.activeToken == nil {
                    EmptyStateView(title: "Chưa chọn Token",
                                   systemImage: "exclamationmark.triangle",
                                   description: "Vào tab Tokens để thêm và chọn tài khoản.")
                } else if app.isLoading {
                    ProgressView("Đang tải Server...")
                } else {
                    List(filteredGuilds) { guild in
                        NavigationLink(value: guild) {
                            HStack {
                                if let icon = guild.icon,
                                   let url = URL(string: "https://cdn.discordapp.com/icons/\(guild.id)/\(icon).png?size=64") {
                                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                        placeholder: { Circle().fill(.gray) }
                                        .frame(width: 35, height: 35).clipShape(Circle())
                                } else {
                                    Circle().fill(.gray.opacity(0.3)).frame(width: 35, height: 35)
                                }
                                Text(guild.name).fontWeight(.medium)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Tìm Server...")
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
        let sections = app.groupedChannels()
        if searchText.isEmpty { return sections }
        return sections.compactMap { section in
            let filteredItems = section.items.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
            }
            return filteredItems.isEmpty ? nil : (section.category, filteredItems)
        }
    }

    var body: some View {
        Group {
            if app.isLoading { ProgressView() }
            else {
                List {
                    ForEach(filteredSections, id: \.category?.id) { sec in
                        Section(header: Text(sec.category?.displayName.uppercased() ?? "KHÁC")
                                    .font(.caption).bold()) {
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

struct SendView: View {
    @EnvironmentObject var app: AppState
    let channel: Channel
    @State private var showImport = false
    @State private var showErrorAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "number.circle.fill")
                        .font(.title)
                        .foregroundStyle(.indigo)
                    Text(channel.displayName).font(.title2.bold())
                    Spacer()
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(15)

                VStack(alignment: .leading, spacing: 15) {
                    Text("CẤU HÌNH").font(.caption).bold().foregroundStyle(.secondary)

                    Toggle("Tag User ID", isOn: $app.useTag).tint(.indigo)
                    if app.useTag {
                        TextField("Nhập User ID (dãy số)", text: $app.targetUserId)
                            .keyboardType(.numberPad)
                            .padding(10)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(8)
                    }

                    Divider()

                    HStack {
                        Toggle("Thêm '>'", isOn: $app.addPrefix).tint(.indigo)
                        Toggle("Thêm '#'", isOn: $app.addSuffix).tint(.indigo)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Delay:")
                            Spacer()
                            Text("\(String(format: "%.1f", app.delaySeconds)) giây")
                                .bold()
                                .foregroundStyle(app.delaySeconds < 1.0 ? .red : .indigo)
                        }
                        Slider(value: $app.delaySeconds, in: 0.1...5.0, step: 0.1).tint(.indigo)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(15)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("NỘI DUNG TIN NHẮN").font(.caption).bold().foregroundStyle(.secondary)
                        Spacer()
                        Button(action: { showImport = true }) {
                            Label("Import File", systemImage: "doc.badge.plus")
                                .font(.caption).bold()
                        }
                    }

                    ZStack(alignment: .topTrailing) {
                        TextEditor(text: $app.inputText)
                            .frame(minHeight: 150)
                            .padding(8)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(10)
                            .onChange(of: app.inputText) { _ in app.parseDirectInput() }

                        if !app.inputText.isEmpty {
                            Button(action: { app.inputText = ""; app.parseDirectInput() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.gray)
                                    .padding(12)
                            }
                        }
                    }

                    if !app.messages.isEmpty {
                        Text("Đã nhận diện: \(app.messages.count) dòng")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(15)

                if app.isSending {
                    VStack(spacing: 15) {
                        ProgressView().scaleEffect(1.5).tint(.indigo).padding(.top)
                        Text("Đang gửi vô hạn...").font(.headline)
                        Text("Tổng đã gửi: \(app.totalSent)").font(.subheadline).foregroundStyle(.secondary)

                        Text(app.currentMessageStr)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(2)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)

                        if let error = app.lastError {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }

                        Button(action: { app.stopSending() }) {
                            Text("DỪNG LẠI").bold().frame(maxWidth: .infinity).padding()
                        }
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(15)
                } else {
                    Button(action: { app.startSending(channel: channel) }) {
                        Text("BẮT ĐẦU GỬI").bold().frame(maxWidth: .infinity).padding()
                    }
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                    .disabled(app.messages.isEmpty || (app.useTag && app.targetUserId.isEmpty))
                    .opacity((app.messages.isEmpty || (app.useTag && app.targetUserId.isEmpty)) ? 0.5 : 1.0)
                }
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Gửi tin nhắn")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Xong") { app.hideKeyboard() }
            }
        }
        .sheet(isPresented: $showImport) {
            DocumentPicker(contentTypes: [.item]) { url in
                app.parseFile(url: url)
                if app.lastError != nil { showErrorAlert = true }
            }
        }
        .alert("Lỗi Import File", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(app.lastError ?? "Không thể đọc file. Vui lòng thử lại.")
        }
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
                if bot.config == nil {
                    BotSetupView()
                } else if bot.isNuking {
                    BotNukeRunningView()
                } else if let g = selectedGuild {
                    NukeOptionsView(guild: g, selectedGuild: $selectedGuild)
                } else {
                    BotGuildListView(selectedGuild: $selectedGuild)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var navTitle: String {
        if bot.config == nil { return "Bot Nuke" }
        if bot.isNuking { return "Đang Nuke..." }
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
                Image(systemName: "server.rack")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)
                    .padding(.top, 30)

                Text("BOT NUKE")
                    .font(.largeTitle.bold())
                Text("Dùng Bot Token để nuke server.\n(Khác với User Token ở tab Tokens)")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    Text("BOT TOKEN").font(.caption).bold().foregroundStyle(.secondary)
                    SecureField("MTU3MDIwMjQ0...", text: $tokenInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(10)
                        .font(.system(.body, design: .monospaced))

                    Text("Vào Discord Developer Portal → Applications → Bot → Reset Token")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(15)

                if let err = bot.tokenError {
                    Text(err).font(.caption).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(action: {
                    Task { await bot.setToken(tokenInput) }
                }) {
                    HStack {
                        if bot.isCheckingToken {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.shield.fill")
                        }
                        Text(bot.isCheckingToken ? "Đang kiểm tra..." : "KẾT NỐI BOT")
                            .bold()
                    }
                    .frame(maxWidth: .infinity).padding()
                }
                .background(Color.red)
                .foregroundStyle(.white)
                .cornerRadius(12)
                .disabled(tokenInput.isEmpty || bot.isCheckingToken)
                .opacity(tokenInput.isEmpty ? 0.5 : 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("📋 YÊU CẦU").font(.caption).bold().foregroundStyle(.secondary)
                    Label("Bot đã vào server cần nuke", systemImage: "checkmark.circle")
                    Label("Bật Server Members Intent (Developer Portal)", systemImage: "checkmark.circle")
                    Label("Bot có quyền Administrator", systemImage: "checkmark.circle")
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding()
        }
    }
}

struct BotGuildListView: View {
    @EnvironmentObject var bot: BotManager
    @Binding var selectedGuild: Guild?
    @State private var searchText = ""

    var filtered: [Guild] {
        searchText.isEmpty ? bot.botGuilds :
            bot.botGuilds.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let cfg = bot.config {
                HStack(spacing: 12) {
                    if let url = cfg.avatarURL {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                        placeholder: { Circle().fill(.gray.opacity(0.3)) }
                            .frame(width: 42, height: 42).clipShape(Circle())
                    } else {
                        Image(systemName: "cpu").font(.title2).frame(width: 42, height: 42)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cfg.displayName).font(.subheadline.bold())
                        Text("Bot ID: \(cfg.userId)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Đổi Bot Token", systemImage: "key") { bot.removeConfig() }
                        Button("Refresh Server List", systemImage: "arrow.clockwise") {
                            Task { await bot.loadGuilds() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
            }

            if bot.isLoadingGuilds {
                ProgressView("Đang tải server...").padding(.top, 40)
                Spacer()
            } else if bot.botGuilds.isEmpty {
                EmptyStateView(title: "Bot chưa vào server nào",
                               systemImage: "server.rack",
                               description: "Mời bot vào server trước rồi bấm Refresh.")
            } else {
                List(filtered) { g in
                    Button {
                        selectedGuild = g
                    } label: {
                        HStack(spacing: 12) {
                            if let icon = g.icon,
                               let url = URL(string: "https://cdn.discordapp.com/icons/\(g.id)/\(icon).png?size=64") {
                                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                placeholder: { Circle().fill(.gray.opacity(0.3)) }
                                    .frame(width: 42, height: 42).clipShape(Circle())
                            } else {
                                Circle().fill(.gray.opacity(0.3)).frame(width: 42, height: 42)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name).font(.headline)
                                Text(g.id).font(.caption2).foregroundStyle(.secondary).monospaced()
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .searchable(text: $searchText, prompt: "Tìm server...")
            }
        }
    }
}

struct NukeOptionsView: View {
    @EnvironmentObject var bot: BotManager
    let guild: Guild
    @Binding var selectedGuild: Guild?
    @State private var options = NukeConfig()

    var canRun: Bool {
        options.doMassBan || options.doDeleteChannels ||
        options.doCreateRoles || options.doCreateChannels || options.doRenameGuild
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("HÀNH ĐỘNG KHÔNG THỂ HOÀN TÁC!")
                        .font(.caption.bold())
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(10)

                HStack(spacing: 12) {
                    if let icon = guild.icon,
                       let url = URL(string: "https://cdn.discordapp.com/icons/\(guild.id)/\(icon).png?size=64") {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                        placeholder: { Circle().fill(.gray.opacity(0.3)) }
                            .frame(width: 48, height: 48).clipShape(Circle())
                    } else {
                        Circle().fill(.gray.opacity(0.3)).frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guild.name).font(.headline)
                        Text(guild.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        selectedGuild = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary).font(.title3)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                toggleSection(title: "Mass Ban", icon: "hammer.fill", color: .red,
                              isOn: $options.doMassBan) {
                    Text("Ban mọi member có role thấp hơn bot (trừ owner + bot khác).")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                toggleSection(title: "Xóa kênh", icon: "trash.fill", color: .orange,
                              isOn: $options.doDeleteChannels) {
                    Text("Xóa TOÀN BỘ kênh hiện có trong server.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                toggleSection(title: "Tạo kênh + Spam", icon: "plus.rectangle.on.rectangle",
                              color: .green, isOn: $options.doCreateChannels) {
                    VStack(spacing: 10) {
                        TextField("Tên kênh", text: $options.channelName)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Text("Số kênh:").font(.subheadline)
                            Spacer()
                            Stepper("\(options.channelCount)", value: $options.channelCount, in: 1...500)
                        }
                        TextField("Nội dung tin nhắn", text: $options.messageContent, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...5)
                        Toggle("Tag @everyone", isOn: $options.tagEveryone).tint(.green)
                    }
                }

                toggleSection(title: "Tạo Role", icon: "star.fill", color: .purple,
                              isOn: $options.doCreateRoles) {
                    VStack(spacing: 10) {
                        TextField("Tên role", text: $options.roleName)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Text("Số role:").font(.subheadline)
                            Spacer()
                            Stepper("\(options.roleCount)", value: $options.roleCount, in: 1...500)
                        }
                    }
                }

                toggleSection(title: "Đổi tên Server", icon: "pencil", color: .blue,
                              isOn: $options.doRenameGuild) {
                    TextField("Tên server mới", text: $options.newGuildName)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    Task { await bot.runNuke(guild: guild, options: options) }
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.octagon.fill")
                        Text("BẮT ĐẦU NUKE").bold()
                    }
                    .frame(maxWidth: .infinity).padding()
                }
                .background(canRun ? Color.red : Color.gray)
                .foregroundStyle(.white)
                .cornerRadius(12)
                .disabled(!canRun)
                .padding(.top, 8)

                if !canRun {
                    Text("Chọn ít nhất 1 chức năng").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    @ViewBuilder
    func toggleSection<Content: View>(
        title: String, icon: String, color: Color,
        isOn: Binding<Bool>, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: icon).foregroundStyle(color).font(.title3)
                    .frame(width: 24)
                Text(title).font(.headline)
                Spacer()
                Toggle("", isOn: isOn).labelsHidden().tint(color)
            }
            .padding()

            if isOn.wrappedValue {
                Divider()
                content()
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct BotNukeRunningView: View {
    @EnvironmentObject var bot: BotManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                statBox("Ban", "\(bot.banSuccess)", .red)
                statBox("Xóa", "\(bot.channelsDeleted)", .orange)
                statBox("Tạo", "\(bot.channelsCreated)", .green)
                statBox("Role", "\(bot.rolesCreated)", .purple)
            }
            .padding()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(bot.nukeLog.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding()
                }
                .onChange(of: bot.nukeLog.count) { _ in
                    if let last = bot.nukeLog.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)

            Button {
                bot.stopNuke()
            } label: {
                HStack {
                    Image(systemName: "stop.circle.fill")
                    Text("DỪNG LẠI").bold()
                }
                .frame(maxWidth: .infinity).padding()
            }
            .background(Color.red)
            .foregroundStyle(.white)
            .cornerRadius(12)
            .padding()
        }
    }

    func statBox(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }
}