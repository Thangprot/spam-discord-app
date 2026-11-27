import Foundation
import CryptoKit
import CFNetwork
import Darwin
import MachO
import UIKit

// ==============================================================================
// MARK: - FEATURE SCOPES (YÊU CẦU XÁC THỰC KEY TRÊN SERVER CHO TỪNG CHỨC NĂNG)
// ==============================================================================

enum FeatureScope: String, CaseIterable, Hashable {
    case tokens = "tokens"
    case spam = "spam"
    case voice = "voice"
    case music = "music"
    case fakeGame = "fake_game"
    case botNuke = "bot_nuke"
    case userNuke = "user_nuke"
}

// ==============================================================================
// MARK: - SERVER-DELIVERED DTOs (TOÀN BỘ API/ROUTE/HEADER TẢI TỪ CLOUDFLARE, RAM-ONLY)
// ==============================================================================

struct RemoteAssetsDTO: Codable {
    let cdn_avatars: String?
    let cdn_icons: String?
}

struct RemoteRoutesDTO: Codable {
    let me: String?
    let me_guilds: String?
    let guild: String?
    let guild_roles: String?
    let guild_member: String?
    let guild_members: String?
    let guild_channels: String?
    let channel: String?
    let channel_messages: String?
    let guild_ban: String?
    let app_external_assets: String?
}

struct RemoteHeadersDTO: Codable {
    let auth: String?
    let bot_prefix: String?
    let content_type: String?
    let json_mime: String?
    let user_agent: String?
    let super_props: String?
    let locale_key: String?
    let locale_val: String?
    let tz_key: String?
    let tz_val: String?
    let ctx_key: String?
    let ctx_val: String?
    let origin: String?
    let referer: String?
}

struct RemoteVoiceDTO: Codable {
    let ws_scheme: String?
    let ws_query: String?
    let ip_lookup_url: String?
    let aead_aes: String?
    let aead_xchacha: String?
    let gw_os: String?
    let gw_browser: String?
    let gw_device: String?
    let audio_codec: String?
    let video_codec: String?
    let audio_pt: Int?
    let video_pt: Int?
    let rtx_pt: Int?
    let stream_rid: String?
    let rpc_app_id: String?
    let rpc_fallback_app_id: String?
}

struct RemoteConfigDTO: Codable {
    let api_base: String?
    let gateway_url: String?
    let cdn_avatars: String?
    let cdn_icons: String?
    let user_agent_desktop: String?
    let user_agent_mobile: String?
    let user_agent_bot: String?
    let super_properties_desktop: String?
    let super_properties_mobile: String?
    let origin: String?
    let referer: String?
    let everyone_allow: String?
    let routes: RemoteRoutesDTO?
    let headers: RemoteHeadersDTO?
    let voice: RemoteVoiceDTO?
}

struct FeatureAuthResponse: Codable {
    let valid: Bool?
    let feature: String?
    let createdAt: Int64?
    let expiresAt: Int64?
    let sessionToken: String?
    let ephemeralKey: String?
    let featureToken: String?
    let featureExp: Double?
    let config: RemoteConfigDTO?
    let error: String?
    let cracked: Bool?
    let expired: Bool?
    let sessionExpired: Bool?

    enum CodingKeys: String, CodingKey {
        case valid, feature, config, error, cracked, expired
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case sessionToken = "session_token"
        case ephemeralKey = "ephemeral_key"
        case featureToken = "feature_token"
        case featureExp = "feature_exp"
        case sessionExpired = "session_expired"
    }
}

struct GameAssetUploadResponse: Codable {
    let valid: Bool?
    let imageURL: String?
    let error: String?
    let cracked: Bool?
    let expired: Bool?
    let sessionExpired: Bool?

    enum CodingKeys: String, CodingKey {
        case valid, error, cracked, expired
        case imageURL = "image_url"
        case sessionExpired = "session_expired"
    }
}

// ==============================================================================
// MARK: - RAM-ONLY SCOPED REMOTE FEATURE VAULT (CHỨC NĂNG NÀO CHỈ NẠP DỮ LIỆU ĐÓ)
// ==============================================================================

final class RemoteFeatureVault {
    static let shared = RemoteFeatureVault()

    private struct ScopedPermit {
        let config: RemoteConfigDTO
        let token: String
        let exp: Double
    }

    private let lock = NSLock()
    private var _scopes: [FeatureScope: ScopedPermit] = [:]
    private var _externalAssetCache: [String: (assetPath: String, appId: String)] = [:]

    private init() {}

