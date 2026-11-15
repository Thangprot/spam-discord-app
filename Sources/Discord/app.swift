import SwiftUI
import Foundation
import Security
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import CryptoKit
import MediaPlayer
import UserNotifications

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
// MARK: - KEYCHAIN HELPER
// ==========================================
class KeychainHelper {
    static let standard = KeychainHelper()
    private init() {}

    func save(_ data: Data, service: String, account: String) {
        let query = [
            kSecValueData: data,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary
        SecItemDelete(query)
        SecItemAdd(query, nil)
    }

    func read(service: String, account: String) -> Data? {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true
        ] as CFDictionary
        var result: AnyObject?
        SecItemCopyMatching(query, &result)
        return (result as? Data)
    }

    func delete(service: String, account: String) {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword
        ] as CFDictionary
        SecItemDelete(query)
    }

    func saveString(_ value: String, forKey key: String) {
        if let data = value.data(using: .utf8) {
            save(data, service: Bundle.main.bundleIdentifier ?? "app", account: key)
        }
    }

    func readString(forKey key: String) -> String? {
        if let data = read(service: Bundle.main.bundleIdentifier ?? "app", account: key) {
            return String(data: data, encoding: .utf8)
        }
        return nil
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
// MARK: - NOW PLAYING HELPER
// ==========================================
final class NowPlayingHelper {
    static let shared = NowPlayingHelper()
    private init() {}
    private var isActive = false
    private var onStopCB: (() -> Void)?

    private lazy var defaultArtwork: MPMediaItemArtwork? = {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor(red: 0.08, green: 0.08, blue: 0.16, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let config = UIImage.SymbolConfiguration(pointSize: 300, weight: .bold)
            if let symbol = UIImage(systemName: "flame.fill", withConfiguration: config)?.withTintColor(.red, renderingMode: .alwaysOriginal) {
                let symbolSize = symbol.size
                let origin = CGPoint(x: (size.width - symbolSize.width) / 2, y: (size.height - symbolSize.height) / 2)
                symbol.draw(at: origin)
            }
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }()

    func start(onStop: (() -> Void)? = nil) {
        isActive = true
        onStopCB = onStop
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.isEnabled = false
        cc.nextTrackCommand.isEnabled = false
        cc.previousTrackCommand.isEnabled = false
        cc.togglePlayPauseCommand.isEnabled = false
        cc.pauseCommand.removeTarget(nil)
        cc.stopCommand.removeTarget(nil)
        if onStop != nil {
            cc.pauseCommand.isEnabled = true
            cc.stopCommand.isEnabled = true
            let handler: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] _ in
                DispatchQueue.main.async { self?.onStopCB?() }
                return .success
            }
            cc.pauseCommand.addTarget(handler: handler)
            cc.stopCommand.addTarget(handler: handler)
        } else {
            cc.pauseCommand.isEnabled = false
            cc.stopCommand.isEnabled = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.update(title: "Quoc Thang Tools", detail: "Đang chuẩn bị...")
        }
    }

    func update(title: String, detail: String) {
        guard isActive else { return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = detail
        info[MPMediaItemPropertyAlbumTitle] = "Quoc Thang Tools"
        info[MPMediaItemPropertyPlaybackDuration] = 0
        info[MPMediaItemPropertyArtwork] = defaultArtwork
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if #available(iOS 16.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .playing
        }
    }

    func stop() {
        isActive = false
        onStopCB = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if #available(iOS 16.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
}

// ==========================================
// MARK: - BACKGROUND (AVAudioEngine)
// ==========================================
class BackgroundManager {
    static let shared = BackgroundManager()
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    func start() {
        if bgTask == .invalid {
            bgTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                self?.stop()
            }
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch { }
        if engine?.isRunning == true { return }
        let eng = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buf in abl {
                let ptr = buf.mData?.assumingMemoryBound(to: Float.self)
                for i in 0..<Int(frameCount) { ptr?[i] = 0.00001 }
            }
            return noErr
        }
        eng.attach(node)
        eng.connect(node, to: eng.mainMixerNode, format: format)
        eng.mainMixerNode.outputVolume = 0.01
        do {
            try eng.start()
            engine = eng
            sourceNode = node
        } catch { }
    }

    func stop() {
        engine?.stop()
        engine = nil
        sourceNode = nil
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}

// ==========================================
// MARK: - DISCORD CLIENT
// ==========================================
class DiscordClient {
    let token: String; let session: URLSession
    init(token: String) {
        self.token = token
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
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
        req.timeoutInterval = 20
        req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        var attempts = 0
        while attempts < 6 {
            attempts += 1
            let (d, r) = try await session.data(for: req)
            if let h = r as? HTTPURLResponse, h.statusCode == 429,
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let retry = j["retry_after"] as? Double {
                let wait = min(max(retry, 0.2), 10.0) + 0.3
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                continue
            }
            try check(r, d)
            return
        }
        throw NSError(domain: "Discord", code: 429,
                      userInfo: [NSLocalizedDescriptionKey: "Rate limit kéo dài"])
    }
}

// ==========================================
// MARK: - APP STATE (SPAM)
// ==========================================
@MainActor
class AppState: ObservableObject {
    @Published var tokens: [TokenInfo] = [] { didSet { saveTokens() } }
    @Published var activeToken: TokenInfo? = nil
    @Published var selectedTokenIds: Set<UUID> = []
    @Published var isCheckingToken = false
    @Published var guilds: [Guild] = []
    @Published var multiGuilds: [Guild] = []
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
    @Published var tokenSendCount: [UUID: Int] = [:]
    @Published var lastError: String?

    private var isCancelled = false
    private var sendTask: Task<Void, Never>?
    private var lastNPUpdate = Date.distantPast

    init() { loadTokens() }
    private func saveTokens() {
        if let e = try? JSONEncoder().encode(tokens) { UserDefaults.standard.set(e, forKey: "SavedTokens") }
    }
    private func loadTokens() {
        if let d = UserDefaults.standard.data(forKey: "SavedTokens"),
           let s = try? JSONDecoder().decode([TokenInfo].self, from: d) {
            tokens = s
            if let a = s.first(where: { $0.isValid }) {
                activeToken = a
                selectedTokenIds = [a.id]
                Task { await recomputeMultiGuilds() }
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
            tokens.append(t)
            if activeToken == nil {
                activeToken = t
                selectedTokenIds.insert(t.id)
            }
            await recomputeMultiGuilds()
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
    func setActiveToken(_ t: TokenInfo) {
        guard t.isValid else { return }
        activeToken = t
        selectedTokenIds = [t.id]
        Task { await recomputeMultiGuilds() }
    }
    func toggleTokenSelection(_ t: TokenInfo) {
        guard t.isValid else { return }
        if selectedTokenIds.contains(t.id) {
            selectedTokenIds.remove(t.id)
        } else {
            selectedTokenIds.insert(t.id)
        }
        activeToken = tokens.first(where: { selectedTokenIds.contains($0.id) })
        Task { await recomputeMultiGuilds() }
    }
    func deleteToken(at off: IndexSet) {
        let deleted = off.map { tokens[$0] }
        if let a = activeToken, deleted.contains(where: { $0.id == a.id }) {
            activeToken = nil; guilds = []; multiGuilds = []
        }
        selectedTokenIds.subtract(deleted.map { $0.id })
        tokens.remove(atOffsets: off)
        Task { await recomputeMultiGuilds() }
    }
    func loadGuilds() async { await recomputeMultiGuilds() }

    func recomputeMultiGuilds() async {
        let selected = tokens.filter { selectedTokenIds.contains($0.id) && $0.isValid }
        if selected.isEmpty {
            multiGuilds = []; guilds = []; return
        }
        isLoading = true
        defer { isLoading = false }

        var sets: [Set<String>] = []
        var guildMap: [String: Guild] = [:]

        await withTaskGroup(of: [Guild]?.self) { group in
            for t in selected {
                group.addTask {
                    for attempt in 0..<3 {
                        do { return try await DiscordClient(token: t.token).getAllGuilds() }
                        catch {
                            if attempt < 2 { try? await Task.sleep(nanoseconds: 500_000_000); continue }
                            return nil
                        }
                    }
                    return nil
                }
            }
            for await gs in group {
                guard let gs = gs else { continue }
                sets.append(Set(gs.map { $0.id }))
                for g in gs { guildMap[g.id] = g }
            }
        }

        if sets.isEmpty { multiGuilds = []; guilds = []; return }

        if selected.count == 1, let firstSet = sets.first {
            let single = firstSet.compactMap { guildMap[$0] }.sorted { $0.name < $1.name }
            guilds = single; multiGuilds = single
            return
        }

        var inter = sets[0]
        for s in sets.dropFirst() { inter.formIntersection(s) }
        let result = inter.compactMap { guildMap[$0] }.sorted { $0.name < $1.name }
        multiGuilds = result; guilds = result
    }

    func loadChannels(for g: Guild) async {
        let selected = tokens.filter { selectedTokenIds.contains($0.id) && $0.isValid }
        guard let first = selected.first else { return }
        isLoading = true
        do {
            let all = try await DiscordClient(token: first.token).getAllChannels(guildId: g.id)
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
        let selectedTokens = tokens.filter { selectedTokenIds.contains($0.id) && $0.isValid }
        guard !selectedTokens.isEmpty, !messages.isEmpty else { return }
        if useTag && targetUserId.isEmpty { return }

        isSending = true
        isCancelled = false
        totalSent = 0
        lastError = nil
        tokenSendCount = Dictionary(uniqueKeysWithValues: selectedTokens.map { ($0.id, 0) })
        let channelId = channel.id
        let totalTokens = selectedTokens.count

        BackgroundManager.shared.start()
        NowPlayingHelper.shared.start(onStop: { [weak self] in
            Task { @MainActor in self?.stopSending() }
        })
        updateNowPlaying(force: true)

        sendTask = Task { [weak self] in
            guard let self = self else { return }
            await withTaskGroup(of: Void.self) { group in
                for (index, token) in selectedTokens.enumerated() {
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        await self.spamLoop(token: token, channelId: channelId, startIndex: index, step: totalTokens)
                    }
                }
            }
            self.isSending = false
            self.currentMessageStr = ""
            BackgroundManager.shared.stop()
            NowPlayingHelper.shared.stop()
        }
    }

    private func spamLoop(token: TokenInfo, channelId: String, startIndex: Int, step: Int) async {
        var client = DiscordClient(token: token.token)
        var i = startIndex
        var consecutiveErrors = 0
        var perTokenTotal = 0

        while !isCancelled && !Task.isCancelled {
            let m = messages[i % messages.count]
            var p = ""
            if addPrefix { p += "> " }
            if addSuffix { p += "# " }
            var fc = p + m.body
            if useTag { fc += " <@\(targetUserId)>" }

            do {
                try await client.sendMessage(channelId: channelId, content: fc)
                consecutiveErrors = 0
                totalSent += 1
                perTokenTotal += 1
                tokenSendCount[token.id] = perTokenTotal
                currentMessageStr = fc
                updateNowPlaying()
            } catch {
                consecutiveErrors += 1
                if consecutiveErrors >= 2 {
                    do {
                        _ = try await DiscordClient(token: token.token).validateToken()
                        client = DiscordClient(token: token.token)
                        consecutiveErrors = 0
                        try? await Task.sleep(nanoseconds: 800_000_000)
                    } catch {
                        return
                    }
                } else {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
                continue
            }

            i += step
            let d = max(0.1, delaySeconds + Double.random(in: -0.3...0.3) * delaySeconds)
            do { try await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000)) } catch { break }
        }
    }

    func stopSending() {
        isCancelled = true
        sendTask?.cancel()
        sendTask = nil
        isSending = false
        BackgroundManager.shared.stop()
        NowPlayingHelper.shared.stop()
    }

    private func updateNowPlaying(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastNPUpdate) >= 0.5 else { return }
        lastNPUpdate = now
        NowPlayingHelper.shared.update(
            title: "Quoc Thang Spam",
            detail: "\(totalSent) tin | \(selectedTokenIds.count) token"
        )
    }

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
        NowPlayingHelper.shared.start(onStop: { [weak self] in
            Task { @MainActor in self?.stopNuke() }
        })
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
            NowPlayingHelper.shared.update(
                title: "Bot Nuke · \(step.rawValue)",
                detail: "\(banSuccess) ban | \(channelsDeleted) xoá | \(channelsCreated) tạo"
            )
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
        NowPlayingHelper.shared.stop()
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
        NowPlayingHelper.shared.start(onStop: { [weak self] in
            Task { @MainActor in self?.stop() }
        })
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
            NowPlayingHelper.shared.update(
                title: "User Nuke · \(step.rawValue)",
                detail: "\(banSuccess) ban | \(channelsDeleted) xoá | \(channelsCreated) tạo"
            )
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
        NowPlayingHelper.shared.stop()
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
    let valid: Bool?
    let expiresAt: Int64?
    let message: String?
    let error: String?
    enum CodingKeys: String, CodingKey {
        case valid, message, error
        case expiresAt = "expires_at"
    }
}

struct LicenseValidationResponse: Codable {
    let valid: Bool?
    let expiresAt: Int64?
    let error: String?
    enum CodingKeys: String, CodingKey {
        case valid, error
        case expiresAt = "expires_at"
    }
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
    let baseURL = "https://key.nqtaff01.workers.dev"

    private func machineID() -> String {
        let keychainKey = "QT_MachineID"
        if let savedID = KeychainHelper.standard.readString(forKey: keychainKey) { return savedID }
        let raw = "\(UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)-\(Bundle.main.bundleIdentifier ?? "app")"
        let hash = SHA256.hash(data: Data(raw.utf8))
        let newID = hash.compactMap { String(format: "%02x", $0) }.joined()
        KeychainHelper.standard.saveString(newID, forKey: keychainKey)
        return newID
    }

    func activate(key: String) async throws -> LicenseActivationResponse {
        var req = URLRequest(url: URL(string: "\(baseURL)/activate")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "license_key": key, "machine_id": machineID()
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(LicenseActivationResponse.self, from: data)
    }

    func validate(key: String) async throws -> LicenseValidationResponse {
        var req = URLRequest(url: URL(string: "\(baseURL)/validate")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "license_key": key, "machine_id": machineID()
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(LicenseValidationResponse.self, from: data)
    }
}

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    @Published var status: LicenseStatus = .notActivated
    @Published var licenseKey: String? = nil
    @Published var activatedAt: Date? = nil
    @Published var isChecking = false

    private let keyStoreKey = "QT_LicenseKey_Server"
    private let expiryStoreKey = "QT_LicenseExpiry"
    private let lastCheckKey = "QT_LicenseLastCheck"
    private let activatedStoreKey = "QT_LicenseActivatedAt"

    init() {
        self.licenseKey = KeychainHelper.standard.readString(forKey: keyStoreKey)
        if let actString = KeychainHelper.standard.readString(forKey: activatedStoreKey),
           let actDouble = Double(actString) {
            self.activatedAt = Date(timeIntervalSince1970: actDouble)
        }
        if licenseKey == nil {
            status = .notActivated
        } else if let expString = KeychainHelper.standard.readString(forKey: expiryStoreKey),
                  let expDouble = Double(expString) {
            let cachedExp = Date(timeIntervalSince1970: expDouble)
            status = Date() > cachedExp ? .expired(expiresOn: cachedExp) : .valid(expiresOn: cachedExp)
        }
        Task { @MainActor [weak self] in await self?.refreshStatus() }
    }

    func activate(key: String) async -> LicenseStatus {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { status = .invalid(reason: "Key trống"); return status }
        isChecking = true
        defer { isChecking = false }
        do {
            let res = try await LicenseAPIClient.shared.activate(key: clean)
            if res.valid == true, let expMs = res.expiresAt {
                let exp = Date(timeIntervalSince1970: Double(expMs) / 1000)
                let now = Date()
                KeychainHelper.standard.saveString(clean, forKey: keyStoreKey)
                KeychainHelper.standard.saveString("\(exp.timeIntervalSince1970)", forKey: expiryStoreKey)
                KeychainHelper.standard.saveString("\(now.timeIntervalSince1970)", forKey: lastCheckKey)
                KeychainHelper.standard.saveString("\(now.timeIntervalSince1970)", forKey: activatedStoreKey)
                licenseKey = clean; activatedAt = now
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
        guard let key = licenseKey else { status = .notActivated; return }
        isChecking = true
        defer { isChecking = false }
        do {
            let res = try await LicenseAPIClient.shared.validate(key: key)
            if res.valid == true, let expMs = res.expiresAt {
                let exp = Date(timeIntervalSince1970: Double(expMs) / 1000)
                KeychainHelper.standard.saveString("\(exp.timeIntervalSince1970)", forKey: expiryStoreKey)
                KeychainHelper.standard.saveString("\(Date().timeIntervalSince1970)", forKey: lastCheckKey)
                status = .valid(expiresOn: exp)
                return
            } else {
                status = .invalid(reason: res.error ?? "Key không hợp lệ")
                return
            }
        } catch {
            if let expString = KeychainHelper.standard.readString(forKey: expiryStoreKey),
               let expDouble = Double(expString) {
                let cachedExp = Date(timeIntervalSince1970: expDouble)
                status = Date() > cachedExp ? .expired(expiresOn: cachedExp) : .valid(expiresOn: cachedExp)
            } else {
                status = .invalid(reason: "Không kết nối được server")
            }
        }
    }

    func deactivate() {
        KeychainHelper.standard.delete(service: Bundle.main.bundleIdentifier ?? "app", account: keyStoreKey)
        KeychainHelper.standard.delete(service: Bundle.main.bundleIdentifier ?? "app", account: expiryStoreKey)
        KeychainHelper.standard.delete(service: Bundle.main.bundleIdentifier ?? "app", account: lastCheckKey)
        KeychainHelper.standard.delete(service: Bundle.main.bundleIdentifier ?? "app", account: activatedStoreKey)
        licenseKey = nil; activatedAt = nil; status = .notActivated
    }

    var isUnlocked: Bool { if case .valid = status { return true }; return false }

    var statusText: String {
        switch status {
        case .notActivated: return "Chưa kích hoạt"
        case .checking: return "Đang kiểm tra..."
        case .valid(let d): return "Còn hạn đến \(formatDate(d))"
        case .expired(let d): return "Đã hết hạn ngày \(formatDate(d))"
        case .invalid(let r): return r
        }
    }

    func formatDate(_ d: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "dd/MM/yyyy"
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
            LinearGradient(colors: [Color(red: 0.08, green: 0.08, blue: 0.16), Color.black],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)
                    VStack(spacing: 14) {
                        Image(systemName: "lock.shield.fill").font(.system(size: 80))
                            .foregroundStyle(.red).shadow(color: .red.opacity(0.4), radius: 20)
                            .onTapGesture {
                                logoTapCount += 1
                                if logoTapCount >= 7 { logoTapCount = 0; showAdminInfo = true }
                            }
                        Text("QUOC THANG TOOLS").font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.white).tracking(1.5)
                        Text("LICENSE REQUIRED").font(.caption.bold())
                            .foregroundStyle(.red.opacity(0.8)).tracking(3)
                    }
                    VStack(spacing: 14) {
                        TextField("Nhập license key...", text: $input)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced)).padding(14)
                            .background(Color.white.opacity(0.08)).foregroundStyle(.white)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .onChange(of: input) { _ in error = nil }
                        if let e = error {
                            Text(e).font(.caption).foregroundStyle(.red)
                                .multilineTextAlignment(.center).padding(.horizontal)
                        }
                        Button {
                            Task {
                                error = nil
                                let st = await license.activate(key: input)
                                switch st {
                                case .valid: error = nil
                                case .invalid(let r): error = r
                                case .expired(let d): error = "Key đã hết hạn ngày \(fmt(d))"
                                default: error = "Không thể kích hoạt"
                                }
                            }
                        } label: {
                            HStack {
                                if license.isChecking { ProgressView().tint(.white) }
                                Text(license.isChecking ? "ĐANG KIỂM TRA..." : "KÍCH HOẠT").bold()
                            }.frame(maxWidth: .infinity).padding()
                        }
                        .background(input.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.indigo)
                        .foregroundStyle(.white).cornerRadius(10)
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || license.isChecking)
                    }.padding(.horizontal, 30)

                    if case .expired(let d) = license.status {
                        Text("⚠️ Key trước đó đã hết hạn ngày \(fmt(d))")
                            .font(.caption).foregroundStyle(.orange)
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }
                    Spacer(minLength: 20)
                    Text("v1.0").font(.caption2).foregroundStyle(.gray.opacity(0.4))
                }.padding(.vertical, 20)
            }
        }
        .sheet(isPresented: $showAdminInfo) {
            LicenseAdminInfoView().environmentObject(license)
        }
    }

    private func fmt(_ d: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "dd/MM/yyyy"
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
                    Text("THÔNG TIN ADMIN").font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Endpoint").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(LicenseAPIClient.shared.baseURL)
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)

                    if let k = license.licenseKey {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("KEY HIỆN TẠI").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(k).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text(license.statusText).font(.caption2).foregroundStyle(.green)
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)
                    }

                    Button(role: .destructive) {
                        license.deactivate(); dismiss()
                    } label: {
                        Label("Xoá key hiện tại", systemImage: "trash").frame(maxWidth: .infinity).padding(10)
                    }
                    .background(Color.red.opacity(0.15)).foregroundStyle(.red).cornerRadius(8)
                }.padding()
            }
            .navigationTitle("Admin Info").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
            }
        }
    }
}

