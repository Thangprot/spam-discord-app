import SwiftUI
import UIKit
import AVFoundation // Thêm thư viện âm thanh

// Class quản lý âm thanh chạy ngầm
class SilentAudioManager {
    static let shared = SilentAudioManager()
    private var audioPlayer: AVAudioPlayer?
    
    func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            
            // Tạo một file WAV câm (1 giây) trong bộ nhớ
            let sampleRate = 8000
            let duration = 1
            let numSamples = sampleRate * duration
            let dataSize = numSamples * 2
            
            var header = Data()
            header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
            var chunkSize = UInt32(36 + dataSize).littleEndian
            header.append(Data(bytes: &chunkSize, count: 4))
            header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
            header.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // fmt 
            var subchunk1Size = UInt32(16).littleEndian
            header.append(Data(bytes: &subchunk1Size, count: 4))
            var audioFormat = UInt16(1).littleEndian // PCM
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
            header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
            var dataChunkSize = UInt32(dataSize).littleEndian
            header.append(Data(bytes: &dataChunkSize, count: 4))
            
            let silentData = Data(repeating: 0, count: dataSize)
            let wavData = header + silentData
            
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.numberOfLoops = -1 // Lặp vô hạn
            audioPlayer?.play()
            print("Bắt đầu phát âm thanh chạy ngầm.")
        } catch {
            print("Lỗi khởi tạo âm thanh chạy ngầm: \(error)")
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        print("Đã dừng âm thanh chạy ngầm.")
    }
}

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
    @Published var totalSent = 0
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
        
        // BẬT ÂM THANH CHẠY NGẦM KHI BẮT ĐẦU GỬI
        SilentAudioManager.shared.start()
        
        let mentionText = useTag ? " <@\(targetUserId)>" : ""
        
        Task {
            var currentIndex = 0
            while !isCancelled {
                let msg = messages[currentIndex]
                let sendingLog = LogEntry(text: "Đang gửi: \(msg.body.prefix(20))...", isSuccess: true, isSendingState: true)
                logs.append(sendingLog)
                
                do {
                    try await client.sendMessage(channelId: channel.id, content: "\(msg.body)\(mentionText)")
                    if let idx = logs.firstIndex(where: { $0.id == sendingLog.id }) { logs.remove(at: idx) }
                    logs.append(LogEntry(text: "Đã gửi: \(msg.body.prefix(20))...", isSuccess: true))
                    totalSent += 1
                } catch { 
                    if let idx = logs.firstIndex(where: { $0.id == sendingLog.id }) { logs.remove(at: idx) }
                    logs.append(LogEntry(text: "Lỗi: \(error.localizedDescription)", isSuccess: false)) 
                }
                
                currentIndex = (currentIndex + 1) % messages.count
                let actualDelay = max(0.1, delaySeconds + Double.random(in: -0.3...0.3) * delaySeconds)
                try? await Task.sleep(nanoseconds: UInt64(actualDelay * 1_000_000_000))
            }
            isSending = false
        }
    }
    
    func stopSending() { 
        isCancelled = true 
        isSending = false
        // TẮT ÂM THANH KHI DỪNG
        SilentAudioManager.shared.stop()
    }
    
    func logout() { 
        stopSending()
        KeychainHelper.delete(key: "token")
        token = ""; me = nil; guilds = []; channels = [] 
    }
    
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}