    func applyScopedConfig(_ dto: RemoteConfigDTO, feature: FeatureScope, featureToken: String, featureExp: Double) {
        lock.lock()
        _scopes[feature] = ScopedPermit(config: dto, token: featureToken, exp: featureExp)
        lock.unlock()
    }

    func hasValidPermit(for scope: FeatureScope) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = _scopes[scope] else { return false }
        return entry.exp > Date().timeIntervalSince1970 + 10.0
    }

    func clearAllFunctionalData() {
        lock.lock()
        _scopes.removeAll()
        _externalAssetCache.removeAll()
        lock.unlock()
    }

    func clearInactiveScopes(keeping active: Set<FeatureScope>) {
        lock.lock()
        for key in Array(_scopes.keys) where !active.contains(key) {
            _scopes.removeValue(forKey: key)
        }
        lock.unlock()
    }

    private func validConfig(for scope: FeatureScope) -> RemoteConfigDTO? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = _scopes[scope] else { return nil }
        guard entry.exp > Date().timeIntervalSince1970 else {
            _scopes.removeValue(forKey: scope)
            return nil
        }
        return entry.config
    }

    // Dynamic URL builder từ route template server cấp riêng cho từng chức năng
    func makeURL(scope: FeatureScope, route: KeyPath<RemoteRoutesDTO, String?>, replacements: [String: String] = [:]) -> URL? {
        guard let cfg = validConfig(for: scope),
              let base = cfg.api_base, !base.isEmpty,
              let r = cfg.routes,
              var path = r[keyPath: route], !path.isEmpty else {
            return nil
        }
        for (k, v) in replacements {
            path = path.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return URL(string: "\(base)\(path)")
    }

    func gatewayURL(scope: FeatureScope) -> URL? {
        guard let cfg = validConfig(for: scope),
              let raw = cfg.gateway_url, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    func everyoneAllow(scope: FeatureScope) -> UInt64 {
        guard let cfg = validConfig(for: scope),
              let raw = cfg.everyone_allow else { return 0 }
        return UInt64(raw) ?? 0
    }

    func voiceConfig(scope: FeatureScope) -> RemoteVoiceDTO? {
        return validConfig(for: scope)?.voice
    }

    func defaultRpcAppIds(scope: FeatureScope) -> [String] {
        guard let v = voiceConfig(scope: scope) else { return [] }
        var list: [String] = []
        if let p = v.rpc_app_id, !p.isEmpty { list.append(p) }
        if let f = v.rpc_fallback_app_id, !f.isEmpty, !list.contains(f) { list.append(f) }
        return list
    }

    /// Chuyển đổi link ảnh ngoài thành `mp:external/...` thông qua route server cấp (RAM-cached)
    func resolveExternalGameImage(
        scope: FeatureScope,
        token: String,
        imageURL: String,
        customAppId: String? = nil
    ) async -> (assetPath: String, appId: String)? {
        let trimmedURL = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = []
        if let custom = customAppId?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            candidates.append(custom)
        }
        for id in defaultRpcAppIds(scope: scope) where !candidates.contains(id) {
            candidates.append(id)
        }
        guard let primaryAppId = candidates.first else { return nil }

        if trimmedURL.isEmpty {
            return ("", primaryAppId)
        }
        if trimmedURL.hasPrefix("mp:") {
            return (trimmedURL, primaryAppId)
        }

        let cacheKey = "\(primaryAppId)|\(trimmedURL)"
        lock.lock()
        if let cached = _externalAssetCache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let headers = mobileHeaders(scope: scope, token: token)
        guard !headers.isEmpty else { return nil }

        let sessionCfg = URLSessionConfiguration.ephemeral
        sessionCfg.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: sessionCfg)

        for appId in candidates {
            guard let url = makeURL(scope: scope, route: \.app_external_assets, replacements: ["app_id": appId]) else {
                continue
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            for (hk, hv) in headers { req.setValue(hv, forHTTPHeaderField: hk) }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["urls": [trimmedURL]])

            if let (data, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let extPath = arr.first?["external_asset_path"] as? String,
               !extPath.isEmpty {
                let finalPath = extPath.hasPrefix("mp:") ? extPath : "mp:\(extPath)"
                let result = (assetPath: finalPath, appId: appId)
                lock.lock()
                _externalAssetCache[cacheKey] = result
                lock.unlock()
                return result
            }
        }

        return (trimmedURL, primaryAppId)
    }

    func desktopHeaders(scope: FeatureScope, token: String) -> [String: String] {
        guard let cfg = validConfig(for: scope), let h = cfg.headers else { return [:] }
        var out: [String: String] = [:]
        if let k = h.auth { out[k] = token }
        if let k = h.content_type, let v = h.json_mime { out[k] = v }
        if let k = h.user_agent, let v = cfg.user_agent_desktop { out[k] = v }
        if let k = h.super_props, let v = cfg.super_properties_desktop { out[k] = v }
        if let k = h.locale_key, let v = h.locale_val { out[k] = v }
        return out
    }

    func mobileHeaders(scope: FeatureScope, token: String) -> [String: String] {
        guard let cfg = validConfig(for: scope), let h = cfg.headers else { return [:] }
        var out: [String: String] = [:]
        if let k = h.auth { out[k] = token }
        if let k = h.content_type, let v = h.json_mime { out[k] = v }
        if let k = h.user_agent, let v = cfg.user_agent_mobile { out[k] = v }
        if let k = h.super_props, let v = cfg.super_properties_mobile { out[k] = v }
        if let k = h.locale_key, let v = h.locale_val { out[k] = v }
        if let k = h.tz_key, let v = h.tz_val { out[k] = v }
        if let k = h.ctx_key, let v = h.ctx_val { out[k] = v }
        if let k = h.origin, let v = cfg.origin { out[k] = v }
        if let k = h.referer, let v = cfg.referer { out[k] = v }
        return out
    }

    func botHeaders(scope: FeatureScope, rawToken: String) -> [String: String] {
        guard let cfg = validConfig(for: scope), let h = cfg.headers else { return [:] }
        let c = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = h.bot_prefix ?? ""
        let authVal = (!prefix.isEmpty && !c.lowercased().hasPrefix(prefix.lowercased())) ? "\(prefix)\(c)" : c
        var out: [String: String] = [:]
        if let k = h.auth { out[k] = authVal }
        if let k = h.content_type, let v = h.json_mime { out[k] = v }
        if let k = h.user_agent, let v = cfg.user_agent_bot { out[k] = v }
        return out
    }

    func basicAuthHeaders(scope: FeatureScope, token: String) -> [String: String] {
        guard let cfg = validConfig(for: scope), let h = cfg.headers else { return [:] }
        var out: [String: String] = [:]
        if let k = h.auth { out[k] = token }
        if let k = h.content_type, let v = h.json_mime { out[k] = v }
        return out
    }

    func voiceWebSocketURL(scope: FeatureScope, cleanHost: String) -> URL? {
        guard !cleanHost.isEmpty,
              let v = voiceConfig(scope: scope),
              let scheme = v.ws_scheme, !scheme.isEmpty,
              let query = v.ws_query else { return nil }
        return URL(string: "\(scheme)\(cleanHost)\(query)")
    }

    func gatewayIdentifyProperties(scope: FeatureScope) -> [String: String] {
        guard let v = voiceConfig(scope: scope),
              let os = v.gw_os, let br = v.gw_browser, let dev = v.gw_device else { return [:] }
        return ["os": os, "browser": br, "device": dev]
    }

    func webrtcCodecs(scope: FeatureScope) -> [[String: Any]] {
        guard let v = voiceConfig(scope: scope),
              let audioName = v.audio_codec, let audioPt = v.audio_pt,
              let videoName = v.video_codec, let videoPt = v.video_pt,
              let rtxPt = v.rtx_pt else { return [] }
        return [
            [
                "name": audioName,
                "type": "audio",
                "priority": 1000,
                "payload_type": audioPt
            ],
            [
                "name": videoName,
                "type": "video",
                "priority": 1000,
                "payload_type": videoPt,
                "rtx_payload_type": rtxPt,
                "encode": true,
                "decode": true
            ]
        ]
    }
}