// ==========================================
// MARK: - ABOUT / INFO VIEW
// ==========================================
struct AboutView: View {
    @EnvironmentObject var license: LicenseManager
    @State private var showFullKey = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LICENSE INFORMATION").font(.caption.bold()).foregroundStyle(.secondary)
                        HStack {
                            Text("License Key").font(.subheadline)
                            Spacer()
                            Text(maskedKey).font(.system(.subheadline, design: .monospaced)).foregroundStyle(.indigo)
                            Toggle("", isOn: $showFullKey).labelsHidden().tint(.indigo).scaleEffect(0.8)
                        }
                        Divider()
                        HStack {
                            Text("Activated On").font(.subheadline)
                            Spacer()
                            Text(license.activatedAt != nil ? license.formatDate(license.activatedAt!) : "N/A")
                                .font(.subheadline.bold()).foregroundStyle(.secondary)
                        }
                        Divider()
                        HStack {
                            Text("Expires On").font(.subheadline)
                            Spacer()
                            if case .valid(let exp) = license.status {
                                Text(license.formatDate(exp)).font(.subheadline.bold()).foregroundStyle(.green)
                            } else if case .expired(let exp) = license.status {
                                Text(license.formatDate(exp)).font(.subheadline.bold()).foregroundStyle(.red)
                            } else {
                                Text("N/A").font(.subheadline.bold()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                            Text("About This App").font(.headline)
                        }
                        Text("Quoc Thang Tools is a comprehensive utility suite designed for Discord power users. It provides advanced features such as Mass Spamming, Server Nuking, Mass Banning, and Voice Room integration. Our tools are optimized for both iOS and Android platforms, ensuring smooth and efficient performance.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "crown.fill").foregroundStyle(.yellow)
                            Text("Admin Services").font(.headline)
                        }
                        Text("The administrator specializes in developing and providing custom tools for both Discord PC and Mobile. Whether you need account registration tools, server nukers, mass DM tools, or any other automation, we can build it for you.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Divider()
                        HStack {
                            Image(systemName: "message.fill").foregroundStyle(.indigo)
                            Text("Contact Admin (Discord):").font(.subheadline.bold())
                            Spacer()
                            Text("@thaitu_thanhhoa")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.indigo).textSelection(.enabled)
                        }
                        .padding().background(Color.indigo.opacity(0.1)).cornerRadius(10)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)

                    Text("Version 1.0.0").font(.caption).foregroundStyle(.tertiary).padding(.top)
                }.padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Information").navigationBarTitleDisplayMode(.inline)
        }
    }

    private var maskedKey: String {
        guard let key = license.licenseKey else { return "No Key" }
        if showFullKey { return key }
        let parts = key.split(separator: "-")
        if parts.count == 3 { return "\(parts[0])-***-\(parts[2])" }
        return "\(key.prefix(4))***\(key.suffix(4))"
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
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
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
                    EmptyStateView(title: "Chưa có Token", systemImage: "key.slash",
                                   description: "Thêm token để bắt đầu.")
                } else {
                    List {
                        Section(header: Text("Danh sách (\(app.selectedTokenIds.count) đã chọn)")) {
                            ForEach(app.tokens) { t in
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
                                    if t.isValid {
                                        Button { app.toggleTokenSelection(t) } label: {
                                            Image(systemName: app.selectedTokenIds.contains(t.id)
                                                  ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(.indigo).font(.title3)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
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

    var displayedGuilds: [Guild] { app.multiGuilds }
    var filtered: [Guild] {
        searchText.isEmpty
            ? displayedGuilds
            : displayedGuilds.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if app.selectedTokenIds.count >= 2 {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                        Text("\(app.selectedTokenIds.count) token · Server chung: \(app.multiGuilds.count)")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.indigo)
                    .padding(8).frame(maxWidth: .infinity)
                    .background(Color.indigo.opacity(0.1)).cornerRadius(8)
                    .padding(.horizontal, 12).padding(.top, 4)
                }

                Group {
                    if app.selectedTokenIds.isEmpty {
                        EmptyStateView(title: "Chưa chọn Token", systemImage: "exclamationmark.triangle",
                                       description: "Vào tab Tokens để chọn 1 hoặc nhiều token.")
                    } else if app.isLoading {
                        ProgressView("Đang tải...")
                    } else if filtered.isEmpty {
                        EmptyStateView(title: "Không có server chung", systemImage: "server.rack",
                                       description: "Các token được chọn không cùng ở server nào.")
                    } else {
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
            }
            .navigationTitle("Chọn Server")
            .navigationDestination(for: Guild.self) { ChannelListView(guild: $0) }
            .refreshable { await app.recomputeMultiGuilds() }
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
                        Text("Đang gửi đa token...").font(.headline)
                        Text("Tổng: \(app.totalSent)").font(.subheadline).foregroundStyle(.secondary)

                        if app.selectedTokenIds.count >= 2 {
                            VStack(spacing: 6) {
                                ForEach(app.tokens.filter { app.selectedTokenIds.contains($0.id) }, id: \.id) { t in
                                    HStack {
                                        Text(t.username).font(.caption).lineLimit(1)
                                        Spacer()
                                        Text("\(app.tokenSendCount[t.id] ?? 0)").font(.caption.bold()).foregroundStyle(.indigo)
                                    }
                                }
                            }
                            .padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)
                        }

                        if !app.currentMessageStr.isEmpty {
                            Text("Tin cuối: \(app.currentMessageStr.prefix(80))")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                .padding(.horizontal)
                        }

                        Button { app.stopSending() } label: {
                            Label("Dừng gửi", systemImage: "stop.circle.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .background(Color.red).foregroundStyle(.white).cornerRadius(10)
                        .padding(.horizontal)
                    }.padding(.vertical)
                } else {
                    Button {
                        guard !app.messages.isEmpty else { showErr = true; return }
                        app.startSending(channel: channel)
                    } label: {
                        Label("Bắt đầu gửi", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .background(Color.indigo).foregroundStyle(.white).cornerRadius(10)
                }
            }
            .padding()
        }
        .navigationTitle("Gửi tin nhắn")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImport) {
            DocumentPicker(contentTypes: [.text]) { u in app.parseFile(url: u) }
        }
        .alert("Lỗi", isPresented: $showErr) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Chưa có nội dung tin nhắn.")
        }
    }
}

// ==========================================
// MARK: - BOT NUKE VIEW
// ==========================================
struct BotNukeView: View {
    @EnvironmentObject var bot: BotManager
    @State private var tokenInput = ""
    @State private var selectedGuild: Guild? = nil
    @State private var cfg = NukeConfig()
    @State private var showConfig = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    botCard
                    if bot.config != nil { guildCard; nukeConfigCard; statsCard; logCard }
                }.padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Bot Nuke")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var botCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "key.fill").foregroundStyle(.indigo)
                Text("Bot Token").font(.headline)
                Spacer()
                if bot.config != nil {
                    Button(role: .destructive) { bot.removeConfig(); selectedGuild = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    }
                }
            }
            if let c = bot.config {
                HStack {
                    if let url = c.avatarURL {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() }
                        placeholder: { Circle().fill(.gray) }.frame(width: 40, height: 40).clipShape(Circle())
                    }
                    VStack(alignment: .leading) {
                        Text(c.displayName).bold()
                        Text("Bot · \(c.userId)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                TextField("Dán bot token...", text: $tokenInput)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(10).background(Color(UIColor.tertiarySystemBackground)).cornerRadius(8)
                Button {
                    Task { await bot.setToken(tokenInput); tokenInput = "" }
                } label: {
                    HStack {
                        if bot.isCheckingToken { ProgressView().tint(.white) }
                        Text(bot.isCheckingToken ? "Đang check..." : "Lưu Bot Token")
                    }.frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .background(Color.indigo).foregroundStyle(.white).cornerRadius(8)
                .disabled(tokenInput.isEmpty || bot.isCheckingToken)
                if let err = bot.tokenError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)
    }

    private var guildCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "server.rack").foregroundStyle(.indigo)
                Text("Chọn Server").font(.headline)
                Spacer()
                if bot.isLoadingGuilds { ProgressView().scaleEffect(0.7) }
            }
            if bot.botGuilds.isEmpty {
                Text("Không có server").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Server", selection: $selectedGuild) {
                    Text("— Chọn —").tag(Guild?.none)
                    ForEach(bot.botGuilds) { g in Text(g.name).tag(Optional(g)) }
                }.pickerStyle(.menu).tint(.indigo)
            }
        }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)
    }

    private var nukeConfigCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(.red)
                Text("Cấu hình Nuke").font(.headline)
                Spacer()
                Button("Sửa") { showConfig = true }.font(.caption.bold())
            }
            ForEach(NukeStepType.allCases) { step in
                HStack {
                    Image(systemName: step.icon).foregroundStyle(cfg.enabledSteps.contains(step) ? .indigo : .gray)
                        .frame(width: 24)
                    Text(step.rawValue).font(.subheadline)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { cfg.enabledSteps.contains(step) },
                        set: { on in
                            if on { cfg.enabledSteps.insert(step) }
                            else { cfg.enabledSteps.remove(step) }
                        }
                    )).labelsHidden().tint(.indigo).scaleEffect(0.8)
                }
            }
        }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)
        .sheet(isPresented: $showConfig) { nukeConfigSheet }
    }

    private var nukeConfigSheet: some View {
        NavigationStack {
            Form {
                Section("Mass Ban") {
                    HStack { Text("Delay"); Spacer(); TextField("0.02", value: $cfg.banDelay, format: .number).frame(width: 80) }
                }
                Section("Xóa kênh") {
                    HStack { Text("Delay"); Spacer(); TextField("0.05", value: $cfg.deleteDelay, format: .number).frame(width: 80) }
                }
                Section("Đổi tên server") {
                    TextField("Tên mới", text: $cfg.newGuildName)
                }
                Section("Tạo Role") {
                    TextField("Tên role", text: $cfg.roleName)
                    HStack { Text("Số lượng"); Spacer(); TextField("50", value: $cfg.roleCount, format: .number).frame(width: 80) }
                    HStack { Text("Delay"); Spacer(); TextField("0.10", value: $cfg.createRoleDelay, format: .number).frame(width: 80) }
                }
                Section("Tạo kênh + Spam") {
                    TextField("Tên kênh", text: $cfg.channelName)
                    HStack { Text("Số lượng"); Spacer(); TextField("50", value: $cfg.channelCount, format: .number).frame(width: 80) }
                    TextField("Nội dung tin nhắn", text: $cfg.messageContent, axis: .vertical).lineLimit(3...6)
                    Toggle("Tag @everyone", isOn: $cfg.tagEveryone).tint(.indigo)
                    HStack { Text("Delay tạo"); Spacer(); TextField("0.10", value: $cfg.createChDelay, format: .number).frame(width: 80) }
                    HStack { Text("Delay tin"); Spacer(); TextField("0.10", value: $cfg.msgDelay, format: .number).frame(width: 80) }
                }
            }
            .navigationTitle("Cấu hình Nuke").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Xong") { showConfig = false } }
            }
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bắt đầu").font(.headline)
                Spacer()
                if bot.isNuking {
                    Button(role: .destructive) { bot.stopNuke() } label: {
                        Label("Dừng", systemImage: "stop.fill").font(.caption.bold())
                    }
                }
            }
            if bot.isNuking {
                ProgressView(value: bot.phaseProgress).tint(.indigo)
                Text(bot.currentPhase).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                statPill("Ban", "\(bot.banSuccess)", .red)
                statPill("Kênh -", "\(bot.channelsDeleted)", .orange)
                statPill("Kênh +", "\(bot.channelsCreated)", .green)
                statPill("Tin", "\(bot.messagesSent)", .blue)
            }
            Button {
                guard let g = selectedGuild else { return }
                Task { await bot.runNuke(guild: g, options: cfg) }
            } label: {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text(bot.isNuking ? "Đang nuke..." : "BẮT ĐẦU NUKE")
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(selectedGuild == nil ? Color.gray : Color.red)
            .foregroundStyle(.white).cornerRadius(10)
            .disabled(selectedGuild == nil || bot.isNuking)
        }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.fill").foregroundStyle(.indigo)
                Text("Log").font(.headline)
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(bot.nukeLog.indices, id: \.self) { i in
                        Text(bot.nukeLog[i])
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 200)
        }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)
    }

    private func statPill(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(.subheadline, weight: .bold)).foregroundStyle(c)
            Text(t).font(.system(size: 9)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(c.opacity(0.1)).cornerRadius(8)
    }
}

