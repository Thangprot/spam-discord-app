import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import Foundation

// ==============================================================================
// MARK: - PHOTO LIBRARY PICKER (CHỌN VIDEO HOẶC ẢNH TỪ APP ẢNH iPHONE — iOS 16+)
// ==============================================================================

enum PhotoLibraryFilterMode {
    case imagesAndVideos
    case imagesOnly
    case videosOnly
}

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let filterMode: PhotoLibraryFilterMode
    let onPickMediaURL: (URL, Bool) -> Void // (localURL, isImage)
    var onCancel: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        switch filterMode {
        case .imagesAndVideos:
            config.filter = .any(of: [.images, .videos])
        case .imagesOnly:
            config.filter = .images
        case .videosOnly:
            config.filter = .videos
        }
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let first = results.first else {
                parent.onCancel?()
                return
            }
            let provider = first.itemProvider
            let fm = FileManager.default
            let cacheDir = (fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory)
                .appendingPathComponent("TreoMedia", isDirectory: true)
            try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            // 1. Ưu tiên kiểm tra Video trước
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { tempURL, _ in
                    guard let src = tempURL else { return }
                    let ext = src.pathExtension.isEmpty ? "mp4" : src.pathExtension
                    let safeName = "photo_vid_\(UUID().uuidString.prefix(8)).\(ext)"
                    let dest = cacheDir.appendingPathComponent(safeName)
                    try? fm.removeItem(at: dest)
                    do {
                        try fm.copyItem(at: src, to: dest)
                        DispatchQueue.main.async {
                            self.parent.onPickMediaURL(dest, false)
                        }
                    } catch {
                        // Fallback đọc data nếu copyItem bị giới hạn sandbox
                        if let d = try? Data(contentsOf: src), (try? d.write(to: dest)) != nil {
                            DispatchQueue.main.async {
                                self.parent.onPickMediaURL(dest, false)
                            }
                        }
                    }
                }
                return
            }

            // 2. Xử lý Ảnh tĩnh (HEIC / PNG / JPG / Live Photo frame) -> chuẩn hóa chiều đứng EXIF
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    guard let img = obj as? UIImage else { return }
                    let maxDim: CGFloat = 1920
                    let scale = min(maxDim / max(img.size.width, 1), maxDim / max(img.size.height, 1), 1.0)
                    let targetSize = CGSize(
                        width: max(2, round(img.size.width * scale)),
                        height: max(2, round(img.size.height * scale))
                    )
                    let fmt = UIGraphicsImageRendererFormat()
                    fmt.scale = 1.0
                    let normalized = UIGraphicsImageRenderer(size: targetSize, format: fmt).image { _ in
                        img.draw(in: CGRect(origin: .zero, size: targetSize))
                    }
                    guard let jpg = normalized.jpegData(compressionQuality: 0.88) else { return }
                    let dest = cacheDir.appendingPathComponent("photo_img_\(UUID().uuidString.prefix(8)).jpg")
                    if (try? jpg.write(to: dest, options: .atomic)) != nil {
                        DispatchQueue.main.async {
                            self.parent.onPickMediaURL(dest, true)
                        }
                    }
                }
            }
        }
    }
}

// ==============================================================================
// MARK: - FAKE GAME MODELS & PRESETS (CÓ SẴN ID CHUẨN DISCORD + ẢNH GỐC CHÍNH CHỦ)
// ==============================================================================

struct FakeGamePreset: Identifiable, Equatable {
    let id: String
    let name: String
    let discordAppId: String      // ID chuẩn trong kho Detectable Games của Discord ("" = Custom RPC trung lập, không mở nhầm Roblox)
    let discordIconHash: String   // Mã icon gốc trên CDN Discord (mp:app-icons/{id}/{hash}.png)
    let externalIconURL: String   // Ảnh gốc 512x512 HD cho các tựa game Mobile (Liên Quân, Tốc Chiến, Free Fire...)
    let aliases: [String]
    let details: String
    let state: String
    let symbol: String
    let c1: UIColor
    let c2: UIColor

    /// Đường dẫn tài nguyên nội bộ `mp:app-icons/...` chuẩn của Discord (hiển thị tức thì 0ms, nét căng 512px)
    var nativeDiscordAssetPath: String {
        guard !discordAppId.isEmpty, !discordIconHash.isEmpty else { return "" }
        return "mp:app-icons/\(discordAppId)/\(discordIconHash).png"
    }

    /// URL ảnh đại diện có sẵn để hiển thị trực tiếp ngay trong giao diện App iOS
    var previewArtworkURL: URL? {
        if !discordAppId.isEmpty, !discordIconHash.isEmpty, !AppEndpoints.cdnAppIcons.isEmpty {
            return URL(string: "\(AppEndpoints.cdnAppIcons)/\(discordAppId)/\(discordIconHash).png?size=512")
        }
        if !externalIconURL.isEmpty {
            return URL(string: externalIconURL)
        }
        return nil
    }