// ==============================================================================
// MARK: - iOS RUNTIME INTEGRITY & LAYER-4 AUDITOR
// ==============================================================================

final class AppIntegrityAuditor {
    static let shared = AppIntegrityAuditor()

    private let lock = NSLock()
    private var cachedTextHash: String?
    private var cachedSourceSig: String?
    private var antiDebugInstalled = false

    private init() {}

    func enforceAntiDebug() {
        #if !DEBUG
        lock.lock()
        let already = antiDebugInstalled
        antiDebugInstalled = true
        lock.unlock()
        if already { return }

        typealias PtraceFn = @convention(c) (CInt, pid_t, UnsafeMutableRawPointer?, CInt) -> CInt
        if let handle = dlopen(nil, RTLD_NOW) {
            defer { dlclose(handle) }
            if let sym = dlsym(handle, "ptrace") {
                let fn = unsafeBitCast(sym, to: PtraceFn.self)
                _ = fn(31, 0, nil, 0)
            }
        }
        #endif
    }

    func isDebuggerAttached() -> Bool {
        #if DEBUG
        return false
        #else
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let res = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        if res != 0 { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
        #endif
    }

    func detectSuspiciousDylibs() -> [String] {
        let blacklist = [
            "frida", "fridagadget", "cycript", "mobilesubstrate", "substrate",
            "substitute", "ellekit", "libhooker", "tweakinject", "cynject",
            "sslkillswitch", "flexdecrypt", "bfdecrypt", "snoop-it", "revealserver"
        ]
        var found: [String] = []
        let count = _dyld_image_count()
        for i in 0..<count {
            if let cName = _dyld_get_image_name(i) {
                let name = String(cString: cName).lowercased()
                for bad in blacklist where name.contains(bad) {
                    found.append(URL(fileURLWithPath: name).lastPathComponent)
                    break
                }
            }
        }
        if let envDylib = getenv("DYLD_INSERT_LIBRARIES") {
            let str = String(cString: envDylib).lowercased()
            if !str.isEmpty {
                for bad in blacklist where str.contains(bad) {
                    found.append("DYLD_INSERT:\(bad)")
                    break
                }
            }
        }
        return found
    }

    /// Phát hiện cấu hình HTTP Proxy hệ thống (Lớp 4 — tùy chọn chặn trên Admin Dashboard)
    func detectNetworkProxy() -> (active: Bool, detail: String) {
        guard let raw = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return (false, "")
        }
        let httpEnable = (raw["HTTPEnable"] as? NSNumber)?.intValue ?? 0
        let httpsEnable = (raw["HTTPSEnable"] as? NSNumber)?.intValue ?? 0
        let host = (raw["HTTPProxy"] as? String) ?? (raw["HTTPSProxy"] as? String) ?? ""
        let port = (raw["HTTPPort"] as? NSNumber)?.intValue ?? (raw["HTTPSPort"] as? NSNumber)?.intValue ?? 0
        if (httpEnable != 0 || httpsEnable != 0) && !host.isEmpty {
            return (true, "\(host):\(port)")
        }
        return (false, "")
    }

