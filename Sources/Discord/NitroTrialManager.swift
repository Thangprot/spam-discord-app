import SwiftUI
import Foundation
import UIKit

// ==============================================================================
// MARK: - NITRO TRIAL MODELS & ENUMS
// ==============================================================================

enum NitroPremiumTier: Int, Codable, Equatable, Sendable {
    case none = 0
    case nitroClassic = 1
    case nitroFull = 2
    case nitroBasic = 3

    var displayName: String {
        switch self {
        case .none: return "Free"
        case .nitroClassic: return "Nitro Classic"
        case .nitroFull: return "Nitro"
        case .nitroBasic: return "Nitro Basic"
        }
    }

    var shortBadge: String {
        switch self {
        case .none: return "FREE"
        case .nitroClassic: return "CLASSIC"
        case .nitroFull: return "NITRO"
        case .nitroBasic: return "BASIC"
        }
    }

    var isNitro: Bool { self != .none }
}

enum NitroTrialOfferSource: String, Codable, Equatable, Sendable {
    case userOffer = "Discord Offer"
    case trialOffersList = "Trial Offers"
    case referral = "Bạn bè tặng Trial"
    case promoLink = "Link Promo Trial"
}

struct NitroSubscriptionTrial: Codable, Equatable, Sendable {
    let id: String
    let interval: Int
    let intervalCount: Int
    let skuId: String

    enum CodingKeys: String, CodingKey {
        case id, interval
        case intervalCount = "interval_count"
        case skuId = "sku_id"
    }

    var skuDisplayName: String {
        switch skuId {
        case "521847234246082599": return "Discord Nitro"
        case "978380684370378762": return "Nitro Basic"
        case "521842865731534868": return "Nitro Classic"
        default: return "Nitro Trial"
        }
    }

    var durationText: String {
        switch interval {
        case 1:
            return "\(intervalCount) tháng"
        case 2:
            return "\(intervalCount) năm"
        case 3:
            if intervalCount % 7 == 0 && intervalCount >= 7 {
                let weeks = intervalCount / 7
                return "\(intervalCount) ngày (\(weeks) tuần)"
            }
            return "\(intervalCount) ngày"
        default:
            return "\(intervalCount) kỳ"
        }
    }

    var fallbackMonthlyPlanId: String {
        switch skuId {
        case "521847234246082599": return "511651880837840896" // Nitro Monthly
        case "978380684370378762": return "978380692553465866" // Nitro Basic Monthly
        case "521842865731534868": return "511651871736201216" // Nitro Classic Monthly
        default: return "511651880837840896"
        }
    }
}

struct NitroTrialOffer: Identifiable, Equatable, Sendable {
    let id: String
    let userId: String?
    let trialId: String
    let expiresAt: String?
    let subscriptionTrial: NitroSubscriptionTrial?
    let referrerId: String?
    let source: NitroTrialOfferSource

    var title: String {
        if let st = subscriptionTrial {
            return "\(st.skuDisplayName) • \(st.durationText)"
        }
        return "Discord Nitro Trial"
    }

    var shortDurationBadge: String {
        if let st = subscriptionTrial {
            return "TRIAL \(st.durationText.uppercased())"
        }
        return "CÓ TRIAL"
    }

    var isAcknowledged: Bool {
        if let exp = expiresAt, !exp.isEmpty { return true }
        return false
    }
}

struct NitroDiscountOffer: Identifiable, Equatable, Sendable {
    let id: String
    let discountId: String?
    let expiresAt: String?
    let amountPercent: Int?
    let planIds: [String]

    var summary: String {
        if let pct = amountPercent, pct > 0 {
            return "Ưu đãi giảm \(pct)% Nitro"
        }
        return "Ưu đãi giảm giá Nitro"
    }
}

struct NitroPaymentSource: Identifiable, Equatable, Sendable {
    let id: String
    let type: Int
    let invalid: Bool
    let isDefault: Bool
    let brand: String?
    let last4: String?
    let expiresMonth: Int?
    let expiresYear: Int?
    let email: String?
    let country: String?
    let currency: String?

    var isValid: Bool { !invalid }

    var displayName: String {
        switch type {
        case 1:
            let b = (brand ?? "Card").uppercased()
            let l4 = last4 ?? "****"
            return "\(b) •••• \(l4)"
        case 2:
            if let em = email, !em.isEmpty { return "PayPal (\(em))" }
            return "PayPal"
        case 3: return "Giropay"
        case 4: return "Sofort"
        case 5: return "Przelewy24"
        case 6: return "SEPA Debit"
        case 7: return "Paysafecard"
        case 8: return "GCash"
        case 9: return "GrabPay"
        case 10: return "MoMo"
        case 11: return "Venmo"
        case 12: return "GoPay"
        case 13: return "KakaoPay"
        case 14: return "Bancontact"
        case 15: return "EPS"
        case 16: return "iDEAL"
        case 17: return "Cash App"
        case 18: return "Apple Pay"
        default: return "Ví/Thẻ #\(type)"
        }
    }
}

struct NitroSubscription: Identifiable, Equatable, Sendable {
    let id: String
    let type: Int
    let status: Int
    let planId: String?
    let trialId: String?
    let trialEndsAt: String?
    let currentPeriodEnd: String?
    let paymentSourceId: String?
    let canceledAt: String?
    let currency: String?

    var isActive: Bool { status == 1 }
    var isCanceled: Bool { status == 3 || canceledAt != nil }
    var isTrial: Bool { trialId != nil || trialEndsAt != nil }

    var endDateString: String? {
        trialEndsAt ?? currentPeriodEnd
    }
}

struct NitroOutboundPromo: Identifiable, Equatable, Sendable {
    let id: String
    let code: String
    let title: String
    let claimedAt: String?
}

struct NitroBillingUser: Sendable {
    let id: String
    let username: String
    let globalName: String?
    let avatar: String?
    let premiumType: NitroPremiumTier
    let verified: Bool?
    let email: String?
    let phone: String?

    var displayName: String {
        if let g = globalName, !g.isEmpty { return g }
        return username
    }
}

struct NitroInvoicePreview: Sendable {
    let total: Int
    let subtotal: Int
    let currency: String
    let renewalAmount: Int?
}

struct NitroGiftCodeInfo: Sendable {
    let code: String
    let planId: String?
    let planName: String?
    let skuId: String?
    let promotionId: String?
    let redeemed: Bool
    let uses: Int
    let maxUses: Int
    let expiresAt: String?

    var isClaimable: Bool {
        if redeemed { return false }
        if maxUses > 0 && uses >= maxUses { return false }
        return true
    }

    var isTrialPromotion: Bool {
        promotionId != nil
    }
}

enum NitroTokenState: Equatable, Sendable {
    case idle
    case scanning
    case claiming
    case trialAvailable
    case claimed
    case alreadyNitro
    case discountOnly
    case needsPayment
    case needsVerification
    case noOffer
    case tokenDead
    case error(String)

    var badgeText: String {
        switch self {
        case .idle: return "CHƯA QUÉT"
        case .scanning: return "ĐANG QUÉT"
        case .claiming: return "ĐANG CLAIM"
        case .trialAvailable: return "CÓ TRIAL"
        case .claimed: return "ĐÃ CLAIM"
        case .alreadyNitro: return "ĐANG NITRO"
        case .discountOnly: return "GIẢM GIÁ"
        case .needsPayment: return "CẦN THẺ"
        case .needsVerification: return "XÁC MINH"
        case .noOffer: return "KHÔNG CÓ"
        case .tokenDead: return "DIE"
        case .error: return "LỖI"
        }
    }

    var badgeColor: Color {
        switch self {
        case .idle, .noOffer: return .secondary
        case .scanning, .claiming: return .indigo
        case .trialAvailable: return Color(red: 0.93, green: 0.28, blue: 0.60)
        case .claimed: return .green
        case .alreadyNitro: return .purple
        case .discountOnly: return .blue
        case .needsPayment: return .orange
        case .needsVerification: return .yellow
        case .tokenDead, .error: return .red
        }
    }

    var iconName: String {
        switch self {
        case .idle: return "clock"
        case .scanning: return "magnifyingglass"
        case .claiming: return "sparkles"
        case .trialAvailable: return "gift.fill"
        case .claimed: return "checkmark.seal.fill"
        case .alreadyNitro: return "crown.fill"
        case .discountOnly: return "tag.fill"
        case .needsPayment: return "creditcard.trianglebadge.exclamationmark"
        case .needsVerification: return "exclamationmark.shield.fill"
        case .noOffer: return "minus.circle"
        case .tokenDead: return "xmark.octagon.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

struct NitroTokenScanResult: Identifiable, Equatable, Sendable {
    let id: UUID
    let token: String
    var userId: String
    var username: String
    var avatarHash: String?
    var state: NitroTokenState = .idle
    var premiumTier: NitroPremiumTier = .none
    var emailVerified: Bool? = nil
    var hasPhone: Bool = false
    var countryCode: String? = nil
    var paymentSources: [NitroPaymentSource] = []
    var activeSubscriptions: [NitroSubscription] = []
    var trialOffers: [NitroTrialOffer] = []
    var discountOffer: NitroDiscountOffer? = nil
    var outboundPromos: [NitroOutboundPromo] = []
    var claimedSubscriptionId: String? = nil
    var claimedTrialEndsAt: String? = nil
    var autoRenewCanceled: Bool = false
    var statusDetail: String = "Chưa quét"
    var lastUpdatedAt: Date? = nil

    var avatarURL: URL? {
        guard let h = avatarHash, !h.isEmpty, !AppEndpoints.cdnAvatars.isEmpty else { return nil }
        return URL(string: "\(AppEndpoints.cdnAvatars)/\(userId)/\(h).png?size=128")
    }

    var validPaymentSources: [NitroPaymentSource] {
        paymentSources.filter { $0.isValid }
    }

    var preferredPaymentSource: NitroPaymentSource? {
        validPaymentSources.first(where: { $0.isDefault }) ?? validPaymentSources.first
    }

    var primaryOffer: NitroTrialOffer? {
        trialOffers.first
    }

    var activeNitroSub: NitroSubscription? {
        activeSubscriptions.first(where: { $0.isActive }) ?? activeSubscriptions.first
    }

    var canAttemptClaim: Bool {
        guard !trialOffers.isEmpty else { return false }
        switch state {
        case .trialAvailable, .needsPayment, .needsVerification, .error:
            return true
        default:
            return false
        }
    }
}

struct NitroLogEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let message: String
    let level: Level

    enum Level: Sendable {
        case info, success, warning, error
    }

    init(id: UUID = UUID(), timestamp: Date = Date(), message: String, level: Level = .info) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
        self.level = level
    }

    var formattedTime: String {
        NitroDateHelper.timeFormatter.string(from: timestamp)
    }
}

enum NitroResultFilter: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case trial = "Có Trial"
    case claimed = "Đã Claim"
    case alreadyNitro = "Đang Nitro"
    case needsPayment = "Cần thẻ"
    case others = "Khác"