    func matchesName(_ raw: String) -> Bool {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return false }
        if name.lowercased() == q { return true }
        return aliases.contains { $0.lowercased() == q }
    }

    static let all: [FakeGamePreset] = [
        FakeGamePreset(
            id: "lqmb",
            name: "Arena of Valor",
            discordAppId: "",
            discordIconHash: "",
            externalIconURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/3f/db/83/3fdb836a-2012-28e5-ef34-45ff04c15708/AppIcon-1x_U007emarketing-0-11-0-85-220-0.png/512x512bb.jpg",
            aliases: ["lien quan", "liên quân", "lien quan mobile", "liên quân mobile", "garena liên quân mobile", "lqmb", "aov"],
            details: "Đấu Xếp Hạng • Chiến Tướng",
            state: "Trong trận (5v5)",
            symbol: "shield.lefthalf.filled",
            c1: UIColor(red: 0.90, green: 0.56, blue: 0.10, alpha: 1),
            c2: UIColor(red: 0.72, green: 0.16, blue: 0.18, alpha: 1)
        ),
        FakeGamePreset(
            id: "lol",
            name: "League of Legends",
            discordAppId: "1402418696126992445",
            discordIconHash: "7c99428541032ac02ec6981d88b78fb7",
            externalIconURL: "",
            aliases: ["lol", "lmht", "lien minh", "liên minh", "liên minh huyền thoại"],
            details: "Summoner's Rift (Ranked)",
            state: "Thách Đấu • 1,250 LP",
            symbol: "crown.fill",
            c1: UIColor(red: 0.08, green: 0.52, blue: 0.78, alpha: 1),
            c2: UIColor(red: 0.76, green: 0.60, blue: 0.20, alpha: 1)
        ),
        FakeGamePreset(
            id: "valorant",
            name: "VALORANT",
            discordAppId: "700136079562375258",
            discordIconHash: "11f81959f4fdd76ca6c39c59eac256c1",
            externalIconURL: "",
            aliases: ["valo"],
            details: "Competitive • Ascent",
            state: "Radiant • 11 - 7",
            symbol: "scope",
            c1: UIColor(red: 0.98, green: 0.24, blue: 0.34, alpha: 1),
            c2: UIColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 1)
        ),
        FakeGamePreset(
            id: "tft",
            name: "Teamfight Tactics",
            discordAppId: "1544195652903247973",
            discordIconHash: "d3565d3ac6d570e99928b1a3f1c02d04",
            externalIconURL: "",
            aliases: ["tft", "dtcl", "đấu trường chân lý", "dau truong chan ly"],
            details: "Xếp Hạng • Thách Đấu",
            state: "Vòng 5-2 • Top 1 (88 HP)",
            symbol: "checkerboard.shield",
            c1: UIColor(red: 0.95, green: 0.65, blue: 0.18, alpha: 1),
            c2: UIColor(red: 0.34, green: 0.22, blue: 0.72, alpha: 1)
        ),
        FakeGamePreset(
            id: "genshin",
            name: "Genshin Impact",
            discordAppId: "762434991303950386",
            discordIconHash: "0a7cc00267310bf4afdd78b175a7aeea",
            externalIconURL: "",
            aliases: ["genshin"],
            details: "Natlan • AR 60",
            state: "La Hoàn Thâm Cảnh Tầng 12",
            symbol: "sparkles",
            c1: UIColor(red: 0.28, green: 0.58, blue: 0.96, alpha: 1),
            c2: UIColor(red: 0.56, green: 0.32, blue: 0.94, alpha: 1)
        ),
        FakeGamePreset(
            id: "wukong",
            name: "Black Myth: Wukong",
            discordAppId: "1272842103910699040",
            discordIconHash: "908f3f31004652e1971c6e8a4b9d7c30",
            externalIconURL: "",
            aliases: ["wukong", "black myth", "ngo khong", "ngộ không"],
            details: "Chapter VI • Mount Huaguo",
            state: "Đang khiêu chiến Boss",
            symbol: "flame.fill",
            c1: UIColor(red: 0.82, green: 0.44, blue: 0.12, alpha: 1),
            c2: UIColor(red: 0.14, green: 0.12, blue: 0.12, alpha: 1)
        ),
        FakeGamePreset(
            id: "cs2",
            name: "Counter-Strike 2",
            discordAppId: "1158877933042143272",
            discordIconHash: "558f5a26ecb3b17c3dea3d15c1df537a",
            externalIconURL: "",
            aliases: ["cs2", "csgo", "counter strike"],
            details: "Premier Competitive • Mirage",
            state: "26,450 CS Rating • 12 - 8",
            symbol: "burst.fill",
            c1: UIColor(red: 0.96, green: 0.62, blue: 0.08, alpha: 1),
            c2: UIColor(red: 0.16, green: 0.22, blue: 0.34, alpha: 1)
        ),
        FakeGamePreset(
            id: "pubg",
            name: "PUBG: BATTLEGROUNDS",
            discordAppId: "1402418717781921935",
            discordIconHash: "9d616d0c960ff87c3bc6beb9475362f5",
            externalIconURL: "",
            aliases: ["pubg"],
            details: "Erangel • Squad FPP",
            state: "Còn lại 8/100",
            symbol: "target",
            c1: UIColor(red: 0.92, green: 0.64, blue: 0.12, alpha: 1),
            c2: UIColor(red: 0.22, green: 0.24, blue: 0.20, alpha: 1)
        ),
        FakeGamePreset(
            id: "gtavi",
            name: "Grand Theft Auto VI",
            discordAppId: "1445160676522856458",
            discordIconHash: "251322eb2a778edc62ecce8d791e3701",
            externalIconURL: "",
            aliases: ["gta 6", "gta vi", "gtavi"],
            details: "Vice City • Leonida",
            state: "Story Mode",
            symbol: "car.fill",
            c1: UIColor(red: 0.96, green: 0.28, blue: 0.66, alpha: 1),
            c2: UIColor(red: 0.98, green: 0.58, blue: 0.18, alpha: 1)
        ),
        FakeGamePreset(
            id: "gtav",
            name: "Grand Theft Auto V Enhanced",
            discordAppId: "1421192030440263791",
            discordIconHash: "419a062fd532ffb5abff6ea227d7c003",
            externalIconURL: "",
            aliases: ["gta 5", "gta v", "gtav", "grand theft auto v"],
            details: "Los Santos • GTA Online",
            state: "Heist Finale",
            symbol: "dollarsign.circle.fill",
            c1: UIColor(red: 0.22, green: 0.72, blue: 0.36, alpha: 1),
            c2: UIColor(red: 0.12, green: 0.18, blue: 0.14, alpha: 1)
        ),
        FakeGamePreset(
            id: "hsr",
            name: "Honkai: Star Rail",
            discordAppId: "1121201675240210523",
            discordIconHash: "444d067889922e42b0af99b13e5d5c72",
            externalIconURL: "",
            aliases: ["hsr", "honkai", "star rail"],
            details: "Amphoreus • Trailblaze Lv.70",
            state: "Hồi Ức Hỗn Độn Tầng 12",
            symbol: "moon.stars.fill",
            c1: UIColor(red: 0.34, green: 0.42, blue: 0.95, alpha: 1),
            c2: UIColor(red: 0.76, green: 0.54, blue: 0.24, alpha: 1)
        ),
        FakeGamePreset(
            id: "wuwa",
            name: "Wuthering Waves",
            discordAppId: "1247227126416146462",
            discordIconHash: "1e7d7e9ca69ea0951467994c581f70f5",
            externalIconURL: "",
            aliases: ["wuwa", "wuthering"],
            details: "Rinascita • UL 80",
            state: "Tower of Adversity",
            symbol: "waveform.path.ecg",
            c1: UIColor(red: 0.14, green: 0.68, blue: 0.76, alpha: 1),
            c2: UIColor(red: 0.10, green: 0.14, blue: 0.22, alpha: 1)
        ),
        FakeGamePreset(
            id: "zzz",
            name: "Zenless Zone Zero",
            discordAppId: "1257819671114289184",
            discordIconHash: "fb528a20677f93d8f365fac88e3f0713",
            externalIconURL: "",
            aliases: ["zzz", "zenless"],
            details: "New Eridu • Inter-Knot Lv.60",
            state: "Hollow Zero",
            symbol: "bolt.circle.fill",
            c1: UIColor(red: 0.96, green: 0.52, blue: 0.12, alpha: 1),
            c2: UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1)
        ),
        FakeGamePreset(
            id: "mc",
            name: "Minecraft",
            discordAppId: "1402418491272986635",
            discordIconHash: "166fbad351ecdd02d11a3b464748f66b",
            externalIconURL: "",
            aliases: ["mc"],
            details: "Hardcore Survival",
            state: "Day 1,000",
            symbol: "cube.fill",
            c1: UIColor(red: 0.18, green: 0.72, blue: 0.34, alpha: 1),
            c2: UIColor(red: 0.36, green: 0.26, blue: 0.16, alpha: 1)
        ),
        FakeGamePreset(
            id: "fc26",
            name: "EA Sports FC 26",
            discordAppId: "1421154726023532544",
            discordIconHash: "e9cd3aff85473f6d4e19ba9bf1b443f7",
            externalIconURL: "",
            aliases: ["fc 26", "fifa", "fc online", "fco"],
            details: "Ultimate Team • Champions",
            state: "Hiệp 2 • 3 - 1",
            symbol: "soccerball",
            c1: UIColor(red: 0.10, green: 0.82, blue: 0.46, alpha: 1),
            c2: UIColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1)
        ),
        FakeGamePreset(
            id: "naraka",
            name: "NARAKA: BLADEPOINT",
            discordAppId: "1126956844993232987",
            discordIconHash: "bbd66a8e473704cbbbab872127f08254",
            externalIconURL: "",
            aliases: ["naraka"],
            details: "The Herald's Trial • Asura",
            state: "Ranked Trios",
            symbol: "wind",
            c1: UIColor(red: 0.86, green: 0.18, blue: 0.24, alpha: 1),
            c2: UIColor(red: 0.16, green: 0.12, blue: 0.14, alpha: 1)
        ),
        FakeGamePreset(
            id: "marvel",
            name: "Marvel Rivals",
            discordAppId: "1314395942253756416",
            discordIconHash: "2dd7882b887306ab5afad03452869ad8",
            externalIconURL: "",
            aliases: ["rivals"],
            details: "Competitive • One Above All",
            state: "Tokyo 2099 • Convoy",
            symbol: "bolt.shield.fill",
            c1: UIColor(red: 0.92, green: 0.20, blue: 0.26, alpha: 1),
            c2: UIColor(red: 0.18, green: 0.28, blue: 0.68, alpha: 1)
        ),
        FakeGamePreset(
            id: "eldenring",
            name: "ELDEN RING",
            discordAppId: "1402418436809953330",
            discordIconHash: "28c674e1de18e7a100a44559d64a55b8",
            externalIconURL: "",
            aliases: ["elden ring"],
            details: "Shadow of the Erdtree",
            state: "Enir-Ilim • NG+7",
            symbol: "sun.max.circle.fill",
            c1: UIColor(red: 0.84, green: 0.68, blue: 0.24, alpha: 1),
            c2: UIColor(red: 0.14, green: 0.16, blue: 0.12, alpha: 1)
        ),
        FakeGamePreset(
            id: "playtogether",
            name: "Play Together",
            discordAppId: "1330084319661920308",
            discordIconHash: "1e6b320419cdfb44fad8c22293afe035",
            externalIconURL: "",
            aliases: ["play together vng"],
            details: "Đảo Kaia • Plaza",
            state: "Đang câu cá hiếm",
            symbol: "figure.socialdance",
            c1: UIColor(red: 0.24, green: 0.74, blue: 0.98, alpha: 1),
            c2: UIColor(red: 0.98, green: 0.52, blue: 0.72, alpha: 1)
        ),
        FakeGamePreset(
            id: "freefire",
            name: "Free Fire",
            discordAppId: "1441993244895477830",
            discordIconHash: "",
            externalIconURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/ef/16/6b/ef166bba-1d69-85f5-ed84-6b7c6e73b55c/AppIcon-1788350393-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.jpg",
            aliases: ["ff", "garena free fire"],
            details: "Tử Chiến Xếp Hạng • Đại Kiện Tướng",
            state: "Đảo Quân Sự • Booyah!",
            symbol: "flame.circle.fill",
            c1: UIColor(red: 0.98, green: 0.46, blue: 0.08, alpha: 1),
            c2: UIColor(red: 0.78, green: 0.12, blue: 0.14, alpha: 1)
        ),
        FakeGamePreset(
            id: "mlbb",
            name: "Mobile Legends: Bang Bang",
            discordAppId: "1441992389232165056",
            discordIconHash: "",
            externalIconURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/4a/38/b0/4a38b030-ac2f-170e-73fa-60a5232b9c1a/AppIcon-0-0-1x_U007emarketing-0-7-0-85-220.png/512x512bb.jpg",
            aliases: ["mlbb", "mobile legends"],
            details: "Mythical Immortal • Ranked",
            state: "Land of Dawn (5v5)",
            symbol: "sparkles.rectangle.stack.fill",
            c1: UIColor(red: 0.22, green: 0.48, blue: 0.94, alpha: 1),
            c2: UIColor(red: 0.86, green: 0.66, blue: 0.18, alpha: 1)
        ),
        FakeGamePreset(
            id: "wildrift",
            name: "LMHT: Tốc Chiến",
            discordAppId: "",
            discordIconHash: "",
            externalIconURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/2d/ae/a3/2daea374-791c-2d94-8662-33b0aaf2a944/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.jpg",
            aliases: ["toc chien", "tốc chiến", "wild rift", "league of legends: wild rift"],
            details: "Xếp Hạng Huyền Thoại • Thách Đấu",
            state: "Trong trận (5v5)",
            symbol: "bolt.horizontal.circle.fill",
            c1: UIColor(red: 0.12, green: 0.66, blue: 0.98, alpha: 1),
            c2: UIColor(red: 0.14, green: 0.24, blue: 0.64, alpha: 1)
        ),
        FakeGamePreset(
            id: "audition",
            name: "Audition Online",
            discordAppId: "1441994911107907585",
            discordIconHash: "60e9ce4d9f59659f11899af5760fc98a",
            externalIconURL: "",
            aliases: ["au", "audition"],
            details: "Choreography 4K • 188 BPM",
            state: "Perfect x24",
            symbol: "music.quarternote.3",
            c1: UIColor(red: 0.96, green: 0.30, blue: 0.68, alpha: 1),
            c2: UIColor(red: 0.56, green: 0.22, blue: 0.88, alpha: 1)
        ),
        FakeGamePreset(
            id: "cf",
            name: "Crossfire",
            discordAppId: "1402416706776989886",
            discordIconHash: "89bc82482d4f321ab8fae27247d54949",
            externalIconURL: "",
            aliases: ["dot kich", "đột kích", "cf"],
            details: "Đặt Bom C4 • Trạm Phát Sóng",
            state: "Xếp Hạng • Tổng Tư Lệnh",
            symbol: "scope",
            c1: UIColor(red: 0.88, green: 0.36, blue: 0.10, alpha: 1),
            c2: UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
        ),
        FakeGamePreset(
            id: "dota2",
            name: "Dota 2",
            discordAppId: "356875988589740042",
            discordIconHash: "6b4b3fa4c83555d3008de69d33a60588",
            externalIconURL: "",
            aliases: ["dota"],
            details: "Ranked All Pick • Immortal",
            state: "Phút 38:20",
            symbol: "flame.fill",
            c1: UIColor(red: 0.86, green: 0.18, blue: 0.14, alpha: 1),
            c2: UIColor(red: 0.14, green: 0.12, blue: 0.12, alpha: 1)
        ),
        FakeGamePreset(
            id: "roblox",
            name: "ROBLOX",
            discordAppId: "363445589247131668",
            discordIconHash: "f2b60e350a2097289b3b0b877495e55f",
            externalIconURL: "",
            aliases: ["roblox", "blox fruits"],
            details: "Blox Fruits • Third Sea",
            state: "Bounty 30,000,000",
            symbol: "square.grid.2x2.fill",
            c1: UIColor(red: 0.22, green: 0.24, blue: 0.30, alpha: 1),
            c2: UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        )
    ]

    func renderCoverJPEG() -> (UIImage, Data)? {
        let size = CGSize(width: 512, height: 512)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [c1.cgColor, c2.cgColor, UIColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 1).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0.0, 0.65, 1.0]) {
                cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 512, y: 512), options: [])
            }
            UIColor.white.withAlphaComponent(0.14).setFill()
            UIBezierPath(roundedRect: CGRect(x: 76, y: 76, width: 360, height: 360), cornerRadius: 84).fill()

            let symCfg = UIImage.SymbolConfiguration(pointSize: 168, weight: .bold)
            if let s = UIImage(systemName: symbol, withConfiguration: symCfg)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                s.draw(at: CGPoint(x: (512 - s.size.width) / 2, y: (512 - s.size.height) / 2 - 18))
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let titleRect = CGRect(x: 36, y: 372, width: 440, height: 44)
            (name.uppercased() as NSString).draw(in: titleRect, withAttributes: attrs)
        }
        guard let jpg = img.jpegData(compressionQuality: 0.85) else { return nil }
        return (img, jpg)
    }
}

