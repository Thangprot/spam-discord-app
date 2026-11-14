import SwiftUI
import Foundation
import Security
import AVFoundation
import UniformTypeIdentifiers
import UIKit

// ==========================================
// MARK: - DOCUMENT PICKER (FIX CHO MỌI iOS)
// ==========================================
// Lý do: SwiftUI .fileImporter bị bug "bấm vào file không phản hồi" khi
// allowedContentTypes trộn .item với UTType con (.data, .text, .plainText).
// Wrapper này dùng UIDocumentPickerViewController trực tiếp với asCopy: true
// → ổn định trên iOS 14+ và mọi nguồn (iCloud, Drive, OneDrive, Files...).
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
            asCopy: true   // 🔑 File được copy vào sandbox → không cần security scope
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel?()
        }
    }
}

// ==========================================
// MARK: - MODELS
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
// MARK: - DISCORD CLIENT
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
            throw NSError(domain: "Discord", code: (res as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? ""])
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
// MARK: - APP STATE
// ==========================================
@MainActor
class AppState: ObservableObject {
    // Token Management
    @Published var tokens: [TokenInfo] = [] { didSet { saveTokens() } }
    @Published var activeToken: TokenInfo? = nil
    @Published var isCheckingToken = false

    // Spam State
    @Published var guilds: [Guild] = []
    @Published var channels: [Channel] = []
    @Published var isLoading = false

    // Config
    @Published var delaySeconds: Double = 2.0
    @Published var useTag: Bool = true
    @Published var targetUserId = ""
    @Published var addPrefix: Bool = false
    @Published var addSuffix: Bool = false

    // Content
    @Published var inputText = ""
    @Published var messages: [ParsedMessage] = []

    // Sending Status
    @Published var isSending = false
    @Published var totalSent = 0
    @Published var currentMessageStr = ""
    @Published var lastError: String?

    private var client: DiscordClient? { activeToken != nil ? DiscordClient(token: activeToken!.token) : nil }
    private var isCancelled = false
    private var sendTask: Task<Void, Never>?

    init() { loadTokens() }

    // --- TOKEN LOGIC ---
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
            let newToken = TokenInfo(token: cleanToken, userId: user.id, username: user.globalName ?? user.username, avatarHash: user.avatar, isValid: true)
            tokens.append(newToken)
            if activeToken == nil { setActiveToken(newToken) }
        } catch {
            let deadToken = TokenInfo(token: cleanToken, userId: "0", username: "Token Chết", avatarHash: nil, isValid: false)
            tokens.append(deadToken)
        }
        isCheckingToken = false
    }

    // ==========================================
    // FIX: addTokensFromFile — đọc được mọi bảng mã + iCloud
    // (URL từ DocumentPicker asCopy:true đã ở sandbox nên không cần security scope,
    //  nhưng vẫn gọi để an toàn khi hàm được dùng từ nguồn khác.)
    // ==========================================
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
        if fileData == nil {
            fileData = try? Data(contentsOf: url)
        }

        guard let data = fileData else {
            lastError = "Không thể đọc file token."
            return
        }

        let encodings: [String.Encoding] = [
            .utf8, .utf16, .utf16LittleEndian, .utf16BigEndian,
            .windowsCP1252, .isoLatin1, .ascii
        ]
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

    // --- SPAM LOGIC ---
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

    // ==========================================
    // FIX: parseFile — đọc được mọi bảng mã + iCloud + sandbox copy
    // ==========================================
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

        let encodings: [String.Encoding] = [
            .utf8, .utf16, .utf16LittleEndian, .utf16BigEndian,
            .windowsCP1252, .isoLatin1, .ascii, .nonLossyASCII
        ]

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
                } catch {
                    break   // Task bị cancel
                }
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
// MARK: - APP ENTRY POINT
// ==========================================
@main
struct SpamDiscordApp: App {
    @StateObject private var app = AppState()
    var body: some Scene {
        WindowGroup {
            MainTabView().environmentObject(app)
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
            // 🔑 FIX: dùng DocumentPicker thay .fileImporter
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
                // 1. Thông tin kênh
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

                // 2. Cấu hình gửi
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

                // 3. Nội dung tin nhắn
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

                // 4. Trạng thái và Nút bấm
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
        // 🔑 FIX: dùng DocumentPicker thay .fileImporter
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