    var id: String { rawValue }
}

enum NitroAutoInterval: Int, CaseIterable, Identifiable {
    case min15 = 15
    case min30 = 30
    case hour1 = 60
    case hour3 = 180
    case hour6 = 360

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .min15: return "15 phút"
        case .min30: return "30 phút"
        case .hour1: return "1 giờ"
        case .hour3: return "3 giờ"
        case .hour6: return "6 giờ"
        }
    }
}

enum NitroDateHelper {
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f
    }()

    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO(_ raw: String?) -> Date? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        if let d = isoWithFractional.date(from: raw) { return d }
        return isoStandard.date(from: raw)
    }

    static func formatDisplay(_ raw: String?) -> String? {
        guard let d = parseISO(raw) else { return nil }
        return displayFormatter.string(from: d)
    }
}

// ==============================================================================
// MARK: - DISCORD NITRO API ERRORS
// ==============================================================================

enum NitroAPIError: LocalizedError, Sendable {
    case securityPermitInvalid
    case invalidEndpoint
    case unauthorized
    case rateLimited(retryAfter: Double)
    case captchaRequired(service: String?)
    case paymentSourceRequired(String)
    case paymentAuthRequired(String)
    case verificationRequired(String)
    case nonZeroChargeBlocked(amount: Int, currency: String)
    case notEligible(String)
    case httpError(code: Int, discordCode: Int?, message: String)

    var errorDescription: String? {
        switch self {
        case .securityPermitInvalid:
            return "Chưa xác thực bản quyền thực thi"
        case .invalidEndpoint:
            return "Endpoint Discord chưa sẵn sàng"
        case .unauthorized:
            return "Token chết hoặc hết hạn (401)"
        case .rateLimited(let sec):
            return String(format: "Bị Discord rate-limit (đợi %.1fs)", sec)
        case .captchaRequired(let svc):
            let name = svc ?? "hCaptcha"
            return "Discord yêu cầu xác minh CAPTCHA (\(name)) — hãy hoàn tất trên app Discord"
        case .paymentSourceRequired(let msg):
            return msg.isEmpty ? "Cần gắn thẻ/PayPal/MoMo hợp lệ trên Discord để claim gói này" : msg
        case .paymentAuthRequired(let msg):
            return msg.isEmpty ? "Thẻ/ngân hàng yêu cầu xác thực 3DS trên trình duyệt Discord" : msg
        case .verificationRequired(let msg):
            return msg.isEmpty ? "Tài khoản cần xác minh Email hoặc SĐT trước khi nhận Trial" : msg
        case .nonZeroChargeBlocked(let amount, let currency):
            let formatted = String(format: "%.2f %@", Double(amount) / 100.0, currency.uppercased())
            return "Chặn claim tự động: hóa đơn preview là \(formatted) (không miễn phí 0đ)"
        case .notEligible(let msg):
            return msg.isEmpty ? "Tài khoản không đủ điều kiện nhận gói Trial này" : msg
        case .httpError(let code, let dcCode, let msg):
            if let dc = dcCode {
                return "Lỗi Discord (\(code)/\(dc)): \(msg)"
            }
            return "Lỗi HTTP \(code): \(msg)"
        }
    }
}

// ==============================================================================
// MARK: - DISCORD NITRO BILLING & TRIAL CLIENT
// ==============================================================================

final class DiscordNitroClient: @unchecked Sendable {
    let token: String
    private let session: URLSession

    init(token: String) {
        self.token = token
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 35
        cfg.httpAdditionalHeaders = [
            "Authorization": token,
            "Content-Type": "application/json",
            "Accept": "*/*",
            "User-Agent": AppEndpoints.userAgentDesktop,
            "X-Super-Properties": AppEndpoints.superPropertiesDesktop,
            "X-Discord-Locale": "en-US",
            "X-Discord-Timezone": TimeZone.current.identifier,
            "Origin": AppEndpoints.origin,
            "Referer": AppEndpoints.referer
        ]
        self.session = URLSession(configuration: cfg)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    // MARK: Core HTTP helper with 429 retry & Discord error classifier
    private func performRequest(
        path: String,
        method: String = "GET",
        jsonBody: [String: Any]? = nil,
        allow404AsEmpty: Bool = false
    ) async throws -> (statusCode: Int, data: Data) {
        guard SecurityGuard.shared.verifyExecutionPermit() else {
            throw NitroAPIError.securityPermitInvalid
        }
        guard !AppEndpoints.apiBase.isEmpty,
              let url = URL(string: "\(AppEndpoints.apiBase)\(path)") else {
            throw NitroAPIError.invalidEndpoint
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        if let body = jsonBody {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        var attempts = 0
        while attempts < 4 {
            try Task.checkCancellation()
            attempts += 1
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw NitroAPIError.httpError(code: 0, discordCode: nil, message: "Phản hồi không hợp lệ")
            }

            if http.statusCode == 429 {
                let retry = Self.extractRetryAfter(from: data, headers: http.allHeaderFields)
                if attempts < 4 {
                    let wait = min(max(retry, 0.5), 15.0) + 0.25
                    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    continue
                }
                throw NitroAPIError.rateLimited(retryAfter: retry)
            }

            if http.statusCode == 401 {
                throw NitroAPIError.unauthorized
            }

            if allow404AsEmpty && (http.statusCode == 404 || http.statusCode == 204 || http.statusCode == 405) {
                return (http.statusCode, Data())
            }

            if (200...299).contains(http.statusCode) {
                return (http.statusCode, data)
            }

            throw Self.classifyError(statusCode: http.statusCode, data: data)
        }

        throw NitroAPIError.rateLimited(retryAfter: 5.0)
    }

    private static func extractRetryAfter(from data: Data, headers: [AnyHashable: Any]) -> Double {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let r = json["retry_after"] as? Double {
            return r
        }
        for (k, v) in headers {
            if String(describing: k).lowercased() == "retry-after",
               let s = v as? String, let d = Double(s) {
                return d
            }
        }
        return 2.0
    }

    private static func extractNestedErrorMessage(_ obj: Any) -> String? {
        if let dict = obj as? [String: Any] {
            if let errs = dict["_errors"] as? [[String: Any]],
               let first = errs.first,
               let msg = first["message"] as? String, !msg.isEmpty {
                return msg
            }
            for (_, v) in dict {
                if let found = extractNestedErrorMessage(v) {
                    return found
                }
            }
        } else if let arr = obj as? [Any] {
            for item in arr {
                if let found = extractNestedErrorMessage(item) {
                    return found
                }
            }
        }
        return nil
    }

    private static func classifyError(statusCode: Int, data: Data) -> NitroAPIError {
        let rawText = String(data: data, encoding: .utf8) ?? ""
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .httpError(code: statusCode, discordCode: nil, message: rawText.isEmpty ? "HTTP \(statusCode)" : String(rawText.prefix(160)))
        }

        if json["captcha_key"] != nil {
            let service = json["captcha_service"] as? String
            return .captchaRequired(service: service)
        }

        let dcCode = json["code"] as? Int
        var message = (json["message"] as? String) ?? ""
        if let errorsObj = json["errors"], let nested = extractNestedErrorMessage(errorsObj) {
            if message.isEmpty || message.lowercased().contains("invalid form body") {
                message = nested
            } else {
                message = "\(message) (\(nested))"
            }
        }
        let lower = message.lowercased()

        // 3DS / payment intent confirmation required
        if json["payment_id"] != nil || json["payment_intent"] != nil || dcCode == 100024 || lower.contains("authentication") || lower.contains("3d secure") {
            return .paymentAuthRequired(message)
        }

        // Verification (email / phone) required
        if dcCode == 40002 || lower.contains("verify your account") || (lower.contains("email") && lower.contains("verif")) {
            return .verificationRequired(message)
        }

        // Payment source missing / invalid / required
        if dcCode == 100028 || dcCode == 100004 || dcCode == 100007 || dcCode == 50048
            || lower.contains("payment source") || lower.contains("payment_source")
            || lower.contains("payment method") || lower.contains("billing address")
            || (lower.contains("card") && lower.contains("declined")) {
            return .paymentSourceRequired(message)
        }

        // Not eligible / already redeemed / already subscribed
        if lower.contains("not eligible") || lower.contains("already") || lower.contains("ineligible") || dcCode == 50050 || dcCode == 100015 {
            return .notEligible(message)
        }

        return .httpError(code: statusCode, discordCode: dcCode, message: message.isEmpty ? "HTTP \(statusCode)" : message)
    }

    // MARK: - 1. Account & Billing Inspection

    func fetchUser() async throws -> NitroBillingUser {
        let (_, data) = try await performRequest(path: "/users/@me")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let username = json["username"] as? String else {
            throw NitroAPIError.httpError(code: 200, discordCode: nil, message: "Không đọc được thông tin tài khoản")
        }
        let premiumRaw = json["premium_type"] as? Int ?? 0
        return NitroBillingUser(
            id: id,
            username: username,
            globalName: json["global_name"] as? String,
            avatar: json["avatar"] as? String,
            premiumType: NitroPremiumTier(rawValue: premiumRaw) ?? .none,
            verified: json["verified"] as? Bool,
            email: json["email"] as? String,
            phone: json["phone"] as? String
        )
    }

    func fetchSubscriptions() async -> [NitroSubscription] {
        guard let (_, data) = try? await performRequest(path: "/users/@me/billing/subscriptions", allow404AsEmpty: true),
              !data.isEmpty,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { Self.parseSubscription($0) }
    }

    func fetchPaymentSources() async -> [NitroPaymentSource] {
        guard let (_, data) = try? await performRequest(path: "/users/@me/billing/payment-sources", allow404AsEmpty: true),
              !data.isEmpty,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { dict -> NitroPaymentSource? in
            guard let id = dict["id"] as? String else { return nil }
            let billingAddr = dict["billing_address"] as? [String: Any]
            return NitroPaymentSource(
                id: id,
                type: dict["type"] as? Int ?? 0,
                invalid: dict["invalid"] as? Bool ?? false,
                isDefault: dict["default"] as? Bool ?? false,
                brand: dict["brand"] as? String,
                last4: dict["last_4"] as? String,
                expiresMonth: dict["expires_month"] as? Int,
                expiresYear: dict["expires_year"] as? Int,
                email: dict["email"] as? String,
                country: (dict["country"] as? String) ?? (billingAddr?["country"] as? String),
                currency: dict["currency"] as? String
            )
        }
    }

    func fetchCountryCode() async -> String? {
        guard let (_, data) = try? await performRequest(path: "/users/@me/billing/country-code", allow404AsEmpty: true),
              !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["country_code"] as? String
    }

    func fetchOutboundPromotions() async -> [NitroOutboundPromo] {
        guard let (_, data) = try? await performRequest(path: "/users/@me/outbound-promotions/codes", allow404AsEmpty: true),
              !data.isEmpty,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { item in
            guard let code = item["code"] as? String, !code.isEmpty else { return nil }
            let promo = item["promotion"] as? [String: Any]
            let pid = (item["promotion_id"] as? String) ?? (promo?["id"] as? String) ?? code
            let title = (promo?["outbound_title"] as? String) ?? "Discord Outbound Promo"
            return NitroOutboundPromo(
                id: pid,
                code: code,
                title: title,
                claimedAt: item["claimed_at"] as? String
            )
        }
    }

    // MARK: - 2. Scan ALL Nitro Trial & Discount Offer Endpoints

    func fetchAllOffers() async -> (trials: [NitroTrialOffer], discount: NitroDiscountOffer?) {
        var foundTrials: [NitroTrialOffer] = []
        var foundDiscount: NitroDiscountOffer? = nil

        // Source A: POST /users/@me/billing/user-offer (Endpoint chính của Discord Client)
        if let (_, data) = try? await performRequest(
            path: "/users/@me/billing/user-offer",
            method: "POST",
            jsonBody: [:],
            allow404AsEmpty: true
        ), !data.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let trialObj = json["user_trial_offer"] as? [String: Any],
               let offer = Self.parseTrialOffer(trialObj, source: .userOffer) {
                foundTrials.append(offer)
            }
            if let discObj = json["user_discount_offer"] as? [String: Any],
               let disc = Self.parseDiscountOffer(discObj) {
                foundDiscount = disc
            }
        }

        // Source B: GET /users/@me/billing/user-trial-offers (Endpoint phụ / danh sách nhiều trial)
        if let (_, data) = try? await performRequest(
            path: "/users/@me/billing/user-trial-offers",
            method: "GET",
            allow404AsEmpty: true
        ), !data.isEmpty {
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for obj in arr {
                    if let offer = Self.parseTrialOffer(obj, source: .trialOffersList) {
                        Self.appendUnique(offer, to: &foundTrials)
                    }
                }
            } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let offer = Self.parseTrialOffer(obj, source: .trialOffersList) {
                Self.appendUnique(offer, to: &foundTrials)
            }
        }