// ==========================================
// MARK: - USER NUKE VIEW
// ==========================================
struct UserNukeView: View {
    @EnvironmentObject var userNuke: UserNukeManager
    @State private var showAddToken = false
    @State private var showImport = false
    @State private var tokenInput = ""
    @State private var selectedGuild: Guild? = nil
    @State private var cfg = NukeConfig()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    tokensCard
                    if !userNuke.selectedTokenIds.isEmpty {
                        guildCard
                        if let g = selectedGuild { nukeCard(guild: g) }
                    }
                    statsCard
                    logCard
                }.padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("User Nuke")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddToken) { addTokenSheet }
            .sheet(isPresented: $showImport) {
                DocumentPicker(contentTypes: [.text]) { u in Task { await userNuke.importFromFile(url: u) } }
            }
        }
    }

    private var tokensCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.2.fill").foregroundStyle(.indigo)
                Text("Tokens (\(userNuke.tokens.count))").font(.headline)
                Spacer()
                Menu {
                    Button("Thêm tay", systemImage: "keyboard") { showAddToken = true }
                    Button("Import file", systemImage: "doc.text") { showImport = true }
                    if !userNuke.tokens.isEmpty {
                        Divider()
                        Button("Xoá tất cả", systemImage: "trash", role: .destructive) { userNuke.clearAll() }
                    }
                } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.indigo) }
            }
            if userNuke.isImporting { ProgressView("Đang import...").scaleEffect(0.8) }
            ForEach(userNuke.tokens) { t in
                HStack {
                    Image(systemName: t.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(t.isValid ? .green : .red)
                    Text(t.username).font(.caption).lineLimit(1)
                    Spacer()
                    if t.isValid {
                        Button {
                            userNuke.toggleSelection(t)
                        } label: {
                            Image(systemName: userNuke.selectedTokenIds.contains(t.id)
                                  ? "checkmark.square.fill" : "square")
                                .foregroundStyle(.indigo)
                        }
                    }
                    Button(role: .destructive) { userNuke.removeToken(t.id) } label: {
                        Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)
    }

    private var addTokenSheet: some View {
        NavigationStack {
            Form {
                Section("User Token") {
                    TextField("Dán token...", text: $tokenInput, axis: .vertical).lineLimit(2...4)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Thêm Token").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { tokenInput = ""; showAddToken = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        Task { _ = await userNuke.addTokenManually(tokenInput); tokenInput = ""; showAddToken = false }
                    }.disabled(tokenInput.isEmpty)
                }
            }
        }
    }

    private var guildCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "server.rack").foregroundStyle(.indigo)
                Text("Chọn Server").font(.headline)
                Spacer()
                if userNuke.isLoadingGuilds { ProgressView().scaleEffect(0.7) }
            }
            if userNuke.eligibleGuilds.isEmpty {
                Button("Tải server khả dụng") {
                    Task { await userNuke.loadAllGuildsForSelected() }
                }.font(.caption.bold())
            } else {
                Picker("Server", selection: $selectedGuild) {
                    Text("— Chọn —").tag(Guild?.none)
                    ForEach(userNuke.eligibleGuilds) { g in Text(g.name).tag(Optional(g)) }
                }.pickerStyle(.menu).tint(.indigo)
            }
        }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)
    }

    private func nukeCard(guild: Guild) -> some View {
        let perms = userNuke.permissionsForGuild(guild.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(.red)
                Text("Nuke: \(guild.name)").font(.headline).lineLimit(1)
            }
            HStack(spacing: 6) {
                if perms.massBan { tag("Ban", .red) }
                if perms.deleteChannels { tag("Xóa kênh", .orange) }
                if perms.createChannels { tag("Tạo kênh", .green) }
                if perms.createRoles { tag("Role", .blue) }
                if perms.renameGuild { tag("Rename", .purple) }
            }
            ForEach(NukeStepType.allCases) { step in
                let allowed: Bool = {
                    switch step {
                    case .massBan: return perms.massBan
                    case .deleteChannels, .createChannels: return perms.deleteChannels || perms.createChannels
                    case .createRoles: return perms.createRoles
                    case .renameGuild: return perms.renameGuild
                    }
                }()
                HStack {
                    Image(systemName: step.icon).foregroundStyle(cfg.enabledSteps.contains(step) ? .indigo : .gray).frame(width: 24)
                    Text(step.rawValue).font(.subheadline).foregroundStyle(allowed ? .primary : .secondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { cfg.enabledSteps.contains(step) && allowed },
                        set: { on in
                            if on { cfg.enabledSteps.insert(step) }
                            else { cfg.enabledSteps.remove(step) }
                        }
                    )).labelsHidden().tint(.indigo).scaleEffect(0.8).disabled(!allowed)
                }
            }
            Button {
                Task { await userNuke.runNuke(guild: guild, options: cfg) }
            } label: {
                HStack {
                    if userNuke.isNuking { ProgressView().tint(.white) }
                    Image(systemName: "bolt.fill")
                    Text(userNuke.isNuking ? "Đang nuke..." : "BẮT ĐẦU NUKE")
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(perms.any ? Color.red : Color.gray).foregroundStyle(.white).cornerRadius(10)
            .disabled(!perms.any || userNuke.isNuking)
        }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tiến độ").font(.headline)
                Spacer()
                if userNuke.isNuking {
                    Button(role: .destructive) { userNuke.stop() } label: {
                        Label("Dừng", systemImage: "stop.fill").font(.caption.bold())
                    }
                }
            }
            if userNuke.isNuking {
                ProgressView(value: userNuke.phaseProgress).tint(.indigo)
                Text(userNuke.currentPhase).font(.caption).foregroundStyle(.secondary)
                Text("Scan: \(userNuke.membersScanned)").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                smallPill("Ban", "\(userNuke.banSuccess)", .red)
                smallPill("Kênh -", "\(userNuke.channelsDeleted)", .orange)
                smallPill("Kênh +", "\(userNuke.channelsCreated)", .green)
                smallPill("Tin", "\(userNuke.messagesSent)", .blue)
            }
        }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(userNuke.nukeLog.indices, id: \.self) { i in
                        Text(userNuke.nukeLog[i])
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 200)
        }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15)
    }

    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(c.opacity(0.2)).foregroundStyle(c).cornerRadius(4)
    }
    private func smallPill(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(.subheadline, weight: .bold)).foregroundStyle(c)
            Text(t).font(.system(size: 9)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(c.opacity(0.1)).cornerRadius(8)
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
// MARK: - LOCAL NOTIFICATIONS
// ==========================================
final class NotificationHelper: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHelper()
    private override init() { super.init() }

    func setup() { UNUserNotificationCenter.current().delegate = self }

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch { return false }
    }

    func notifyAvailable(username: String) {
        let content = UNMutableNotificationContent()
        content.title = "🎉 Username Available!"
        content.body  = "'\(username)' chưa được sử dụng"
        content.sound = .default
        content.badge = 1
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// ==========================================
// MARK: - USERNAME CHECK CLIENT
// ==========================================
final class UsernameCheckClient {
    let session: URLSession

    init(proxy: String?) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest  = 10
        cfg.timeoutIntervalForResource = 15
        cfg.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept": "*/*",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ]
        if let p = proxy, let dict = Self.parseProxy(p) {
            cfg.connectionProxyDictionary = dict
        }
        session = URLSession(configuration: cfg)
    }

    // iOS chỉ hỗ trợ HTTP proxy keys — HTTPS keys không có sẵn trên iOS.
    // iOS tự tunnel HTTPS qua HTTP CONNECT khi chỉ set HTTP keys.
    static func parseProxy(_ str: String) -> [AnyHashable: Any]? {
        var s = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        var user: String? = nil, pass: String? = nil
        if let at = s.lastIndex(of: "@") {
            let creds = String(s[..<at])
            s = String(s[s.index(after: at)...])
            let parts = creds.split(separator: ":", maxSplits: 1)
            if parts.count == 2 { user = String(parts[0]); pass = String(parts[1]) }
        }
        var host = s, port = 80
        let parts = s.split(separator: ":")
        if parts.count == 4 {
            host = String(parts[0]); port = Int(parts[1]) ?? 80
            user = String(parts[2]); pass = String(parts[3])
        } else if parts.count == 2 {
            host = String(parts[0]); port = Int(parts[1]) ?? 80
        } else { return nil }
        guard !host.isEmpty, (1...65535).contains(port) else { return nil }
        var dict: [AnyHashable: Any] = [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPProxy:  host,
            kCFNetworkProxiesHTTPPort:   port,
        ]
        if let u = user, let p = pass {
            dict[kCFProxyUsernameKey] = u
            dict[kCFProxyPasswordKey] = p
        }
        return dict
    }

    func check(username: String) async -> (Bool, Bool) {
        do {
            var req = URLRequest(url: URL(string:
                "https://discord.com/api/v9/unique-username/username-attempt-unauthed")!)
            req.httpMethod = "POST"
            req.httpBody = try JSONSerialization.data(withJSONObject: ["username": username])
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return (false, false) }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let taken = json["taken"] as? Bool else { return (false, false) }
            return (true, !taken)
        } catch { return (false, false) }
    }
}

// ==========================================
// MARK: - PROXY POOL
// ==========================================
final class ProxyPool {
    struct Entry {
        var url: String
        var alive: Bool
        var failCount: Int
        var lastDead: Date
    }
    private var entries: [Entry] = []
    private var cursor = 0
    private let lock = NSLock()
    let cooldown: TimeInterval = 10.0

    func add(_ url: String) {
        lock.lock(); defer { lock.unlock() }
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if entries.contains(where: { $0.url == t }) { return }
        entries.append(Entry(url: t, alive: true, failCount: 0, lastDead: .distantPast))
    }

    func size()       -> Int { lock.lock(); defer { lock.unlock() }; return entries.count }
    func aliveCount() -> Int { lock.lock(); defer { lock.unlock() }; return entries.filter { $0.alive }.count }

    func acquire() -> Int? {
        lock.lock(); defer { lock.unlock() }
        let n = entries.count
        guard n > 0 else { return nil }
        let now = Date()
        for i in 0..<n {
            let idx = (cursor + i) % n
            let e = entries[idx]
            if e.alive && now.timeIntervalSince(e.lastDead) >= cooldown {
                cursor = (idx + 1) % n
                return idx
            }
        }
        if entries.allSatisfy({ !$0.alive }) {
            let minLastDead = entries.map { $0.lastDead }.min() ?? .distantPast
            if now.timeIntervalSince(minLastDead) < cooldown {
                return nil
            }
            for i in entries.indices { entries[i].alive = true }
            cursor = n > 1 ? 1 : 0
            return 0
        }
        for i in 0..<n {
            let idx = (cursor + i) % n
            if entries[idx].alive {
                cursor = (idx + 1) % n
                return idx
            }
        }
        return nil
    }

    func markDead(_ idx: Int) {
        lock.lock(); defer { lock.unlock() }
        guard idx < entries.count else { return }
        entries[idx].alive = false
        entries[idx].failCount += 1
        entries[idx].lastDead = Date()
    }

    func getURL(_ idx: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        return idx < entries.count ? entries[idx].url : ""
    }

    func clear() { lock.lock(); defer { lock.unlock() }; entries = []; cursor = 0 }
}

// ==========================================
// MARK: - RATE LIMITER
// ==========================================
actor RateLimiter {
    let rps: Int
    private var lastTime: Date = .distantPast
    init(rps: Int) { self.rps = rps }
    func acquire() async {
        guard rps > 0 else { return }
        let minGap = 1.0 / Double(rps)
        let reserved = max(Date(), lastTime.addingTimeInterval(minGap))
        lastTime = reserved
        let wait = reserved.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
    }
}

// ==========================================
// MARK: - USERNAME CHECKER MANAGER
// ==========================================
struct CheckResult: Identifiable {
    let id = UUID()
    let username: String
    let available: Bool
    let date: Date
}

@MainActor
final class UsernameChecker: ObservableObject {
    @Published var minLength: Int = 3
    @Published var maxLength: Int = 4
    @Published var threads: Int = 50
    @Published var rpsLimit: Int = 0
    @Published var proxyText: String = "" {
        didSet { validateProxyText() }
    }
    @Published var notifyOnAvailable: Bool = true

    @Published var isRunning = false
    @Published var results: [CheckResult] = []
    @Published var totalChecked = 0
    @Published var totalAvailable = 0
    @Published var totalRequests = 0
    @Published var total429 = 0
    @Published var showOnlyAvailable = false
    @Published var proxyAlive = 0
    @Published var proxyTotal = 0
    @Published var notificationDenied = false
    @Published var errorMessage: String? = nil
    @Published var startedAt: Date? = nil

    private var isCancelled = false
    private var tasks: [Task<Void, Never>] = []
    private var rateLimiter: RateLimiter?
    private var proxyPool = ProxyPool()
    private var lastNPUpdate = Date.distantPast
    private var lastNotify = Date.distantPast
    private let maxResults = 500

    private func validateProxyText() {
        let trimmed = proxyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            proxyTotal = 0
            proxyAlive = 0
            if !isRunning { errorMessage = nil }
        } else if UsernameCheckClient.parseProxy(trimmed) != nil {
            proxyTotal = 1
            proxyAlive = 1
            if !isRunning { errorMessage = nil }
        } else {
            proxyTotal = 0
            proxyAlive = 0
            errorMessage = "Proxy không đúng định dạng"
        }
    }

    func start() {
        guard !isRunning else { return }
        errorMessage = nil

        let proxyLine = proxyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proxyLine.isEmpty else {
            errorMessage = "Vui lòng nhập proxy trước khi Start"
            return
        }
        guard UsernameCheckClient.parseProxy(proxyLine) != nil else {
            errorMessage = "Proxy không đúng định dạng (VD: host:port hoặc host:port:user:pass)"
            return
        }
        guard minLength >= 3, maxLength >= minLength else {
            errorMessage = "Độ dài username không hợp lệ (Min ≥ 3 và ≤ Max)"
            return
        }
        guard threads >= 1, threads <= 500 else {
            errorMessage = "Số luồng phải từ 1 đến 500"
            return
        }

        proxyPool = ProxyPool()
        proxyPool.add(proxyLine)
        proxyTotal = proxyPool.size()
        proxyAlive = proxyPool.aliveCount()
        guard proxyTotal > 0 else {
            errorMessage = "Không thể nạp proxy"
            return
        }

        isRunning = true; isCancelled = false
        results = []; totalChecked = 0; totalAvailable = 0
        totalRequests = 0; total429 = 0
        startedAt = Date()
        rateLimiter = RateLimiter(rps: rpsLimit)

        BackgroundManager.shared.start()
        NowPlayingHelper.shared.start(onStop: { [weak self] in
            Task { @MainActor in self?.stop() }
        })
        updateNowPlaying(force: true)

        if notifyOnAvailable {
            Task { @MainActor [weak self] in
                let ok = await NotificationHelper.shared.requestPermission()
                if !ok { self?.notificationDenied = true }
            }
        }

        tasks = (0..<max(1, threads)).map { i in
            Task { [weak self] in await self?.workerLoop(workerId: i) }
        }
    }

    func stop() {
        isCancelled = true
        tasks.forEach { $0.cancel() }
        tasks = []
        isRunning = false
        BackgroundManager.shared.stop()
        NowPlayingHelper.shared.stop()
    }

    private func workerLoop(workerId: Int) async {
        while !isCancelled && !Task.isCancelled {
            guard let proxyIdx = proxyPool.acquire() else {
                try? await Task.sleep(nanoseconds: 500_000_000); continue
            }
            let proxyURL = proxyPool.getURL(proxyIdx)
            let client = UsernameCheckClient(proxy: proxyURL)

            while !isCancelled && !Task.isCancelled {
                let username = generateUsername()
                guard !username.isEmpty else { break }

                await rateLimiter?.acquire()
                totalRequests += 1

                let (success, available) = await client.check(username: username)

                if !success {
                    proxyPool.markDead(proxyIdx)
                    proxyAlive = proxyPool.aliveCount()
                    break
                }

                totalChecked += 1
                let r = CheckResult(username: username, available: available, date: Date())
                results.insert(r, at: 0)
                if results.count > maxResults { results.removeLast(results.count - maxResults) }

                if available {
                    totalAvailable += 1
                    sendAvailableNotification(username)
                }

                proxyAlive = proxyPool.aliveCount()
                updateNowPlaying()
                try? await Task.sleep(nanoseconds: UInt64.random(in: 5_000_000...20_000_000))
            }
        }
    }

    private func generateUsername() -> String {
        let letters  = Array("abcdefghijklmnopqrstuvwxyz")
        let allChars = Array("abcdefghijklmnopqrstuvwxyz0123456789_.")
        let lo = max(3, min(minLength, maxLength))
        let hi = max(lo, maxLength)
        let len = Int.random(in: lo...hi)
        var chars: [Character] = []
        var hasLetter = false
        for i in 0..<len {
            let c: Character
            if i == len - 1 && !hasLetter { c = letters.randomElement()! }
            else { c = allChars.randomElement()! }
            chars.append(c)
            if c.isLetter { hasLetter = true }
        }
        return String(chars)
    }

    private func sendAvailableNotification(_ username: String) {
        guard notifyOnAvailable else { return }
        let now = Date()
        guard now.timeIntervalSince(lastNotify) >= 2.0 else { return }
        lastNotify = now
        NotificationHelper.shared.notifyAvailable(username: username)
    }

    private func updateNowPlaying(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastNPUpdate) >= 1.0 else { return }
        lastNPUpdate = now
        let elapsed = startedAt.map { now.timeIntervalSince($0) } ?? 0
        let rps = elapsed > 0 ? Double(totalRequests) / elapsed : 0
        NowPlayingHelper.shared.update(
            title:  "🔍 Checker · \(totalAvailable) avail",
            detail: "\(totalChecked) checked · \(String(format: "%.1f", rps)) rq/s · \(proxyAlive)/\(proxyTotal) proxy"
        )
    }

    var filteredResults: [CheckResult] {
        showOnlyAvailable ? results.filter { $0.available } : results
    }

    func copyAvailable() -> Int {
        let all = results.filter { $0.available }.map { $0.username }
        UIPasteboard.general.string = all.joined(separator: "\n")
        return all.count
    }

    func clearResults() {
        results = []
        totalChecked = 0; totalAvailable = 0
        totalRequests = 0; total429 = 0
        startedAt = nil
    }

    var rpsString: String {
        guard let s = startedAt else { return "0.0" }
        let e = Date().timeIntervalSince(s)
        return e > 0 ? String(format: "%.1f", Double(totalRequests) / e) : "0.0"
    }

    var elapsedString: String {
        guard let s = startedAt else { return "0s" }
        return "\(Int(Date().timeIntervalSince(s)))s"
    }
}

// ==========================================
// MARK: - USERNAME CHECKER VIEW
// ==========================================
struct UsernameCheckerView: View {
    @EnvironmentObject var checker: UsernameChecker
    @State private var showConfig = false
    @State private var copiedToast = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statsHeader
                if let err = checker.errorMessage, !checker.isRunning {
                    Text("⚠️ \(err)")
                        .font(.caption.bold()).foregroundStyle(.red)
                        .frame(maxWidth: .infinity).padding(8)
                        .background(Color.red.opacity(0.1))
                }
                controlBar
                resultsArea
            }
            .navigationTitle("Username Checker")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { checker.clearResults() } label: { Image(systemName: "trash") }
                        .disabled(checker.isRunning || checker.results.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showConfig = true } label: { Image(systemName: "gearshape.fill") }
                }
            }
            .sheet(isPresented: $showConfig) { CheckerConfigSheet() }
            .overlay(alignment: .top) {
                if copiedToast {
                    Text("Đã copy!")
                        .font(.caption.bold()).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private var statsHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                StatBadge(title: "Checked",   value: "\(checker.totalChecked)",   color: .blue)
                StatBadge(title: "Available", value: "\(checker.totalAvailable)", color: .green)
                StatBadge(title: "RPS",       value: checker.rpsString,           color: .purple)
                StatBadge(title: "429",       value: "\(checker.total429)",       color: .red)
                StatBadge(title: "Proxy",     value: "\(checker.proxyAlive)/\(checker.proxyTotal)", color: .orange)
            }
            HStack(spacing: 6) {
                if checker.isRunning {
                    ProgressView().scaleEffect(0.6)
                    Text("Đang chạy · \(checker.elapsedString)")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if checker.proxyTotal == 0 {
                    Text("Chưa có proxy — bấm ⚙️ để thêm")
                        .font(.caption2).foregroundStyle(.orange)
                } else {
                    Text("Sẵn sàng · 1 proxy")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if checker.notificationDenied {
                    Text("· 🔕 Thông báo bị tắt")
                        .font(.caption2).foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 8).padding(.horizontal)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            if checker.isRunning {
                Button { checker.stop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .background(Color.red).foregroundStyle(.white).cornerRadius(10)
            } else {
                Button { checker.start() } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .background(Color.green).foregroundStyle(.white).cornerRadius(10)
            }

            Button {
                let n = checker.copyAvailable()
                if n > 0 {
                    withAnimation { copiedToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { copiedToast = false }
                    }
                }
            } label: {
                Image(systemName: "doc.on.doc.fill").padding(.vertical, 10).padding(.horizontal, 14)
            }
            .background(Color.indigo).foregroundStyle(.white).cornerRadius(10)

            Button { checker.showOnlyAvailable.toggle() } label: {
                Image(systemName: checker.showOnlyAvailable
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .padding(.vertical, 10).padding(.horizontal, 14)
            }
            .background(checker.showOnlyAvailable ? Color.green : Color.gray.opacity(0.3))
            .foregroundStyle(.white).cornerRadius(10)
        }
        .padding(.horizontal).padding(.vertical, 6)
    }

    private var resultsArea: some View {
        Group {
            if checker.filteredResults.isEmpty {
                EmptyStateView(title: "Chưa có kết quả",
                               systemImage: "magnifyingglass",
                               description: checker.proxyTotal == 0
                                    ? "Nhập proxy và bấm Start."
                                    : "Bấm Start để bắt đầu check username.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(checker.filteredResults) { r in
                            HStack {
                                Text(r.username)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(r.available ? .green : .red)
                                Spacer()
                                Text(r.available ? "AVAILABLE" : "TAKEN")
                                    .font(.caption2.bold())
                                    .foregroundStyle(r.available ? .green : .red)
                            }
                            .padding(.horizontal).padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct StatBadge: View {
    let title: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 1) {
            Text(value).font(.system(.subheadline, weight: .bold))
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// ==========================================
// MARK: - CHECKER CONFIG SHEET
// ==========================================
struct CheckerConfigSheet: View {
    @EnvironmentObject var checker: UsernameChecker
    @Environment(\.dismiss) var dismiss
    @FocusState private var focus: Field?
    enum Field { case proxy, threads, rps, minLen, maxLen }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Độ dài Username")) {
                    HStack {
                        Text("Min")
                        Spacer()
                        TextField("3", value: $checker.minLength, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .focused($focus, equals: .minLen)
                        Stepper("", value: $checker.minLength, in: 3...20).labelsHidden()
                    }
                    HStack {
                        Text("Max")
                        Spacer()
                        TextField("4", value: $checker.maxLength, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .focused($focus, equals: .maxLen)
                        Stepper("", value: $checker.maxLength, in: 3...20).labelsHidden()
                    }
                    if checker.minLength > checker.maxLength {
                        Text("⚠️ Min > Max").font(.caption).foregroundStyle(.red)
                    }
                }

                Section(header: Text("Hiệu năng")) {
                    HStack {
                        Text("Threads")
                        Spacer()
                        TextField("50", value: $checker.threads, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focus, equals: .threads)
                    }
                    HStack {
                        Text("Rate limit (RQ/s)")
                        Spacer()
                        TextField("0", value: $checker.rpsLimit, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focus, equals: .rps)
                    }
                    Text(checker.rpsLimit == 0 ? "0 = không giới hạn" : "~\(checker.rpsLimit) request/giây")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section(header: Text("Thông báo")) {
                    Toggle("Báo khi tìm được username available", isOn: $checker.notifyOnAvailable)
                        .tint(.indigo)
                }

                Section {
                    TextField("host:port hoặc host:port:user:pass", text: $checker.proxyText)
                        .font(.system(.caption, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .focused($focus, equals: .proxy)
                        .submitLabel(.done)
                        .onSubmit { focus = nil }
                    if let err = checker.errorMessage {
                        Text("⚠️ \(err)")
                            .font(.caption).foregroundStyle(.red)
                    } else if !checker.proxyText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("✓ Proxy hợp lệ")
                            .font(.caption).foregroundStyle(.green)
                    }
                    Text("Chỉ nhập 1 proxy duy nhất. Định dạng:\n• host:port\n• host:port:user:pass\n• http://user:pass@host:port")
                        .font(.caption2).foregroundStyle(.secondary)
                } header: {
                    HStack {
                        Text("Proxy")
                        Spacer()
                        Link(destination: URL(string: "https://discord.gg/sdn9NedNJ")!) {
                            Label("Mua Proxy", systemImage: "cart.fill")
                                .font(.caption.bold())
                        }
                    }
                }
            }
            .navigationTitle("Cấu hình Checker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        focus = nil
                        dismiss()
                    }.disabled(checker.isRunning)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Xong") { focus = nil }
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
    @StateObject private var app      = AppState()
    @StateObject private var bot      = BotManager()
    @StateObject private var userNuke = UserNukeManager()
    @StateObject private var checker  = UsernameChecker()
    @StateObject private var license  = LicenseManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationHelper.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if license.isUnlocked {
                    MainTabView()
                        .environmentObject(app)
                        .environmentObject(bot)
                        .environmentObject(userNuke)
                        .environmentObject(checker)
                        .environmentObject(license)
                } else {
                    LockView().environmentObject(license)
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task { @MainActor in await license.refreshStatus() }
                    if app.isSending {
                        BackgroundManager.shared.start()
                        NowPlayingHelper.shared.update(
                            title: "Quoc Thang Spam",
                            detail: "\(app.totalSent) tin | \(app.selectedTokenIds.count) token"
                        )
                    }
                    if checker.isRunning {
                        BackgroundManager.shared.start()
                    }
                }
            }
            .onChange(of: license.isUnlocked) { isUnlocked in
                if !isUnlocked {
                    app.stopSending()
                    bot.stopNuke()
                    userNuke.stop()
                    checker.stop()
                    BackgroundManager.shared.stop()
                    NowPlayingHelper.shared.stop()
                }
            }
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
            NukeTabView()
                .tabItem { Label("Nuke", systemImage: "flame.fill") }
            UsernameCheckerView()
                .tabItem { Label("Checker", systemImage: "magnifyingglass.circle.fill") }
            AboutView()
                .tabItem { Label("Info", systemImage: "info.circle.fill") }
        }.tint(.indigo)
    }
}