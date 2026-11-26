import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MediaPlayer

// ==============================================================================
// MARK: - MAIN TAB VIEW (MODERN STUDIO SHELL + FLOATING iPHONE NOW PLAYING BAR)
// ==============================================================================
struct MainTabView: View {
    @ObservedObject private var nowPlaying = NowPlayingHelper.shared
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                SpamView()
                    .tabItem { Label("Spam", systemImage: "paperplane.fill") }
                    .tag(0)

                TokenListView()
                    .tabItem { Label("Tokens", systemImage: "person.2.fill") }
                    .tag(1)

                VoiceRoomTabView()
                    .tabItem { Label("Treo Voice", systemImage: "waveform.circle.fill") }
                    .tag(2)

                NukeTabView()
                    .tabItem { Label("Nuke", systemImage: "flame.fill") }
                    .tag(3)

                AboutView()
                    .tabItem { Label("Info", systemImage: "sparkles") }
                    .tag(4)
            }
            .tint(.indigo)

            LiveNowPlayingBar(nowPlaying: nowPlaying) { targetTab in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    selectedTab = targetTab
                }
            }
            .padding(.bottom, 52)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: nowPlaying.currentSession?.feature)
        }
    }
}

// ==============================================================================
// MARK: - CRACKED / LOADING / LOCK / ADMIN VIEWS (MODERN OBSIDIAN STUDIO)
// ==============================================================================
struct CrackedView: View {
    @EnvironmentObject var license: LicenseManager
    let message: String
    @State private var showInput = false
    @State private var input = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.14, green: 0.02, blue: 0.04), Color.black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    Spacer(minLength: 48)

                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.18))
                            .frame(width: 112, height: 112)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(.red)
                            .shadow(color: .red.opacity(0.55), radius: 18)
                    }

                    VStack(spacing: 8) {
                        Text("BẢO MẬT BỊ CAN THIỆP")
                            .font(.system(size: 21, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .tracking(1.2)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    if showInput {
                        VStack(spacing: 12) {
                            TextField("Nhập license key...", text: $input)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                                .padding(14)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                                )

                            if let e = error {
                                Text(e)
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
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
                                    case .expired(let d): error = "Key hết hạn lúc \(license.formatDate(d))"
                                    default: error = "Không thể kích hoạt"
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if license.isChecking { ProgressView().tint(.white) }
                                    Text(license.isChecking ? "ĐANG XÁC THỰC..." : "KÍCH HOẠT LẠI")
                                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                            }
                            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || license.isChecking)
                        }
                        .padding(18)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
                        .padding(.horizontal, 22)
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showInput = true }
                        } label: {
                            Text("Nhập License Key")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 11)
                                .background(Color.red.opacity(0.25), in: Capsule())
                                .overlay(Capsule().stroke(Color.red.opacity(0.5), lineWidth: 1))
                        }
                    }

                    Button {
                        Task { await license.refreshStatus() }
                    } label: {
                        Label("Thử xác thực lại", systemImage: "arrow.clockwise")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer(minLength: 20)
                    Text("Quoc Thang Studio • v2.0")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.32))
                }
            }
        }
    }
}

struct LoadingView: View {
    @EnvironmentObject var license: LicenseManager
    @State private var showRecoveryActions = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.07, blue: 0.16), Color.black],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(StudioPalette.infoGradient)
                        .frame(width: 72, height: 72)
                        .shadow(color: Color.indigo.opacity(0.45), radius: 18, y: 6)
                    Image(systemName: "waveform")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                }

                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)

                Text("Đang xác thực bản quyền...")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                if showRecoveryActions {
                    VStack(spacing: 10) {
                        Text("Kết nối máy chủ hơi chậm, bạn có thể thử lại hoặc nhập key mới:")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        HStack(spacing: 10) {
                            Button {
                                Task { await license.refreshStatus(force: true) }
                            } label: {
                                Label("Thử lại", systemImage: "arrow.clockwise")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(Color.indigo.opacity(0.85), in: Capsule())
                            }

                            Button {
                                license.deactivate()
                            } label: {
                                Label("Nhập Key khác", systemImage: "key.fill")
                                    .font(.caption.bold())
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(Color.white.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity)
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            withAnimation(.easeInOut(duration: 0.25)) {
                showRecoveryActions = true
            }
        }
    }
}

struct LockView: View {
    @EnvironmentObject var license: LicenseManager
    @State private var input = ""
    @State private var error: String? = nil
    @State private var showAdminInfo = false
    @State private var logoTapCount = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.08, blue: 0.19), Color(red: 0.03, green: 0.03, blue: 0.07)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    Spacer(minLength: 48)

                    VStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(StudioPalette.infoGradient)
                                .frame(width: 88, height: 88)
                                .shadow(color: Color.indigo.opacity(0.5), radius: 22, y: 8)
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .onTapGesture {
                            logoTapCount += 1
                            if logoTapCount >= 7 { logoTapCount = 0; showAdminInfo = true }
                        }

                        Text("QUOC THANG STUDIO")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .tracking(1.2)

                        Text("KÍCH HOẠT LICENSE KEY ĐỂ TIẾP TỤC")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.indigo.opacity(0.9))
                            .tracking(1.6)
                    }

                    VStack(spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.indigo)
                            TextField("Nhập license key...", text: $input)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.white)
                                .onChange(of: input) { _ in error = nil }

                            if !input.isEmpty {
                                Button { input = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                            } else {
                                Button {
                                    if let s = UIPasteboard.general.string {
                                        input = s.trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                } label: {
                                    Text("Dán")
                                        .font(.caption.bold())
                                        .foregroundColor(.indigo)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(Color.indigo.opacity(0.22), in: Capsule())
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )

                        if let e = error {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(e)
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        }

                        let canActivate = !input.trimmingCharacters(in: .whitespaces).isEmpty && !license.isChecking
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
                            HStack(spacing: 8) {
                                if license.isChecking { ProgressView().tint(.white) }
                                Image(systemName: "checkmark.shield.fill")
                                Text(license.isChecking ? "ĐANG KIỂM TRA..." : "KÍCH HOẠT NGAY")
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                canActivate
                                    ? AnyShapeStyle(StudioPalette.infoGradient)
                                    : AnyShapeStyle(Color.gray.opacity(0.45)),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .shadow(color: canActivate ? Color.indigo.opacity(0.45) : .clear, radius: 12, y: 5)
                        }
                        .disabled(!canActivate)
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .padding(.horizontal, 22)

                    if case .expired(let d) = license.status {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                            Text("Key trước đó đã hết hạn lúc: \(fmt(d))")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                    } else if case .invalid(let reason) = license.status, !reason.isEmpty {
                        VStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(reason)
                                    .multilineTextAlignment(.center)
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 22)

                            if let existingKey = license.licenseKey, !existingKey.isEmpty {
                                Button {
                                    Task { await license.refreshStatus(force: true) }
                                } label: {
                                    Label("Thử kiểm tra lại key đã lưu", systemImage: "arrow.clockwise")
                                        .font(.caption.bold())
                                        .foregroundColor(.white.opacity(0.85))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }

                    Spacer(minLength: 20)
                    Text("Quoc Thang Studio • v2.0")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.vertical, 20)
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

struct LicenseAdminInfoView: View {
    @EnvironmentObject var license: LicenseManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                StudioAmbientBackdrop(topColor: .indigo, secondColor: .purple)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("INTEGRITY (__TEXT SHA-256)")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text(AppIntegrityAuditor.shared.computeTextSectionHash())
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                            Text("SOURCE SIG")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            Text(AppIntegrityAuditor.shared.computeSourceSignature())
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .studioCard()

                        if let k = license.licenseKey {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("KEY HIỆN TẠI")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                Text(k)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Text(license.statusText)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.green)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .studioCard()
                        }

                        Button(role: .destructive) {
                            license.deactivate()
                            dismiss()
                        } label: {
                            Label("Xoá key hiện tại", systemImage: "trash.fill")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Admin Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
            }
        }
    }
}