/// Hiển thị ảnh gốc chính chủ của Game có sẵn (kèm nền gradient dự phòng mượt mà khi đang tải)
struct PresetArtworkView: View {
    let preset: FakeGamePreset
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color(preset.c1), Color(preset.c2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)

            Image(systemName: preset.symbol)
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundColor(.white.opacity(0.92))

            if let url = preset.previewArtworkURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// ==============================================================================
// MARK: - LIGHTWEIGHT GATEWAY SESSION FOR STANDALONE FAKE GAME 24/7
// ==============================================================================

final class FakeGameGatewaySession: NSObject, Identifiable, ObservableObject, URLSessionWebSocketDelegate {
    let id: UUID
    let token: String
    let username: String
    let avatarURL: URL?

    @Published var isConnected = false
    @Published var lastStatus = "Đang kết nối..."

    private var urlSession: URLSession?
    private var wsTask: URLSessionWebSocketTask?
    private var listenTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var gatewaySeq: Int?
    private var currentActivity: [String: Any]?
    private var isStopped = false
    var onLog: ((String) -> Void)?

    init(tokenInfo: TokenInfo) {
        self.id = tokenInfo.id
        self.token = tokenInfo.token
        self.username = tokenInfo.username
        self.avatarURL = tokenInfo.avatarURL
        super.init()
    }

    private func log(_ msg: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastStatus = msg
            self.onLog?("[\(self.username)] \(msg)")
        }
    }

    func start(activity: [String: Any]) {
        self.currentActivity = activity
        self.isStopped = false
        connect()
    }

    func updateActivity(_ activity: [String: Any]?) {
        self.currentActivity = activity
        sendPresenceUpdate()
    }