        // Source C: GET /users/@me/billing/user-trial-offer (Single fallback)
        if foundTrials.isEmpty,
           let (_, data) = try? await performRequest(
            path: "/users/@me/billing/user-trial-offer",
            method: "GET",
            allow404AsEmpty: true
           ), !data.isEmpty,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let offer = Self.parseTrialOffer(obj, source: .trialOffersList) {
            Self.appendUnique(offer, to: &foundTrials)
        }

        // Source D: GET /users/@me/referrals (Friend Referral Nitro Trial 2 tuần)
        if let (_, data) = try? await performRequest(
            path: "/users/@me/referrals",
            method: "GET",
            allow404AsEmpty: true
        ), !data.isEmpty {
            let referralDicts: [[String: Any]]
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                referralDicts = arr
            } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let nested = obj["referrals"] as? [[String: Any]] {
                referralDicts = nested
            } else {
                referralDicts = []
            }

            for ref in referralDicts {
                if let trialObj = ref["user_trial_offer"] as? [String: Any],
                   let offer = Self.parseTrialOffer(trialObj, source: .referral) {
                    Self.appendUnique(offer, to: &foundTrials)
                } else if let offer = Self.parseTrialOffer(ref, source: .referral) {
                    Self.appendUnique(offer, to: &foundTrials)
                }
            }
        }

        return (foundTrials, foundDiscount)
    }

    // MARK: - 3. Acknowledge Offer, Resolve Plan, Preview (0đ Guard) & Redeem

    func acknowledgeTrialOffer(_ offer: NitroTrialOffer) async -> NitroTrialOffer {
        // Endpoint chính: POST /users/@me/billing/user-offer/ack
        let body: [String: Any] = [
            "user_trial_offer_id": offer.id,
            "user_discount_offer_id": NSNull()
        ]
        if let (code, data) = try? await performRequest(
            path: "/users/@me/billing/user-offer/ack",
            method: "POST",
            jsonBody: body,
            allow404AsEmpty: true
        ), (200...299).contains(code), !data.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let updatedObj = json["user_trial_offer"] as? [String: Any],
               let updated = Self.parseTrialOffer(updatedObj, source: offer.source) {
                return updated
            }
            if let updated = Self.parseTrialOffer(json, source: offer.source) {
                return updated
            }
        }

        // Endpoint fallback: POST /users/@me/billing/user-trial-offers/{id}/ack
        if let (code, data) = try? await performRequest(
            path: "/users/@me/billing/user-trial-offers/\(offer.id)/ack",
            method: "POST",
            jsonBody: [:],
            allow404AsEmpty: true
        ), (200...299).contains(code), !data.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let updated = Self.parseTrialOffer(json, source: offer.source) {
            return updated
        }

        return offer
    }

    func resolvePlanId(for trial: NitroSubscriptionTrial?) async -> String {
        guard let trial = trial else { return "511651880837840896" }
        let skuId = trial.skuId

        // Thử lấy danh sách subscription-plans động từ Discord Store trước
        if let (_, data) = try? await performRequest(
            path: "/store/skus/\(skuId)/subscription-plans",
            method: "GET",
            allow404AsEmpty: true
        ), !data.isEmpty,
           let plans = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            // Ưu tiên gói hàng tháng (interval == 1, interval_count == 1)
            if let monthly = plans.first(where: {
                ($0["interval"] as? Int) == 1 && ($0["interval_count"] as? Int) == 1
            }), let pid = monthly["id"] as? String {
                return pid
            }
            if let first = plans.first, let pid = first["id"] as? String {
                return pid
            }
        }

        return trial.fallbackMonthlyPlanId
    }

    func previewTrialSubscription(
        planId: String,
        trialId: String?,
        promoCode: String? = nil,
        paymentSourceId: String?,
        currency: String?
    ) async throws -> NitroInvoicePreview {
        var body: [String: Any] = [
            "items": [["plan_id": planId, "quantity": 1]]
        ]
        if let tid = trialId, !tid.isEmpty {
            body["trial_id"] = tid
        }
        if let code = promoCode, !code.isEmpty {
            body["code"] = code
        }
        if let psid = paymentSourceId, !psid.isEmpty {
            body["payment_source_id"] = psid
        }
        if let cur = currency, !cur.isEmpty {
            body["currency"] = cur.lowercased()
        }

        let (_, data) = try await performRequest(
            path: "/users/@me/billing/subscriptions/preview",
            method: "POST",
            jsonBody: body
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NitroAPIError.httpError(code: 200, discordCode: nil, message: "Không đọc được hóa đơn preview")
        }

        let total = json["total"] as? Int ?? -1
        let subtotal = json["subtotal"] as? Int ?? total
        let resolvedCurrency = (json["currency"] as? String) ?? currency ?? "usd"
        let renewalDict = json["renewal_invoice"] as? [String: Any]
        let renewalAmount = renewalDict?["total"] as? Int

        if total != 0 {
            throw NitroAPIError.nonZeroChargeBlocked(amount: max(total, 0), currency: resolvedCurrency)
        }

        return NitroInvoicePreview(
            total: total,
            subtotal: subtotal,
            currency: resolvedCurrency.lowercased(),
            renewalAmount: renewalAmount
        )
    }

    /// Claim gói Nitro Trial đã quét thấy trên tài khoản (có bảo vệ preview == 0đ!)
    func claimTrialOffer(
        _ rawOffer: NitroTrialOffer,
        paymentSource: NitroPaymentSource?,
        countryCode: String?
    ) async throws -> (subscription: NitroSubscription?, usedNoCardFallback: Bool) {
        // 1. Ack offer nếu chưa ack
        let offer = await acknowledgeTrialOffer(rawOffer)
        let planId = await resolvePlanId(for: offer.subscriptionTrial)
        let preferredCurrency = Self.resolveCurrency(paymentSource: paymentSource, countryCode: countryCode)

        // 2. Nếu không có thẻ, thử preview không thẻ trước; nếu Discord có Reverse Trial / user-offer/redeem
        let psId = paymentSource?.id
        var resolvedCurrency = preferredCurrency
        var renewalAmount: Int? = nil

        do {
            let preview = try await previewTrialSubscription(
                planId: planId,
                trialId: offer.trialId,
                paymentSourceId: psId,
                currency: preferredCurrency
            )
            resolvedCurrency = preview.currency
            renewalAmount = preview.renewalAmount
        } catch let apiErr as NitroAPIError {
            // Nếu bị chặn vì giá > 0đ -> DỪNG NGAY LẬP TỨC, không thử fallback!
            if case .nonZeroChargeBlocked = apiErr { throw apiErr }
            // Nếu không có thẻ và preview fail, thử fallback endpoint Reverse Trial (user-offer/redeem) không tính phí
            if psId == nil {
                if let sub = try? await tryRedeemNoCardUserOffer(offerId: offer.id) {
                    return (sub, true)
                }
            }
            throw apiErr
        }

        // 3. Tạo subscription với expected_invoice_price = 0 để đảm bảo 100% miễn phí
        var body: [String: Any] = [
            "items": [["plan_id": planId, "quantity": 1]],
            "trial_id": offer.trialId,
            "currency": resolvedCurrency,
            "expected_invoice_price": [
                "amount": 0,
                "currency": resolvedCurrency
            ]
        ]
        if let psId = psId {
            body["payment_source_id"] = psId
        }
        if let renew = renewalAmount, renew >= 0 {
            body["expected_renewal_price"] = [
                "amount": renew,
                "currency": resolvedCurrency
            ]
        }

        do {
            let (_, data) = try await performRequest(
                path: "/users/@me/billing/subscriptions",
                method: "POST",
                jsonBody: body
            )
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sub = Self.parseSubscription(json) {
                return (sub, psId == nil)
            }
            return (nil, psId == nil)
        } catch let apiErr as NitroAPIError {
            if psId == nil {
                if case .captchaRequired = apiErr { throw apiErr }
                if case .verificationRequired = apiErr { throw apiErr }
                if let sub = try? await tryRedeemNoCardUserOffer(offerId: offer.id) {
                    return (sub, true)
                }
            }
            throw apiErr
        }
    }

    /// Fallback cho các gói Trial không cần thẻ (Reverse Trial / Instant Trial)
    private func tryRedeemNoCardUserOffer(offerId: String) async throws -> NitroSubscription? {
        let body: [String: Any] = [
            "user_trial_offer_id": offerId,
            "payment_source_id": NSNull()
        ]
        let (code, data) = try await performRequest(
            path: "/users/@me/billing/user-offer/redeem",
            method: "POST",
            jsonBody: body,
            allow404AsEmpty: true
        )
        guard (200...299).contains(code), !data.isEmpty else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let subDict = json["subscription"] as? [String: Any] {
                return Self.parseSubscription(subDict)
            }
            return Self.parseSubscription(json)
        }
        return nil
    }

    /// Tắt tự động gia hạn sau khi claim thành công (giữ nguyên toàn bộ thời gian Nitro Trial!)
    func cancelAutoRenewal(subscriptionId: String) async throws {
        _ = try await performRequest(
            path: "/users/@me/billing/subscriptions/\(subscriptionId)",
            method: "DELETE"
        )
    }

    // MARK: - 4. Promo / Gift Trial Link Support

    static func extractPromoCode(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clean = trimmed.components(separatedBy: "?").first ?? trimmed
        if clean.contains("/") {
            let parts = clean.split(separator: "/").map(String.init)
            if let last = parts.last, !last.isEmpty {
                return last
            }
        }
        return clean
    }

    func fetchGiftOrPromoInfo(code: String) async throws -> NitroGiftCodeInfo {
        let (_, data) = try await performRequest(
            path: "/entitlements/gift-codes/\(code)?with_application=false&with_subscription_plan=true",
            method: "GET"
        )
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NitroAPIError.httpError(code: 200, discordCode: nil, message: "Không đọc được thông tin mã Promo/Gift")
        }
        let plan = json["subscription_plan"] as? [String: Any]
        let storeListing = json["store_listing"] as? [String: Any]
        let promo = json["promotion"] as? [String: Any]
        return NitroGiftCodeInfo(
            code: (json["code"] as? String) ?? code,
            planId: (json["subscription_plan_id"] as? String) ?? (plan?["id"] as? String),
            planName: (plan?["name"] as? String) ?? (storeListing?["name"] as? String) ?? (promo?["inbound_header_text"] as? String),
            skuId: (json["sku_id"] as? String) ?? (storeListing?["sku_id"] as? String),
            promotionId: (json["promotion_id"] as? String) ?? (promo?["id"] as? String),
            redeemed: json["redeemed"] as? Bool ?? false,
            uses: json["uses"] as? Int ?? 0,
            maxUses: json["max_uses"] as? Int ?? 1,
            expiresAt: json["expires_at"] as? String
        )
    }

    func redeemGiftOrPromo(
        info: NitroGiftCodeInfo,
        paymentSource: NitroPaymentSource?,
        countryCode: String?
    ) async throws -> NitroSubscription? {
        guard info.isClaimable else {
            throw NitroAPIError.notEligible("Link/mã \(info.code) đã được dùng hoặc hết lượt")
        }

        let currency = Self.resolveCurrency(paymentSource: paymentSource, countryCode: countryCode)

        // Nếu là Promo Trial link có subscription_plan -> kiểm tra preview == 0đ trước!
        if info.isTrialPromotion, let planId = info.planId {
            _ = try await previewTrialSubscription(
                planId: planId,
                trialId: nil,
                promoCode: info.code,
                paymentSourceId: paymentSource?.id,
                currency: currency
            )
        }

        var body: [String: Any] = [
            "channel_id": NSNull()
        ]
        if let psId = paymentSource?.id {
            body["payment_source_id"] = psId
        }

        let (_, data) = try await performRequest(
            path: "/entitlements/gift-codes/\(info.code)/redeem",
            method: "POST",
            jsonBody: body
        )

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let subDict = json["subscription"] as? [String: Any] {
                return Self.parseSubscription(subDict)
            }
            return Self.parseSubscription(json)
        }
        return nil
    }

    // MARK: - JSON Parsers

    private static func appendUnique(_ offer: NitroTrialOffer, to list: inout [NitroTrialOffer]) {
        let duplicate = list.contains { $0.id == offer.id || $0.trialId == offer.trialId }
        if !duplicate {
            list.append(offer)
        }
    }

    private static func parseTrialOffer(_ dict: [String: Any], source: NitroTrialOfferSource) -> NitroTrialOffer? {
        let trialId = (dict["trial_id"] as? String)
            ?? ((dict["subscription_trial"] as? [String: Any])?["id"] as? String)
        guard let tid = trialId, !tid.isEmpty else { return nil }
        let id = (dict["id"] as? String) ?? tid

        var subTrial: NitroSubscriptionTrial? = nil
        if let st = dict["subscription_trial"] as? [String: Any],
           let stId = st["id"] as? String,
           let interval = st["interval"] as? Int,
           let count = st["interval_count"] as? Int,
           let skuId = st["sku_id"] as? String {
            subTrial = NitroSubscriptionTrial(id: stId, interval: interval, intervalCount: count, skuId: skuId)
        }

        return NitroTrialOffer(
            id: id,
            userId: dict["user_id"] as? String,
            trialId: tid,
            expiresAt: dict["expires_at"] as? String,
            subscriptionTrial: subTrial,
            referrerId: dict["referrer_id"] as? String,
            source: (dict["referrer_id"] as? String) != nil ? .referral : source
        )
    }

    private static func parseDiscountOffer(_ dict: [String: Any]) -> NitroDiscountOffer? {
        guard let id = dict["id"] as? String else { return nil }
        let disc = dict["discount"] as? [String: Any]
        return NitroDiscountOffer(
            id: id,
            discountId: (dict["discount_id"] as? String) ?? (disc?["id"] as? String),
            expiresAt: dict["expires_at"] as? String,
            amountPercent: disc?["amount"] as? Int,
            planIds: (disc?["plan_ids"] as? [String]) ?? []
        )
    }

    private static func parseSubscription(_ dict: [String: Any]) -> NitroSubscription? {
        guard let id = dict["id"] as? String else { return nil }
        let items = dict["items"] as? [[String: Any]]
        let itemPlanId = items?.first?["plan_id"] as? String
        return NitroSubscription(
            id: id,
            type: dict["type"] as? Int ?? 1,
            status: dict["status"] as? Int ?? 0,
            planId: (dict["plan_id"] as? String) ?? itemPlanId,
            trialId: dict["trial_id"] as? String,
            trialEndsAt: dict["trial_ends_at"] as? String,
            currentPeriodEnd: dict["current_period_end"] as? String,
            paymentSourceId: dict["payment_source_id"] as? String,
            canceledAt: dict["canceled_at"] as? String,
            currency: dict["currency"] as? String
        )
    }

    private static func resolveCurrency(paymentSource: NitroPaymentSource?, countryCode: String?) -> String {
        if let cur = paymentSource?.currency, !cur.isEmpty {
            return cur.lowercased()
        }
        switch (paymentSource?.country ?? countryCode ?? "").uppercased() {
        case "VN": return "vnd"
        case "GB", "UK": return "gbp"
        case "DE", "FR", "IT", "ES", "NL", "BE", "AT", "PT", "IE", "FI": return "eur"
        case "JP": return "jpy"
        case "KR": return "krw"
        case "BR": return "brl"
        case "TR": return "try"
        case "PH": return "php"
        case "ID": return "idr"
        case "TH": return "thb"
        case "MY": return "myr"
        case "SG": return "sgd"
        case "AU": return "aud"
        case "CA": return "cad"
        case "PL": return "pln"
        default: return "usd"
        }
    }
}