// ==============================================================================
// MARK: - ABOUT / INFO & iPHONE NOW PLAYING STUDIO VIEW
// ==============================================================================
struct AboutView: View {
    @EnvironmentObject var license: LicenseManager
    @ObservedObject private var nowPlaying = NowPlayingHelper.shared
    @State private var showFullKey = false
    @State private var copiedAdmin = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                StudioAmbientBackdrop(
                    topColor: Color(red: 0.36, green: 0.34, blue: 0.96),
                    secondColor: Color(red: 0.66, green: 0.30, blue: 0.96)
                )

                VStack(spacing: 0) {
                    StudioTopHeaderBar(
                        icon: "sparkles",
                        title: "Quoc Thang Studio",
                        subtitle: "Cài đặt hệ thống & Trình phát nhạc iPhone",
                        isLive: nowPlaying.currentSession != nil,
                        liveText: "NOW PLAYING • \(nowPlaying.activeCount) TÁC VỤ",
                        colors: [Color(red: 0.36, green: 0.34, blue: 0.96), Color(red: 0.66, green: 0.30, blue: 0.96)]
                    ) {
                        Text("v2.0")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(StudioPalette.infoGradient, in: Capsule())
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            nowPlayingStudioCard
                            licenseCard
                            aboutAppCard
                            adminContactCard
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 96)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var nowPlayingStudioCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trình Phát Nhạc iPhone (Now Playing)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Tương tác Màn hình khóa, Control Center & Dynamic Island")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Live status pill
            HStack(spacing: 10) {
                Circle()
                    .fill(nowPlaying.currentSession != nil ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 9, height: 9)
                if let active = nowPlaying.currentSession {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(active.title)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Text(active.controlsHint)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Chưa có tác vụ đang chạy — bấm nút bên dưới để thử Widget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Exclusive lock screen toggle
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ưu tiên Widget Màn hình khóa")
                        .font(.subheadline.weight(.semibold))
                    Text("BẬT để iOS luôn hiện thanh nhạc & Dynamic Island cho mọi chức năng. TẮT nếu muốn phát chung với Spotify/YouTube.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $nowPlaying.claimExclusiveNowPlaying)
                    .labelsHidden()
                    .tint(.indigo)
            }
            .padding(11)
            .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Controls legend
            VStack(alignment: .leading, spacing: 6) {
                Text("PHÍM TƯƠNG TÁC TRÊN MÀN HÌNH KHÓA / AIRPODS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                nowPlayingLegendRow(icon: "flame.fill", color: .red, feature: "Xả Nhạc VIP", desc: "⏸ Câm/Sủa • ◀◀/▶▶ Đổi bài • Kéo thanh tua")
                nowPlayingLegendRow(icon: "waveform", color: .indigo, feature: "Treo Voice", desc: "⏸ Tắt/Mở Mic • ◀◀ Bật/Tắt Cam • ▶▶ Go Live")
                nowPlayingLegendRow(icon: "paperplane.fill", color: .blue, feature: "Spam Tin Nhắn", desc: "⏸ Tạm dừng/Tiếp tục • ◀◀/▶▶ Chỉnh tốc độ")
                nowPlayingLegendRow(icon: "bolt.shield.fill", color: .orange, feature: "Bot / User Nuke", desc: "Thanh tiến độ 0–100% • ⏸ Dừng tác vụ")
            }
            .padding(11)
            .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            let isPreviewing = (nowPlaying.currentSession?.feature == .preview)
            Button {
                if isPreviewing {
                    nowPlaying.stopPreviewSession()
                } else {
                    nowPlaying.startPreviewSession()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isPreviewing ? "stop.circle.fill" : "play.circle.fill")
                    Text(isPreviewing ? "Tắt thử Widget Màn Hình Khóa" : "Thử Widget Phát Nhạc iPhone ngay")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    isPreviewing
                        ? AnyShapeStyle(Color.red)
                        : AnyShapeStyle(LinearGradient(colors: [.pink, .purple, .indigo], startPoint: .leading, endPoint: .trailing)),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
            }
        }
        .studioCard()
    }

    private func nowPlayingLegendRow(icon: String, color: Color, feature: String, desc: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(feature)
                .font(.caption2.bold())
                .frame(width: 88, alignment: .leading)
            Text(desc)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var licenseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Thông Tin Bản Quyền")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                if case .valid = license.status {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
            }

            HStack {
                Text("License Key").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(maskedKey)
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(.indigo)
                Toggle("", isOn: $showFullKey)
                    .labelsHidden()
                    .tint(.indigo)
                    .scaleEffect(0.8)
            }
            Divider()
            HStack {
                Text("Kích hoạt lúc").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(license.activatedAt != nil ? license.formatDateTime(license.activatedAt!) : "N/A")
                    .font(.caption.bold())
            }
            Divider()
            HStack {
                Text("Hết hạn lúc").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if case .valid(let exp) = license.status {
                    Text(license.formatDateTime(exp)).font(.caption.bold()).foregroundStyle(.green)
                } else if case .expired(let exp) = license.status {
                    Text(license.formatDateTime(exp)).font(.caption.bold()).foregroundStyle(.red)
                } else {
                    Text("N/A").font(.caption.bold()).foregroundStyle(.secondary)
                }
            }
            if case .valid(let exp) = license.status {
                Divider()
                HStack {
                    Text("Thời gian còn lại").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(license.timeRemaining(until: exp))
                        .font(.caption.bold())
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.indigo.opacity(0.13), in: Capsule())
                }
            }
        }
        .studioCard()
    }

    private var aboutAppCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                Text("Giới Thiệu Ứng Dụng")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            Text("Quoc Thang Studio là bộ công cụ tiện ích Discord trên iOS với giao diện hiện đại, hỗ trợ chạy nền 24/7, phát Video/Fake Cam WebRTC 0% GPU và điều khiển đồng bộ trực tiếp trên Màn hình khóa / Dynamic Island của iPhone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var adminContactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill").foregroundStyle(.orange)
                Text("Hỗ Trợ & Dịch Vụ Admin")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            Text("Liên hệ Admin qua Discord để gia hạn bản quyền hoặc hỗ trợ kỹ thuật cho công cụ iOS / PC.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: "message.fill").foregroundStyle(.indigo)
                Text("@thaitu.thanhhoa")
                    .font(.system(.subheadline, design: .monospaced).bold())
                    .foregroundStyle(.indigo)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = "@thaitu.thanhhoa"
                    copiedAdmin = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedAdmin = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedAdmin ? "checkmark" : "doc.on.doc")
                        Text(copiedAdmin ? "Đã copy" : "Copy")
                    }
                    .font(.caption2.bold())
                    .foregroundColor(copiedAdmin ? .green : .indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((copiedAdmin ? Color.green : Color.indigo).opacity(0.14), in: Capsule())
                }
            }
            .padding(11)
            .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var maskedKey: String {
        guard let key = license.licenseKey else { return "No Key" }
        if showFullKey { return key }
        let parts = key.split(separator: "-")
        if parts.count == 3 { return "\(parts[0])-***-\(parts[2])" }
        return "\(key.prefix(4))***\(key.suffix(4))"
    }
}

