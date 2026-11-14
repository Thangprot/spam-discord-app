import SwiftUI
import Foundation
import Security
import AVFoundation
import UniformTypeIdentifiers
import UIKit

// ==========================================
// MARK: - MODELS
// ==========================================
struct DiscordUser: Codable { let id, username: String; let globalName: String? }
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
// MARK: - SILENT AUDIO & BACKGROUND MANAGER
// ==========================================
class BackgroundManager {
    static let shared = BackgroundManager()
    private var audioPlayer: AVAudioPlayer?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    
    func start() {
        // 1. Kích hoạt Background Task
        bgTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.stop()
        }
        
        // 2. Phát âm thanh câm để giữ app tỉnh
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            
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
            
            let wavData = header + Data(repeating: 0, count: dataSize)
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.play()
        } catch {}
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
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
    let token: String
    let session: URLSession
    
    init(token: String) {
        self.token = token
        let config = URLSessionConfiguration.default
        let superProps = """
        {"os":"Mac OS X","browser":"Chrome","device":"","system_locale":"en-US","browser_user_agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36","browser_version":"126.0.0.0","os_version":"10.15.7","referrer":"","referring_domain":"","referrer_current":"","referring_domain_current":"","release_channel":"stable","client_build_number":305000,"client_event_source":null}
        """
        config.httpAdditionalHeaders = [
            "Authorization": token,
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            "X-Super-Properties": Data(superProps.utf8).base64EncodedString(),
            "X-Discord-Locale": "en-US"
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
    // Auth
    @Published var activeToken = "" { didSet { UserDefaults.standard.set(activeToken, forKey: "ActiveToken") } }
    @Published var savedTokens: [String] = [] { didSet { UserDefaults.standard.set(savedTokens, forKey: "SavedTokens") } }
    @Published var me: DiscordUser?
    @Published var isLoggingIn = false
    @Published var loginError: String?
    
    // Data
    @Published var guilds: [Guild] = []
    @Published var channels: [Channel] = []
    @Published var isLoading = false
    
    // Config
    @Published var delaySeconds: Double = 2.0
    @Published var useTag: Bool = true 
    @Published var targetUserId = ""
    @Published var addPrefix: Bool = false // Bật/tắt dấu >
    @Published var addSuffix: Bool = false // Bật/tắt dấu #
    
    // Content
    @Published var inputText = "" 
    @Published var messages: [ParsedMessage] = []
    
    // Sending Status
    @Published var isSending = false
    @Published var totalSent = 0
    @Published var currentMessageStr = ""
    @Published var lastError: String?
    
    private var client: DiscordClient? { activeToken.isEmpty ? nil : DiscordClient(token: activeToken) }
    private var isCancelled = false
    
    init() {
        if let saved = UserDefaults.standard.string(forKey: "ActiveToken"), !saved.isEmpty {
            self.activeToken = saved
            Task { await login(silent: true) }
        }
        if let tokens = UserDefaults.standard.stringArray(forKey: "SavedTokens") {
            self.savedTokens = tokens
        }
    }
    
    func login(silent: Bool = false) async {
        if !silent { isLoggingIn = true }
        loginError = nil
        do {
            guard let client = client else { return }
            self.me = try await client.validateToken()
            if !savedTokens.contains(activeToken) {
                savedTokens.append(activeToken)
            }
            self.guilds = try await client.getAllGuilds().sorted { $0.name < $1.name }
        } catch { 
            loginError = error.localizedDescription
            self.me = nil 
        }
        isLoggingIn = false
    }
    
    func logout() {
        stopSending()
        activeToken = ""
        me = nil
        guilds = []
        channels = []
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
    
    // Đọc từ file txt (Fix lỗi bộ nhớ và định dạng)
    func parseFile(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            self.inputText = content
            parseDirectInput()
        } catch {
            lastError = "Không thể đọc file: \(error.localizedDescription)"
        }
    }
    
    // Xử lý nội dung text
    func parseDirectInput() {
        messages = inputText.components(separatedBy: .newlines).compactMap {
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : ParsedMessage(body: t)
        }
    }
    
    // Bắt đầu spam
    func startSending(channel: Channel) {
        guard let client = client, !messages.isEmpty else { return }
        if useTag && targetUserId.isEmpty { return }
        
        isSending = true; isCancelled = false; totalSent = 0; lastError = nil
        BackgroundManager.shared.start() // Giữ app chạy ngầm
        
        Task {
            var currentIndex = 0
            while !isCancelled {
                let msg = messages[currentIndex]
                
                // Xử lý format > và #
                var finalContent = msg.body
                if addPrefix { finalContent = "> " + finalContent }
                if addSuffix { finalContent = finalContent + " #" }
                if useTag { finalContent += " <@\(targetUserId)>" }
                
                currentMessageStr = finalContent
                
                do {
                    try await client.sendMessage(channelId: channel.id, content: finalContent)
                    totalSent += 1
                } catch { 
                    lastError = "Lỗi: \(error.localizedDescription)"
                }
                
                currentIndex = (currentIndex + 1) % messages.count
                let actualDelay = max(0.1, delaySeconds + Double.random(in: -0.3...0.3) * delaySeconds)
                try? await Task.sleep(nanoseconds: UInt64(actualDelay * 1_000_000_000))
            }
            isSending = false
            currentMessageStr = ""
        }
    }
    
    func stopSending() { 
        isCancelled = true 
        isSending = false
        BackgroundManager.shared.stop()
    }
    
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// ==========================================
// MARK: - APP ENTRY POINT (TAB BAR)
// ==========================================
@main
struct SpamDiscordApp: App {
    @StateObject private var app = AppState()
    var body: some Scene {
        WindowGroup {
            if app.me != nil {
                MainTabView().environmentObject(app)
            } else {
                LoginView().environmentObject(app)
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        TabView {
            GuildListView()
                .tabItem { Label("Spam", systemImage: "paperplane.fill") }
            
            TokenManagerView()
                .tabItem { Label("Tokens", systemImage: "key.fill") }
        }
    }
}

// ==========================================
// MARK: - VIEWS
// ==========================================
struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var tokenInput = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Discord Spammer").font(.largeTitle).bold()
            TextField("Nhập User Token", text: $tokenInput).textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
            if let err = app.loginError { Text(err).foregroundStyle(Color.red).font(.caption) }
            Button {
                app.activeToken = tokenInput
                Task { await app.login() }
            } label: {
                if app.isLoggingIn { ProgressView() } else { Text("Đăng nhập").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(tokenInput.isEmpty || app.isLoggingIn)
        }.padding()
    }
}

struct TokenManagerView: View {
    @EnvironmentObject var app: AppState
    @State private var newToken = ""
    @State private var showImport = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Thêm Token Mới")) {
                    TextField("Dán token vào đây...", text: $newToken)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("Lưu Token") {
                        if !newToken.isEmpty && !app.savedTokens.contains(newToken) {
                            app.savedTokens.append(newToken)
                            newToken = ""
                        }
                    }
                    Button("Nhập từ File .txt") { showImport = true }
                }
                
                Section(header: Text("Danh sách Token đã lưu")) {
                    ForEach(app.savedTokens, id: \.self) { token in
                        HStack {
                            Text(token.prefix(15) + "...")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            if token == app.activeToken {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Button("Dùng") {
                                    app.activeToken = token
                                    Task { await app.login() }
                                }.buttonStyle(.bordered)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        app.savedTokens.remove(atOffsets: indexSet)
                    }
                }
            }
            .navigationTitle("Quản lý Token")
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.plainText, .text], allowsMultipleSelection: false) { res in
                if case .success(let urls) = res, let url = urls.first {
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let content = try? String(contentsOf: url, encoding: .utf8) {
                        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
                        for line in lines {
                            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !app.savedTokens.contains(t) { app.savedTokens.append(t) }
                        }
                    }
                }
            }
        }
    }
}

