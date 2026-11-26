import SwiftUI
import UIKit
import MediaPlayer

// ==============================================================================
// MARK: - NOW PLAYING FEATURE & SESSION MODELS (MULTI-FEATURE iOS LOCK SCREEN)
// ==============================================================================

enum NowPlayingFeature: String, CaseIterable, Identifiable, Hashable {
    case music
    case treoVoice
    case spam
    case botNuke
    case userNuke
    case tokenCheck
    case preview

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .music: return "Xả Nhạc VIP"
        case .treoVoice: return "Treo Voice 24/7"
        case .spam: return "Spam Tin Nhắn"
        case .botNuke: return "Bot Nuke"
        case .userNuke: return "User Nuke"
        case .tokenCheck: return "Check Token"
        case .preview: return "Quoc Thang Tools"
        }
    }

    var symbolName: String {
        switch self {
        case .music: return "flame.fill"
        case .treoVoice: return "waveform"
        case .spam: return "paperplane.fill"
        case .botNuke: return "bolt.shield.fill"
        case .userNuke: return "exclamationmark.triangle.fill"
        case .tokenCheck: return "person.2.fill"
        case .preview: return "sparkles"
        }
    }

    var targetTabIndex: Int {
        switch self {
        case .spam: return 0
        case .tokenCheck: return 1
        case .music, .treoVoice: return 2
        case .botNuke, .userNuke: return 3
        case .preview: return 4
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .music:
            return [Color(red: 0.95, green: 0.24, blue: 0.28), Color(red: 1.0, green: 0.50, blue: 0.14)]
        case .treoVoice:
            return [Color(red: 0.36, green: 0.34, blue: 0.96), Color(red: 0.62, green: 0.28, blue: 0.95)]
        case .spam:
            return [Color(red: 0.28, green: 0.39, blue: 0.98), Color(red: 0.16, green: 0.67, blue: 0.96)]
        case .botNuke:
            return [Color(red: 0.92, green: 0.20, blue: 0.26), Color(red: 0.96, green: 0.48, blue: 0.18)]
        case .userNuke:
            return [Color(red: 0.88, green: 0.16, blue: 0.42), Color(red: 0.96, green: 0.36, blue: 0.22)]
        case .tokenCheck:
            return [Color(red: 0.10, green: 0.72, blue: 0.56), Color(red: 0.20, green: 0.54, blue: 0.95)]
        case .preview:
            return [Color(red: 0.35, green: 0.39, blue: 0.95), Color(red: 0.68, green: 0.31, blue: 0.96)]
        }
    }

    var uiGradientColors: (UIColor, UIColor) {
        switch self {
        case .music:
            return (UIColor(red: 0.95, green: 0.24, blue: 0.28, alpha: 1), UIColor(red: 1.0, green: 0.50, blue: 0.14, alpha: 1))
        case .treoVoice:
            return (UIColor(red: 0.36, green: 0.34, blue: 0.96, alpha: 1), UIColor(red: 0.62, green: 0.28, blue: 0.95, alpha: 1))
        case .spam:
            return (UIColor(red: 0.28, green: 0.39, blue: 0.98, alpha: 1), UIColor(red: 0.16, green: 0.67, blue: 0.96, alpha: 1))
        case .botNuke:
            return (UIColor(red: 0.92, green: 0.20, blue: 0.26, alpha: 1), UIColor(red: 0.96, green: 0.48, blue: 0.18, alpha: 1))
        case .userNuke:
            return (UIColor(red: 0.88, green: 0.16, blue: 0.42, alpha: 1), UIColor(red: 0.96, green: 0.36, blue: 0.22, alpha: 1))
        case .tokenCheck:
            return (UIColor(red: 0.10, green: 0.72, blue: 0.56, alpha: 1), UIColor(red: 0.20, green: 0.54, blue: 0.95, alpha: 1))
        case .preview:
            return (UIColor(red: 0.35, green: 0.39, blue: 0.95, alpha: 1), UIColor(red: 0.68, green: 0.31, blue: 0.96, alpha: 1))
        }
    }

    /// Thứ tự ưu tiên hiển thị mặc định khi nhiều chức năng chạy song song
    var priority: Int {
        switch self {
        case .music: return 100
        case .treoVoice: return 90
        case .spam: return 80
        case .botNuke: return 70
        case .userNuke: return 65
        case .tokenCheck: return 50
        case .preview: return 10
        }
    }
}