// ==============================================================================
// MARK: - EMPTY STATE & STAT CARD (MODERN)
// ==============================================================================
struct EmptyStateView: View {
    let title, systemImage, description: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 68, height: 68)
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.indigo)
            }
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 36)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .padding(.horizontal, 8)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }
}

// ==============================================================================
// MARK: - TOKEN MANAGEMENT VIEWS (MODERN STUDIO)
// ==============================================================================
struct TokenListView: View {
    @EnvironmentObject var app: AppState
    @State private var showAdd = false
    @State private var showImport = false

    private var liveCount: Int { app.tokens.filter { $0.isValid }.count }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                StudioAmbientBackdrop(
                    topColor: Color(red: 0.10, green: 0.72, blue: 0.56),
                    secondColor: Color(red: 0.22, green: 0.52, blue: 0.96)
                )

                VStack(spacing: 0) {
                    StudioTopHeaderBar(
                        icon: "person.2.fill",
                        title: "Quản Lý Token",
                        subtitle: "\(liveCount) live • \(app.selectedTokenIds.count) đang chọn",
                        isLive: app.isCheckingToken,
                        liveText: "ĐANG CHECK TOKEN...",
                        colors: [Color(red: 0.10, green: 0.72, blue: 0.56), Color(red: 0.22, green: 0.52, blue: 0.96)]
                    ) {
                        Menu {
                            Button { showAdd = true } label: { Label("Thêm thủ công", systemImage: "keyboard") }
                            Button { showImport = true } label: { Label("Nhập từ file .txt", systemImage: "doc.text") }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                Text("Thêm")
                            }
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(StudioPalette.tokenGradient, in: Capsule())
                            .shadow(color: Color.teal.opacity(0.32), radius: 6, y: 2)
                        }
                    }

                    if app.tokens.isEmpty {
                        EmptyStateView(
                            title: "Chưa có Token",
                            systemImage: "key.slash",
                            description: "Bấm nút + Thêm ở góc phải để dán token hoặc nhập hàng loạt từ file .txt."
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 14) {
                                // 3-Column Metrics
                                HStack(spacing: 10) {
                                    StudioMiniMetricTile(title: "Tổng Token", value: "\(app.tokens.count)", icon: "key.fill", color: .blue)
                                    StudioMiniMetricTile(title: "Đang Live", value: "\(liveCount)", icon: "checkmark.circle.fill", color: .green)
                                    StudioMiniMetricTile(title: "Đang Chọn", value: "\(app.selectedTokenIds.count)", icon: "person.3.fill", color: .indigo)
                                }

                                // Quick Actions Row
                                HStack(spacing: 8) {
                                    Button { app.selectAllValidTokens() } label: {
                                        Label("Chọn tất cả", systemImage: "checkmark.circle")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 7)
                                            .background(Color.teal.opacity(0.14), in: Capsule())
                                            .foregroundColor(.teal)
                                    }

                                    if !app.selectedTokenIds.isEmpty {
                                        Button { app.clearTokenSelection() } label: {
                                            Label("Bỏ chọn", systemImage: "xmark.circle")
                                                .font(.caption.bold())
                                                .padding(.horizontal, 11)
                                                .padding(.vertical, 7)
                                                .background(Color.orange.opacity(0.14), in: Capsule())
                                                .foregroundColor(.orange)
                                        }
                                    }

                                    Spacer()

                                    Button { showImport = true } label: {
                                        Label("Nhập file", systemImage: "doc.badge.plus")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 7)
                                            .background(Color(UIColor.secondarySystemGroupedBackground), in: Capsule())
                                            .foregroundColor(.primary)
                                    }
                                }