struct GuildListView: View {
    @EnvironmentObject var app: AppState
    @State private var searchText = ""
    
    var filteredGuilds: [Guild] {
        searchText.isEmpty ? app.guilds : app.guilds.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredGuilds) { guild in
                NavigationLink(value: guild) { Text(guild.name).fontWeight(.medium) }
            }
            .searchable(text: $searchText, prompt: "Tìm Server...")
            .navigationTitle("Chọn Server")
            .toolbar { Button("Đăng xuất", role: .destructive) { app.logout() } }
            .navigationDestination(for: Guild.self) { ChannelListView(guild: $0) }
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
            let filteredItems = section.items.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
            return filteredItems.isEmpty ? nil : (section.category, filteredItems)
        }
    }
    
    var body: some View {
        Group {
            if app.isLoading { ProgressView("Đang tải kênh...") }
            else {
                List {
                    ForEach(filteredSections, id: \.category?.id) { sec in
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
    @State private var inputMode = 1 
    
    var body: some View {
        Form {
            Section(header: Text("Kênh đang chọn")) {
                HStack {
                    Image(systemName: channel.type == 5 ? "megaphone" : "number").foregroundStyle(.blue)
                    Text(channel.displayName).bold()
                }
            }
            
            Section(header: Text("Cấu hình gửi")) {
                Toggle("Tag User ID vào cuối", isOn: $app.useTag)
                if app.useTag {
                    TextField("Nhập User ID", text: $app.targetUserId).keyboardType(.numberPad)
                }
                
                Toggle("Thêm '>' ở đầu tin nhắn", isOn: $app.addPrefix)
                Toggle("Thêm '#' ở cuối tin nhắn", isOn: $app.addSuffix)
                
                VStack(alignment: .leading) {
                    Text("Delay: \(String(format: "%.1f", app.delaySeconds)) giây")
                    Slider(value: $app.delaySeconds, in: 0.1...5.0, step: 0.1)
                }
            }
            
            Section(header: Text("Nội dung")) {
                Picker("Nguồn", selection: $inputMode) {
                    Text("Nhập tay").tag(1)
                    Text("File .txt").tag(0)
                }.pickerStyle(.segmented)
                .onChange(of: inputMode) { _ in app.parseDirectInput() }
                
                if inputMode == 0 {
                    Button("Chọn file .txt") { showImport = true }
                } else {
                    ZStack(alignment: .topTrailing) {
                        TextEditor(text: $app.inputText)
                            .frame(minHeight: 100)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                            .onChange(of: app.inputText) { _ in app.parseDirectInput() }
                        
                        if !app.inputText.isEmpty {
                            Button(action: { app.inputText = ""; app.parseDirectInput() }) {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.gray).padding(8)
                            }
                        }
                    }
                }
            }
            
            // KHU VỰC HIỂN THỊ TIẾN TRÌNH VÀ HIỆU ỨNG LOADING
            Section {
                if app.isSending {
                    VStack(spacing: 15) {
                        // Hiệu ứng Spinner / Progress Ring
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(1.5)
                            .padding(.top, 10)
                        
                        Text("Đang chạy vòng lặp vô hạn...")
                            .font(.headline)
                        
                        Text("Đã gửi: \(app.totalSent) tin nhắn")
                            .font(.subheadline).foregroundStyle(.secondary)
                        
                        Text(app.currentMessageStr)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                            .padding(.horizontal)
                        
                        if let err = app.lastError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                        
                        Button(action: { app.stopSending() }) {
                            Text("DỪNG LẠI").bold().frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.red)
                        .padding(.top, 10)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    Button(action: { app.startSending(channel: channel) }) {
                        Text("BẮT ĐẦU GỬI").bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(app.messages.isEmpty || (app.useTag && app.targetUserId.isEmpty))
                }
            }
        }
        .navigationTitle("Cấu hình")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Xong") { app.hideKeyboard() }
            }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.plainText, .text, .item], allowsMultipleSelection: false) { res in
            switch res {
            case .success(let urls):
                if let url = urls.first { app.parseFile(url: url) }
            case .failure(let error):
                app.lastError = "Lỗi file: \(error.localizedDescription)"
            }
        }
    }
}