// ==============================================================================
// MARK: - NITRO TRIAL AUTO SCANNER & CLAIMER MANAGER
// ==============================================================================

@MainActor
final class NitroTrialManager: ObservableObject {
    static let shared = NitroTrialManager()

    // Scan results keyed by TokenInfo.id
    @Published var results: [UUID: NitroTokenScanResult] = [:]
    @Published var logs: [NitroLogEntry] = []

    // Runtime states
    @Published var isRunning = false
    @Published var isAutoMonitorActive = false
    @Published var currentActionText = ""
    @Published var processedCount = 0
    @Published var totalTargetCount = 0
    @Published var nextAutoRunAt: Date? = nil
    @Published var promoLinksInput: String = ""

    // Settings (persisted to UserDefaults)
    @Published var onlySelectedTokens: Bool {
        didSet { UserDefaults.standard.set(onlySelectedTokens, forKey: "QT_Nitro_OnlySelected") }
    }
    @Published var useSavedPaymentSource: Bool {
        didSet { UserDefaults.standard.set(useSavedPaymentSource, forKey: "QT_Nitro_UseSavedPayment") }
    }
    @Published var autoCancelRenewal: Bool {
        didSet { UserDefaults.standard.set(autoCancelRenewal, forKey: "QT_Nitro_AutoCancelRenewal") }
    }
    @Published var scanDelaySeconds: Double {
        didSet { UserDefaults.standard.set(scanDelaySeconds, forKey: "QT_Nitro_ScanDelay") }
    }
    @Published var autoRepeatInterval: NitroAutoInterval {
        didSet { UserDefaults.standard.set(autoRepeatInterval.rawValue, forKey: "QT_Nitro_AutoInterval") }
    }

    private var activeTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?