                                // Token Cards
                                LazyVStack(spacing: 10) {
                                    ForEach(app.tokens) { t in
                                        let isSelected = app.selectedTokenIds.contains(t.id)
                                        HStack(spacing: 12) {
                                            StudioTokenAvatarView(token: t, size: 44)

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(t.username)
                                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                                    .lineLimit(1)
                                                HStack(spacing: 6) {
                                                    Text(t.isValid ? "LIVE" : "DIE")
                                                        .font(.system(size: 9, weight: .black, design: .rounded))
                                                        .foregroundColor(t.isValid ? .green : .red)
                                                        .padding(.horizontal, 7)
                                                        .padding(.vertical, 2)
                                                        .background((t.isValid ? Color.green : Color.red).opacity(0.14), in: Capsule())
                                                    if isSelected {
                                                        Text("ĐÃ CHỌN")
                                                            .font(.system(size: 9, weight: .black, design: .rounded))
                                                            .foregroundColor(.indigo)
                                                            .padding(.horizontal, 7)
                                                            .padding(.vertical, 2)
                                                            .background(Color.indigo.opacity(0.14), in: Capsule())
                                                    }
                                                }
                                            }

                                            Spacer()

                                            if t.isValid {
                                                Button {
                                                    withAnimation(.easeInOut(duration: 0.18)) {
                                                        app.toggleTokenSelection(t)
                                                    }
                                                } label: {
                                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                        .font(.system(size: 22))
                                                        .foregroundStyle(isSelected ? .indigo : .secondary)
                                                }
                                                .buttonStyle(.plain)
                                            }

                                            Button {
                                                withAnimation { app.removeToken(id: t.id) }
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.red)
                                                    .padding(8)
                                                    .background(Color.red.opacity(0.10), in: Circle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(12)
                                        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(isSelected ? Color.indigo.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 96)
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdd) { AddTokenSheet() }
            .sheet(isPresented: $showImport) {
                DocumentPicker(contentTypes: [.item]) { u in Task { await app.addTokensFromFile(url: u) } }
            }
            .overlay {
                if app.isCheckingToken {
                    VStack(spacing: 10) {
                        ProgressView().scaleEffect(1.2)
                        Text("Đang kiểm tra token...")
                            .font(.caption.bold())
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            ZStack {
                StudioAmbientBackdrop(topColor: .teal, secondColor: .blue)
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Dán Token Discord", systemImage: "key.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.teal)
                            Spacer()
                            Button {
                                if let str = UIPasteboard.general.string {
                                    input = str.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            } label: {
                                Label("Dán Clipboard", systemImage: "doc.on.clipboard")
                                    .font(.caption.bold())
                                    .foregroundColor(.teal)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.teal.opacity(0.14), in: Capsule())
                            }
                        }

                        TextField("Nhập hoặc dán token...", text: $input)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.subheadline, design: .monospaced))
                            .padding(12)
                            .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .studioCard()

                    Button {
                        Task {
                            await app.addToken(input)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if app.isCheckingToken { ProgressView().tint(.white) }
                            Image(systemName: "checkmark.circle.fill")
                            Text(app.isCheckingToken ? "Đang kiểm tra..." : "Kiểm tra & Lưu Token")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            (input.isEmpty || app.isCheckingToken)
                                ? AnyShapeStyle(Color.gray.opacity(0.5))
                                : AnyShapeStyle(StudioPalette.tokenGradient),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .disabled(input.isEmpty || app.isCheckingToken)

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Thêm Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
            }
        }
    }
}

// ==============================================================================
// MARK: - SPAM STUDIO VIEWS (MODERN)
// ==============================================================================
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
            ZStack(alignment: .top) {
                StudioAmbientBackdrop(
                    topColor: Color(red: 0.28, green: 0.39, blue: 0.98),
                    secondColor: Color(red: 0.16, green: 0.67, blue: 0.96)
                )

                VStack(spacing: 0) {
                    StudioTopHeaderBar(
                        icon: "paperplane.fill",
                        title: "Spam Studio",
                        subtitle: "\(app.selectedTokenIds.count) token • \(app.multiGuilds.count) server chung",
                        isLive: app.isSending,
                        liveText: app.isPausedSending ? "TẠM DỪNG • \(app.totalSent) TIN" : "ĐANG GỬI • \(app.totalSent) TIN",
                        colors: [Color(red: 0.28, green: 0.39, blue: 0.98), Color(red: 0.16, green: 0.67, blue: 0.96)]
                    ) {
                        Button {
                            Task { await app.recomputeMultiGuilds() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.indigo)
                                .frame(width: 34, height: 34)
                                .background(Color.indigo.opacity(0.14), in: Circle())
                        }
                    }

                    if app.selectedTokenIds.isEmpty {
                        EmptyStateView(
                            title: "Chưa chọn Token",
                            systemImage: "person.crop.circle.badge.exclamationmark",
                            description: "Vào tab Tokens để chọn 1 hoặc nhiều token Live trước khi chọn Server."
                        )
                    } else if app.isLoading {
                        VStack(spacing: 12) {
                            ProgressView().scaleEffect(1.2)
                            Text("Đang tải danh sách Server...").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 12) {
                                StudioSearchBar(text: $searchText, placeholder: "Tìm kiếm Server...")

                                if app.selectedTokenIds.count >= 2 {
                                    HStack(spacing: 8) {
                                        Image(systemName: "person.3.fill").foregroundStyle(.indigo)
                                        Text("\(app.selectedTokenIds.count) token đồng bộ • \(app.multiGuilds.count) Server chung")
                                            .font(.caption.bold())
                                            .foregroundStyle(.indigo)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(Color.indigo.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }

                                if filtered.isEmpty {
                                    EmptyStateView(
                                        title: "Không có Server chung",
                                        systemImage: "server.rack",
                                        description: "Các token đang chọn không tham gia cùng Server nào."
                                    )
                                } else {
                                    LazyVStack(spacing: 10) {
                                        ForEach(filtered) { g in
                                            NavigationLink(value: g) {
                                                HStack(spacing: 12) {
                                                    StudioGuildAvatarView(guild: g, size: 42)
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(g.name)
                                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                                            .foregroundStyle(.primary)
                                                            .lineLimit(1)
                                                        Text("ID: \(g.id)")
                                                            .font(.system(size: 10, design: .monospaced))
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption.bold())
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(12)
                                                .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 96)
                        }
                        .refreshable { await app.recomputeMultiGuilds() }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Guild.self) { ChannelListView(guild: $0) }
            .task {
                if app.multiGuilds.isEmpty && !app.selectedTokenIds.isEmpty {
                    await app.recomputeMultiGuilds()
                }
            }
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
        ZStack(alignment: .top) {
            StudioAmbientBackdrop(
                topColor: Color(red: 0.28, green: 0.39, blue: 0.98),
                secondColor: Color(red: 0.16, green: 0.67, blue: 0.96)
            )

            if app.isLoading {
                VStack(spacing: 12) {
                    ProgressView().scaleEffect(1.2)
                    Text("Đang tải danh sách kênh...").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        StudioSearchBar(text: $searchText, placeholder: "Tìm kênh văn bản...")

                        ForEach(Array(sections.enumerated()), id: \.offset) { _, sec in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(sec.category?.displayName.uppercased() ?? "KÊNH CHÍNH")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)

                                VStack(spacing: 0) {
                                    ForEach(Array(sec.items.enumerated()), id: \.element.id) { idx, c in
                                        NavigationLink(value: c) {
                                            HStack(spacing: 10) {
                                                Image(systemName: c.type == 5 ? "megaphone.fill" : "number")
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundColor(.indigo)
                                                    .frame(width: 28, height: 28)
                                                    .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                Text(c.displayName)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                        }
                                        .buttonStyle(.plain)

                                        if idx < sec.items.count - 1 {
                                            Divider().padding(.leading, 50)
                                        }
                                    }
                                }
                                .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 96)
                }
            }
        }
        .navigationTitle(guild.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await app.loadChannels(for: guild) }
        .navigationDestination(for: Channel.self) { SendView(channel: $0) }
    }
}

struct SendView: View {
    @EnvironmentObject var app: AppState
    let channel: Channel
    @State private var showImport = false

    var body: some View {
        ZStack(alignment: .top) {
            StudioAmbientBackdrop(
                topColor: Color(red: 0.28, green: 0.39, blue: 0.98),
                secondColor: Color(red: 0.16, green: 0.67, blue: 0.96)
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Hero Channel Card
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(StudioPalette.spamGradient)
                                .frame(width: 44, height: 44)
                            Image(systemName: "number")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.displayName)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .lineLimit(1)
                            Text("\(app.selectedTokenIds.count) token sẵn sàng • Điều khiển được trên Màn hình khóa")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .studioCard()

                    // Config Card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CẤU HÌNH GỬI TIN")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)

                        Toggle(isOn: $app.useTag) {
                            Label("Tag User ID", systemImage: "at")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(.indigo)

                        if app.useTag {
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill").foregroundStyle(.secondary).font(.caption)
                                TextField("Nhập User ID cần tag...", text: $app.targetUserId)
                                    .keyboardType(.numberPad)
                                    .font(.system(.subheadline, design: .monospaced))
                            }
                            .padding(11)
                            .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }

                        HStack(spacing: 10) {
                            spamMiniToggle(title: "Tiền tố '>'", isOn: $app.addPrefix)
                            spamMiniToggle(title: "Hậu tố '#'", isOn: $app.addSuffix)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("Tốc độ Delay", systemImage: "timer")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(String(format: "%.1f", app.delaySeconds))s")
                                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(app.delaySeconds < 1.0 ? .red : .indigo)
                            }
                            Slider(value: $app.delaySeconds, in: 0.1...5.0, step: 0.1).tint(.indigo)
                            HStack(spacing: 6) {
                                ForEach([0.5, 1.0, 2.0, 3.0], id: \.self) { val in
                                    let active = abs(app.delaySeconds - val) < 0.05
                                    Button { app.delaySeconds = val } label: {
                                        Text("\(String(format: "%.1f", val))s")
                                            .font(.caption2.bold())
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .background(active ? Color.indigo : Color(UIColor.tertiarySystemGroupedBackground), in: Capsule())
                                            .foregroundColor(active ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .studioCard()

                    // Message Editor Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("NỘI DUNG TIN NHẮN")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !app.messages.isEmpty {
                                Text("\(app.messages.count) dòng")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.14), in: Capsule())
                            }
                            Button { showImport = true } label: {
                                Label("Import", systemImage: "doc.badge.plus")
                                    .font(.caption.bold())
                                    .foregroundColor(.indigo)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.indigo.opacity(0.14), in: Capsule())
                            }
                        }

                        ZStack(alignment: .topTrailing) {
                            TextEditor(text: $app.inputText)
                                .scrollContentBackground(.hidden)
                                .frame(height: 110)
                                .padding(10)
                                .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onChange(of: app.inputText) { _ in app.parseDirectInput() }
                            if !app.inputText.isEmpty {
                                Button {
                                    app.inputText = ""
                                    app.parseDirectInput()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .padding(12)
                                }
                            }
                        }
                    }
                    .studioCard()

                    // Live Control or Start CTA
                    if app.isSending {
                        VStack(spacing: 14) {
                            HStack {
                                Circle()
                                    .fill(app.isPausedSending ? Color.orange : Color.green)
                                    .frame(width: 10, height: 10)
                                Text(app.isPausedSending ? "ĐANG TẠM DỪNG" : "ĐANG GỬI LIÊN TỤC")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(app.isPausedSending ? .orange : .green)
                                Spacer()
                                Text("\(app.totalSent) tin")
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .foregroundStyle(.indigo)
                                    .monospacedDigit()
                            }

                            if !app.currentMessageStr.isEmpty {
                                Text(app.currentMessageStr)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            if !app.tokenSendCount.isEmpty {
                                VStack(spacing: 6) {
                                    ForEach(Array(app.tokenSendCount.keys), id: \.self) { id in
                                        if let t = app.tokens.first(where: { $0.id == id }) {
                                            HStack {
                                                Text(t.username).font(.caption.bold())
                                                Spacer()
                                                Text("\(app.tokenSendCount[id] ?? 0) tin")
                                                    .font(.system(.caption, design: .monospaced).bold())
                                                    .foregroundStyle(.indigo)
                                            }
                                        }
                                    }
                                }
                                .padding(10)
                                .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            HStack(spacing: 10) {
                                Button {
                                    if app.isPausedSending { app.resumeSending() } else { app.pauseSending() }
                                } label: {
                                    Label(app.isPausedSending ? "Tiếp tục" : "Tạm dừng", systemImage: app.isPausedSending ? "play.fill" : "pause.fill")
                                        .font(.subheadline.bold())
                                        .foregroundColor(app.isPausedSending ? .green : .orange)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background((app.isPausedSending ? Color.green : Color.orange).opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                }

                                Button(role: .destructive) {
                                    app.stopSending()
                                } label: {
                                    Label("Dừng hẳn", systemImage: "stop.fill")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Color.red, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                }
                            }
                        }
                        .studioCard()
                    } else {
                        let canStart = !app.messages.isEmpty && !(app.useTag && app.targetUserId.isEmpty)
                        Button {
                            app.hideKeyboard()
                            app.startSending(channel: channel)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "paperplane.fill")
                                Text("BẮT ĐẦU SPAM")
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                canStart
                                    ? AnyShapeStyle(StudioPalette.spamGradient)
                                    : AnyShapeStyle(Color.gray.opacity(0.5)),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .shadow(color: canStart ? Color.indigo.opacity(0.35) : .clear, radius: 10, y: 5)
                        }
                        .disabled(!canStart)
                    }

                    if let err = app.lastError {
                        Text(err)
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 96)
            }
        }
        .navigationTitle("Gửi Tin")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImport) {
            DocumentPicker(contentTypes: [.plainText, .text, .item]) { u in app.parseFile(url: u) }
        }
    }

    private func spamMiniToggle(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isOn.wrappedValue.toggle() }
        } label: {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isOn.wrappedValue ? .indigo : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isOn.wrappedValue ? Color.indigo.opacity(0.14) : Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isOn.wrappedValue ? Color.indigo.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// ==============================================================================
// MARK: - NUKE STUDIO TAB & VIEWS (MODERN)
// ==============================================================================
struct NukeTabView: View {
    @EnvironmentObject var bot: BotManager
    @EnvironmentObject var userNuke: UserNukeManager
    @State private var mode: Mode = .bot
    enum Mode { case bot, user }

    private var isRunningAny: Bool { bot.isNuking || userNuke.isNuking }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                StudioAmbientBackdrop(
                    topColor: mode == .bot ? Color(red: 0.92, green: 0.20, blue: 0.26) : Color(red: 0.88, green: 0.16, blue: 0.42),
                    secondColor: Color(red: 0.98, green: 0.48, blue: 0.16)
                )

                VStack(spacing: 0) {
                    StudioTopHeaderBar(
                        icon: "flame.fill",
                        title: mode == .bot ? "Nuke Studio • Bot" : "Nuke Studio • User",
                        subtitle: "Tự động đồng bộ tiến độ lên Màn hình khóa iPhone",
                        isLive: isRunningAny,
                        liveText: "ĐANG CHẠY • \(Int((bot.isNuking ? bot.phaseProgress : userNuke.phaseProgress) * 100))%",
                        colors: mode == .bot
                            ? [Color(red: 0.92, green: 0.20, blue: 0.26), Color(red: 0.98, green: 0.48, blue: 0.16)]
                            : [Color(red: 0.88, green: 0.16, blue: 0.42), Color(red: 0.96, green: 0.36, blue: 0.22)]
                    ) {
                        Text(mode == .bot ? "BOT" : "USER")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(mode == .bot ? StudioPalette.nukeBotGradient : StudioPalette.nukeUserGradient, in: Capsule())
                    }

                    // Floating Capsule Mode Switcher
                    HStack(spacing: 6) {
                        nukeModeButton(target: .bot, title: "Bot Nuke", icon: "bolt.shield.fill", isLive: bot.isNuking, colors: [Color(red: 0.92, green: 0.20, blue: 0.26), Color(red: 0.98, green: 0.48, blue: 0.16)])
                        nukeModeButton(target: .user, title: "User Token", icon: "person.2.fill", isLive: userNuke.isNuking, colors: [Color(red: 0.88, green: 0.16, blue: 0.42), Color(red: 0.96, green: 0.36, blue: 0.22)])
                    }
                    .padding(4)
                    .background(Color(UIColor.secondarySystemGroupedBackground), in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                    if mode == .bot {
                        BotNukeView()
                    } else {
                        UserNukeView()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func nukeModeButton(target: Mode, title: String, icon: String, isLive: Bool, colors: [Color]) -> some View {
        let selected = (mode == target)
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { mode = target }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
                if isLive {
                    Circle().fill(selected ? Color.white : Color.green).frame(width: 7, height: 7)
                }
            }
            .foregroundColor(selected ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.clear),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

struct BotNukeView: View {
    @EnvironmentObject var bot: BotManager
    @State private var showTokenSheet = false
    @State private var tokenInput = ""
    @State private var selectedGuild: Guild?
    @State private var showConfigSheet = false
    @State private var nukeConfig = NukeConfig()
    @State private var copiedLog = false

    var body: some View {
        Group {
            if bot.config == nil {
                VStack(spacing: 18) {
                    EmptyStateView(
                        title: "Chưa cấu hình Bot",
                        systemImage: "key.slash",
                        description: "Nhập Bot Token để tải danh sách Server và thiết lập các bước thực thi."
                    )
                    Button { showTokenSheet = true } label: {
                        Label("Nhập Bot Token", systemImage: "key.fill")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(StudioPalette.nukeBotGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .shadow(color: Color.red.opacity(0.32), radius: 10, y: 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
            } else if bot.isNuking {
                nukeLiveDashboard(
                    phase: bot.currentPhase,
                    progress: bot.phaseProgress,
                    banSuccess: bot.banSuccess,
                    banFailed: bot.banFailed,
                    channelsDeleted: bot.channelsDeleted,
                    channelsCreated: bot.channelsCreated,
                    messagesSent: bot.messagesSent,
                    rolesCreated: bot.rolesCreated,
                    logs: bot.nukeLog,
                    copied: $copiedLog,
                    onStop: { bot.stopNuke() }
                )
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Bot Profile Card
                        HStack(spacing: 12) {
                            if let url = bot.config?.avatarURL {
                                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                placeholder: { Circle().fill(.gray.opacity(0.25)) }
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            } else {
                                Circle().fill(Color.red.opacity(0.15)).frame(width: 44, height: 44)
                                    .overlay(Image(systemName: "bolt.shield.fill").foregroundStyle(.red))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bot.config?.displayName ?? "Bot")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                Text("Bot Token • \(bot.botGuilds.count) Server")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await bot.loadGuilds() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption.bold())
                                    .foregroundStyle(.indigo)
                                    .padding(8)
                                    .background(Color.indigo.opacity(0.12), in: Circle())
                            }
                            Button(role: .destructive) { bot.removeConfig() } label: {
                                Image(systemName: "trash")
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
                                    .padding(8)
                                    .background(Color.red.opacity(0.12), in: Circle())
                            }
                        }
                        .studioCard()

                        // Server List
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CHỌN SERVER (\(bot.botGuilds.count))")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)

                            if bot.botGuilds.isEmpty {
                                Text("Bot chưa tham gia Server nào.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 20)
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(bot.botGuilds) { g in
                                        Button {
                                            selectedGuild = g
                                            showConfigSheet = true
                                        } label: {
                                            HStack(spacing: 12) {
                                                StudioGuildAvatarView(guild: g, size: 38)
                                                Text(g.name)
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(10)
                                            .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .studioCard()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
                .refreshable { await bot.loadGuilds() }
            }
        }
        .sheet(isPresented: $showTokenSheet) {
            NavigationStack {
                ZStack {
                    StudioAmbientBackdrop(topColor: .red, secondColor: .orange)
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("DÁN BOT TOKEN")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            TextField("Dán bot token...", text: $tokenInput)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(.subheadline, design: .monospaced))
                                .padding(12)
                                .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            if let e = bot.tokenError {
                                Text(e).font(.caption.bold()).foregroundStyle(.red)
                            }
                        }
                        .studioCard()

                        Button {
                            Task {
                                await bot.setToken(tokenInput)
                                if bot.config != nil { showTokenSheet = false }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if bot.isCheckingToken { ProgressView().tint(.white) }
                                Text(bot.isCheckingToken ? "Đang xác thực..." : "Lưu Bot Token")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                (tokenInput.isEmpty || bot.isCheckingToken)
                                    ? AnyShapeStyle(Color.gray.opacity(0.5))
                                    : AnyShapeStyle(StudioPalette.nukeBotGradient),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .disabled(tokenInput.isEmpty || bot.isCheckingToken)

                        Spacer()
                    }
                    .padding(16)
                }
                .navigationTitle("Bot Token")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { showTokenSheet = false } }
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
        .task {
            if bot.config != nil && bot.botGuilds.isEmpty {
                await bot.loadGuilds()
            }
        }
    }
}

struct UserNukeView: View {
    @EnvironmentObject var userNuke: UserNukeManager
    @State private var showImport = false
    @State private var showAddManual = false
    @State private var manualToken = ""
    @State private var selectedGuild: Guild?
    @State private var showConfigSheet = false
    @State private var nukeConfig = NukeConfig()
    @State private var copiedLog = false

    var body: some View {
        Group {
            if userNuke.isNuking {
                nukeLiveDashboard(
                    phase: userNuke.currentPhase,
                    progress: userNuke.phaseProgress,
                    banSuccess: userNuke.banSuccess,
                    banFailed: userNuke.banFailed,
                    channelsDeleted: userNuke.channelsDeleted,
                    channelsCreated: userNuke.channelsCreated,
                    messagesSent: userNuke.messagesSent,
                    rolesCreated: userNuke.rolesCreated,
                    logs: userNuke.nukeLog,
                    copied: $copiedLog,
                    onStop: { userNuke.stop() }
                )
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Tokens Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("TOKENS (\(userNuke.selectedTokenIds.count)/\(userNuke.tokens.count))")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button { showAddManual = true } label: {
                                    Label("Thêm tay", systemImage: "plus")
                                        .font(.caption2.bold())
                                        .foregroundColor(.pink)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(Color.pink.opacity(0.14), in: Capsule())
                                }
                                Button { showImport = true } label: {
                                    Label("Import", systemImage: "doc.badge.plus")
                                        .font(.caption2.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(StudioPalette.nukeUserGradient, in: Capsule())
                                }
                            }

                            if userNuke.tokens.isEmpty {
                                Text("Chưa có token — bấm Thêm tay hoặc Import file .txt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 16)
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(userNuke.tokens) { t in
                                        let selected = userNuke.selectedTokenIds.contains(t.id)
                                        HStack(spacing: 10) {
                                            StudioTokenAvatarView(token: t, size: 36)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(t.username).font(.subheadline.bold()).lineLimit(1)
                                                Text(t.isValid ? "LIVE" : "DIE")
                                                    .font(.system(size: 9, weight: .black))
                                                    .foregroundStyle(t.isValid ? .green : .red)
                                            }
                                            Spacer()
                                            if t.isValid {
                                                Button { userNuke.toggleSelection(t) } label: {
                                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                                        .font(.title3)
                                                        .foregroundStyle(selected ? .pink : .secondary)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            Button(role: .destructive) { userNuke.removeToken(t.id) } label: {
                                                Image(systemName: "trash")
                                                    .font(.caption)
                                                    .foregroundStyle(.red)
                                                    .padding(7)
                                                    .background(Color.red.opacity(0.10), in: Circle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(9)
                                        .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                            }
                        }
                        .studioCard()

                        // Eligible Guilds Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("SERVER PHÙ HỢP (\(userNuke.eligibleGuilds.count))")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if userNuke.isLoadingGuilds { ProgressView().scaleEffect(0.75) }
                            }

                            if userNuke.selectedTokenIds.isEmpty {
                                Text("Chọn ít nhất 1 token Live ở trên để tải Server.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 10)
                            } else if userNuke.eligibleGuilds.isEmpty && !userNuke.isLoadingGuilds {
                                Text("Không tìm thấy Server có quyền thực thi.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 10)
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(userNuke.eligibleGuilds) { g in
                                        Button {
                                            selectedGuild = g
                                            showConfigSheet = true
                                        } label: {
                                            HStack(spacing: 12) {
                                                StudioGuildAvatarView(guild: g, size: 38)
                                                Text(g.name)
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(10)
                                            .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .studioCard()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
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
        .sheet(isPresented: $showAddManual) {
            NavigationStack {
                ZStack {
                    StudioAmbientBackdrop(topColor: .pink, secondColor: .red)
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("USER TOKEN").font(.caption2.bold()).foregroundStyle(.secondary)
                            TextField("Dán user token...", text: $manualToken)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(.subheadline, design: .monospaced))
                                .padding(12)
                                .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .studioCard()

                        Button {
                            Task {
                                _ = await userNuke.addTokenManually(manualToken)
                                manualToken = ""
                                showAddManual = false
                            }
                        } label: {
                            Text("Lưu Token")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(StudioPalette.nukeUserGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || userNuke.isImporting)
                        Spacer()
                    }
                    .padding(16)
                }
                .navigationTitle("Thêm User Token")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { showAddManual = false } }
                }
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

private func nukeLiveDashboard(
    phase: String,
    progress: Double,
    banSuccess: Int,
    banFailed: Int,
    channelsDeleted: Int,
    channelsCreated: Int,
    messagesSent: Int,
    rolesCreated: Int,
    logs: [String],
    copied: Binding<Bool>,
    onStop: @escaping () -> Void
) -> some View {
    ScrollView(showsIndicators: false) {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ProgressView().tint(.red)
                    Text(phase.isEmpty ? "Đang xử lý..." : phase)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(Int(min(1.0, max(0.0, progress)) * 100))%")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundStyle(.red)
                }
                ProgressView(value: min(1.0, max(0.0, progress)))
                    .tint(.red)
            }
            .studioCard()

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    StudioMiniMetricTile(title: "Ban OK", value: "\(banSuccess)", icon: "checkmark.circle.fill", color: .green)
                    StudioMiniMetricTile(title: "Ban FAIL", value: "\(banFailed)", icon: "xmark.circle.fill", color: .red)
                }
                HStack(spacing: 10) {
                    StudioMiniMetricTile(title: "Xóa kênh", value: "\(channelsDeleted)", icon: "trash.fill", color: .orange)
                    StudioMiniMetricTile(title: "Tạo kênh", value: "\(channelsCreated)", icon: "plus.square.fill", color: .blue)
                }
                HStack(spacing: 10) {
                    StudioMiniMetricTile(title: "Tin nhắn", value: "\(messagesSent)", icon: "paperplane.fill", color: .purple)
                    StudioMiniMetricTile(title: "Role", value: "\(rolesCreated)", icon: "star.fill", color: .pink)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Nhật ký thực thi", systemImage: "terminal.fill")
                        .font(.subheadline.bold())
                    Spacer()
                    Button {
                        UIPasteboard.general.string = logs.joined(separator: "\n")
                        copied.wrappedValue = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied.wrappedValue = false }
                    } label: {
                        Text(copied.wrappedValue ? "Đã copy" : "Copy")
                            .font(.caption2.bold())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.indigo.opacity(0.14), in: Capsule())
                            .foregroundColor(.indigo)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(logs.suffix(200).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(line.contains("Lỗi") || line.contains("FAIL") ? Color(red: 1, green: 0.45, blue: 0.45) : Color(white: 0.85))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .frame(height: 185)
                .background(Color(red: 0.08, green: 0.09, blue: 0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .studioCard()

            Button(role: .destructive, action: onStop) {
                Label("DỪNG TÁC VỤ", systemImage: "stop.circle.fill")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: Color.red.opacity(0.35), radius: 10, y: 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 96)
    }
}

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
                            }
                        )) {
                            Label(step.rawValue, systemImage: step.icon)
                        }
                        .tint(.red)
                    }
                }

                Section("Tuỳ chọn chi tiết") {
                    if config.enabledSteps.contains(.massBan) {
                        TextField("Ban role ID (tuỳ chọn)", text: $config.banRoleId)
                            .keyboardType(.numberPad)
                        HStack {
                            Text("Delay ban")
                            Slider(value: $config.banDelay, in: 0...1.0, step: 0.01).tint(.red)
                            Text("\(String(format: "%.2f", config.banDelay))s").font(.caption.monospacedDigit())
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
                        Toggle("Tag @everyone", isOn: $config.tagEveryone).tint(.red)
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
                    .foregroundStyle(.red)
                    .disabled(config.enabledSteps.isEmpty)
                }
            }
        }
    }
}