struct NowPlayingSessionState {
    let feature: NowPlayingFeature
    var title: String
    var detail: String
    var controlsHint: String
    var isPaused: Bool = false
    var elapsedTime: Double = 0
    var duration: Double = 0
    var isLiveStream: Bool = true
    var onPlay: (@MainActor () -> Void)? = nil
    var onPause: (@MainActor () -> Void)? = nil
    var onStop: (@MainActor () -> Void)? = nil
    var onNext: (@MainActor () -> Void)? = nil
    var onPrevious: (@MainActor () -> Void)? = nil
    var onSeek: (@MainActor (Double) -> Void)? = nil

    var supportsPauseResume: Bool {
        onPlay != nil || onPause != nil
    }
}

enum NowPlayingArtworkFactory {
    private static var cache: [NowPlayingFeature: MPMediaItemArtwork] = [:]

    static func artwork(for feature: NowPlayingFeature) -> MPMediaItemArtwork {
        if let cached = cache[feature] { return cached }
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        let (c1, c2) = feature.uiGradientColors
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor(red: 0.06, green: 0.07, blue: 0.13, alpha: 1).cgColor,
                c1.withAlphaComponent(0.95).cgColor,
                c2.withAlphaComponent(0.95).cgColor
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0.0, 0.55, 1.0]) {
                cg.drawLinearGradient(
                    grad,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            // Vòng sáng glass trung tâm
            let circleRect = CGRect(x: 96, y: 96, width: 320, height: 320)
            UIColor.white.withAlphaComponent(0.14).setFill()
            UIBezierPath(ovalIn: circleRect).fill()
            UIColor.white.withAlphaComponent(0.28).setStroke()
            let ring = UIBezierPath(ovalIn: circleRect.insetBy(dx: 2, dy: 2))
            ring.lineWidth = 4
            ring.stroke()

            let symConfig = UIImage.SymbolConfiguration(pointSize: 175, weight: .bold)
            if let sym = UIImage(systemName: feature.symbolName, withConfiguration: symConfig)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let s = sym.size
                sym.draw(at: CGPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2))
            }
        }
        let art = MPMediaItemArtwork(boundsSize: size) { _ in image }
        cache[feature] = art
        return art
    }
}

// ==============================================================================
// MARK: - MODERN STUDIO DESIGN SYSTEM (SHARED ACROSS ALL TABS)
// ==============================================================================