    private init() {
        let ud = UserDefaults.standard
        self.onlySelectedTokens = ud.bool(forKey: "QT_Nitro_OnlySelected")
        self.useSavedPaymentSource = ud.object(forKey: "QT_Nitro_UseSavedPayment") == nil ? true : ud.bool(forKey: "QT_Nitro_UseSavedPayment")
        self.autoCancelRenewal = ud.object(forKey: "QT_Nitro_AutoCancelRenewal") == nil ? true : ud.bool(forKey: "QT_Nitro_AutoCancelRenewal")
        let savedDelay = ud.double(forKey: "QT_Nitro_ScanDelay")
        self.scanDelaySeconds = savedDelay > 0 ? savedDelay : 1.0
        let savedInterval = ud.integer(forKey: "QT_Nitro_AutoInterval")
        self.autoRepeatInterval = NitroAutoInterval(rawValue: savedInterval) ?? .hour1
    }

    // MARK: Aggregated Metrics

    func orderedResults(for tokens: [TokenInfo]) -> [NitroTokenScanResult] {
        tokens.map { tok in
            if var existing = results[tok.id] {
                existing.username = existing.username.isEmpty ? tok.username : existing.username
                return existing
            }
            return NitroTokenScanResult(
                id: tok.id,
                token: tok.token,
                userId: tok.userId,
                username: tok.username,
                avatarHash: tok.avatarHash,
                state: tok.isValid ? .idle : .tokenDead,
                statusDetail: tok.isValid ? "Sẵn sàng quét" : "Token chết"
            )
        }
    }

    func pruneRemovedTokens(_ validTokens: [TokenInfo]) {
        let validIds = Set(validTokens.map { $0.id })
        let staleKeys = results.keys.filter { !validIds.contains($0) }
        for k in staleKeys {
            results.removeValue(forKey: k)
        }
    }

    func countTrialAvailable(for tokens: [TokenInfo]) -> Int {
        tokens.filter { results[$0.id]?.state == .trialAvailable }.count
    }

    func countClaimed(for tokens: [TokenInfo]) -> Int {
        tokens.filter { results[$0.id]?.state == .claimed }.count
    }

    func countAlreadyNitro(for tokens: [TokenInfo]) -> Int {
        tokens.filter { results[$0.id]?.state == .alreadyNitro }.count
    }

    func countNeedsPayment(for tokens: [TokenInfo]) -> Int {
        tokens.filter { results[$0.id]?.state == .needsPayment }.count
    }

    func countScanned(for tokens: [TokenInfo]) -> Int {
        tokens.filter {
            guard let st = results[$0.id]?.state else { return false }
            return st != .idle && st != .scanning
        }.count
    }

    var progressFraction: Double {
        guard totalTargetCount > 0 else { return 0 }
        return min(1.0, Double(processedCount) / Double(totalTargetCount))
    }

    // MARK: Logging