    func computeTextSectionHash() -> String {
        lock.lock()
        if let cached = cachedTextHash {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let rawHdr = _dyld_get_image_header(0) else { return "" }
        let slide = _dyld_get_image_vmaddr_slide(0)
        let sectOpt: UnsafePointer<section_64>? = rawHdr.withMemoryRebound(to: mach_header_64.self, capacity: 1) { hdr64 in
            getsectbynamefromheader_64(hdr64, "__TEXT", "__text")
        }
        guard let sect = sectOpt else { return "" }

        let addr = UInt(sect.pointee.addr) &+ UInt(bitPattern: slide)
        let size = Int(sect.pointee.size)
        guard size > 0, let ptr = UnsafeRawPointer(bitPattern: addr) else { return "" }

        let buf = UnsafeRawBufferPointer(start: ptr, count: size)
        let digest = SHA256.hash(data: buf)
        let hex = digest.map { String(format: "%02x", $0) }.joined()

        lock.lock()
        cachedTextHash = hex
        lock.unlock()
        return hex
    }

    func computeSourceSignature() -> String {
        lock.lock()
        if let cached = cachedSourceSig {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var data = Data()
        data.append(contentsOf: AppSecrets.baseURL)
        data.append(0x7C)
        data.append(contentsOf: AppSecrets.masterSecret)
        data.append(contentsOf: "QT_ANTI_TAMPER_V3".utf8)
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        lock.lock()
        cachedSourceSig = hex
        lock.unlock()
        return hex
    }

    func collectReport() -> (payload: [String: Any], tampered: Bool, reasons: [String]) {
        var reasons: [String] = []
        if isDebuggerAttached() {
            reasons.append("debugger_attached")
        }
        let dylibs = detectSuspiciousDylibs()
        if !dylibs.isEmpty {
            reasons.append("injected_dylib:\(dylibs.joined(separator: ","))")
        }

        let proxy = detectNetworkProxy()
        let textHash = computeTextSectionHash()
        let sourceSig = computeSourceSignature()
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let tampered = !reasons.isEmpty

        let payload: [String: Any] = [
            "text_hash": textHash,
            "source_sig": sourceSig,
            "bundle_id": bundleId,
            "tampered": tampered,
            "reasons": reasons,
            "proxy_active": proxy.active,
            "proxy_detail": proxy.detail
        ]
        return (payload, tampered, reasons)
    }
}