    func stop() {
        isStopped = true
        if let ws = wsTask {
            let clearPayload: [String: Any] = [
                "op": 3,
                "d": ["since": 0, "activities": [], "status": "online", "afk": false]
            ]
            if let d = try? JSONSerialization.data(withJSONObject: clearPayload),
               let s = String(data: d, encoding: .utf8) {
                ws.send(.string(s)) { _ in }
            }
        }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        listenTask?.cancel()
        listenTask = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.lastStatus = "Đã dừng"
        }
    }

    private func connect() {
        guard !isStopped,
              SecurityGuard.shared.verifyExecutionPermit(),
              let url = RemoteFeatureVault.shared.gatewayURL(scope: .fakeGame) else {
            log("Chưa xác thực Gateway cho Fake Game")
            return
        }

        heartbeatTask?.cancel()
        listenTask?.cancel()
        wsTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 604800
        let sess = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        self.urlSession = sess

        let ws = sess.webSocketTask(with: url)
        ws.maximumMessageSize = 64 * 1024 * 1024
        self.wsTask = ws
        ws.resume()

        listenTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                while !Task.isCancelled && !self.isStopped {
                    let msg = try await ws.receive()
                    switch msg {
                    case .string(let s):
                        await self.handleMessage(s)
                    case .data(let d):
                        if let s = String(data: d, encoding: .utf8) {
                            await self.handleMessage(s)
                        }
                    @unknown default:
                        break
                    }
                }
            } catch {
                if !Task.isCancelled && !self.isStopped && self.wsTask === ws {
                    DispatchQueue.main.async { self.isConnected = false }
                    self.log("Mất kết nối — tự nối lại sau 3s...")
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if !self.isStopped { self.connect() }
                }
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let d = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let op = json["op"] as? Int else { return }

        if let s = json["s"] as? Int { gatewaySeq = s }

        switch op {
        case 10:
            if let dd = json["d"] as? [String: Any],
               let hb = (dd["heartbeat_interval"] as? Int) ?? (dd["heartbeat_interval"] as? NSNumber)?.intValue {
                startHeartbeat(ms: hb)
                sendIdentify()
            }
        case 0:
            if (json["t"] as? String) == "READY" {
                DispatchQueue.main.async { self.isConnected = true }
                sendPresenceUpdate()
                let gName = (currentActivity?["name"] as? String) ?? "Game"
                log("🎮 Đang hiển thị chơi: \(gName)")
            }
        case 7, 9:
            if !isStopped {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                connect()
            }
        default:
            break
        }
    }

    private func startHeartbeat(ms: Int) {
        heartbeatTask?.cancel()
        let sec = max(5.0, Double(ms) / 1000.0)
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(sec * 1_000_000_000))
                guard let self = self, !self.isStopped, let ws = self.wsTask else { break }
                let seqStr = self.gatewaySeq.map { String($0) } ?? "null"
                try? await ws.send(.string("{\"op\":1,\"d\":\(seqStr)}"))
            }
        }
    }

    private func sendIdentify() {
        guard let ws = wsTask else { return }
        let props = RemoteFeatureVault.shared.gatewayIdentifyProperties(scope: .fakeGame)
        guard !props.isEmpty else { return }
        let acts: [[String: Any]] = currentActivity.map { [$0] } ?? []
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
                    "activities": acts,
                    "afk": false
                ]
            ]
        ]
        if let d = try? JSONSerialization.data(withJSONObject: payload),
           let s = String(data: d, encoding: .utf8) {
            Task { try? await ws.send(.string(s)) }
        }
    }

    private func sendPresenceUpdate() {
        guard let ws = wsTask else { return }
        let acts: [[String: Any]] = currentActivity.map { [$0] } ?? []
        let payload: [String: Any] = [
            "op": 3,
            "d": [
                "since": 0,
                "activities": acts,
                "status": "online",
                "afk": false
            ]
        ]
        if let d = try? JSONSerialization.data(withJSONObject: payload),
           let s = String(data: d, encoding: .utf8) {
            Task { try? await ws.send(.string(s)) }
        }
    }
}

// ==============================================================================
// MARK: - FAKE GAME MANAGER (CHẠY ĐỘC LẬP 24/7 + ĐỒNG BỘ SONG SONG VỚI VOICE & NHẠC)
// ==============================================================================

@MainActor
final class FakeGameManager: ObservableObject {
    static let shared = FakeGameManager()

    enum ImageMode: String, CaseIterable, Identifiable {
        case photoApp = "Từ App Ảnh"
        case preset = "Kho Game"
        case customURL = "Dán Link"
        var id: String { rawValue }
    }

    @Published var gameName: String = "Arena of Valor" { didSet { saveSettings() } }
    @Published var detailsText: String = "Đấu Xếp Hạng • Chiến Tướng" { didSet { saveSettings() } }
    @Published var stateText: String = "Trong trận (5v5)" { didSet { saveSettings() } }
    @Published var imageMode: ImageMode = .preset { didSet { saveSettings() } }
    @Published var selectedPreset: FakeGamePreset = FakeGamePreset.all[0] { didSet { saveSettings() } }
    @Published var customImageURL: String = "" { didSet { saveSettings() } }
    @Published var customAppId: String = "" { didSet { saveSettings() } }
    @Published var prePlayedMinutes: Int = 0 { didSet { saveSettings() } }
    @Published var onlineStatus: String = "online" // online, idle, dnd

    @Published var pickedImagePreview: UIImage? = nil
    @Published var uploadedPhotoWorkerURL: String? = nil
    @Published var isUploadingImage: Bool = false
    @Published var uploadError: String? = nil

    // Chế độ chạy độc lập ở tab Fake Game riêng
    @Published var multiTokenMode: Bool = true
    @Published var selectedToken: TokenInfo? = nil
    @Published var isRunningStandalone: Bool = false
    @Published var isPausedStandalone: Bool = false
    @Published var standaloneSessions: [FakeGameGatewaySession] = []
    @Published var elapsedSeconds: Int = 0
    @Published var logs: [VoiceLogEntry] = []

    // Công tắc chạy SONG SONG trực tiếp bên trong Treo Room & Xả Nhạc
    @Published var enabledInTreoRoom: Bool = false
    @Published var enabledInMusicStream: Bool = false

    private var timer: Timer?
    private var startEpochMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    private var isRestoringSettings = false
    private let storePrefix = "QT_FakeGame_"

    private init() {
        loadSettings()
    }

    /// Tự động nhận diện tựa game chính thức khớp với tên game hiện tại (kể cả khi khách gõ tay hoặc đang chọn Preset)
    var matchedPresetForCurrentName: FakeGamePreset? {
        if selectedPreset.matchesName(gameName) {
            return selectedPreset
        }
        return FakeGamePreset.all.first { $0.matchesName(gameName) }
    }

    /// Preset dùng để lấy ảnh gốc mặc định trên giao diện khi đang ở chế độ `.preset`
    var activeArtworkPreset: FakeGamePreset {
        return matchedPresetForCurrentName ?? selectedPreset
    }

    /// Xác định `application_id` chuẩn cho Discord (Game nào ra đúng trang Tổng quan Game đó — TUYỆT ĐỐI không dính Roblox!)
    var resolvedOfficialAppId: String {
        let manual = customAppId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty { return manual }
        if let matched = matchedPresetForCurrentName, !matched.discordAppId.isEmpty {
            return matched.discordAppId
        }
        return ""
    }

    private func saveSettings() {
        guard !isRestoringSettings else { return }
        let ud = UserDefaults.standard
        ud.set(gameName, forKey: storePrefix + "name")
        ud.set(detailsText, forKey: storePrefix + "details")
        ud.set(stateText, forKey: storePrefix + "state")
        ud.set(customImageURL, forKey: storePrefix + "url")
        ud.set(customAppId, forKey: storePrefix + "appid")
        ud.set(prePlayedMinutes, forKey: storePrefix + "mins")
        ud.set(selectedPreset.id, forKey: storePrefix + "preset_id")
        ud.set(imageMode.rawValue, forKey: storePrefix + "img_mode")
        if let up = uploadedPhotoWorkerURL {
            ud.set(up, forKey: storePrefix + "worker_img")
        }
    }