    func log(_ message: String, level: NitroLogEntry.Level = .info) {
        logs.append(NitroLogEntry(message: message, level: level))
        if logs.count > 250 {
            logs.removeFirst(logs.count - 250)
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func exportLogsText() -> String {
        logs.map { "[\($0.formattedTime)] \($0.message)" }.joined(separator: "\n")
    }

    // MARK: Target Token Resolution

    func targetTokens(from app: AppState) -> [TokenInfo] {
        let live = app.tokens.filter { $0.isValid }
        if onlySelectedTokens {
            let selected = live.filter { app.selectedTokenIds.contains($0.id) }
            return selected.isEmpty ? live : selected
        }
        return live
    }

    // MARK: Batch Scan / Auto Scan & Claim

    func startBatch(tokens: [TokenInfo], autoClaim: Bool) {
        guard SecurityGuard.shared.verifyExecutionPermit() else {
            log("Không thể chạy: chưa có quyền xác thực bản quyền", level: .error)
            return
        }
        guard !isRunning else { return }
        let targets = tokens.filter { $0.isValid }
        guard !targets.isEmpty else {
            log("Không có token Live nào để quét!", level: .warning)
            return
        }

        isRunning = true
        processedCount = 0
        totalTargetCount = targets.count
        currentActionText = autoClaim ? "Đang quét & tự động claim..." : "Đang quét gói Nitro Trial..."
        BackgroundManager.shared.start(tag: "nitro")

        log(autoClaim
            ? "Bắt đầu QUÉT & TỰ ĐỘNG CLAIM cho \(targets.count) token..."
            : "Bắt đầu QUÉT Nitro Trial cho \(targets.count) token...", level: .info)

        activeTask = Task { [weak self] in
            guard let self = self else { return }
            await self.runBatchCycle(targets: targets, autoClaim: autoClaim)
            self.isRunning = false
            self.currentActionText = ""
            if !self.isAutoMonitorActive {
                BackgroundManager.shared.stop(tag: "nitro")
            }
        }
    }

    func claimAllDiscovered(tokens: [TokenInfo]) {
        guard !isRunning else { return }
        let claimables = tokens.filter { tok in
            guard let res = results[tok.id] else { return false }
            return res.canAttemptClaim
        }
        guard !claimables.isEmpty else {
            log("Không có token nào đang có gói Trial để claim.", level: .warning)
            return
        }

        isRunning = true
        processedCount = 0
        totalTargetCount = claimables.count
        currentActionText = "Đang claim \(claimables.count) gói Nitro Trial..."
        BackgroundManager.shared.start(tag: "nitro")

        log("Bắt đầu claim \(claimables.count) token có gói Nitro Trial...", level: .info)

        activeTask = Task { [weak self] in
            guard let self = self else { return }
            for (idx, tok) in claimables.enumerated() {
                if Task.isCancelled { break }
                await self.claimSingleTokenInternal(tok)
                self.processedCount = idx + 1
                if idx + 1 < claimables.count {
                    let wait = max(0.3, self.scanDelaySeconds)
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
            }
            self.log("Hoàn tất đợt claim hàng loạt.", level: .success)
            self.isRunning = false
            self.currentActionText = ""
            if !self.isAutoMonitorActive {
                BackgroundManager.shared.stop(tag: "nitro")
            }
        }
    }

    func startAutoMonitor(app: AppState) {
        guard SecurityGuard.shared.verifyExecutionPermit() else { return }
        stopAutoMonitor()
        isAutoMonitorActive = true
        BackgroundManager.shared.start(tag: "nitro")
        log("Bật tự động quét & claim định kỳ mỗi \(autoRepeatInterval.label) (chạy nền 24/7).", level: .success)

        monitorTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled && self.isAutoMonitorActive {
                let targets = self.targetTokens(from: app)
                if !targets.isEmpty && !self.isRunning {
                    self.isRunning = true
                    self.processedCount = 0
                    self.totalTargetCount = targets.count
                    self.currentActionText = "Auto 24/7 đang quét & claim..."
                    await self.runBatchCycle(targets: targets, autoClaim: true)
                    self.isRunning = false
                    self.currentActionText = ""
                } else if targets.isEmpty {
                    self.log("Auto 24/7: chưa có token Live để quét.", level: .warning)
                }

                let waitSeconds = TimeInterval(self.autoRepeatInterval.rawValue * 60)
                let nextDate = Date().addingTimeInterval(waitSeconds)
                self.nextAutoRunAt = nextDate
                self.log("Lần quét tiếp theo lúc \(NitroDateHelper.timeFormatter.string(from: nextDate))", level: .info)

                do {
                    try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                } catch {
                    break
                }
            }
            self.nextAutoRunAt = nil
        }
    }

    func stopAutoMonitor() {
        isAutoMonitorActive = false
        nextAutoRunAt = nil
        monitorTask?.cancel()
        monitorTask = nil
        if !isRunning {
            BackgroundManager.shared.stop(tag: "nitro")
        }
    }

    func stopAll() {
        activeTask?.cancel()
        activeTask = nil
        isRunning = false
        currentActionText = ""
        stopAutoMonitor()
        BackgroundManager.shared.stop(tag: "nitro")
        log("Đã dừng toàn bộ tiến trình quét/claim Nitro.", level: .warning)
    }

    // MARK: Per-Token Operations

    func scanSingleToken(_ token: TokenInfo) {
        guard !isRunning else { return }
        Task { [weak self] in
            await self?.scanSingleTokenInternal(token, autoClaim: false)
        }
    }

    func claimSingleToken(_ token: TokenInfo) {
        guard !isRunning else { return }
        Task { [weak self] in
            await self?.claimSingleTokenInternal(token)
        }
    }

    func cancelRenewalForToken(_ token: TokenInfo) {
        guard let existing = results[token.id],
              let subId = existing.claimedSubscriptionId ?? existing.activeNitroSub?.id else {
            log("[\(token.username)] Không tìm thấy ID gói Nitro để hủy gia hạn.", level: .warning)
            return
        }
        Task { [weak self] in
            guard let self = self else { return }
            let client = DiscordNitroClient(token: token.token)
            do {
                try await client.cancelAutoRenewal(subscriptionId: subId)
                if var updated = self.results[token.id] {
                    updated.autoRenewCanceled = true
                    updated.statusDetail = "Đã tắt gia hạn — giữ nguyên toàn bộ thời gian Trial"
                    updated.lastUpdatedAt = Date()
                    self.results[token.id] = updated
                }
                self.log("[\(token.username)] Đã tắt tự động gia hạn cho gói #\(subId).", level: .success)
            } catch {
                self.log("[\(token.username)] Lỗi tắt gia hạn: \(error.localizedDescription)", level: .error)
            }
        }
    }

    // MARK: Claim Promo / Gift Links Batch

    func claimPromoLinks(tokens: [TokenInfo]) {
        guard !isRunning else { return }
        let rawLines = promoLinksInput
            .components(separatedBy: .newlines)
            .compactMap { DiscordNitroClient.extractPromoCode(from: $0) }
        var seen = Set<String>()
        let codes = rawLines.filter { seen.insert($0).inserted }

        guard !codes.isEmpty else {
            log("Vui lòng dán ít nhất 1 link/mã Nitro Promo Trial!", level: .warning)
            return
        }
        let liveTokens = tokens.filter { $0.isValid }
        guard !liveTokens.isEmpty else {
            log("Chưa có token Live để claim link Promo!", level: .warning)
            return
        }

        isRunning = true
        processedCount = 0
        totalTargetCount = min(codes.count, liveTokens.count)
        currentActionText = "Đang kiểm tra & claim \(codes.count) link Promo..."
        BackgroundManager.shared.start(tag: "nitro")

        activeTask = Task { [weak self] in
            guard let self = self else { return }
            var codeIndex = 0

            for tok in liveTokens {
                if Task.isCancelled || codeIndex >= codes.count { break }

                // Đảm bảo đã có thông tin tài khoản + thẻ của token
                if self.results[tok.id] == nil || self.results[tok.id]?.state == .idle {
                    await self.scanSingleTokenInternal(tok, autoClaim: false)
                }
                guard let snap = self.results[tok.id] else { continue }
                if snap.state == .tokenDead || snap.state == .alreadyNitro || snap.state == .claimed {
                    continue
                }

                let code = codes[codeIndex]
                let client = DiscordNitroClient(token: tok.token)
                var mutable = snap
                mutable.state = .claiming
                mutable.statusDetail = "Đang kiểm tra link Promo \(code.prefix(8))..."
                self.results[tok.id] = mutable

                let info: NitroGiftCodeInfo
                do {
                    info = try await client.fetchGiftOrPromoInfo(code: code)
                } catch {
                    self.log("Mã/link \(code) không hợp lệ hoặc đã hết hạn (\(error.localizedDescription)) — bỏ qua.", level: .warning)
                    codeIndex += 1
                    mutable.state = snap.state
                    mutable.statusDetail = snap.statusDetail
                    self.results[tok.id] = mutable
                    continue
                }

                if !info.isClaimable {
                    self.log("Mã \(code) đã hết lượt hoặc đã được dùng — bỏ qua.", level: .warning)
                    codeIndex += 1
                    mutable.state = snap.state
                    mutable.statusDetail = snap.statusDetail
                    self.results[tok.id] = mutable
                    continue
                }

                do {
                    let ps = self.useSavedPaymentSource ? mutable.preferredPaymentSource : nil
                    let sub = try await client.redeemGiftOrPromo(
                        info: info,
                        paymentSource: ps,
                        countryCode: mutable.countryCode
                    )

                    mutable.state = .claimed
                    mutable.claimedSubscriptionId = sub?.id
                    mutable.claimedTrialEndsAt = sub?.endDateString
                    mutable.statusDetail = "Claim thành công link \(info.planName ?? "Nitro Promo")!"
                    mutable.lastUpdatedAt = Date()

                    if self.autoCancelRenewal, let subId = sub?.id, ps != nil {
                        if (try? await client.cancelAutoRenewal(subscriptionId: subId)) != nil {
                            mutable.autoRenewCanceled = true
                            mutable.statusDetail += " (Đã tắt gia hạn)"
                        }
                    }

                    self.results[tok.id] = mutable
                    self.log("[\(mutable.username)] CLAIM LINK THÀNH CÔNG: \(info.planName ?? code)!", level: .success)
                    codeIndex += 1
                    self.processedCount += 1
                } catch let apiErr as NitroAPIError {
                    self.applyClaimError(apiErr, to: &mutable)
                    self.results[tok.id] = mutable
                    self.log("[\(mutable.username)] Claim link \(code) thất bại: \(apiErr.localizedDescription)", level: .warning)
                } catch {
                    mutable.state = .error(error.localizedDescription)
                    mutable.statusDetail = error.localizedDescription
                    self.results[tok.id] = mutable
                    self.log("[\(mutable.username)] Lỗi claim link: \(error.localizedDescription)", level: .error)
                }

                let wait = max(0.4, self.scanDelaySeconds)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }

            self.log("Hoàn tất xử lý Promo Links (\(self.processedCount) thành công).", level: .info)
            self.isRunning = false
            self.currentActionText = ""
            if !self.isAutoMonitorActive {
                BackgroundManager.shared.stop(tag: "nitro")
            }
        }
    }

    // MARK: Internal Execution Core

    private func runBatchCycle(targets: [TokenInfo], autoClaim: Bool) async {
        var foundCount = 0
        var claimedCount = 0

        for (idx, tok) in targets.enumerated() {
            if Task.isCancelled { break }
            currentActionText = "[\(idx + 1)/\(targets.count)] Quét \(tok.username)..."
            let stateAfter = await scanSingleTokenInternal(tok, autoClaim: autoClaim)
            if stateAfter == .trialAvailable || stateAfter == .needsPayment {
                foundCount += 1
            } else if stateAfter == .claimed {
                foundCount += 1
                claimedCount += 1
            }
            processedCount = idx + 1

            if idx + 1 < targets.count {
                let jitter = Double.random(in: -0.15...0.25)
                let delay = max(0.3, scanDelaySeconds + jitter)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        if autoClaim {
            log("Xong chu kỳ Quét & Claim: \(targets.count) token | Tìm thấy \(foundCount) Trial | Claim thành công \(claimedCount).", level: .success)
        } else {
            log("Xong quét \(targets.count) token: Tìm thấy \(foundCount) token có gói Nitro Trial.", level: .success)
        }
    }

    @discardableResult
    private func scanSingleTokenInternal(_ token: TokenInfo, autoClaim: Bool) async -> NitroTokenState {
        var entry = results[token.id] ?? NitroTokenScanResult(
            id: token.id,
            token: token.token,
            userId: token.userId,
            username: token.username,
            avatarHash: token.avatarHash
        )
        entry.state = .scanning
        entry.statusDetail = "Đang kiểm tra tài khoản & ưu đãi..."
        results[token.id] = entry

        let client = DiscordNitroClient(token: token.token)

        do {
            let user = try await client.fetchUser()
            entry.userId = user.id
            entry.username = user.displayName
            entry.avatarHash = user.avatar
            entry.premiumTier = user.premiumType
            entry.emailVerified = user.verified
            entry.hasPhone = !(user.phone ?? "").isEmpty

            // Gọi song song các thông tin billing & offers
            async let subsTask = client.fetchSubscriptions()
            async let payTask = client.fetchPaymentSources()
            async let countryTask = client.fetchCountryCode()
            async let offersTask = client.fetchAllOffers()
            async let outboundTask = client.fetchOutboundPromotions()

            let subs = await subsTask
            let payments = await payTask
            let country = await countryTask
            let (trials, discount) = await offersTask
            let outbounds = await outboundTask

            entry.activeSubscriptions = subs
            entry.paymentSources = payments
            entry.countryCode = country
            entry.trialOffers = trials
            entry.discountOffer = discount
            entry.outboundPromos = outbounds
            entry.lastUpdatedAt = Date()

            let hasActiveSub = subs.contains(where: { $0.isActive })
            if user.premiumType.isNitro || hasActiveSub {
                entry.state = .alreadyNitro
                if let sub = entry.activeNitroSub, let endStr = NitroDateHelper.formatDisplay(sub.endDateString) {
                    let prefix = sub.isTrial ? "Đang dùng Nitro Trial" : "Đang có \(user.premiumType.displayName)"
                    entry.statusDetail = "\(prefix) • Hết hạn: \(endStr)"
                } else {
                    entry.statusDetail = "Đang kích hoạt \(user.premiumType.displayName)"
                }
                results[token.id] = entry
                log("[\(entry.username)] \(entry.statusDetail)", level: .info)
                return entry.state
            }

            if let firstTrial = trials.first {
                entry.state = .trialAvailable
                let payNote = entry.preferredPaymentSource.map { "Thẻ sẵn: \($0.displayName)" } ?? "Chưa gắn thẻ"
                entry.statusDetail = "Tìm thấy \(firstTrial.title) • \(payNote)"
                results[token.id] = entry
                log("[\(entry.username)] PHÁT HIỆN GÓI TRIAL: \(firstTrial.title) (\(payNote))", level: .success)

                if autoClaim {
                    return await claimSingleTokenInternal(token)
                }
                return entry.state
            }

            if let disc = discount {
                entry.state = .discountOnly
                entry.statusDetail = "\(disc.summary) (không phải gói Trial 0đ)"
                results[token.id] = entry
                log("[\(entry.username)] Chỉ có ưu đãi giảm giá: \(disc.summary)", level: .info)
                return entry.state
            }

            entry.state = .noOffer
            let payCount = entry.validPaymentSources.count
            entry.statusDetail = payCount > 0
                ? "Không có gói Trial • Có \(payCount) thẻ hợp lệ"
                : "Không có gói Nitro Trial khả dụng"
            results[token.id] = entry
            return entry.state

        } catch let apiErr as NitroAPIError {
            entry.lastUpdatedAt = Date()
            switch apiErr {
            case .unauthorized:
                entry.state = .tokenDead
                entry.statusDetail = "Token chết / hết hạn (401)"
                log("[\(entry.username)] Token die (401).", level: .error)
            case .captchaRequired:
                entry.state = .needsVerification
                entry.statusDetail = apiErr.localizedDescription
                log("[\(entry.username)] \(apiErr.localizedDescription)", level: .warning)
            default:
                entry.state = .error(apiErr.localizedDescription)
                entry.statusDetail = apiErr.localizedDescription
                log("[\(entry.username)] Lỗi quét: \(apiErr.localizedDescription)", level: .error)
            }
            results[token.id] = entry
            return entry.state
        } catch {
            entry.state = .error(error.localizedDescription)
            entry.statusDetail = error.localizedDescription
            entry.lastUpdatedAt = Date()
            results[token.id] = entry
            log("[\(entry.username)] Lỗi kết nối: \(error.localizedDescription)", level: .error)
            return entry.state
        }
    }

    @discardableResult
    private func claimSingleTokenInternal(_ token: TokenInfo) async -> NitroTokenState {
        guard var entry = results[token.id], let offer = entry.primaryOffer else {
            return await scanSingleTokenInternal(token, autoClaim: true)
        }

        if entry.emailVerified == false {
            entry.state = .needsVerification
            entry.statusDetail = "Email chưa xác minh — Discord yêu cầu verify email trước khi claim Trial"
            entry.lastUpdatedAt = Date()
            results[token.id] = entry
            log("[\(entry.username)] Bỏ qua claim: chưa xác minh Email.", level: .warning)
            return entry.state
        }

        entry.state = .claiming
        entry.statusDetail = "Đang ack & kiểm tra hóa đơn 0đ cho \(offer.title)..."
        results[token.id] = entry

        let client = DiscordNitroClient(token: token.token)
        let selectedPayment = useSavedPaymentSource ? entry.preferredPaymentSource : nil

        do {
            let (createdSub, usedNoCard) = try await client.claimTrialOffer(
                offer,
                paymentSource: selectedPayment,
                countryCode: entry.countryCode
            )

            entry.state = .claimed
            entry.premiumTier = .nitroFull
            entry.claimedSubscriptionId = createdSub?.id
            entry.claimedTrialEndsAt = createdSub?.endDateString
            if let sub = createdSub {
                entry.activeSubscriptions.insert(sub, at: 0)
            }

            let expStr = NitroDateHelper.formatDisplay(createdSub?.endDateString) ?? "đã kích hoạt"
            let modeLabel = usedNoCard ? "Không cần thẻ" : (selectedPayment?.displayName ?? "Thẻ đã lưu")
            entry.statusDetail = "CLAIM THÀNH CÔNG \(offer.title) • \(modeLabel) • Hạn: \(expStr)"
            entry.lastUpdatedAt = Date()

            // Tự động tắt gia hạn để an toàn không bị trừ tiền sau khi hết Trial
            if autoCancelRenewal, let subId = createdSub?.id, !usedNoCard {
                do {
                    try await client.cancelAutoRenewal(subscriptionId: subId)
                    entry.autoRenewCanceled = true
                    entry.statusDetail += " • Đã tắt gia hạn"
                    log("[\(entry.username)] Đã tự động tắt gia hạn cho gói Trial #\(subId).", level: .info)
                } catch {
                    log("[\(entry.username)] Claim xong nhưng chưa tắt gia hạn tự động: \(error.localizedDescription)", level: .warning)
                }
            }

            results[token.id] = entry
            log("[\(entry.username)] CLAIM THÀNH CÔNG: \(offer.title) (\(modeLabel))!", level: .success)
            return entry.state

        } catch let apiErr as NitroAPIError {
            applyClaimError(apiErr, to: &entry)
            entry.lastUpdatedAt = Date()
            results[token.id] = entry
            log("[\(entry.username)] Claim chưa thành công: \(apiErr.localizedDescription)", level: .warning)
            return entry.state
        } catch {
            entry.state = .error(error.localizedDescription)
            entry.statusDetail = error.localizedDescription
            entry.lastUpdatedAt = Date()
            results[token.id] = entry
            log("[\(entry.username)] Lỗi claim: \(error.localizedDescription)", level: .error)
            return entry.state
        }
    }

    private func applyClaimError(_ apiErr: NitroAPIError, to entry: inout NitroTokenScanResult) {
        switch apiErr {
        case .paymentSourceRequired:
            entry.state = .needsPayment
            if !useSavedPaymentSource && entry.preferredPaymentSource != nil {
                entry.statusDetail = "Gói cần thẻ/ví — hãy bật 'Dùng thẻ đã lưu trên token' để claim!"
            } else {
                entry.statusDetail = "Gói Trial đã sẵn sàng nhưng cần gắn thẻ/PayPal/MoMo trên Discord"
            }
        case .captchaRequired, .paymentAuthRequired, .verificationRequired:
            entry.state = .needsVerification
            entry.statusDetail = apiErr.localizedDescription
        case .unauthorized:
            entry.state = .tokenDead
            entry.statusDetail = apiErr.localizedDescription
        case .nonZeroChargeBlocked:
            entry.state = .discountOnly
            entry.statusDetail = apiErr.localizedDescription
        default:
            entry.state = .error(apiErr.localizedDescription)
            entry.statusDetail = apiErr.localizedDescription
        }
    }

    // MARK: Export Helpers

    func exportTokens(from tokens: [TokenInfo], matching states: Set<String>) -> String {
        var lines: [String] = []
        for tok in tokens {
            guard let res = results[tok.id] else { continue }
            let key: String
            switch res.state {
            case .trialAvailable: key = "trial"
            case .claimed: key = "claimed"
            case .alreadyNitro: key = "nitro"
            case .needsPayment: key = "needsPayment"
            default: key = "other"
            }
            if states.contains(key) {
                let info = res.primaryOffer?.title ?? res.statusDetail
                lines.append("\(tok.token) | \(res.username) | \(res.state.badgeText) | \(info)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// ==============================================================================
// MARK: - NITRO TRIAL DASHBOARD VIEW (SWIFTUI iOS 16+)
// ==============================================================================

struct NitroTrialDashboardView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var nitro: NitroTrialManager

    @State private var selectedFilter: NitroResultFilter = .all
    @State private var showSettings = false
    @State private var showPromoCard = false
    @State private var showConsole = true
    @State private var copiedToast: String? = nil

    private let nitroStart = Color(red: 0.35, green: 0.39, blue: 0.95) // #5865F2
    private let nitroMid = Color(red: 0.67, green: 0.31, blue: 0.96)   // Violet
    private let nitroEnd = Color(red: 0.93, green: 0.28, blue: 0.60)   // Nitro Pink

    private var nitroGradient: LinearGradient {
        LinearGradient(colors: [nitroStart, nitroMid, nitroEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var allResults: [NitroTokenScanResult] {
        nitro.orderedResults(for: app.tokens)
    }

    private var filteredResults: [NitroTokenScanResult] {
        allResults.filter { item in
            switch selectedFilter {
            case .all:
                return true
            case .trial:
                return item.state == .trialAvailable
            case .claimed:
                return item.state == .claimed
            case .alreadyNitro:
                return item.state == .alreadyNitro
            case .needsPayment:
                return item.state == .needsPayment || item.state == .needsVerification
            case .others:
                switch item.state {
                case .noOffer, .discountOnly, .tokenDead, .error, .idle:
                    return true
                default:
                    return false
                }
            }
        }
    }

    private var claimableCount: Int {
        allResults.filter { $0.canAttemptClaim }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                heroHeaderCard
                statsGrid
                controlDeckCard
                settingsAccordionCard
                promoLinksAccordionCard
                resultsSection
                consoleSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .overlay(alignment: .top) {
            if let toast = copiedToast {
                Text(toast)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.82), in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            nitro.pruneRemovedTokens(app.tokens)
        }
        .onChange(of: app.tokens.count) { _ in
            nitro.pruneRemovedTokens(app.tokens)
        }
    }

    // MARK: 1. Hero Header Card

    private var heroHeaderCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(nitroGradient)
                    .frame(width: 46, height: 46)
                    .shadow(color: nitroEnd.opacity(0.35), radius: 8, y: 4)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Nitro Trial Auto Claimer")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if nitro.isRunning {
                    Text(nitro.currentActionText.isEmpty ? "Đang xử lý..." : nitro.currentActionText)
                        .font(.caption)
                        .foregroundStyle(nitroMid)
                        .lineLimit(1)
                } else if nitro.isAutoMonitorActive, let next = nitro.nextAutoRunAt {
                    Text("Auto 24/7 • Quét tiếp lúc \(NitroDateHelper.timeFormatter.string(from: next))")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                } else {
                    Text("Quét ưu đãi Trial, kiểm tra 0đ & tự động Claim")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            statusBadgePill
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusBadgeLabel: String {
        if nitro.isRunning { return "ĐANG CHẠY" }
        if nitro.isAutoMonitorActive { return "AUTO 24/7" }
        return "0Đ SAFE"
    }

    private var statusBadgeColor: Color {
        if nitro.isRunning { return nitroEnd }
        if nitro.isAutoMonitorActive { return .green }
        return nitroStart
    }

    private var statusBadgePill: some View {
        Text(statusBadgeLabel)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusBadgeColor, in: Capsule())
    }

    // MARK: 2. 4-Column Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 10) {
            NitroMiniStatBox(
                title: "Đã quét",
                value: "\(nitro.countScanned(for: app.tokens))/\(app.tokens.filter(\.isValid).count)",
                icon: "magnifyingglass.circle.fill",
                color: .indigo
            )
            NitroMiniStatBox(
                title: "Có Trial",
                value: "\(nitro.countTrialAvailable(for: app.tokens))",
                icon: "gift.fill",
                color: nitroEnd
            )
            NitroMiniStatBox(
                title: "Đã Claim",
                value: "\(nitro.countClaimed(for: app.tokens))",
                icon: "checkmark.seal.fill",
                color: .green
            )
            NitroMiniStatBox(
                title: "Nitro",
                value: "\(nitro.countAlreadyNitro(for: app.tokens))",
                icon: "crown.fill",
                color: .purple
            )
        }
    }

    // MARK: 3. Control Deck Card

    private var controlDeckCard: some View {
        VStack(spacing: 12) {
            // Primary CTA: Auto Scan & Claim OR Stop
            if nitro.isRunning {
                Button {
                    nitro.stopAll()
                } label: {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                        Text("Dừng Quét / Claim (\(nitro.processedCount)/\(nitro.totalTargetCount))")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            } else {
                Button {
                    let targets = nitro.targetTokens(from: app)
                    nitro.startBatch(tokens: targets, autoClaim: true)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                        Text("Quét & Tự động Claim Nitro Trial")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(nitroGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: nitroMid.opacity(0.30), radius: 8, y: 4)
                }
                .disabled(app.tokens.filter(\.isValid).isEmpty)
                .opacity(app.tokens.filter(\.isValid).isEmpty ? 0.5 : 1.0)
            }

            if nitro.isRunning && nitro.totalTargetCount > 0 {
                ProgressView(value: nitro.progressFraction)
                    .tint(nitroEnd)
            }

            // Secondary row: Scan only | Claim All | Auto 24/7 toggle
            HStack(spacing: 8) {
                Button {
                    let targets = nitro.targetTokens(from: app)
                    nitro.startBatch(tokens: targets, autoClaim: false)
                } label: {
                    Label("Chỉ Quét", systemImage: "magnifyingglass")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(.indigo)
                }
                .disabled(nitro.isRunning || app.tokens.filter(\.isValid).isEmpty)

                Button {
                    nitro.claimAllDiscovered(tokens: app.tokens)
                } label: {
                    Label("Claim (\(claimableCount))", systemImage: "gift.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(nitroEnd.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(nitroEnd)
                }
                .disabled(nitro.isRunning || claimableCount == 0)

                Button {
                    if nitro.isAutoMonitorActive {
                        nitro.stopAutoMonitor()
                    } else {
                        nitro.startAutoMonitor(app: app)
                    }
                } label: {
                    Label(nitro.isAutoMonitorActive ? "Tắt 24/7" : "Auto 24/7",
                          systemImage: nitro.isAutoMonitorActive ? "stop.circle.fill" : "clock.arrow.2.circlepath")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background((nitro.isAutoMonitorActive ? Color.green : Color.purple).opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(nitro.isAutoMonitorActive ? .green : .purple)
                }
                .disabled(app.tokens.filter(\.isValid).isEmpty)
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: 4. Configuration Accordion Card

    private var settingsAccordionCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() }
            } label: {
                HStack {
                    Label("Cấu hình Quét & Claim An toàn", systemImage: "slider.horizontal.3")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(nitro.autoCancelRenewal ? "Tắt gia hạn: BẬT" : "Tùy chỉnh")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Image(systemName: showSettings ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if showSettings {
                Divider().padding(.horizontal, 14)
                VStack(spacing: 12) {
                    Toggle(isOn: $nitro.onlySelectedTokens) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chỉ quét Token đang chọn")
                                .font(.subheadline)
                            Text("Hiện chọn \(app.selectedTokenIds.count)/\(app.tokens.filter(\.isValid).count) token Live")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.indigo)

                    Divider()

                    Toggle(isOn: $nitro.useSavedPaymentSource) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dùng thẻ/ví đã lưu trên token")
                                .font(.subheadline)
                            Text("Tắt = chỉ claim gói 0đ không cần thẻ. Luôn kiểm tra preview = 0đ trước khi claim.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .tint(nitroEnd)

                    Divider()

                    Toggle(isOn: $nitro.autoCancelRenewal) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tự động tắt gia hạn sau khi Claim")
                                .font(.subheadline)
                            Text("Hủy gia hạn tự động ngay để tránh trừ tiền sau trial, vẫn giữ đủ thời hạn Nitro.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)

                    Divider()

                    HStack {
                        Text("Chu kỳ Auto 24/7")
                            .font(.subheadline)
                        Spacer()
                        Picker("Chu kỳ", selection: $nitro.autoRepeatInterval) {
                            ForEach(NitroAutoInterval.allCases) { interval in
                                Text(interval.label).tag(interval)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.indigo)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Delay giữa mỗi token")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1fs", nitro.scanDelaySeconds))
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(.indigo)
                        }
                        Slider(value: $nitro.scanDelaySeconds, in: 0.3...5.0, step: 0.1)
                            .tint(.indigo)
                    }
                }
                .padding(14)
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: 5. Promo / Gift Trial Link Card

    private var promoLinksAccordionCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showPromoCard.toggle() }
            } label: {
                HStack {
                    Label("Claim từ Link Promo / Gift Trial", systemImage: "link.badge.plus")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Tùy chọn")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: showPromoCard ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if showPromoCard {
                Divider().padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dán danh sách link `discord.com/billing/promotions/...`, `promos.discord.gg/...` hoặc `discord.gift/...` (mỗi dòng 1 link):")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $nitro.promoLinksInput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 74, maxHeight: 120)
                        .padding(8)
                        .background(Color(UIColor.tertiarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 10) {
                        Button {
                            let targets = nitro.targetTokens(from: app)
                            nitro.claimPromoLinks(tokens: targets)
                        } label: {
                            Label("Claim Promo vào Token", systemImage: "gift.fill")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(nitroGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .disabled(nitro.isRunning || nitro.promoLinksInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if !nitro.promoLinksInput.isEmpty {
                            Button("Xóa") {
                                nitro.promoLinksInput = ""
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(14)
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: 6. Filter Bar & Token Results List

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kết quả Token (\(filteredResults.count))")
                    .font(.subheadline.bold())
                Spacer()
                Menu {
                    Button("Copy Token có Nitro Trial", systemImage: "gift") {
                        copyExport(states: ["trial", "needsPayment"], label: "Đã copy Token có Trial!")
                    }
                    Button("Copy Token đã Claim thành công", systemImage: "checkmark.seal") {
                        copyExport(states: ["claimed"], label: "Đã copy Token đã Claim!")
                    }
                    Button("Copy Token đang có Nitro", systemImage: "crown") {
                        copyExport(states: ["nitro", "claimed"], label: "Đã copy Token có Nitro!")
                    }
                } label: {
                    Label("Xuất", systemImage: "doc.on.doc")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.indigo.opacity(0.12), in: Capsule())
                        .foregroundStyle(.indigo)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NitroResultFilter.allCases) { f in
                        let selected = (selectedFilter == f)
                        Button {
                            selectedFilter = f
                        } label: {
                            Text(f.rawValue)
                                .font(.caption.bold())
                                .foregroundColor(selected ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selected ? AnyShapeStyle(nitroGradient) : AnyShapeStyle(Color(UIColor.secondarySystemGroupedBackground)),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if app.tokens.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Chưa có Token nào")
                        .font(.subheadline.bold())
                    Text("Chuyển sang mục Danh sách Token để thêm hoặc nhập file token trước.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if filteredResults.isEmpty {
                Text("Không có token nào trong bộ lọc '\(selectedFilter.rawValue)'.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredResults) { res in
                        if let tok = app.tokens.first(where: { $0.id == res.id }) {
                            NitroTokenResultCard(
                                result: res,
                                isBusy: nitro.isRunning,
                                onRescan: { nitro.scanSingleToken(tok) },
                                onClaim: { nitro.claimSingleToken(tok) },
                                onCancelRenewal: { nitro.cancelRenewalForToken(tok) }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: 7. Live Activity Console

    private var consoleSection: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showConsole.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal.fill")
                            .foregroundStyle(.green)
                        Text("Nhật ký Quét & Claim (\(nitro.logs.count))")
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                        Image(systemName: showConsole ? "chevron.up" : "chevron.down")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if !nitro.logs.isEmpty {
                    Button {
                        UIPasteboard.general.string = nitro.exportLogsText()
                        triggerToast("Đã copy nhật ký!")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                    }
                    .padding(.trailing, 8)

                    Button {
                        nitro.clearLogs()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(12)

            if showConsole {
                Divider()
                if nitro.logs.isEmpty {
                    Text("Chưa có log. Nhấn 'Quét & Tự động Claim' để bắt đầu.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(nitro.logs.reversed())) { entry in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(entry.formattedTime)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.gray)
                                    Text(entry.message)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(logColor(entry.level))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(10)
                    }
                    .frame(minHeight: 100, maxHeight: 210)
                    .background(Color.black.opacity(0.88))
                }
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func logColor(_ level: NitroLogEntry.Level) -> Color {
        switch level {
        case .info: return Color(white: 0.88)
        case .success: return Color(red: 0.35, green: 0.92, blue: 0.55)
        case .warning: return Color(red: 1.0, green: 0.78, blue: 0.25)
        case .error: return Color(red: 1.0, green: 0.42, blue: 0.42)
        }
    }

    private func copyExport(states: Set<String>, label: String) {
        let content = nitro.exportTokens(from: app.tokens, matching: states)
        if content.isEmpty {
            triggerToast("Không có token phù hợp để copy")
        } else {
            UIPasteboard.general.string = content
            triggerToast(label)
        }
    }

    private func triggerToast(_ msg: String) {
        withAnimation { copiedToast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                if copiedToast == msg { copiedToast = nil }
            }
        }
    }
}

// ==============================================================================
// MARK: - HELPER SUBVIEWS (SMALL & FAST FOR SWIFT TYPECHECKER)
// ==============================================================================

struct NitroMiniStatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct NitroTokenResultCard: View {
    let result: NitroTokenScanResult
    let isBusy: Bool
    let onRescan: () -> Void
    let onClaim: () -> Void
    let onCancelRenewal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Row: Avatar + Name + State Badge
            HStack(spacing: 10) {
                avatarView

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(result.username)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        if result.premiumTier.isNitro {
                            Text(result.premiumTier.shortBadge)
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple, in: Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        if let verified = result.emailVerified {
                            Label(verified ? "Email OK" : "Chưa Verify",
                                  systemImage: verified ? "checkmark.shield.fill" : "exclamationmark.shield")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(verified ? .green : .orange)
                        }
                        if let ps = result.preferredPaymentSource {
                            Label(ps.displayName, systemImage: "creditcard.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.indigo)
                                .lineLimit(1)
                        } else if result.state != .idle && result.state != .tokenDead {
                            Label("Chưa có thẻ", systemImage: "creditcard")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    if result.state == .scanning || result.state == .claiming {
                        ProgressView().scaleEffect(0.65)
                    } else {
                        Image(systemName: result.state.iconName)
                            .font(.system(size: 10, weight: .bold))
                    }
                    Text(result.state.badgeText)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                }
                .foregroundColor(result.state.badgeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(result.state.badgeColor.opacity(0.14), in: Capsule())
            }

            // Offer Highlight Pill (if trial offer discovered)
            if let offer = result.primaryOffer {
                HStack(spacing: 8) {
                    Image(systemName: "gift.fill")
                        .foregroundStyle(Color(red: 0.93, green: 0.28, blue: 0.60))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(offer.title)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                        HStack(spacing: 8) {
                            Text(offer.source.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            if let exp = NitroDateHelper.formatDisplay(offer.expiresAt) {
                                Text("Hạn nhận: \(exp)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(9)
                .background(Color(red: 0.93, green: 0.28, blue: 0.60).opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Status Detail Line
            Text(result.statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Action Buttons Row
            if result.state != .tokenDead {
                HStack(spacing: 8) {
                    Button(action: onRescan) {
                        Label("Quét lại", systemImage: "arrow.clockwise")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(UIColor.tertiarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(.primary)
                    }
                    .disabled(isBusy)

                    if result.canAttemptClaim {
                        Button(action: onClaim) {
                            Label("Claim ngay", systemImage: "sparkles")
                                .font(.caption2.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.35, green: 0.39, blue: 0.95), Color(red: 0.93, green: 0.28, blue: 0.60)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    in: Capsule()
                                )
                                .foregroundColor(.white)
                        }
                        .disabled(isBusy)
                    }

                    if result.state == .claimed && !result.autoRenewCanceled && (result.claimedSubscriptionId != nil || result.activeNitroSub != nil) {
                        Button(action: onCancelRenewal) {
                            Label("Tắt gia hạn", systemImage: "xmark.circle")
                                .font(.caption2.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.16), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        .disabled(isBusy)
                    }

                    Spacer()

                    if !result.outboundPromos.isEmpty {
                        Text("\(result.outboundPromos.count) Promo")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.indigo.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
        .padding(13)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var avatarView: some View {
        Group {
            if let url = result.avatarURL {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.25))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.gray)
            }
        }
    }
}

/// Badge gọn hiển thị trên mỗi dòng trong Danh sách Token sau khi quét
struct NitroTokenInlineBadge: View {
    let result: NitroTokenScanResult

    private var badgeLabel: String {
        if result.state == .trialAvailable, let offer = result.primaryOffer {
            return offer.shortDurationBadge
        }
        return result.state.badgeText
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: result.state.iconName)
                .font(.system(size: 9, weight: .bold))
            Text(badgeLabel)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
        }
        .foregroundColor(result.state.badgeColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(result.state.badgeColor.opacity(0.14), in: Capsule())
    }
}