enum StudioPalette {
    static let spamGradient = LinearGradient(
        colors: [Color(red: 0.28, green: 0.39, blue: 0.98), Color(red: 0.16, green: 0.67, blue: 0.96)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let tokenGradient = LinearGradient(
        colors: [Color(red: 0.10, green: 0.72, blue: 0.56), Color(red: 0.22, green: 0.52, blue: 0.96)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let nukeBotGradient = LinearGradient(
        colors: [Color(red: 0.92, green: 0.20, blue: 0.26), Color(red: 0.98, green: 0.48, blue: 0.16)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let nukeUserGradient = LinearGradient(
        colors: [Color(red: 0.88, green: 0.16, blue: 0.42), Color(red: 0.96, green: 0.36, blue: 0.22)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let infoGradient = LinearGradient(
        colors: [Color(red: 0.36, green: 0.34, blue: 0.96), Color(red: 0.66, green: 0.30, blue: 0.96)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

struct StudioAmbientBackdrop: View {
    let topColor: Color
    let secondColor: Color

    var body: some View {
        ZStack(alignment: .top) {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            LinearGradient(
                colors: [topColor.opacity(0.15), secondColor.opacity(0.05), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 230)
            .ignoresSafeArea(edges: .top)
        }
    }
}

struct StudioCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
    }
}

extension View {
    func studioCard(cornerRadius: CGFloat = 18, padding: CGFloat = 14) -> some View {
        modifier(StudioCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

struct StudioTopHeaderBar<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let isLive: Bool
    let liveText: String
    let colors: [Color]
    @ViewBuilder let trailing: () -> Trailing

    init(
        icon: String,
        title: String,
        subtitle: String,
        isLive: Bool = false,
        liveText: String = "ĐANG CHẠY",
        colors: [Color],
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isLive = isLive
        self.liveText = liveText
        self.colors = colors
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 42, height: 42)
                    .shadow(color: (colors.first ?? .indigo).opacity(0.35), radius: 8, y: 4)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if isLive {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(liveText)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.14), in: Capsule())
                } else {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

struct StudioMiniMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
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
        .padding(.horizontal, 6)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.16), lineWidth: 1)
        )
    }
}

struct StudioGuildAvatarView: View {
    let guild: Guild
    var size: CGFloat = 42

    var body: some View {
        Group {
            if let icon = guild.icon, !AppEndpoints.cdnIcons.isEmpty,
               let url = URL(string: "\(AppEndpoints.cdnIcons)/\(guild.id)/\(icon).png?size=128") {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    fallbackCircle
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.30, style: .continuous))
            } else {
                fallbackCircle
            }
        }
    }

    private var fallbackCircle: some View {
        RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.indigo.opacity(0.85), Color.purple.opacity(0.8)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Text(String(guild.name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            )
    }
}

struct StudioTokenAvatarView: View {
    let token: TokenInfo
    var size: CGFloat = 44

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = token.avatarURL {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.25))
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.indigo.opacity(0.15))
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: size * 0.44))
                                .foregroundStyle(.indigo)
                        )
                }
            }
            .overlay(
                Circle().stroke(token.isValid ? Color.green.opacity(0.75) : Color.red.opacity(0.75), lineWidth: 2)
            )

            Circle()
                .fill(token.isValid ? Color.green : Color.red)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color(UIColor.secondarySystemGroupedBackground), lineWidth: 2))
        }
    }
}

struct StudioSearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .font(.subheadline)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// ==============================================================================
// MARK: - FLOATING IN-APP NOW PLAYING BAR (SYNCED 1:1 WITH iPHONE LOCK SCREEN)
// ==============================================================================

struct LiveNowPlayingBar: View {
    @ObservedObject var nowPlaying: NowPlayingHelper
    let onTapNavigate: (Int) -> Void

    var body: some View {
        if let active = nowPlaying.currentSession {
            HStack(spacing: 10) {
                Button {
                    onTapNavigate(active.feature.targetTabIndex)
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LinearGradient(colors: active.feature.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 38, height: 38)
                            Image(systemName: active.feature.symbolName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(active.isPaused ? Color.orange : Color.green)
                                    .frame(width: 6, height: 6)
                                Text(active.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if nowPlaying.activeCount > 1 {
                                    Text("\(nowPlaying.activeIndex + 1)/\(nowPlaying.activeCount)")
                                        .font(.system(size: 9, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.indigo, in: Capsule())
                                }
                            }
                            Text(active.detail)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    if nowPlaying.activeCount > 1 {
                        Button {
                            nowPlaying.cycleNextSession()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.indigo)
                                .frame(width: 30, height: 30)
                                .background(Color.indigo.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if active.supportsPauseResume {
                        Button {
                            nowPlaying.triggerPlayPause()
                        } label: {
                            Image(systemName: active.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(
                                    LinearGradient(colors: active.feature.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if active.feature == .music {
                        Button {
                            nowPlaying.triggerNext()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(width: 30, height: 30)
                                .background(Color.primary.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        nowPlaying.triggerStopCurrent()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 30, height: 30)
                            .background(Color.red.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 12, y: 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