    private func loadSettings() {
        isRestoringSettings = true
        defer { isRestoringSettings = false }
        let ud = UserDefaults.standard
        if let pid = ud.string(forKey: storePrefix + "preset_id"),
           let found = FakeGamePreset.all.first(where: { $0.id == pid }) {
            selectedPreset = found
        }
        if let n = ud.string(forKey: storePrefix + "name"), !n.isEmpty { gameName = n }
        if let d = ud.string(forKey: storePrefix + "details") { detailsText = d }
        if let s = ud.string(forKey: storePrefix + "state") { stateText = s }
        if let u = ud.string(forKey: storePrefix + "url") { customImageURL = u }
        if let a = ud.string(forKey: storePrefix + "appid") { customAppId = a }
        prePlayedMinutes = ud.integer(forKey: storePrefix + "mins")
        if let up = ud.string(forKey: storePrefix + "worker_img"), !up.isEmpty {
            uploadedPhotoWorkerURL = up
        }
        let savedPath = localAvatarCacheURL()
        if let data = try? Data(contentsOf: savedPath), let ui = UIImage(data: data) {
            pickedImagePreview = ui
        }
        if let rawMode = ud.string(forKey: storePrefix + "img_mode"),
           let mode = ImageMode(rawValue: rawMode) {
            if mode == .photoApp && pickedImagePreview == nil {
                imageMode = .preset
            } else if mode == .customURL && customImageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                imageMode = .preset
            } else {
                imageMode = mode
            }
        }
    }

    private func localAvatarCacheURL() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("fake_game_picked_icon.jpg")
    }

    func addLog(_ message: String) {
        logs.append(VoiceLogEntry(timestamp: Date(), message: message))
        if logs.count > 120 {
            logs.removeFirst(logs.count - 120)
        }
    }

    func applyPreset(_ preset: FakeGamePreset) {
        selectedPreset = preset
        imageMode = .preset
        gameName = preset.name
        detailsText = preset.details
        stateText = preset.state
        uploadError = nil
        Task { await refreshAllActivePresences() }
    }

    /// Khôi phục lại ảnh gốc có sẵn của tựa game đang chọn (sau khi người dùng đã thử thay ảnh riêng)
    func restoreBuiltInPresetArtwork() {
        imageMode = .preset
        uploadError = nil
        Task { await refreshAllActivePresences() }
    }

    /// Xử lý ảnh người dùng chọn từ App Ảnh -> cắt vuông 512x512 sắc nét & tải lên CDN Cloudflare Worker
    func handlePickedPhoto(from url: URL) {
        guard let rawImg = UIImage(contentsOfFile: url.path) else {
            uploadError = "Không đọc được ảnh đã chọn."
            return
        }

        let side: CGFloat = 512
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = true
        let squareImg = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in
            let iw = rawImg.size.width
            let ih = rawImg.size.height
            let scale = max(side / max(iw, 1), side / max(ih, 1))
            let dw = iw * scale
            let dh = ih * scale
            rawImg.draw(in: CGRect(x: (side - dw) / 2, y: (side - dh) / 2, width: dw, height: dh))
        }

        guard let jpgData = squareImg.jpegData(compressionQuality: 0.82) else {
            uploadError = "Không thể nén ảnh đại diện game."
            return
        }

        try? jpgData.write(to: localAvatarCacheURL(), options: .atomic)
        pickedImagePreview = squareImg
        imageMode = .photoApp
        uploadError = nil

        Task {
            await uploadImageDataToWorker(jpgData)
            await refreshAllActivePresences()
        }
    }

    private func uploadImageDataToWorker(_ jpgData: Data) async {
        guard let key = LicenseManager.shared.licenseKey, !key.isEmpty else {
            uploadError = "Chưa kích hoạt License Key."
            return
        }
        isUploadingImage = true
        defer { isUploadingImage = false }

        // Đảm bảo đã có khóa phiên Lớp 4 trước khi upload
        if SecurityGuard.shared.currentEphemeralKey == nil {
            await LicenseManager.shared.refreshStatus(force: true)
        }

        do {
            let b64 = jpgData.base64EncodedString()
            var res = try await ConfigAPIClient.shared.uploadGameAsset(key: key, imageBase64: b64)
            if res.sessionExpired == true {
                await LicenseManager.shared.refreshStatus(force: true)
                res = try await ConfigAPIClient.shared.uploadGameAsset(key: key, imageBase64: b64)
            }
            if res.valid == true, let remoteURL = res.imageURL, !remoteURL.isEmpty {
                uploadedPhotoWorkerURL = remoteURL
                saveSettings()
                uploadError = nil
                addLog("✅ Đã tải ảnh Game lên CDN thành công!")
            } else {
                uploadError = res.error ?? "Không tải được ảnh lên máy chủ."
                addLog("⚠️ Lỗi tải ảnh Game: \(uploadError ?? "")")
            }
        } catch {
            uploadError = error.localizedDescription
            addLog("⚠️ Lỗi kết nối tải ảnh Game: \(error.localizedDescription)")
        }
    }

    /// Giải quyết ảnh đại diện Game: ưu tiên ảnh gốc có sẵn chuẩn Discord (`mp:app-icons/...` / HD App Store),
    /// đồng thời cho phép người dùng tự do thay thế bằng Ảnh từ Thư viện iPhone hoặc Link ngoài!
    private func resolveActiveImageURL() async -> String {
        switch imageMode {
        case .customURL:
            return customImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        case .photoApp:
            if let existing = uploadedPhotoWorkerURL, !existing.isEmpty {
                return existing
            }
            if let ui = pickedImagePreview, let jpg = ui.jpegData(compressionQuality: 0.82) {
                await uploadImageDataToWorker(jpg)
                return uploadedPhotoWorkerURL ?? ""
            }
            return ""
        case .preset:
            let preset = activeArtworkPreset
            // 1. Có sẵn icon chính chủ trên kho Discord -> dùng thẳng `mp:app-icons/...` tức thì (0ms, nét căng 512px)
            if !preset.nativeDiscordAssetPath.isEmpty {
                return preset.nativeDiscordAssetPath
            }
            // 2. Có sẵn icon HD chính thức trên App Store (Liên Quân, Tốc Chiến, Free Fire, MLBB...)
            if !preset.externalIconURL.isEmpty {
                return preset.externalIconURL
            }
            // 3. Dự phòng render poster nếu game không có URL ảnh ngoài
            let presetKey = "\(storePrefix)preset_url_\(preset.id)"
            if let cachedURL = UserDefaults.standard.string(forKey: presetKey), !cachedURL.isEmpty {
                return cachedURL
            }
            if let (_, jpg) = preset.renderCoverJPEG(),
               let key = LicenseManager.shared.licenseKey, !key.isEmpty {
                if SecurityGuard.shared.currentEphemeralKey == nil {
                    await LicenseManager.shared.refreshStatus(force: true)
                }
                if let res = try? await ConfigAPIClient.shared.uploadGameAsset(key: key, imageBase64: jpg.base64EncodedString()),
                   res.valid == true, let u = res.imageURL, !u.isEmpty {
                    UserDefaults.standard.set(u, forKey: presetKey)
                    return u
                }
            }
            return ""
        }
    }

    /// Tạo gói dữ liệu Activity Discord chuẩn cho từng Game (đúng `application_id` chính chủ, KHÔNG dính Roblox!)
    func buildActivityPayload(scope: FeatureScope, token: String, resetStartTime: Bool = false) async -> [String: Any] {
        if resetStartTime {
            startEpochMs = Int64((Date().timeIntervalSince1970 - Double(prePlayedMinutes * 60)) * 1000.0)
        }
        // Nếu người dùng tự gõ đúng tên hoặc tên viết tắt (VD: "lol", "valorant", "cs2", "dtcl"), chuẩn hóa về tên chuẩn của Game trên Discord
        let matched = matchedPresetForCurrentName
        let rawInputName = gameName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName: String
        if let m = matched, m.name.lowercased() != rawInputName.lowercased(), m.aliases.contains(where: { $0.lowercased() == rawInputName.lowercased() }) {
            cleanName = m.name
        } else {
            cleanName = rawInputName.isEmpty ? "Playing a Game" : rawInputName
        }

        let targetAppId = resolvedOfficialAppId
        let rawImgURL = await resolveActiveImageURL()
        let resolved = await RemoteFeatureVault.shared.resolveExternalGameImage(
            scope: scope,
            token: token,
            imageURL: rawImgURL,
            customAppId: targetAppId
        )

        var activity: [String: Any] = [
            "name": cleanName,
            "type": 0,
            "timestamps": ["start": startEpochMs]
        ]
        let det = detailsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let st = stateText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !det.isEmpty { activity["details"] = det }
        if !st.isEmpty { activity["state"] = st }

        if let res = resolved {
            if !res.appId.isEmpty {
                activity["application_id"] = res.appId
            }
            if !res.assetPath.isEmpty {
                activity["assets"] = [
                    "large_image": res.assetPath,
                    "large_text": cleanName
                ]
            }
        } else if !targetAppId.isEmpty {
            activity["application_id"] = targetAppId
        }
        return activity
    }

    // MARK: - ĐỒNG BỘ SONG SONG VỚI TREO ROOM & XẢ NHẠC
    func setEnabledInTreoRoom(_ enabled: Bool) {
        enabledInTreoRoom = enabled
        Task {
            await syncWithVoiceRoom(VoiceRoomManager.shared)
        }
    }

    func setEnabledInMusicStream(_ enabled: Bool) {
        enabledInMusicStream = enabled
        Task {
            await syncWithMusicStream(MusicStreamManager.shared)
        }
    }

    func syncWithVoiceRoom(_ voiceRoom: VoiceRoomManager) async {
        guard voiceRoom.isRunning, !voiceRoom.sessions.isEmpty else { return }
        if enabledInTreoRoom {
            guard await LicenseManager.shared.authorizeFeature(.voice) else { return }
            startEpochMs = Int64((Date().timeIntervalSince1970 - Double(prePlayedMinutes * 60)) * 1000.0)
            for s in voiceRoom.sessions {
                let act = await buildActivityPayload(scope: .voice, token: s.token)
                s.setCustomGameActivity(act)
            }
            voiceRoom.addLog("🎮 Đã BẬT Fake Chơi Game song song: \(gameName)")
        } else {
            for s in voiceRoom.sessions {
                s.setCustomGameActivity(nil)
            }
            voiceRoom.addLog("⏹ Đã TẮT Fake Chơi Game trong Treo Room")
        }
    }

    func syncWithMusicStream(_ music: MusicStreamManager) async {
        guard music.isPlaying, !music.activeSessions.isEmpty else { return }
        if enabledInMusicStream {
            guard await LicenseManager.shared.authorizeFeature(.music) else { return }
            startEpochMs = Int64((Date().timeIntervalSince1970 - Double(prePlayedMinutes * 60)) * 1000.0)
            for s in music.activeSessions {
                let act = await buildActivityPayload(scope: .music, token: s.token)
                s.setCustomGameActivity(act)
            }
            music.addLog("🎮 Đã BẬT Fake Chơi Game song song khi Xả Nhạc: \(gameName)")
        } else {
            for s in music.activeSessions {
                s.setCustomGameActivity(nil)
            }
            music.addLog("⏹ Đã TẮT Fake Chơi Game trong Xả Nhạc")
        }
    }

    func refreshAllActivePresences() async {
        if isRunningStandalone && !isPausedStandalone {
            for s in standaloneSessions {
                let act = await buildActivityPayload(scope: .fakeGame, token: s.token)
                s.updateActivity(act)
            }
            syncStandaloneNowPlaying()
        }
        if enabledInTreoRoom && VoiceRoomManager.shared.isRunning {
            await syncWithVoiceRoom(VoiceRoomManager.shared)
        }
        if enabledInMusicStream && MusicStreamManager.shared.isPlaying {
            await syncWithMusicStream(MusicStreamManager.shared)
        }
    }

    // MARK: - CHẠY ĐỘC LẬP 24/7 Ở TAB FAKE GAME RIÊNG
    func startStandalone(app: AppState) {
        let validTokens: [TokenInfo]
        if multiTokenMode {
            let sel = app.tokens.filter { app.selectedTokenIds.contains($0.id) && $0.isValid }
            validTokens = sel.isEmpty ? app.tokens.filter { $0.isValid } : sel
        } else {
            if let st = selectedToken, st.isValid {
                validTokens = [st]
            } else if let at = app.activeToken, at.isValid {
                validTokens = [at]
            } else if let first = app.tokens.first(where: { $0.isValid }) {
                validTokens = [first]
            } else {
                validTokens = []
            }
        }

        guard !validTokens.isEmpty else {
            addLog("❌ Chưa có Token hợp lệ nào để chạy Fake Game!")
            return
        }

        stopStandalone()
        isRunningStandalone = true
        isPausedStandalone = false
        elapsedSeconds = prePlayedMinutes * 60
        startEpochMs = Int64((Date().timeIntervalSince1970 - Double(elapsedSeconds)) * 1000.0)
        logs.removeAll()
        addLog("🚀 Đang xác thực quyền Fake Game trên Cloudflare cho \(validTokens.count) tài khoản...")

        BackgroundManager.shared.start(tag: "fakeGame")
        NowPlayingHelper.shared.registerSession(
            NowPlayingSessionState(
                feature: .fakeGame,
                title: "Đang chơi • \(gameName)",
                detail: "\(validTokens.count) tài khoản • Chạy nền 24/7",
                controlsHint: "⏸ Ẩn/Hiện Game • ◀◀/▶▶ Đổi Game mẫu",
                isPaused: false,
                elapsedTime: Double(elapsedSeconds),
                duration: 0,
                isLiveStream: true,
                onPlay: { [weak self] in self?.resumeStandalone() },
                onPause: { [weak self] in self?.pauseStandalone() },
                onStop: { [weak self] in self?.stopStandalone() },
                onNext: { [weak self] in self?.cyclePreset(step: 1) },
                onPrevious: { [weak self] in self?.cyclePreset(step: -1) }
            ),
            focus: true
        )

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let ok = await LicenseManager.shared.authorizeFeature(.fakeGame)
            guard ok else {
                self.addLog("❌ Server từ chối xác thực chức năng Fake Game!")
                self.stopStandalone()
                return
            }

            var created: [FakeGameGatewaySession] = []
            for tok in validTokens {
                if !self.isRunningStandalone { break }
                let act = await self.buildActivityPayload(scope: .fakeGame, token: tok.token)
                let sess = FakeGameGatewaySession(tokenInfo: tok)
                sess.onLog = { [weak self] m in self?.addLog(m) }
                sess.start(activity: act)
                created.append(sess)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            self.standaloneSessions = created
            self.syncStandaloneNowPlaying()
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunningStandalone else { return }
                if !self.isPausedStandalone {
                    self.elapsedSeconds += 1
                }
                if self.elapsedSeconds % 3 == 0 {
                    self.syncStandaloneNowPlaying()
                }
            }
        }
    }

    func pauseStandalone() {
        guard isRunningStandalone else { return }
        isPausedStandalone = true
        for s in standaloneSessions { s.updateActivity(nil) }
        addLog("⏸ Đã tạm ẩn trạng thái chơi game.")
        syncStandaloneNowPlaying()
    }

    func resumeStandalone() {
        guard isRunningStandalone else { return }
        isPausedStandalone = false
        Task {
            for s in standaloneSessions {
                let act = await buildActivityPayload(scope: .fakeGame, token: s.token)
                s.updateActivity(act)
            }
            addLog("▶️ Tiếp tục hiển thị chơi: \(gameName)")
            syncStandaloneNowPlaying()
        }
    }

    func cyclePreset(step: Int) {
        let all = FakeGamePreset.all
        guard !all.isEmpty else { return }
        let idx = all.firstIndex(of: selectedPreset) ?? 0
        let nextIdx = (idx + step + all.count) % all.count
        applyPreset(all[nextIdx])
    }

    func stopStandalone() {
        isRunningStandalone = false
        isPausedStandalone = false
        timer?.invalidate()
        timer = nil
        for s in standaloneSessions { s.stop() }
        standaloneSessions.removeAll()
        BackgroundManager.shared.stop(tag: "fakeGame")
        NowPlayingHelper.shared.endSession(.fakeGame)
    }

    private func syncStandaloneNowPlaying() {
        guard isRunningStandalone else { return }
        let onlineCount = standaloneSessions.filter { $0.isConnected }.count
        NowPlayingHelper.shared.updateSession(
            .fakeGame,
            title: isPausedStandalone ? "Tạm ẩn • \(gameName)" : "Đang chơi • \(gameName)",
            detail: "\(onlineCount)/\(standaloneSessions.count) token • \(formatElapsed(elapsedSeconds))",
            isPaused: isPausedStandalone,
            elapsedTime: Double(elapsedSeconds),
            isLiveStream: true
        )
    }

    func formatElapsed(_ sec: Int) -> String {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// ==============================================================================
// MARK: - COMPACT PARALLEL FAKE GAME CARD (NHÚNG TRỰC TIẾP VÀO TREO ROOM & XẢ NHẠC)
// ==============================================================================

struct ParallelFakeGameDeckCard: View {
    let isForMusic: Bool
    @ObservedObject var fakeGame = FakeGameManager.shared
    @State private var showPhotoPicker = false
    @State private var showQuickEdit = false

    private var isEnabled: Bool {
        isForMusic ? fakeGame.enabledInMusicStream : fakeGame.enabledInTreoRoom
    }

    private var accent: Color {
        Color(red: 0.08, green: 0.74, blue: 0.54)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(StudioPalette.fakeGameGradient)
                        .frame(width: 38, height: 38)
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Fake Chơi Game")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(isEnabled ? "● SONG SONG" : "SONG SONG")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(isEnabled ? accent : accent.opacity(0.14))
                            .foregroundColor(isEnabled ? .white : accent)
                            .clipShape(Capsule())
                    }
                    Text(isForMusic ? "Hiển thị đang chơi game cùng lúc khi Xả Nhạc" : "Hiển thị đang chơi game cùng lúc với Treo Voice / Stream")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { val in
                        if isForMusic {
                            fakeGame.setEnabledInMusicStream(val)
                        } else {
                            fakeGame.setEnabledInTreoRoom(val)
                        }
                    }
                ))
                .labelsHidden()
                .tint(accent)
            }

            // Preview dòng trạng thái Game hiện tại + Nút đổi nhanh Tên & Ảnh
            HStack(spacing: 10) {
                gameThumbnailView(size: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Playing \(fakeGame.gameName)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(fakeGame.detailsText.isEmpty ? "Chạm Đổi Game để chỉnh tên & ảnh" : fakeGame.detailsText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    showPhotoPicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(accent)
                        .frame(width: 32, height: 32)
                        .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showQuickEdit.toggle() }
                } label: {
                    Text(showQuickEdit ? "Thu gọn" : "Đổi Game")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(StudioPalette.fakeGameGradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if showQuickEdit {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(FakeGamePreset.all) { p in
                                let sel = (fakeGame.selectedPreset.id == p.id && p.matchesName(fakeGame.gameName))
                                Button {
                                    fakeGame.applyPreset(p)
                                } label: {
                                    HStack(spacing: 5) {
                                        PresetArtworkView(preset: p, size: 18, cornerRadius: 5)
                                        Text(p.name)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                    }
                                    .padding(.leading, 5)
                                    .padding(.trailing, 10)
                                    .padding(.vertical, 5)
                                    .background(sel ? accent : Color(UIColor.tertiarySystemGroupedBackground), in: Capsule())
                                    .foregroundColor(sel ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if fakeGame.imageMode != .preset {
                        Button {
                            fakeGame.restoreBuiltInPresetArtwork()
                        } label: {
                            Label("Dùng lại ảnh gốc có sẵn của \(fakeGame.activeArtworkPreset.name)", systemImage: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(accent)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 8) {
                        TextField("Nhập tên game tùy ý...", text: $fakeGame.gameName)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Button {
                            Task { await fakeGame.refreshAllActivePresences() }
                        } label: {
                            Text("Áp dụng")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isEnabled ? accent.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: isEnabled ? 1.5 : 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
        .sheet(isPresented: $showPhotoPicker) {
            PhotoLibraryPicker(filterMode: .imagesOnly) { url, _ in
                fakeGame.handlePickedPhoto(from: url)
            }
        }
    }

    @ViewBuilder
    private func gameThumbnailView(size: CGFloat) -> some View {
        if fakeGame.imageMode == .photoApp, let ui = fakeGame.pickedImagePreview {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if fakeGame.imageMode == .customURL, let url = URL(string: fakeGame.customImageURL), !fakeGame.customImageURL.isEmpty {
            AsyncImage(url: url) { img in img.resizable().scaledToFill() }
            placeholder: { RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.2)) }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            PresetArtworkView(preset: fakeGame.activeArtworkPreset, size: size, cornerRadius: 10)
        }
    }
}

// ==============================================================================
// MARK: - STANDALONE FAKE GAME STUDIO TAB VIEW (MỤC RIÊNG FAKE GAME 24/7)
// ==============================================================================

struct FakeGameTabView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var fakeGame = FakeGameManager.shared
    @State private var showPhotoPicker = false
    @State private var showImageFilePicker = false
    @State private var copiedLog = false

    private let accent = Color(red: 0.08, green: 0.74, blue: 0.54)

    private var activeTokensCount: Int {
        if !app.selectedTokenIds.isEmpty {
            return app.tokens.filter { app.selectedTokenIds.contains($0.id) && $0.isValid }.count
        }
        return app.tokens.filter { $0.isValid }.count
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                StudioAmbientBackdrop(
                    topColor: Color(red: 0.08, green: 0.74, blue: 0.54),
                    secondColor: Color(red: 0.12, green: 0.62, blue: 0.96)
                )

                VStack(spacing: 0) {
                    StudioTopHeaderBar(
                        icon: "gamecontroller.fill",
                        title: "Fake Game Studio",
                        subtitle: "Tùy chỉnh Tên & Ảnh Game từ App Ảnh • Chạy nền 24/7",
                        isLive: fakeGame.isRunningStandalone,
                        liveText: "ĐANG CHƠI • \(fakeGame.formatElapsed(fakeGame.elapsedSeconds))",
                        colors: [Color(red: 0.08, green: 0.74, blue: 0.54), Color(red: 0.12, green: 0.62, blue: 0.96)]
                    ) {
                        Text("RPC PRO")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(StudioPalette.fakeGameGradient, in: Capsule())
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            discordLivePreviewCard
                            tokenModeCard
                            gameIdentityCard
                            gameImagePickerCard
                            timeSpoofCard
                            actionButtonCard
                            if !fakeGame.standaloneSessions.isEmpty {
                                sessionsListCard
                            }
                            if !fakeGame.logs.isEmpty {
                                logsCard
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 110)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPhotoPicker) {
                PhotoLibraryPicker(filterMode: .imagesOnly) { url, _ in
                    fakeGame.handlePickedPhoto(from: url)
                }
            }
            .sheet(isPresented: $showImageFilePicker) {
                DocumentPicker(contentTypes: [.image], allowsMultipleSelection: false) { url in
                    let got = url.startAccessingSecurityScopedResource()
                    defer { if got { url.stopAccessingSecurityScopedResource() } }
                    let dest = FileManager.default.temporaryDirectory.appendingPathComponent("file_game_\(UUID().uuidString.prefix(6)).jpg")
                    try? FileManager.default.removeItem(at: dest)
                    if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                        fakeGame.handlePickedPhoto(from: dest)
                    }
                }
            }
        }
    }

    // 1. Discord Rich Presence Live Preview Card
    private var discordLivePreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("XEM TRƯỚC HIỂN THỊ TRÊN HỒ SƠ")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(0.6)
                Spacer()
                if fakeGame.isUploadingImage {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.65).tint(.white)
                        Text("Đang đồng bộ ảnh CDN...")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                    }
                } else if !fakeGame.resolvedOfficialAppId.isEmpty {
                    Text("✓ CHUẨN ID GAME DISCORD")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.16), in: Capsule())
                } else {
                    Text("✦ CUSTOM RPC (KHÔNG DÍNH ROBLOX)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.16), in: Capsule())
                }
            }

            HStack(alignment: .top, spacing: 14) {
                largeArtworkPreview

                VStack(alignment: .leading, spacing: 3) {
                    Text(fakeGame.gameName.isEmpty ? "Tên Game" : fakeGame.gameName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if !fakeGame.detailsText.isEmpty {
                        Text(fakeGame.detailsText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.82))
                            .lineLimit(1)
                    }

                    if !fakeGame.stateText.isEmpty {
                        Text(fakeGame.stateText)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.68))
                            .lineLimit(1)
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(fakeGame.isRunningStandalone
                             ? fakeGame.formatElapsed(fakeGame.elapsedSeconds)
                             : fakeGame.formatElapsed(fakeGame.prePlayedMinutes * 60))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(Color(red: 0.25, green: 0.92, blue: 0.62))
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.12, blue: 0.18), Color(red: 0.07, green: 0.08, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.38), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 5)
    }

    @ViewBuilder
    private var largeArtworkPreview: some View {
        if fakeGame.imageMode == .photoApp, let ui = fakeGame.pickedImagePreview {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if fakeGame.imageMode == .customURL, let u = URL(string: fakeGame.customImageURL), !fakeGame.customImageURL.isEmpty {
            AsyncImage(url: u) { img in img.resizable().scaledToFill() }
            placeholder: { RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.25)) }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            PresetArtworkView(preset: fakeGame.activeArtworkPreset, size: 68, cornerRadius: 14)
        }
    }

    // 2. Token Selection Card
    private var tokenModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tài Khoản Chạy Fake Game", systemImage: "person.2.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text("\(activeTokensCount) token sẵn sàng")
                    .font(.caption.bold())
                    .foregroundColor(accent)
            }

            HStack(spacing: 8) {
                Button {
                    fakeGame.multiTokenMode = true
                } label: {
                    Label("Cả Dàn (\(activeTokensCount))", systemImage: "person.3.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(fakeGame.multiTokenMode ? accent.opacity(0.18) : Color(UIColor.tertiarySystemGroupedBackground))
                        .foregroundColor(fakeGame.multiTokenMode ? accent : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    fakeGame.multiTokenMode = false
                } label: {
                    Label("1 Token Lẻ", systemImage: "person.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(!fakeGame.multiTokenMode ? accent.opacity(0.18) : Color(UIColor.tertiarySystemGroupedBackground))
                        .foregroundColor(!fakeGame.multiTokenMode ? accent : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if !fakeGame.multiTokenMode {
                Menu {
                    ForEach(app.tokens.filter { $0.isValid }) { t in
                        Button(t.username) { fakeGame.selectedToken = t }
                    }
                } label: {
                    HStack {
                        Text("Token: \((fakeGame.selectedToken ?? app.activeToken ?? app.tokens.first)?.username ?? "Chưa có")")
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .studioCard()
    }

    // 3. Game Name & Details Card
    private var gameIdentityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tên Game & Trạng Thái Hiển Thị", systemImage: "pencil.and.outline")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                if fakeGame.isRunningStandalone || fakeGame.enabledInTreoRoom || fakeGame.enabledInMusicStream {
                    Button {
                        Task { await fakeGame.refreshAllActivePresences() }
                    } label: {
                        Text("Cập nhật Live")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(accent, in: Capsule())
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FakeGamePreset.all) { preset in
                        let sel = (fakeGame.selectedPreset.id == preset.id && preset.matchesName(fakeGame.gameName))
                        Button {
                            fakeGame.applyPreset(preset)
                        } label: {
                            HStack(spacing: 7) {
                                PresetArtworkView(preset: preset, size: 24, cornerRadius: 6)
                                Text(preset.name).font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .padding(.leading, 6)
                            .padding(.trailing, 12)
                            .padding(.vertical, 6)
                            .background(sel ? AnyShapeStyle(StudioPalette.fakeGameGradient) : AnyShapeStyle(Color(UIColor.tertiarySystemGroupedBackground)), in: Capsule())
                            .foregroundColor(sel ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("TÊN GAME (HIỆN SAU CHỮ PLAYING)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                TextField("VD: Liên Quân Mobile, GTA VI, Học bài...", text: $fakeGame.gameName)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(11)
                    .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("DÒNG MÔ TẢ 1 (DETAILS — TÙY CHỌN)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                TextField("VD: Đấu Xếp Hạng • Thách Đấu", text: $fakeGame.detailsText)
                    .font(.system(size: 13))
                    .padding(11)
                    .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("DÒNG MÔ TẢ 2 (STATE — TÙY CHỌN)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                TextField("VD: Trong trận (5v5)", text: $fakeGame.stateText)
                    .font(.system(size: 13))
                    .padding(11)
                    .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .studioCard()
    }

    // 4. Game Image Picker Card (Có sẵn ảnh gốc theo Game + vẫn cho phép thay ảnh từ App Ảnh / Tệp / Link!)
    private var gameImagePickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ảnh Đại Diện Game", systemImage: "photo.fill.on.rectangle.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                if fakeGame.imageMode != .preset {
                    Button {
                        fakeGame.restoreBuiltInPresetArtwork()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Dùng Ảnh Gốc Game")
                        }
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(accent.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: fakeGame.imageMode == .preset ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accent)
                Text(fakeGame.imageMode == .preset
                     ? "Đang dùng sẵn ảnh gốc chính thức của \(fakeGame.activeArtworkPreset.name). Bạn vẫn có thể chọn ảnh khác bên dưới để thay thế!"
                     : "Đang dùng ảnh riêng của bạn (vẫn giữ chuẩn ID Game \(fakeGame.matchedPresetForCurrentName?.name ?? "Custom")).")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            HStack(spacing: 8) {
                Button {
                    showPhotoPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Chọn Từ App Ảnh")
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(StudioPalette.fakeGameGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    showImageFilePicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.badge.plus")
                        Text("Chọn Tệp")
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("HOẶC DÁN LINK ẢNH / GIF TRỰC TIẾP (HTTPS)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("https://.../icon.png hoặc .gif", text: $fakeGame.customImageURL)
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: fakeGame.customImageURL) { val in
                            if !val.trimmingCharacters(in: .whitespaces).isEmpty {
                                fakeGame.imageMode = .customURL
                            }
                        }
                    if !fakeGame.customImageURL.isEmpty {
                        Button {
                            fakeGame.customImageURL = ""
                            fakeGame.imageMode = .preset
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            if let err = fakeGame.uploadError {
                Text("⚠️ \(err)")
                    .font(.caption2.bold())
                    .foregroundColor(.red)
            }
        }
        .studioCard()
    }

    // 5. Elapsed Time Spoof Card
    private var timeSpoofCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Thời Gian Đã Chơi (Bộ Đếm Giờ)", systemImage: "clock.badge.checkmark.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text(fakeGame.prePlayedMinutes == 0 ? "Đếm từ 00:00" : "+\(fakeGame.prePlayedMinutes / 60)h \(fakeGame.prePlayedMinutes % 60)p")
                    .font(.caption.bold())
                    .foregroundColor(accent)
            }

            HStack(spacing: 6) {
                ForEach([(0, "00:00"), (60, "1 Giờ"), (180, "3 Giờ"), (720, "12 Giờ"), (1440, "24 Giờ")], id: \.0) { mins, label in
                    let sel = (fakeGame.prePlayedMinutes == mins)
                    Button {
                        fakeGame.prePlayedMinutes = mins
                        Task { await fakeGame.refreshAllActivePresences() }
                    } label: {
                        Text(label)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(sel ? accent : Color(UIColor.tertiarySystemGroupedBackground), in: Capsule())
                            .foregroundColor(sel ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .studioCard()
    }

    // 6. Primary Start / Stop CTA
    private var actionButtonCard: some View {
        Group {
            if fakeGame.isRunningStandalone {
                Button {
                    fakeGame.stopStandalone()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "stop.circle.fill").font(.system(size: 20, weight: .bold))
                        Text("DỪNG FAKE GAME 24/7")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.red.opacity(0.35), radius: 10, y: 5)
                }
            } else {
                let canRun = activeTokensCount > 0
                Button {
                    fakeGame.startStandalone(app: app)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "gamecontroller.fill").font(.system(size: 18, weight: .bold))
                        Text("BẮT ĐẦU CHẠY FAKE GAME 24/7")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        canRun ? AnyShapeStyle(StudioPalette.fakeGameGradient) : AnyShapeStyle(Color.gray.opacity(0.5)),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(color: canRun ? accent.opacity(0.38) : .clear, radius: 12, y: 6)
                }
                .disabled(!canRun)
            }
        }
    }

    private var sessionsListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tài Khoản Đang Chạy Game")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text("\(fakeGame.standaloneSessions.filter { $0.isConnected }.count)/\(fakeGame.standaloneSessions.count) ONLINE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.14), in: Capsule())
            }

            ForEach(fakeGame.standaloneSessions) { s in
                HStack(spacing: 10) {
                    Circle()
                        .fill(s.isConnected ? Color.green : Color.orange)
                        .frame(width: 9, height: 9)
                    Text(s.username)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Spacer()
                    Text(s.lastStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .studioCard()
    }

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nhật Ký Fake Game")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    fakeGame.logs.removeAll()
                } label: {
                    Image(systemName: "trash").font(.caption.bold()).foregroundColor(.red)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(fakeGame.logs) { entry in
                        Text(entry.message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.88))
                    }
                }
                .padding(10)
            }
            .frame(height: 110)
            .background(Color(red: 0.08, green: 0.09, blue: 0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .studioCard()
    }
}
