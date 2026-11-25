import Foundation
import AVFoundation
import CoreGraphics
import VideoToolbox
import CoreMedia
import CoreVideo
import CryptoKit
import Darwin

// ==============================================================================
// MARK: - NITRO STREAM PROFILE & MEDIA SOURCE (PORT TỪ room.js)
// ==============================================================================

struct DiscordStreamProfile: Equatable {
    let width: Int
    let height: Int
    let fps: Int
    let bitrateKbps: Int
    let maxBitrateKbps: Int
    let label: String

    /// Tự động chọn cấu hình theo Nitro (y hệt getStreamProfile trong room.js)
    /// premiumType: 0 = None, 1 = Nitro Classic, 2 = Nitro Full, 3 = Nitro Basic
    static func forPremiumType(_ premiumType: Int) -> DiscordStreamProfile {
        let hasBoost = (premiumType == 1 || premiumType == 2)
        if hasBoost {
            return DiscordStreamProfile(
                width: 1920,
                height: 1080,
                fps: 60,
                bitrateKbps: 6000,
                maxBitrateKbps: 8000,
                label: "NITRO 1080p60 • 8Mbps"
            )
        }
        return DiscordStreamProfile(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateKbps: 1500,
            maxBitrateKbps: 2500,
            label: "FREE/BASIC 720p30 • 2.5Mbps"
        )
    }

    static func premiumName(_ premiumType: Int) -> String {
        switch premiumType {
        case 1: return "Nitro Classic"
        case 2: return "Nitro"
        case 3: return "Nitro Basic"
        default: return "None"
        }
    }
}

enum TreoVideoQualityMode: String, CaseIterable, Identifiable {
    case autoNitro = "Tự động (Nitro)"
    case hd720p30 = "720p • 30fps"
    case fhd1080p60 = "1080p • 60fps"

    var id: String { rawValue }

    func resolveProfile(hasNitroAccount: Bool) -> DiscordStreamProfile {
        switch self {
        case .autoNitro:
            return DiscordStreamProfile.forPremiumType(hasNitroAccount ? 2 : 0)
        case .hd720p30:
            return DiscordStreamProfile(
                width: 1280,
                height: 720,
                fps: 30,
                bitrateKbps: 1500,
                maxBitrateKbps: 2500,
                label: "720p30 • 2.5Mbps"
            )
        case .fhd1080p60:
            return DiscordStreamProfile(
                width: 1920,
                height: 1080,
                fps: 60,
                bitrateKbps: 6000,
                maxBitrateKbps: 8000,
                label: "1080p60 • 8Mbps"
            )
        }
    }
}

struct TreoMediaSource: Identifiable, Equatable {
    let id: UUID
    let title: String
    let url: URL?
    let isAudioOnly: Bool
    let isVirtualPattern: Bool

    static let virtualCamPattern = TreoMediaSource(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000C401") ?? UUID(),
        title: "🌈 Video Mẫu Ảo (Loop ∞)",
        url: nil,
        isAudioOnly: false,
        isVirtualPattern: true
    )

    static let virtualBlackScreen = TreoMediaSource(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000B1AC") ?? UUID(),
        title: "⬛ Màn Hình Đen 720p (Loop ∞)",
        url: nil,
        isAudioOnly: true,
        isVirtualPattern: true
    )

    static func == (lhs: TreoMediaSource, rhs: TreoMediaSource) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url && lhs.isVirtualPattern == rhs.isVirtualPattern
    }
}

// ==============================================================================
// MARK: - SHARED TRANSPORT NONCE COUNTER (CHỐNG TRÙNG NONCE AUDIO/VIDEO AEAD)
// ==============================================================================

final class TransportNonceBox {
    private let lock = NSLock()
    private var counter: UInt32 = 0

    func reset() {
        lock.lock()
        counter = 0
        lock.unlock()
    }

    func next() -> UInt32 {
        lock.lock()
        counter = counter &+ 1
        let val = counter
        lock.unlock()
        return val
    }
}

// ==============================================================================
// MARK: - H.264 ANNEX-B SPLITTER & DISCORD UDP RTP VIDEO PACKETIZER (RFC 6184)
// ==============================================================================

enum H264AnnexBHelper {
    /// Tách luồng Annex-B (start code 00 00 01 hoặc 00 00 00 01) thành các NALU riêng lẻ
    static func splitNALUs(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        let count = bytes.count
        guard count >= 4 else { return [] }

        var starts: [(nalStart: Int, scStart: Int)] = []
        var i = 0
        while i + 2 < count {
            if bytes[i] == 0 && bytes[i + 1] == 0 {
                if bytes[i + 2] == 1 {
                    starts.append((i + 3, i))
                    i += 3
                    continue
                } else if i + 3 < count && bytes[i + 2] == 0 && bytes[i + 3] == 1 {
                    starts.append((i + 4, i))
                    i += 4
                    continue
                }
            }
            i += 1
        }

        if starts.isEmpty {
            return [data]
        }

        var nalus: [Data] = []
        nalus.reserveCapacity(starts.count)
        for idx in 0..<starts.count {
            let start = starts[idx].nalStart
            let end = (idx + 1 < starts.count) ? starts[idx + 1].scStart : count
            if end > start {
                nalus.append(Data(bytes[start..<end]))
            }
        }
        return nalus
    }

    /// Viết lại SPS VUI (max_num_reorder_frames = 0, bỏ video_signal_type) để Discord Desktop/Chrome giải mã ngay lập tức
    static func rewriteSPSVUI(_ spsNalu: Data) -> Data {
        guard spsNalu.count >= 4, (spsNalu[spsNalu.startIndex] & 0x1F) == 7 else {
            return spsNalu
        }
        let rewritten: Data? = spsNalu.withUnsafeBytes { raw in
            guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let buf = dave_h264_rewrite_sps_vui(ptr, spsNalu.count)
            defer { dave_buffer_free(buf) }
            guard let outPtr = buf.ptr, buf.len > 0 else { return nil }
            return Data(bytes: outPtr, count: buf.len)
        }
        return rewritten ?? spsNalu
    }
}

/// Đóng gói khung H.264 Annex-B thành các gói RTP chuẩn RFC 6184:
/// - STAP-A (Type 24) gộp SPS + PPS (và các NALU nhỏ) để SFU & Chrome nhận diện Keyframe tức thì
/// - Single NALU (<= 1200B) và FU-A (Type 28, > 1200B)
/// - One-Byte Extension Header 0xBE 0xDE + Playout Delay chuẩn 3 byte (0x52 00 00 0A)
/// - Dùng chung bộ đếm nonce AEAD với Audio để không bị anti-replay SFU loại bỏ
final class DiscordRtpVideoPacketizer {
    private let lock = NSLock()
    private let payloadType: UInt8 = 101 // H264 payload type chuẩn Discord
    private let mtu: Int = 1150

    private var ssrc: UInt32 = 0
    private var sequence: UInt16 = UInt16.random(in: 0...65535)
    private var timestamp: UInt32 = UInt32.random(in: 0...4_000_000)
    private var totalPackets: UInt32 = 0
    private var totalBytes: UInt32 = 0
    private var prevSrPackets: UInt32 = 0
    private let srInterval: UInt32 = 150

    // One-byte RTP header extension: playout-delay (id=5, len=3 -> 0x52, min=0, max=10)
    private let extHeader: [UInt8] = [0xBE, 0xDE, 0x00, 0x01]
    private let extPayload: [UInt8] = [0x52, 0x00, 0x00, 0x0A]

    func configure(ssrc: UInt32) {
        lock.lock()
        self.ssrc = ssrc
        self.totalPackets = 0
        self.totalBytes = 0
        self.prevSrPackets = 0
        lock.unlock()
    }

    /// Đóng gói & gửi khung H.264 Annex-B (đã qua DAVE E2EE nếu có) ra UDP socket
    @discardableResult
    func sendFrame(
        annexBFrame: Data,
        frametimeMs: Double,
        secretKey: Data,
        encryptionMode: String,
        nonceBox: TransportNonceBox,
        udpClient: DiscordVoiceUDPClient
    ) -> Int {
        guard secretKey.count == 32, !annexBFrame.isEmpty else { return 0 }
        let nalus = H264AnnexBHelper.splitNALUs(annexBFrame)
        guard !nalus.isEmpty else { return 0 }

        // Bước 1: Tạo danh sách RTP payloads (STAP-A cho cụm NALU nhỏ như SPS+PPS, Single NALU, hoặc FU-A)
        var rtpPayloads: [Data] = []
        rtpPayloads.reserveCapacity(max(nalus.count, annexBFrame.count / mtu + 2))

        var idx = 0
        while idx < nalus.count {
            let nalu = nalus[idx]
            if nalu.isEmpty {
                idx += 1
                continue
            }

            if nalu.count > mtu {
                // Fragmentation Unit A (FU-A, RFC 6184)
                let nal0 = nalu[nalu.startIndex]
                let nalType = nal0 & 0x1F
                let fnri = nal0 & 0xE0
                let fuIndicator: UInt8 = 0x1C | fnri

                let payloadData = Data(nalu.dropFirst(1))
                let totalLen = payloadData.count
                var offset = 0
                while offset < totalLen {
                    let chunkLen = min(mtu, totalLen - offset)
                    let isFirst = (offset == 0)
                    let isFinal = (offset + chunkLen >= totalLen)

                    var fuHeader: UInt8 = nalType
                    if isFirst { fuHeader |= 0x80 }
                    else if isFinal { fuHeader |= 0x40 }

                    var fuPacket = Data(capacity: 2 + chunkLen)
                    fuPacket.append(fuIndicator)
                    fuPacket.append(fuHeader)
                    let chunkStart = payloadData.startIndex + offset
                    fuPacket.append(payloadData[chunkStart..<(chunkStart + chunkLen)])
                    rtpPayloads.append(fuPacket)
                    offset += chunkLen
                }
                idx += 1
            } else {
                // Kiểm tra gộp STAP-A (Type 24) nếu có >= 2 NALU nhỏ liên tiếp (đặc biệt SPS + PPS) vừa trong MTU
                var group: [Data] = [nalu]
                var stapSize = 1 + 2 + nalu.count
                var nextIdx = idx + 1
                while nextIdx < nalus.count {
                    let candidate = nalus[nextIdx]
                    if candidate.isEmpty {
                        nextIdx += 1
                        continue
                    }
                    let added = 2 + candidate.count
                    if stapSize + added <= mtu {
                        group.append(candidate)
                        stapSize += added
                        nextIdx += 1
                    } else {
                        break
                    }
                }

                if group.count > 1 {
                    var maxNri: UInt8 = 0
                    for g in group {
                        let nri = g[g.startIndex] & 0x60
                        if nri > maxNri { maxNri = nri }
                    }
                    var stap = Data(capacity: stapSize)
                    stap.append(maxNri | 24) // STAP-A header (Type 24)
                    for g in group {
                        let len = UInt16(g.count)
                        stap.append(UInt8((len >> 8) & 0xFF))
                        stap.append(UInt8(len & 0xFF))
                        stap.append(g)
                    }
                    rtpPayloads.append(stap)
                } else {
                    rtpPayloads.append(nalu)
                }
                idx = nextIdx
            }
        }

        guard !rtpPayloads.isEmpty else { return 0 }

        // Bước 2: Mã hóa AEAD từng gói RTP với chung TransportNonceBox & marker M=1 trên gói cuối
        lock.lock()
        let curSsrc = self.ssrc
        guard curSsrc != 0 else {
            lock.unlock()
            return 0
        }
        let curTs = self.timestamp
        var packetsOut: [Data] = []
        packetsOut.reserveCapacity(rtpPayloads.count)

        for (pIdx, rtpBody) in rtpPayloads.enumerated() {
            let isLastPacket = (pIdx == rtpPayloads.count - 1)
            let seq = nextSeqLocked()
            let nonceVal = nonceBox.next()
            let aad = makeRtpHeaderWithExt(seq: seq, ts: curTs, ssrc: curSsrc, marker: isLastPacket)

            var plaintext = Data(capacity: 4 + rtpBody.count)
            plaintext.append(contentsOf: extPayload)
            plaintext.append(rtpBody)

            if let pkt = encryptTransport(aad: aad, plaintext: plaintext, nonceVal: nonceVal, key: secretKey, mode: encryptionMode) {
                packetsOut.append(pkt)
            }
        }

        // Thống kê & RTCP Sender Report mỗi ~150 gói
        let sentCount = UInt32(packetsOut.count)
        let sentBytes = packetsOut.reduce(UInt32(0)) { $0 &+ UInt32($1.count) }
        self.totalPackets = self.totalPackets &+ sentCount
        self.totalBytes = self.totalBytes &+ sentBytes

        var srPacket: Data? = nil
        if (self.totalPackets / srInterval) > (self.prevSrPackets / srInterval) {
            self.prevSrPackets = self.totalPackets
            let srNonce = nonceBox.next()
            srPacket = makeRtcpSenderReport(
                ssrc: curSsrc,
                rtpTs: curTs,
                packetCount: self.totalPackets,
                octetCount: self.totalBytes,
                nonceVal: srNonce,
                key: secretKey,
                mode: encryptionMode
            )
        }

        // Video RTP clock = 90,000 Hz
        let tsInc = UInt32(max(1, Int((90_000.0 * frametimeMs) / 1000.0)))
        self.timestamp = self.timestamp &+ tsInc
        lock.unlock()

        for pkt in packetsOut {
            udpClient.sendPacket(pkt)
        }
        if let sr = srPacket {
            udpClient.sendPacket(sr)
        }
        return packetsOut.count
    }

    private func nextSeqLocked() -> UInt16 {
        let s = self.sequence
        self.sequence = self.sequence &+ 1
        return s
    }

    private func makeRtpHeaderWithExt(seq: UInt16, ts: UInt32, ssrc: UInt32, marker: Bool) -> [UInt8] {
        var hdr = [UInt8](repeating: 0, count: 16)
        hdr[0] = 0x90 // V=2, P=0, X=1, CC=0
        hdr[1] = payloadType | (marker ? 0x80 : 0x00)
        hdr[2] = UInt8((seq >> 8) & 0xFF)
        hdr[3] = UInt8(seq & 0xFF)
        hdr[4] = UInt8((ts >> 24) & 0xFF)
        hdr[5] = UInt8((ts >> 16) & 0xFF)
        hdr[6] = UInt8((ts >> 8) & 0xFF)
        hdr[7] = UInt8(ts & 0xFF)
        hdr[8] = UInt8((ssrc >> 24) & 0xFF)
        hdr[9] = UInt8((ssrc >> 16) & 0xFF)
        hdr[10] = UInt8((ssrc >> 8) & 0xFF)
        hdr[11] = UInt8(ssrc & 0xFF)
        hdr[12] = extHeader[0]
        hdr[13] = extHeader[1]
        hdr[14] = extHeader[2]
        hdr[15] = extHeader[3]
        return hdr
    }

    private func makeRtcpSenderReport(
        ssrc: UInt32,
        rtpTs: UInt32,
        packetCount: UInt32,
        octetCount: UInt32,
        nonceVal: UInt32,
        key: Data,
        mode: String
    ) -> Data? {
        var header = [UInt8](repeating: 0, count: 8)
        header[0] = 0x80
        header[1] = 0xC8 // RTCP SR (200)
        header[2] = 0x00
        header[3] = 0x06
        header[4] = UInt8((ssrc >> 24) & 0xFF)
        header[5] = UInt8((ssrc >> 16) & 0xFF)
        header[6] = UInt8((ssrc >> 8) & 0xFF)
        header[7] = UInt8(ssrc & 0xFF)

        let ntpSec = Date().timeIntervalSince1970 + 2_208_988_800.0
        let ntpMsw = UInt32(truncatingIfNeeded: UInt64(max(0, floor(ntpSec))))
        let ntpLsw = UInt32(truncatingIfNeeded: UInt64(max(0, (ntpSec - floor(ntpSec)) * 4_294_967_296.0)))

        var body = [UInt8](repeating: 0, count: 20)
        func writeBE32(_ val: UInt32, at offset: Int) {
            body[offset] = UInt8((val >> 24) & 0xFF)
            body[offset + 1] = UInt8((val >> 16) & 0xFF)
            body[offset + 2] = UInt8((val >> 8) & 0xFF)
            body[offset + 3] = UInt8(val & 0xFF)
        }
        writeBE32(ntpMsw, at: 0)
        writeBE32(ntpLsw, at: 4)
        writeBE32(rtpTs, at: 8)
        writeBE32(packetCount, at: 12)
        writeBE32(octetCount, at: 16)

        return encryptTransport(aad: header, plaintext: Data(body), nonceVal: nonceVal, key: key, mode: mode)
    }

    private func encryptTransport(
        aad: [UInt8],
        plaintext: Data,
        nonceVal: UInt32,
        key: Data,
        mode: String
    ) -> Data? {
        let noncePrefix: [UInt8] = [
            UInt8((nonceVal >> 24) & 0xFF),
            UInt8((nonceVal >> 16) & 0xFF),
            UInt8((nonceVal >> 8) & 0xFF),
            UInt8(nonceVal & 0xFF)
        ]

        if mode == "aead_xchacha20_poly1305_rtpsize" {
            var nonce24 = [UInt8](repeating: 0, count: 24)
            nonce24[0] = noncePrefix[0]
            nonce24[1] = noncePrefix[1]
            nonce24[2] = noncePrefix[2]
            nonce24[3] = noncePrefix[3]

            let ct: Data? = key.withUnsafeBytes { keyRaw in
                aad.withUnsafeBufferPointer { aadBuf in
                    plaintext.withUnsafeBytes { ptRaw in
                        guard let kPtr = keyRaw.bindMemory(to: UInt8.self).baseAddress,
                              let pPtr = ptRaw.bindMemory(to: UInt8.self).baseAddress else { return nil }
                        let out = dave_xchacha20_poly1305_encrypt(kPtr, nonce24, aadBuf.baseAddress, aad.count, pPtr, plaintext.count)
                        defer { dave_buffer_free(out) }
                        guard let ptr = out.ptr, out.len > 0 else { return nil }
                        return Data(bytes: ptr, count: out.len)
                    }
                }
            }
            guard let ctData = ct else { return nil }
            var packet = Data(capacity: aad.count + ctData.count + 4)
            packet.append(contentsOf: aad)
            packet.append(ctData)
            packet.append(contentsOf: noncePrefix)
            return packet
        } else {
            var nonce12 = [UInt8](repeating: 0, count: 12)
            nonce12[0] = noncePrefix[0]
            nonce12[1] = noncePrefix[1]
            nonce12[2] = noncePrefix[2]
            nonce12[3] = noncePrefix[3]

            do {
                let nonce = try AES.GCM.Nonce(data: nonce12)
                let symKey = SymmetricKey(data: key)
                let sealed = try AES.GCM.seal(plaintext, using: symKey, nonce: nonce, authenticating: Data(aad))
                var packet = Data(capacity: aad.count + sealed.ciphertext.count + sealed.tag.count + 4)
                packet.append(contentsOf: aad)
                packet.append(sealed.ciphertext)
                packet.append(sealed.tag)
                packet.append(contentsOf: noncePrefix)
                return packet
            } catch {
                return nil
            }
        }
    }
}

// ==============================================================================
// MARK: - HARDWARE H.264 ENCODER (APPLE VIDEOTOOLBOX -> ANNEX-B + SPS VUI FIX)
// ==============================================================================

final class HardwareH264Encoder {
    private var session: VTCompressionSession?
    let width: Int
    let height: Int
    private let fps: Int
    private let bitrateKbps: Int
    private let maxBitrateKbps: Int
    private let stateLock = NSLock()
    private var hasLoggedEncodeErr = false
    private var _needsRebuild = false

    var needsRebuild: Bool {
        stateLock.lock()
        let v = _needsRebuild
        stateLock.unlock()
        return v
    }

    private func markNeedsRebuild() {
        stateLock.lock()
        _needsRebuild = true
        stateLock.unlock()
    }

    init?(
        width: Int,
        height: Int,
        fps: Int,
        bitrateKbps: Int,
        maxBitrateKbps: Int,
        realTime: Bool = true,
        keyFrameIntervalSec: Double = 2.0
    ) {
        self.width = max(160, (width / 2) * 2)
        self.height = max(120, (height / 2) * 2)
        self.fps = max(10, min(60, fps))
        self.bitrateKbps = max(300, bitrateKbps)
        self.maxBitrateKbps = max(self.bitrateKbps, maxBitrateKbps)

        var sess: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(self.width),
            height: Int32(self.height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &sess
        )
        guard status == noErr, let s = sess else { return nil }
        self.session = s

        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: realTime ? kCFBooleanTrue : kCFBooleanFalse)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: NSNumber(value: 0))
        let kfFrames = max(15, Int((Double(self.fps) * max(1.0, keyFrameIntervalSec)).rounded()))
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: kfFrames))
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: max(1.0, keyFrameIntervalSec)))
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: self.fps))
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: self.bitrateKbps * 1000))
        let byteLimit = (self.maxBitrateKbps * 1000) / 8
        let limits: [NSNumber] = [NSNumber(value: byteLimit), NSNumber(value: 1)]
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_DataRateLimits, value: limits as CFArray)
        VTCompressionSessionPrepareToEncodeFrames(s)
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        if let s = session {
            VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(s)
            session = nil
        }
    }

    /// Mã hóa 1 frame và luôn gọi `onFinished` ĐÚNG 1 LẦN trên mọi nhánh (an toàn tuyệt đối cho semaphore backpressure)
    func encodeGuaranteed(
        pixelBuffer: CVPixelBuffer,
        pts: CMTime,
        duration: CMTime,
        forceKeyFrame: Bool,
        onFinished: @escaping (Data?, Bool, OSStatus) -> Void
    ) {
        guard let s = session else {
            onFinished(nil, false, -1)
            return
        }
        var frameProps: CFDictionary? = nil
        if forceKeyFrame {
            let dict: [CFString: Any] = [kVTEncodeFrameOptionKey_ForceKeyFrame: true]
            frameProps = dict as CFDictionary
        }

        let encStatus = VTCompressionSessionEncodeFrame(
            s,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: frameProps,
            infoFlagsOut: nil
        ) { [weak self] status, _, sampleBuffer in
            if status != noErr {
                self?.markNeedsRebuild()
                onFinished(nil, false, status)
                return
            }
            guard let sb = sampleBuffer else {
                onFinished(nil, false, noErr)
                return
            }
            let isKey = HardwareH264Encoder.isKeyFrame(sb)
            let annexB = HardwareH264Encoder.extractAnnexB(from: sb, includeParameterSets: isKey)
            onFinished(annexB, isKey, noErr)
        }
        if encStatus != noErr {
            markNeedsRebuild()
            onFinished(nil, false, encStatus)
        }
    }

    func encode(
        pixelBuffer: CVPixelBuffer,
        pts: CMTime,
        duration: CMTime,
        forceKeyFrame: Bool,
        onError: ((OSStatus) -> Void)? = nil,
        completion: @escaping (Data, Bool) -> Void
    ) {
        guard let s = session else { return }
        var frameProps: CFDictionary? = nil
        if forceKeyFrame {
            let dict: [CFString: Any] = [kVTEncodeFrameOptionKey_ForceKeyFrame: true]
            frameProps = dict as CFDictionary
        }

        let encStatus = VTCompressionSessionEncodeFrame(
            s,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: frameProps,
            infoFlagsOut: nil
        ) { [weak self] status, _, sampleBuffer in
            if status != noErr {
                self?.markNeedsRebuild()
                if let self = self, !self.hasLoggedEncodeErr {
                    self.hasLoggedEncodeErr = true
                    onError?(status)
                }
                return
            }
            guard let sb = sampleBuffer else { return }
            let isKey = HardwareH264Encoder.isKeyFrame(sb)
            guard let annexB = HardwareH264Encoder.extractAnnexB(from: sb, includeParameterSets: isKey),
                  !annexB.isEmpty else { return }
            completion(annexB, isKey)
        }
        if encStatus != noErr {
            markNeedsRebuild()
            if !hasLoggedEncodeErr {
                hasLoggedEncodeErr = true
                onError?(encStatus)
            }
        }
    }

    static func isKeyFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
              CFArrayGetCount(attachments) > 0 else {
            return true
        }
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
        if let notSyncRaw = CFDictionaryGetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()) {
            let notSync = unsafeBitCast(notSyncRaw, to: CFBoolean.self)
            return !CFBooleanGetValue(notSync)
        }
        return true
    }

    static func extractAnnexB(from sampleBuffer: CMSampleBuffer, includeParameterSets: Bool) -> Data? {
        let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]
        var output = Data()
        var naluHeaderLength: Int = 4

        if let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var paramCount: Int = 0
            var hdrLen: Int32 = 4
            let cntStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                fmt,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &paramCount,
                nalUnitHeaderLengthOut: &hdrLen
            )
            if cntStatus == noErr {
                if hdrLen == 1 || hdrLen == 2 || hdrLen == 4 {
                    naluHeaderLength = Int(hdrLen)
                }
                if includeParameterSets && paramCount > 0 {
                    for idx in 0..<paramCount {
                        var ptr: UnsafePointer<UInt8>?
                        var size: Int = 0
                        let st = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                            fmt,
                            parameterSetIndex: idx,
                            parameterSetPointerOut: &ptr,
                            parameterSetSizeOut: &size,
                            parameterSetCountOut: nil,
                            nalUnitHeaderLengthOut: nil
                        )
                        if st == noErr, let p = ptr, size > 0 {
                            let rawParam = Data(bytes: p, count: size)
                            // Viết lại SPS VUI (max_num_reorder_frames = 0) chuẩn WebRTC/Chrome
                            let nalType = rawParam[rawParam.startIndex] & 0x1F
                            let finalParam = (nalType == 7) ? H264AnnexBHelper.rewriteSPSVUI(rawParam) : rawParam
                            output.append(contentsOf: startCode)
                            output.append(finalParam)
                        }
                    }
                }
            }
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return output.isEmpty ? nil : output
        }

        let totalLength = CMBlockBufferGetDataLength(blockBuffer)
        guard totalLength > naluHeaderLength else {
            return output.isEmpty ? nil : output
        }

        var contiguousBytes = [UInt8](repeating: 0, count: totalLength)
        let copySt = contiguousBytes.withUnsafeMutableBytes { rawBuf -> OSStatus in
            guard let dst = rawBuf.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: totalLength, destination: dst)
        }
        guard copySt == kCMBlockBufferNoErr else {
            return output.isEmpty ? nil : output
        }

        var offset = 0
        while offset + naluHeaderLength <= totalLength {
            var naluLen = 0
            for b in 0..<naluHeaderLength {
                naluLen = (naluLen << 8) | Int(contiguousBytes[offset + b])
            }
            offset += naluHeaderLength
            guard naluLen > 0, offset + naluLen <= totalLength else { break }

            let nalType = contiguousBytes[offset] & 0x1F
            // Bỏ qua AUD (9) và SEI (6) để tối ưu băng thông & tương thích DAVE H.264
            if nalType != 9 && nalType != 6 {
                let rawNalu = Data(contiguousBytes[offset..<(offset + naluLen)])
                let finalNalu = (nalType == 7) ? H264AnnexBHelper.rewriteSPSVUI(rawNalu) : rawNalu
                output.append(contentsOf: startCode)
                output.append(finalNalu)
            }
            offset += naluLen
        }

        return output.isEmpty ? nil : output
    }

    /// Tạo CVPixelBuffer NV12 (màn hình đen cho file âm thanh hoặc sóng màu cho Cam/Stream mẫu)
    static func makeSyntheticPixelBuffer(width: Int, height: Int, frameIndex: Int, blackOnly: Bool) -> CVPixelBuffer? {
        let w = max(160, (width / 2) * 2)
        let h = max(120, (height / 2) * 2)
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            w,
            h,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        if let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
           let uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
            let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

            if blackOnly {
                memset(yBase, 16, yStride * h)
                memset(uvBase, 128, uvStride * (h / 2))
            } else {
                let yPtr = yBase.assumingMemoryBound(to: UInt8.self)
                let uvPtr = uvBase.assumingMemoryBound(to: UInt8.self)
                let shift = (frameIndex * 6) % max(1, w)
                let bandW = max(1, w / 6)

                for row in 0..<h {
                    let rowBase = row * yStride
                    let yVal = UInt8(40 + ((row * 160) / max(1, h)))
                    memset(yPtr + rowBase, Int32(yVal), w)
                }

                let uvH = h / 2
                let uvW = w / 2
                let uPalette: [UInt8] = [210, 170, 90, 50, 140, 220]
                let vPalette: [UInt8] = [90, 50, 220, 190, 230, 130]
                for row in 0..<uvH {
                    let rowBase = row * uvStride
                    for col in 0..<uvW {
                        let px = (col * 2 + shift) % w
                        let band = (px / bandW) % 6
                        uvPtr[rowBase + col * 2] = uPalette[band]
                        uvPtr[rowBase + col * 2 + 1] = vPalette[band]
                    }
                }
            }
        }
        return pixelBuffer
    }
}

// ==============================================================================
// MARK: - NATIVE RUST WEBRTC TRANSPORT (str0m: ICE + DTLS-SRTP + RTCP NACK/RTX/PLI)
// ==============================================================================

final class DiscordWebRtcClient {
    private let lock = NSLock()
    private var handle: OpaquePointer?

    static func discordWebRtcCodecs() -> [[String: Any]] {
        [
            [
                "name": "opus",
                "type": "audio",
                "priority": 1000,
                "payload_type": 120
            ],
            [
                "name": "H264",
                "type": "video",
                "priority": 1000,
                "payload_type": 101,
                "rtx_payload_type": 102,
                "encode": true,
                "decode": true
            ]
        ]
    }

    init?(audioSsrc: UInt32, videoSsrc: UInt32, rtxSsrc: UInt32) {
        guard let h = dave_webrtc_new(audioSsrc, videoSsrc, rtxSsrc) else {
            return nil
        }
        self.handle = h
    }

    deinit {
        close()
    }

    func close() {
        lock.lock()
        let h = handle
        handle = nil
        lock.unlock()
        if let h = h {
            dave_webrtc_free(h)
        }
    }

    var offerSdp: String? {
        lock.lock()
        defer { lock.unlock() }
        guard let h = handle else { return nil }
        let buf = dave_webrtc_get_offer_sdp(h)
        defer { dave_buffer_free(buf) }
        guard let ptr = buf.ptr, buf.len > 0 else { return nil }
        return String(bytes: UnsafeBufferPointer(start: ptr, count: buf.len), encoding: .utf8)
    }

    func setDiscordAnswer(_ sdp: String) -> Bool {
        guard let data = sdp.data(using: .utf8), !data.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard let h = handle else { return false }
        return data.withUnsafeBytes { raw in
            guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            return dave_webrtc_set_discord_answer(h, ptr, data.count)
        }
    }

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let h = handle else { return false }
        return dave_webrtc_is_connected(h)
    }

    func takeKeyframeRequest() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let h = handle else { return false }
        return dave_webrtc_take_keyframe_request(h)
    }

    var txVideoPackets: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        guard let h = handle else { return 0 }
        return dave_webrtc_tx_video_packets(h)
    }

    @discardableResult
    func sendOpus(_ opusData: Data) -> Bool {
        guard !opusData.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard let h = handle else { return false }
        return opusData.withUnsafeBytes { raw in
            guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            return dave_webrtc_send_opus(h, ptr, opusData.count)
        }
    }

    @discardableResult
    func sendH264(_ annexB: Data, frametimeMs: Double) -> Bool {
        guard !annexB.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard let h = handle else { return false }
        return annexB.withUnsafeBytes { raw in
            guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            return dave_webrtc_send_h264(h, ptr, annexB.count, frametimeMs)
        }
    }
}

// ==============================================================================
// MARK: - DISCORD GO-LIVE STREAM MEDIA SESSION (WEBRTC DTLS-SRTP + DAVE E2EE)
// ==============================================================================

final class DiscordStreamMediaSession: NSObject, URLSessionWebSocketDelegate {
    let rtcServerId: String
    let streamKey: String
    let userId: String
    let sessionId: String
    let token: String
    let endpoint: String
    let username: String

    private var wsTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var listenTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var webrtcMonitorTask: Task<Void, Never>?

    private var webrtcClient: DiscordWebRtcClient?
    private var audioSsrc: Int = 0
    private var videoSsrc: Int = 0
    private var rtxSsrc: Int = 0
    private var voiceSeq: Int = -1
    private var daveSession: DaveE2EESession?
    private var negotiatedVideoCodec: String = "H264"
    private var negotiatedDaveVer: Int = 0

    private var hasSentIdentify = false
    private var hasSentSelectProtocol = false
    private var hasLoggedDaveReady = false
    private var hasLoggedVideoStart = false
    private var hasLoggedDaveVidErr = false
    private var hasLoggedWaitingDave = false
    private var isStopped = false

    private(set) var isReady = false
    var targetWidth: Int = 1280
    var targetHeight: Int = 720
    var targetFps: Int = 30
    var targetMaxBitrateKbps: Int = 2500

    var onLog: ((String) -> Void)?
    var onReady: (() -> Void)?
    var onRequestKeyFrame: (() -> Void)?

    init(
        rtcServerId: String,
        streamKey: String,
        userId: String,
        sessionId: String,
        token: String,
        endpoint: String,
        username: String
    ) {
        self.rtcServerId = rtcServerId
        self.streamKey = streamKey
        self.userId = userId
        self.sessionId = sessionId
        self.token = token
        self.endpoint = endpoint
        self.username = username
        super.init()
    }

    private func log(_ msg: String) {
        onLog?("[\(username)] [STREAM] \(msg)")
    }

    func connect() {
        let cleanHost = cleanVoiceEndpoint(endpoint)
        guard !cleanHost.isEmpty, let vUrl = URL(string: "wss://\(cleanHost)/?v=8") else {
            log("Endpoint Stream không hợp lệ: \(endpoint)")
            return
        }

        isStopped = false
        isReady = false
        hasSentIdentify = false
        hasSentSelectProtocol = false
        hasLoggedDaveReady = false
        hasLoggedVideoStart = false
        hasLoggedDaveVidErr = false
        hasLoggedWaitingDave = false
        voiceSeq = -1
        webrtcMonitorTask?.cancel()
        webrtcMonitorTask = nil
        webrtcClient?.close()
        webrtcClient = nil

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 604800
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.urlSession = session

        let ws = session.webSocketTask(with: vUrl)
        ws.maximumMessageSize = 32 * 1024 * 1024
        self.wsTask = ws
        ws.resume()
        log("Bắt tay Stream Gateway v8 (WebRTC): \(vUrl.absoluteString)")

        listenTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                while !Task.isCancelled && !self.isStopped {
                    let msg = try await ws.receive()
                    switch msg {
                    case .string(let text):
                        await self.handleJSON(text)
                    case .data(let data):
                        await self.handleBinary(data)
                    @unknown default:
                        break
                    }
                }
            } catch {
                if !Task.isCancelled && !self.isStopped {
                    self.log("Stream WS ngắt: \(error.localizedDescription)")
                }
            }
        }
    }

    private func sendJSON(_ payload: [String: Any]) async {
        guard let ws = wsTask, !isStopped else { return }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            try? await ws.send(.string(str))
        }
    }

    private func sendBinary(op: UInt8, payload: Data) async {
        guard let ws = wsTask, !isStopped else { return }
        var frame = Data([op])
        frame.append(payload)
        try? await ws.send(.data(frame))
    }

    private func handleJSON(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = json["op"] as? Int else { return }

        if let seq = json["seq"] as? Int {
            self.voiceSeq = seq
        }

        switch op {
        case 8: // Hello
            if let d = json["d"] as? [String: Any] {
                let interval = (d["heartbeat_interval"] as? Double)
                    ?? (d["heartbeat_interval"] as? Int).map { Double($0) }
                    ?? (d["heartbeat_interval"] as? NSNumber)?.doubleValue
                    ?? 13750.0
                startHeartbeat(intervalMs: interval)
                if !hasSentIdentify {
                    hasSentIdentify = true
                    await sendIdentify()
                }
            }
        case 2: // Ready
            if let d = json["d"] as? [String: Any] {
                self.audioSsrc = (d["ssrc"] as? Int) ?? (d["ssrc"] as? NSNumber)?.intValue ?? 0
                if let streams = d["streams"] as? [[String: Any]], let first = streams.first {
                    self.videoSsrc = (first["ssrc"] as? Int) ?? (first["ssrc"] as? NSNumber)?.intValue ?? (self.audioSsrc + 1)
                    self.rtxSsrc = (first["rtx_ssrc"] as? Int) ?? (first["rtx_ssrc"] as? NSNumber)?.intValue ?? (self.audioSsrc + 2)
                } else {
                    self.videoSsrc = self.audioSsrc + 1
                    self.rtxSsrc = self.audioSsrc + 2
                }

                // Gửi Op 12 VIDEO ban đầu (tắt) giống BaseMediaConnection.ts rồi mới mở sau WebRTC Connected
                await sendJSON([
                    "op": 12,
                    "d": ["audio_ssrc": audioSsrc, "video_ssrc": 0, "rtx_ssrc": 0, "streams": []]
                ])

                log("Stream Ready! AudioSSRC=\(audioSsrc), VideoSSRC=\(videoSsrc), RTX=\(rtxSsrc) -> Khởi tạo WebRTC Offer...")
                await startWebRtcOffer()
            }
        case 4: // Session Description (WebRTC SDP Answer)
            if let d = json["d"] as? [String: Any] {
                self.negotiatedVideoCodec = d["video_codec"] as? String ?? "H264"
                let daveVer = (d["dave_protocol_version"] as? Int)
                    ?? (d["dave_protocol_version"] as? NSNumber)?.intValue
                    ?? 0
                self.negotiatedDaveVer = daveVer

                let uid64 = UInt64(self.userId) ?? 0
                let srv64 = UInt64(self.rtcServerId) ?? 0
                let daveCid64 = (srv64 > 0) ? (srv64 &- 1) : 0

                self.daveSession?.destroy()
                if uid64 > 0 && daveCid64 > 0 {
                    let dave = DaveE2EESession(protocolVersion: UInt16(daveVer), userId: uid64, channelId: daveCid64)
                    self.daveSession = dave
                    if let kp = dave.reinit() {
                        await sendBinary(op: 26, payload: kp)
                        log("🔐 Stream DAVE v\(daveVer): Đã gửi KeyPackage (\(kp.count)B)")
                    }
                } else {
                    self.daveSession = nil
                }

                if let answerSdp = d["sdp"] as? String, !answerSdp.isEmpty, let rtc = self.webrtcClient {
                    if rtc.setDiscordAnswer(answerSdp) {
                        log("🌐 Đã nhận WebRTC SDP Answer (V:\(negotiatedVideoCodec)) -> Đang bắt tay ICE + DTLS-SRTP...")
                        startWebRtcMonitor()
                    } else {
                        log("❌ Không parse được WebRTC SDP Answer từ Discord")
                    }
                } else {
                    log("❌ Discord Op 4 không trả về WebRTC SDP Answer")
                }
            }
        case 15: // MEDIA_SINK_WANTS (có người bấm xem stream -> ép gửi IDR KeyFrame ngay lập tức!)
            onRequestKeyFrame?()
        case 21: // DAVE Prepare Transition
            if let d = json["d"] as? [String: Any],
               let tid = (d["transition_id"] as? Int) ?? (d["transition_id"] as? NSNumber)?.intValue,
               let ver = (d["protocol_version"] as? Int) ?? (d["protocol_version"] as? NSNumber)?.intValue,
               let dave = self.daveSession {
                if dave.prepareTransition(transitionId: UInt16(tid), protocolVersion: UInt16(ver)) {
                    await sendJSON(["op": 23, "d": ["transition_id": tid]])
                }
            }
        case 22: // DAVE Execute Transition
            if let d = json["d"] as? [String: Any],
               let tid = (d["transition_id"] as? Int) ?? (d["transition_id"] as? NSNumber)?.intValue,
               let dave = self.daveSession {
                if dave.executeTransition(transitionId: UInt16(tid)) {
                    if dave.canEncrypt && !self.hasLoggedDaveReady {
                        self.hasLoggedDaveReady = true
                        log("🔐 Stream DAVE E2EE đã kích hoạt (Transition #\(tid))!")
                    }
                    self.onRequestKeyFrame?()
                }
            }
        case 24: // DAVE Prepare Epoch
            if let d = json["d"] as? [String: Any],
               let epoch = (d["epoch"] as? Int) ?? (d["epoch"] as? NSNumber)?.intValue,
               let ver = (d["protocol_version"] as? Int) ?? (d["protocol_version"] as? NSNumber)?.intValue,
               epoch == 1 {
                if let kp = self.daveSession?.reinit(protocolVersion: UInt16(ver)) {
                    await sendBinary(op: 26, payload: kp)
                }
            }
        default:
            break
        }
    }

    private func handleBinary(_ raw: Data) async {
        guard raw.count >= 3 else { return }
        let b = raw.startIndex
        self.voiceSeq = (Int(raw[b]) << 8) | Int(raw[b + 1])
        let op = raw[b + 2]
        let payload = Data(raw.dropFirst(3))
        guard let dave = self.daveSession else { return }

        switch op {
        case 25:
            _ = dave.setExternalSender(payload)
        case 27:
            let res = dave.processProposals(payload: payload)
            if res.ok, let cw = res.commitWelcome {
                await sendBinary(op: 28, payload: cw)
            }
        case 29:
            let res = dave.processCommit(payload: payload)
            if res.result == 1 {
                if res.transitionId != 0 {
                    await sendJSON(["op": 23, "d": ["transition_id": Int(res.transitionId)]])
                } else {
                    if dave.canEncrypt && !self.hasLoggedDaveReady {
                        self.hasLoggedDaveReady = true
                        log("🔐 Stream DAVE E2EE đã kích hoạt (Commit #0)!")
                    }
                    self.onRequestKeyFrame?()
                }
            } else if res.result == -1 {
                await sendJSON(["op": 31, "d": ["transition_id": Int(res.transitionId)]])
                if let kp = dave.reinit() {
                    await sendBinary(op: 26, payload: kp)
                }
            }
        case 30:
            let res = dave.processWelcome(payload: payload)
            if res.ok {
                if res.transitionId != 0 {
                    await sendJSON(["op": 23, "d": ["transition_id": Int(res.transitionId)]])
                } else {
                    if dave.canEncrypt && !self.hasLoggedDaveReady {
                        self.hasLoggedDaveReady = true
                        log("🔐 Stream DAVE E2EE đã kích hoạt (Welcome #0)!")
                    }
                    self.onRequestKeyFrame?()
                }
            } else {
                await sendJSON(["op": 31, "d": ["transition_id": Int(res.transitionId)]])
                if let kp = dave.reinit() {
                    await sendBinary(op: 26, payload: kp)
                }
            }
        default:
            break
        }
    }

    private func sendIdentify() async {
        let payload: [String: Any] = [
            "op": 0,
            "d": [
                "server_id": rtcServerId,
                "user_id": userId,
                "session_id": sessionId,
                "token": token,
                "video": true,
                "streams": [
                    ["type": "screen", "rid": "100", "quality": 100]
                ],
                "max_dave_protocol_version": DaveE2EESession.maxProtocolVersion
            ]
        ]
        await sendJSON(payload)
    }

    private func startHeartbeat(intervalMs: Double) {
        heartbeatTask?.cancel()
        let sec = max(1.0, intervalMs / 1000.0)
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(sec * 1_000_000_000))
                guard let self = self, !self.isStopped else { break }
                let nowMs = Int(Date().timeIntervalSince1970 * 1000)
                await self.sendJSON(["op": 3, "d": ["t": nowMs, "seq_ack": self.voiceSeq]])
            }
        }
    }

    private func startWebRtcOffer() async {
        guard !hasSentSelectProtocol else { return }
        hasSentSelectProtocol = true

        webrtcClient?.close()
        guard let rtc = DiscordWebRtcClient(
            audioSsrc: UInt32(truncatingIfNeeded: audioSsrc),
            videoSsrc: UInt32(truncatingIfNeeded: videoSsrc),
            rtxSsrc: UInt32(truncatingIfNeeded: rtxSsrc)
        ), let offerSdp = rtc.offerSdp else {
            log("❌ Không thể khởi tạo WebRTC transport cho Go Live")
            return
        }
        self.webrtcClient = rtc

        let rtcConnId = UUID().uuidString.lowercased()
        let payload: [String: Any] = [
            "op": 1,
            "d": [
                "protocol": "webrtc",
                "codecs": DiscordWebRtcClient.discordWebRtcCodecs(),
                "data": offerSdp,
                "sdp": offerSdp,
                "rtc_connection_id": rtcConnId
            ]
        ]
        await sendJSON(payload)
    }

    private func startWebRtcMonitor() {
        webrtcMonitorTask?.cancel()
        webrtcMonitorTask = Task { [weak self] in
            guard let self = self else { return }
            var notifiedReady = false
            var waitedTicks = 0
            while !Task.isCancelled && !self.isStopped {
                guard let rtc = self.webrtcClient else { break }
                if !notifiedReady {
                    if rtc.isConnected {
                        notifiedReady = true
                        self.isReady = true
                        await self.setVideoAttributes(
                            enabled: true,
                            width: self.targetWidth,
                            height: self.targetHeight,
                            fps: self.targetFps,
                            maxBitrateKbps: self.targetMaxBitrateKbps
                        )
                        await self.setSpeaking(true)
                        let silence = Data([0xF8, 0xFF, 0xFE])
                        for _ in 0..<5 { self.sendOpusPacket(silence) }
                        self.log("✅ Go Live WebRTC DTLS-SRTP sẵn sàng (V:\(self.negotiatedVideoCodec) | DAVE v\(self.negotiatedDaveVer))!")
                        self.onReady?()
                        self.onRequestKeyFrame?()
                    } else {
                        waitedTicks += 1
                        if waitedTicks == 125 { // ~10s
                            self.log("⚠️ Go Live WebRTC ICE/DTLS chưa kết nối sau 10s (kiểm tra mạng/UDP)")
                        }
                    }
                }
                if notifiedReady && rtc.takeKeyframeRequest() {
                    self.onRequestKeyFrame?()
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    func setVideoAttributes(enabled: Bool, width: Int, height: Int, fps: Int, maxBitrateKbps: Int) async {
        targetWidth = width
        targetHeight = height
        targetFps = fps
        targetMaxBitrateKbps = maxBitrateKbps
        guard isReady else { return }

        let d: [String: Any]
        if enabled {
            d = [
                "audio_ssrc": audioSsrc,
                "video_ssrc": videoSsrc,
                "rtx_ssrc": rtxSsrc,
                "streams": [[
                    "type": "video",
                    "rid": "100",
                    "ssrc": videoSsrc,
                    "active": true,
                    "quality": 100,
                    "rtx_ssrc": rtxSsrc,
                    "max_bitrate": maxBitrateKbps * 1000,
                    "max_framerate": fps,
                    "max_resolution": [
                        "type": "fixed",
                        "width": width,
                        "height": height
                    ]
                ]]
            ]
        } else {
            d = [
                "audio_ssrc": audioSsrc,
                "video_ssrc": 0,
                "rtx_ssrc": 0,
                "streams": []
            ]
        }
        await sendJSON(["op": 12, "d": d])
    }

    func setSpeaking(_ speaking: Bool) async {
        await sendJSON([
            "op": 5,
            "d": [
                "speaking": speaking ? 2 : 0,
                "delay": 0,
                "ssrc": audioSsrc
            ]
        ])
    }

    func sendVideoH264Frame(_ annexBFrame: Data, frametimeMs: Double) {
        guard isReady, !isStopped, let rtc = webrtcClient, rtc.isConnected else { return }
        if rtc.takeKeyframeRequest() {
            onRequestKeyFrame?()
        }

        let frameToSend: Data
        if let dave = self.daveSession, dave.isEncryptionRequired {
            if let encrypted = dave.encryptVideoH264(annexBFrame) {
                frameToSend = encrypted
            } else {
                if dave.canEncrypt {
                    if !hasLoggedDaveVidErr {
                        hasLoggedDaveVidErr = true
                        log("⚠️ Lỗi DAVE mã hóa khung H.264 (\(annexBFrame.count)B)")
                    }
                } else if !hasLoggedWaitingDave {
                    hasLoggedWaitingDave = true
                    log("⏳ Đang chờ Stream DAVE MLS sẵn sàng để mã hóa hình H.264...")
                }
                return
            }
        } else {
            frameToSend = annexBFrame
        }

        let sent = rtc.sendH264(frameToSend, frametimeMs: frametimeMs)
        if !hasLoggedVideoStart && sent {
            hasLoggedVideoStart = true
            log("📺 Go Live WebRTC đang phát hình H.264 (\(targetWidth)x\(targetHeight)@\(targetFps)fps | \(frameToSend.count)B)!")
        }
    }

    func sendOpusPacket(_ opusPayload: Data) {
        guard isReady, !isStopped, let rtc = webrtcClient, rtc.isConnected else { return }

        let silenceFrame = Data([0xF8, 0xFF, 0xFE])
        let mediaPayload: Data
        if let dave = self.daveSession, dave.isEncryptionRequired {
            if let encrypted = dave.encryptOpus(opusPayload) {
                mediaPayload = encrypted
            } else {
                mediaPayload = silenceFrame
            }
        } else {
            mediaPayload = opusPayload
        }

        rtc.sendOpus(mediaPayload)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        log("Stream WS đóng [Mã \(closeCode.rawValue)]: \(reasonStr)")
    }

    func stop() {
        isStopped = true
        isReady = false
        heartbeatTask?.cancel(); heartbeatTask = nil
        webrtcMonitorTask?.cancel(); webrtcMonitorTask = nil
        listenTask?.cancel(); listenTask = nil
        wsTask?.cancel(with: .goingAway, reason: nil); wsTask = nil
        urlSession?.invalidateAndCancel(); urlSession = nil
        daveSession?.destroy(); daveSession = nil
        webrtcClient?.close(); webrtcClient = nil
    }
}

// ==============================================================================
// MARK: - BACKGROUND H.264 GOP CACHE (GIỮ VIDEO CHẠY MƯỢT 0% GPU KHI THOÁT APP)
// ==============================================================================

final class BackgroundH264LoopCache {
    private let lock = NSLock()
    private var committedGop: [Data] = []
    private var currentGop: [Data] = []
    private var currentBytes: Int = 0
    private var lastKeyFrame: Data?
    private var playIndex: Int = 0
    private let maxFrames: Int = 180
    private let maxBytes: Int = 6 * 1024 * 1024

    func reset() {
        lock.lock()
        committedGop.removeAll()
        currentGop.removeAll()
        currentBytes = 0
        lastKeyFrame = nil
        playIndex = 0
        lock.unlock()
    }

    func record(frame: Data, isKey: Bool) {
        guard !frame.isEmpty else { return }
        lock.lock()
        if isKey {
            lastKeyFrame = frame
            if !currentGop.isEmpty {
                committedGop = currentGop
            }
            currentGop = [frame]
            currentBytes = frame.count
        } else if !currentGop.isEmpty && currentGop.count < maxFrames && (currentBytes + frame.count) <= maxBytes {
            currentGop.append(frame)
            currentBytes += frame.count
        }
        lock.unlock()
    }

    func nextFrame(forceKey: Bool) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        let source: [Data]
        if !committedGop.isEmpty {
            source = committedGop
        } else if !currentGop.isEmpty {
            source = currentGop
        } else if let kf = lastKeyFrame {
            return kf
        } else {
            return nil
        }

        if forceKey || playIndex >= source.count {
            playIndex = 0
        }
        let frame = source[playIndex]
        playIndex = (playIndex + 1) % source.count
        return frame
    }

    var hasCachedFrames: Bool {
        lock.lock()
        let ok = !committedGop.isEmpty || !currentGop.isEmpty || lastKeyFrame != nil
        lock.unlock()
        return ok
    }
}

// ==============================================================================
// MARK: - FULL-VIDEO PROGRESSIVE ZERO-GPU H.264 DISK CACHE (KHÔNG BAO GIỜ LẶP ĐOẠN NGẮN!)
// ==============================================================================

enum H264CacheStatus: Equatable {
    case none
    case directPassthrough
    case preparing(progress: Double, cachedSeconds: Double)
    case pausedForBackground(progress: Double, cachedSeconds: Double)
    case ready(totalSeconds: Double)
    case failed(String)
}

/// Ghi toàn bộ video ra file `.h264bin` (H.264 Baseline Annex-B, không B-frame, đã rewrite SPS VUI)
/// ở tốc độ phần cứng tối đa (20x–50x real-time). Sau đó phát trực tiếp từ ổ đĩa bằng CPU 0% GPU:
/// - Thoát app / khóa màn hình vẫn phát FULL VIDEO từ đầu đến cuối, KHÔNG lặp đoạn 2 giây!
/// - Hỗ trợ đọc song song ngay trong lúc đang ghi (progressive) và tự nối tiếp khi mở lại app!
final class H264FullVideoCacheSession {
    static let headerSize: Int64 = 16
    private static let magic: [UInt8] = [0x54, 0x48, 0x32, 0x36] // "TH26"

    let cacheKey: String
    let sourceURL: URL
    let sourceTitle: String
    let profile: DiscordStreamProfile
    let cacheURL: URL

    private let lock = NSLock()
    private let writeLock = NSLock()
    private var _validByteLength: Int64 = 0
    private var _lastEncodedPtsSec: Double = -1.0
    private var _cachedDurationSec: Double = 0.0
    private var _totalDurationSec: Double = 0.0
    private var _isComplete: Bool = false
    private var _isPreparing: Bool = false
    private var _isPausedForBackground: Bool = false
    private var _isBackgroundMode: Bool = false
    private var _failedError: String? = nil
    private var _status: H264CacheStatus = .none
    private var _frameCount: Int = 0

    private var prepTask: Task<Void, Never>?
    private var statusListeners: [UUID: (H264CacheStatus) -> Void] = [:]
    private var logListeners: [UUID: (String) -> Void] = [:]

    var validByteLength: Int64 {
        lock.lock(); defer { lock.unlock() }
        return _validByteLength
    }
    var isComplete: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isComplete
    }
    var isPreparing: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isPreparing
    }
    var isBackgroundMode: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isBackgroundMode
    }
    var failedError: String? {
        lock.lock(); defer { lock.unlock() }
        return _failedError
    }
    var status: H264CacheStatus {
        lock.lock(); defer { lock.unlock() }
        return _status
    }
    var cachedDurationSec: Double {
        lock.lock(); defer { lock.unlock() }
        return _cachedDurationSec
    }

    init(cacheKey: String, sourceURL: URL, sourceTitle: String, profile: DiscordStreamProfile, cacheURL: URL) {
        self.cacheKey = cacheKey
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.profile = profile
        self.cacheURL = cacheURL
        loadExistingIfComplete()
    }

    @discardableResult
    func addListener(onStatus: ((H264CacheStatus) -> Void)?, onLog: ((String) -> Void)?) -> UUID {
        let id = UUID()
        lock.lock()
        if let s = onStatus { statusListeners[id] = s }
        if let l = onLog { logListeners[id] = l }
        let curStatus = _status
        lock.unlock()
        if let s = onStatus, curStatus != .none {
            DispatchQueue.main.async { s(curStatus) }
        }
        return id
    }

    func removeListener(_ id: UUID) {
        lock.lock()
        statusListeners.removeValue(forKey: id)
        logListeners.removeValue(forKey: id)
        lock.unlock()
    }

    private func emitStatus(_ newStatus: H264CacheStatus) {
        lock.lock()
        _status = newStatus
        let listeners = Array(statusListeners.values)
        lock.unlock()
        DispatchQueue.main.async {
            for cb in listeners { cb(newStatus) }
        }
    }

    private func emitLog(_ msg: String) {
        lock.lock()
        let listeners = Array(logListeners.values)
        lock.unlock()
        DispatchQueue.main.async {
            for cb in listeners { cb(msg) }
        }
    }

    private func loadExistingIfComplete() {
        guard let fh = try? FileHandle(forReadingFrom: cacheURL) else { return }
        defer { try? fh.close() }
        guard let hdr = try? fh.read(upToCount: Int(Self.headerSize)),
              hdr.count == Int(Self.headerSize),
              hdr[0] == Self.magic[0], hdr[1] == Self.magic[1], hdr[2] == Self.magic[2], hdr[3] == Self.magic[3],
              hdr[4] == 1,
              (hdr[5] & 0x01) == 0x01 else {
            return
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)
        let fsize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        guard fsize > Self.headerSize + 16 else { return }

        let durMs = (UInt32(hdr[12]) << 24) | (UInt32(hdr[13]) << 16) | (UInt32(hdr[14]) << 8) | UInt32(hdr[15])
        let durSec = Double(durMs) / 1000.0

        lock.lock()
        _validByteLength = fsize
        _totalDurationSec = durSec
        _cachedDurationSec = durSec
        _isComplete = true
        _isPreparing = false
        _status = .ready(totalSeconds: durSec)
        lock.unlock()
    }

    func setBackgroundMode(_ inBackground: Bool) {
        lock.lock()
        let prev = _isBackgroundMode
        _isBackgroundMode = inBackground
        let shouldResume = (!inBackground && !_isComplete && !_isPreparing && _failedError == nil)
        lock.unlock()

        if !inBackground && prev && shouldResume {
            startOrResumePreparation()
        }
    }

    func startOrResumePreparation() {
        lock.lock()
        if _isComplete || _isPreparing || _isBackgroundMode {
            lock.unlock()
            return
        }
        _isPreparing = true
        _isPausedForBackground = false
        _failedError = nil
        let resuming = (_validByteLength > Self.headerSize && _lastEncodedPtsSec >= 0)
        let resumeFromPts = _lastEncodedPtsSec
        lock.unlock()

        prepTask = Task.detached(priority: .userInitiated) { [weak self] in
            self?.runPreparationLoop(resuming: resuming, resumeFromPts: resumeFromPts)
        }
    }

    func cancelPreparation() {
        prepTask?.cancel()
        prepTask = nil
        lock.lock()
        _isPreparing = false
        lock.unlock()
    }

    private func makeHeaderBytes(complete: Bool, width: Int, height: Int, fps: Int, durationMs: UInt32) -> Data {
        var hdr = Data(capacity: Int(Self.headerSize))
        hdr.append(contentsOf: Self.magic)
        hdr.append(1) // version
        hdr.append(complete ? 0x01 : 0x00)
        let w16 = UInt16(clamping: width)
        let h16 = UInt16(clamping: height)
        let f16 = UInt16(clamping: fps)
        hdr.append(UInt8((w16 >> 8) & 0xFF)); hdr.append(UInt8(w16 & 0xFF))
        hdr.append(UInt8((h16 >> 8) & 0xFF)); hdr.append(UInt8(h16 & 0xFF))
        hdr.append(UInt8((f16 >> 8) & 0xFF)); hdr.append(UInt8(f16 & 0xFF))
        hdr.append(UInt8((durationMs >> 24) & 0xFF))
        hdr.append(UInt8((durationMs >> 16) & 0xFF))
        hdr.append(UInt8((durationMs >> 8) & 0xFF))
        hdr.append(UInt8(durationMs & 0xFF))
        return hdr
    }

    private func runPreparationLoop(resuming: Bool, resumeFromPts: Double) {
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            markFailed("File \(sourceTitle) không có track video")
            return
        }

        let trackDur = CMTimeGetSeconds(asset.duration)
        let totalDur = (trackDur.isFinite && trackDur > 0) ? trackDur : 0.0
        lock.lock()
        if totalDur > 0 { _totalDurationSec = totalDur }
        lock.unlock()

        // Tính kích thước hiển thị thực (tự động xoay đúng chiều cho video dọc TikTok / iPhone!)
        let prefTransform = videoTrack.preferredTransform
        let transformedRect = CGRect(origin: .zero, size: videoTrack.naturalSize).applying(prefTransform)
        let displaySize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let (encW, encH) = TreoMediaBroadcastEngine.computeTargetSize(
            naturalSize: displaySize,
            maxWidth: profile.width,
            maxHeight: profile.height
        )

        let nominalFps = Double(videoTrack.nominalFrameRate)
        let targetFps = Double(profile.fps)
        let effFps = (nominalFps >= 5 && nominalFps <= 60) ? min(nominalFps, targetFps) : min(30.0, targetFps)
        let effFpsInt = max(10, min(60, Int(effFps.rounded())))
        let minFrameSec = 1.0 / targetFps
        let defaultStepMs = 1000.0 / effFps

        // Chuẩn bị file đích
        let fm = FileManager.default
        let dir = cacheURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        if !resuming {
            let initHdr = makeHeaderBytes(complete: false, width: encW, height: encH, fps: effFpsInt, durationMs: UInt32(max(0, totalDur * 1000.0)))
            do {
                try initHdr.write(to: cacheURL, options: .atomic)
            } catch {
                markFailed("Không tạo được file cache video: \(error.localizedDescription)")
                return
            }
            lock.lock()
            _validByteLength = Self.headerSize
            _lastEncodedPtsSec = -1.0
            _cachedDurationSec = 0.0
            _frameCount = 0
            lock.unlock()
            emitLog("⚡ Đang tối ưu Full Video chạy nền (0% GPU): \(sourceTitle) (\(encW)x\(encH)@\(effFpsInt)fps)...")
        } else {
            emitLog("☀️ Tiếp tục tối ưu phần còn lại của video từ \(Int(resumeFromPts))s...")
        }

        guard let writeHandle = try? FileHandle(forWritingTo: cacheURL) else {
            markFailed("Không mở được file cache để ghi")
            return
        }
        defer { try? writeHandle.close() }

        lock.lock()
        let startWriteOffset = _validByteLength
        lock.unlock()
        do {
            try writeHandle.truncate(atOffset: UInt64(startWriteOffset))
            try writeHandle.seek(toOffset: UInt64(startWriteOffset))
        } catch {
            markFailed("Lỗi chuẩn bị vị trí ghi cache: \(error.localizedDescription)")
            return
        }

        guard let encoder = HardwareH264Encoder(
            width: encW,
            height: encH,
            fps: effFpsInt,
            bitrateKbps: profile.bitrateKbps,
            maxBitrateKbps: profile.maxBitrateKbps,
            realTime: false,
            keyFrameIntervalSec: 1.5
        ) else {
            if isBackgroundMode {
                markPausedForBackground()
            } else {
                markFailed("Không khởi tạo được Hardware H.264 Encoder")
            }
            return
        }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            kCVPixelBufferWidthKey as String: encW,
            kCVPixelBufferHeightKey as String: encH,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]

        let needsTransform = (abs(prefTransform.b) > 0.01 || abs(prefTransform.c) > 0.01 || prefTransform.a < 0 || prefTransform.d < 0)

        func makeReader(useComposition: Bool) -> (AVAssetReader, AVAssetReaderOutput)? {
            guard let r = try? AVAssetReader(asset: asset) else { return nil }
            if resuming && resumeFromPts >= 0 {
                let startTime = CMTime(seconds: resumeFromPts + 0.001, preferredTimescale: 90_000)
                r.timeRange = CMTimeRange(start: startTime, duration: .positiveInfinity)
            }
            if useComposition {
                let comp = AVMutableVideoComposition()
                comp.renderSize = CGSize(width: encW, height: encH)
                comp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(effFpsInt))

                let instr = AVMutableVideoCompositionInstruction()
                let dur = asset.duration.isValid && !asset.duration.isIndefinite
                    ? asset.duration
                    : CMTime(seconds: max(1.0, totalDur), preferredTimescale: 600)
                instr.timeRange = CMTimeRange(start: .zero, duration: dur)

                let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                let tx = -transformedRect.origin.x
                let ty = -transformedRect.origin.y
                let sx = CGFloat(encW) / max(1.0, displaySize.width)
                let sy = CGFloat(encH) / max(1.0, displaySize.height)
                let finalTransform = prefTransform
                    .concatenating(CGAffineTransform(translationX: tx, y: ty))
                    .concatenating(CGAffineTransform(scaleX: sx, y: sy))
                layerInstr.setTransform(finalTransform, at: .zero)
                instr.layerInstructions = [layerInstr]
                comp.instructions = [instr]

                // AVAssetReaderVideoCompositionOutput KHÔNG cho phép width/height keys trong videoSettings (comp.renderSize quyết định kích thước)
                let compSettings: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
                ]
                let compOut = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: compSettings)
                compOut.videoComposition = comp
                compOut.alwaysCopiesSampleData = false
                if r.canAdd(compOut) {
                    r.add(compOut)
                    if r.startReading() { return (r, compOut) }
                }
                return nil
            } else {
                let trackOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
                trackOut.alwaysCopiesSampleData = false
                if r.canAdd(trackOut) {
                    r.add(trackOut)
                    if r.startReading() { return (r, trackOut) }
                }
                return nil
            }
        }

        let readerPair: (AVAssetReader, AVAssetReaderOutput)? = needsTransform
            ? (makeReader(useComposition: true) ?? makeReader(useComposition: false))
            : makeReader(useComposition: false)

        guard let (reader, readerOutput) = readerPair else {
            encoder.invalidate()
            if isBackgroundMode {
                markPausedForBackground()
            } else {
                markFailed("AVAssetReader không mở được video \(sourceTitle)")
            }
            return
        }
        defer { reader.cancelReading() }

        // Semaphore backpressure: giữ tối đa 4 frame in-flight -> RAM luôn < 15MB, tốc độ ~25x–50x!
        let inFlightSem = DispatchSemaphore(value: 4)
        var lastEmittedPtsSec = resuming ? resumeFromPts : -1.0
        var localFrameIdx: Int64 = 0
        var hitBgInterrupt = false
        var lastProgressEmit = Date.distantPast

        emitStatus(.preparing(
            progress: totalDur > 0 ? min(0.99, max(0.0, cachedDurationSec / totalDur)) : 0.0,
            cachedSeconds: cachedDurationSec
        ))

        while !Task.isCancelled && reader.status == .reading {
            if isBackgroundMode || encoder.needsRebuild {
                hitBgInterrupt = true
                break
            }

            let stepResult: Int = autoreleasepool {
                guard let sb = readerOutput.copyNextSampleBuffer() else { return 0 } // EOF
                guard let pb = CMSampleBufferGetImageBuffer(sb) else { return 1 } // skip

                let srcPts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
                let validPts = srcPts.isFinite ? srcPts : (lastEmittedPtsSec >= 0 ? lastEmittedPtsSec + (defaultStepMs / 1000.0) : 0.0)
                if lastEmittedPtsSec >= 0 && validPts >= lastEmittedPtsSec && (validPts - lastEmittedPtsSec) < minFrameSec * 0.75 {
                    return 1 // skip frame vượt FPS target
                }

                let deltaMs: Double
                if lastEmittedPtsSec >= 0 && validPts > lastEmittedPtsSec && (validPts - lastEmittedPtsSec) < 0.5 {
                    deltaMs = (validPts - lastEmittedPtsSec) * 1000.0
                } else {
                    deltaMs = defaultStepMs
                }
                let deltaMicros = UInt32(max(8_000.0, min(250_000.0, (deltaMs * 1000.0).rounded())))
                lastEmittedPtsSec = validPts

                let forceKey = (localFrameIdx == 0) || (localFrameIdx % Int64(max(15, Int(Double(effFpsInt) * 1.5))) == 0)
                let encPts = CMTime(seconds: validPts, preferredTimescale: 90_000)
                let encDur = CMTime(value: Int64(deltaMicros), timescale: 1_000_000)
                localFrameIdx += 1

                inFlightSem.wait()
                encoder.encodeGuaranteed(
                    pixelBuffer: pb,
                    pts: encPts,
                    duration: encDur,
                    forceKeyFrame: forceKey
                ) { [weak self] annexB, isKey, status in
                    defer { inFlightSem.signal() }
                    guard let self = self, status == noErr else { return }
                    guard let data = annexB, !data.isEmpty else { return }
                    self.appendRecord(
                        writeHandle: writeHandle,
                        deltaMicros: deltaMicros,
                        isKey: isKey,
                        annexB: data,
                        ptsSec: validPts
                    )
                }
                return 2
            }

            if stepResult == 0 { break } // EOF
            if encoder.needsRebuild {
                hitBgInterrupt = true
                break
            }

            let now = Date()
            if now.timeIntervalSince(lastProgressEmit) >= 0.25 {
                lastProgressEmit = now
                let curCached = cachedDurationSec
                let pct = totalDur > 0 ? min(0.99, max(0.01, curCached / totalDur)) : 0.5
                emitStatus(.preparing(progress: pct, cachedSeconds: curCached))
            }
        }

        // Xả toàn bộ frame đang in-flight trong VideoToolbox trước khi đóng handle
        encoder.invalidate()

        if Task.isCancelled {
            lock.lock()
            _isPreparing = false
            lock.unlock()
            return
        }

        if hitBgInterrupt || isBackgroundMode || encoder.needsRebuild {
            markPausedForBackground()
            return
        }

        // Hoàn tất 100% toàn bộ video! Cập nhật cờ COMPLETE (byte 5 = 0x01) trên header đĩa
        lock.lock()
        let finalDur = max(_cachedDurationSec, _totalDurationSec)
        let finalBytes = _validByteLength
        let finalFrames = _frameCount
        lock.unlock()

        if finalBytes <= Self.headerSize {
            markFailed("Không trích xuất được khung hình H.264 nào từ \(sourceTitle)")
            return
        }

        let completeHdr = makeHeaderBytes(
            complete: true,
            width: encW,
            height: encH,
            fps: effFpsInt,
            durationMs: UInt32(max(0, finalDur * 1000.0))
        )
        writeLock.lock()
        do {
            try writeHandle.seek(toOffset: 0)
            try writeHandle.write(contentsOf: completeHdr)
            try writeHandle.synchronize()
        } catch {}
        writeLock.unlock()

        lock.lock()
        _isComplete = true
        _isPreparing = false
        _isPausedForBackground = false
        lock.unlock()

        let mb = Double(finalBytes) / (1024.0 * 1024.0)
        emitStatus(.ready(totalSeconds: finalDur))
        emitLog(String(format: "✅ Đã tối ưu xong Full Video 100%% (%.1fs | %d khung | %.1fMB • 0%% GPU chạy nền): %@", finalDur, finalFrames, mb, sourceTitle))
    }

    private func appendRecord(writeHandle: FileHandle, deltaMicros: UInt32, isKey: Bool, annexB: Data, ptsSec: Double) {
        let len = UInt32(annexB.count)
        var rec = Data(capacity: 9 + annexB.count)
        rec.append(UInt8((deltaMicros >> 24) & 0xFF))
        rec.append(UInt8((deltaMicros >> 16) & 0xFF))
        rec.append(UInt8((deltaMicros >> 8) & 0xFF))
        rec.append(UInt8(deltaMicros & 0xFF))
        rec.append(isKey ? 1 : 0)
        rec.append(UInt8((len >> 24) & 0xFF))
        rec.append(UInt8((len >> 16) & 0xFF))
        rec.append(UInt8((len >> 8) & 0xFF))
        rec.append(UInt8(len & 0xFF))
        rec.append(annexB)

        writeLock.lock()
        let wroteOK: Bool
        do {
            _ = try writeHandle.seekToEnd()
            try writeHandle.write(contentsOf: rec)
            wroteOK = true
        } catch {
            wroteOK = false
        }
        writeLock.unlock()

        guard wroteOK else { return }

        lock.lock()
        _validByteLength += Int64(rec.count)
        _lastEncodedPtsSec = max(_lastEncodedPtsSec, ptsSec)
        _cachedDurationSec += Double(deltaMicros) / 1_000_000.0
        _frameCount += 1
        lock.unlock()
    }

    private func markPausedForBackground() {
        lock.lock()
        _isPreparing = false
        _isPausedForBackground = true
        let cached = _cachedDurationSec
        let total = _totalDurationSec
        lock.unlock()

        let pct = total > 0 ? min(0.99, max(0.0, cached / total)) : 0.0
        emitStatus(.pausedForBackground(progress: pct, cachedSeconds: cached))
        if cached >= 1.0 {
            emitLog(String(format: "🌙 Đã tối ưu %.0f%% (%.1fs) — phát liên tục phần này ở nền & tự nối tiếp khi mở lại app.", pct * 100.0, cached))
        }
    }

    private func markFailed(_ message: String) {
        lock.lock()
        _isPreparing = false
        _failedError = message
        lock.unlock()
        emitStatus(.failed(message))
        emitLog("❌ \(message)")
    }
}

/// Quản lý cache Full Video H.264 trên đĩa (chia sẻ giữa Go Live & Fake Cam, tự dọn cache cũ > 350MB)
final class H264FullVideoCacheManager {
    static let shared = H264FullVideoCacheManager()

    private let lock = NSLock()
    private var sessions: [String: H264FullVideoCacheSession] = [:]
    private var isBackgroundMode = false

    private init() {}

    private var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("TreoH264Cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func setAppInBackground(_ inBackground: Bool) {
        lock.lock()
        isBackgroundMode = inBackground
        let all = Array(sessions.values)
        lock.unlock()
        for s in all {
            s.setBackgroundMode(inBackground)
        }
    }

    static func cacheKey(url: URL, title: String, profile: DiscordStreamProfile) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fsize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let raw = "\(title)|\(fsize)|\(profile.width)x\(profile.height)|\(profile.fps)|\(profile.bitrateKbps)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    func getOrCreateSession(url: URL, title: String, profile: DiscordStreamProfile) -> H264FullVideoCacheSession {
        let key = Self.cacheKey(url: url, title: title, profile: profile)
        lock.lock()
        if let existing = sessions[key] {
            let bg = isBackgroundMode
            lock.unlock()
            existing.setBackgroundMode(bg)
            return existing
        }
        let cacheURL = cacheDirectory.appendingPathComponent("\(key).h264bin")
        let sess = H264FullVideoCacheSession(
            cacheKey: key,
            sourceURL: url,
            sourceTitle: title,
            profile: profile,
            cacheURL: cacheURL
        )
        sess.setBackgroundMode(isBackgroundMode)
        sessions[key] = sess
        let protectedNames = Set(sessions.values.map { $0.cacheURL.lastPathComponent })
        lock.unlock()

        pruneOldCacheFiles(keeping: protectedNames)
        return sess
    }

    private func pruneOldCacheFiles(keeping protectedNames: Set<String>) {
        DispatchQueue.global(qos: .utility).async { [cacheDirectory] in
            let fm = FileManager.default
            guard let urls = try? fm.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            var items: [(url: URL, size: Int64, mtime: Date)] = []
            var totalBytes: Int64 = 0
            for u in urls where u.pathExtension == "h264bin" {
                let vals = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let sz = Int64(vals?.fileSize ?? 0)
                let mt = vals?.contentModificationDate ?? .distantPast
                totalBytes += sz
                items.append((u, sz, mt))
            }

            let maxBytes: Int64 = 350 * 1024 * 1024
            let maxFiles = 8
            guard totalBytes > maxBytes || items.count > maxFiles else { return }

            items.sort { $0.mtime < $1.mtime }
            var remaining = items.count
            for item in items {
                if totalBytes <= maxBytes && remaining <= maxFiles { break }
                if protectedNames.contains(item.url.lastPathComponent) { continue }
                try? fm.removeItem(at: item.url)
                totalBytes -= item.size
                remaining -= 1
            }
        }
    }
}

// ==============================================================================
// MARK: - SHARED MEDIA BROADCAST ENGINE (LOOP ∞ FULL VIDEO + AUDIO -> ALL TOKENS)
// ==============================================================================

final class TreoMediaBroadcastEngine {
    private var videoTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private let stateLock = NSLock()
    private var pendingKeyFrame = true
    private var _isBackgroundMode = false
    private let bgLoopCache = BackgroundH264LoopCache()

    func setBackgroundMode(_ inBackground: Bool) {
        stateLock.lock()
        let changed = (_isBackgroundMode != inBackground)
        _isBackgroundMode = inBackground
        if changed {
            pendingKeyFrame = true
        }
        stateLock.unlock()
    }

    private var isBackgroundMode: Bool {
        stateLock.lock()
        let v = _isBackgroundMode
        stateLock.unlock()
        return v
    }

    func requestKeyFrame() {
        stateLock.lock()
        pendingKeyFrame = true
        stateLock.unlock()
    }

    private func consumeKeyFrameRequest() -> Bool {
        stateLock.lock()
        let v = pendingKeyFrame
        pendingKeyFrame = false
        stateLock.unlock()
        return v
    }

    func stop() {
        videoTask?.cancel()
        videoTask = nil
        audioTask?.cancel()
        audioTask = nil
        bgLoopCache.reset()
    }

    /// Kiểm tra file .mp4/.mov có thể đọc H.264 trực tiếp (không cần tối ưu trước) với 0% GPU hay không
    static func canUseDirectH264Passthrough(asset: AVURLAsset, track: AVAssetTrack, profile: DiscordStreamProfile) -> Bool {
        guard let fmtAny = track.formatDescriptions.first else { return false }
        let fmt = fmtAny as! CMFormatDescription
        guard CMFormatDescriptionGetMediaSubType(fmt) == kCMVideoCodecType_H264 else {
            return false
        }
        // Nếu video bị xoay/lật (TikTok/iPhone dọc có preferredTransform) -> tối ưu để xoay đứng chuẩn xác
        let t = track.preferredTransform
        if abs(t.b) > 0.01 || abs(t.c) > 0.01 || t.a < 0 || t.d < 0 {
            return false
        }
        // Nếu độ phân giải hoặc bitrate vượt xa profile Discord -> tối ưu để tránh Discord drop khung hình
        let nw = Int(abs(track.naturalSize.width))
        let nh = Int(abs(track.naturalSize.height))
        if nw > profile.width + 16 || nh > profile.height + 16 {
            return false
        }
        if track.estimatedDataRate > Float(profile.maxBitrateKbps * 1300) {
            return false
        }

        guard let reader = try? AVAssetReader(asset: asset) else { return false }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return false }
        reader.add(output)
        guard reader.startReading() else { return false }
        defer { reader.cancelReading() }

        var prevPts: Double = -Double.infinity
        var sawKeyFrame = false
        var checked = 0
        while checked < 60, let sb = output.copyNextSampleBuffer() {
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            if pts.isFinite {
                // Nếu có B-frame (PTS nhảy lùi so với frame trước) -> dùng Full-Video H.264 Cache để mượt tuyệt đối
                if pts + 0.0005 < prevPts {
                    return false
                }
                prevPts = pts
            }
            if HardwareH264Encoder.isKeyFrame(sb) {
                sawKeyFrame = true
            }
            checked += 1
        }
        return sawKeyFrame && checked > 0
    }

    /// Tính kích thước chẵn vừa trong profile mà vẫn giữ đúng tỷ lệ gốc (không làm méo video hoặc lệch kích thước encoder)
    static func computeTargetSize(naturalSize: CGSize, maxWidth: Int, maxHeight: Int) -> (Int, Int) {
        let nw = Double(abs(naturalSize.width))
        let nh = Double(abs(naturalSize.height))
        guard nw > 16, nh > 16 else { return (maxWidth, maxHeight) }
        let scale = min(Double(maxWidth) / nw, Double(maxHeight) / nh, 1.0)
        var w = Int((nw * scale).rounded())
        var h = Int((nh * scale).rounded())
        w = max(160, (w / 2) * 2)
        h = max(120, (h / 2) * 2)
        return (w, h)
    }

    /// Phát lặp vô hạn (Loop ∞) FULL VIDEO (.mp4/.mov), Audio (.mp3/.m4a/.wav -> màn hình đen), hoặc mẫu ảo
    /// 0% GPU chạy nền 24/7: Direct H.264 Passthrough HOẶC Full-Video Progressive `.h264bin` Disk Stream!
    func start(
        source: TreoMediaSource,
        profile: DiscordStreamProfile,
        includeAudio: Bool,
        onVideoFrame: @escaping (Data, Double) -> Void,
        onAudioFrame: ((Data) -> Void)? = nil,
        onLog: ((String) -> Void)? = nil
    ) {
        stop()
        requestKeyFrame()
        bgLoopCache.reset()

        // 1. Luồng Video
        videoTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            if source.isVirtualPattern || source.isAudioOnly || source.url == nil {
                // Mẫu ảo (sóng màu) hoặc màn hình đen (file nhạc .mp3/.wav)
                let encFps = source.isAudioOnly ? min(profile.fps, 15) : min(profile.fps, 30)
                let encW = source.isAudioOnly ? 1280 : profile.width
                let encH = source.isAudioOnly ? 720 : profile.height
                let encBitrate = source.isAudioOnly ? 500 : profile.bitrateKbps
                let encMaxBitrate = source.isAudioOnly ? 800 : profile.maxBitrateKbps

                var encoder: HardwareH264Encoder? = HardwareH264Encoder(
                    width: encW,
                    height: encH,
                    fps: encFps,
                    bitrateKbps: encBitrate,
                    maxBitrateKbps: encMaxBitrate
                )
                defer { encoder?.invalidate() }

                let frameDurationMs = 1000.0 / Double(encFps)
                let frameDurationNs = UInt64(frameDurationMs * 1_000_000.0)
                let cmDuration = CMTime(value: 1, timescale: CMTimeScale(encFps))
                var frameIndex: Int64 = 0
                var nextTick = DispatchTime.now().uptimeNanoseconds
                var loggedFirst = false
                var loggedBgFallback = false

                let staticBlackPB = source.isAudioOnly
                    ? HardwareH264Encoder.makeSyntheticPixelBuffer(width: encW, height: encH, frameIndex: 0, blackOnly: true)
                    : nil

                while !Task.isCancelled {
                    nextTick &+= frameDurationNs
                    let wantKey = (frameIndex % Int64(encFps * 2) == 0) || self.consumeKeyFrameRequest()
                    let inBg = self.isBackgroundMode

                    if (inBg || encoder == nil || encoder?.needsRebuild == true) && self.bgLoopCache.hasCachedFrames {
                        if !loggedBgFallback {
                            loggedBgFallback = true
                            onLog?("🌙 Đã chuyển mẫu ảo/màn đen sang chạy nền (0% GPU).")
                        }
                        if let cached = self.bgLoopCache.nextFrame(forceKey: wantKey) {
                            onVideoFrame(cached, frameDurationMs)
                        }
                        frameIndex += 1
                    } else {
                        if !inBg && (encoder == nil || encoder?.needsRebuild == true) {
                            encoder?.invalidate()
                            encoder = HardwareH264Encoder(
                                width: encW,
                                height: encH,
                                fps: encFps,
                                bitrateKbps: encBitrate,
                                maxBitrateKbps: encMaxBitrate
                            )
                            if encoder != nil && loggedBgFallback {
                                loggedBgFallback = false
                            }
                        }

                        let pb = staticBlackPB ?? HardwareH264Encoder.makeSyntheticPixelBuffer(
                            width: encW,
                            height: encH,
                            frameIndex: Int(frameIndex),
                            blackOnly: false
                        )
                        if let pixelBuffer = pb, let enc = encoder {
                            let pts = CMTime(value: frameIndex, timescale: CMTimeScale(encFps))
                            enc.encode(
                                pixelBuffer: pixelBuffer,
                                pts: pts,
                                duration: cmDuration,
                                forceKeyFrame: wantKey,
                                onError: { st in
                                    if !self.bgLoopCache.hasCachedFrames {
                                        onLog?("⚠️ VideoToolbox tạm ngưng (OSStatus \(st)), chuyển sang nền...")
                                    }
                                }
                            ) { annexB, isKey in
                                self.bgLoopCache.record(frame: annexB, isKey: isKey)
                                if !loggedFirst {
                                    loggedFirst = true
                                    onLog?("🎬 H.264 Encoder OK (\(encW)x\(encH)@\(encFps)fps | Frame đầu: \(annexB.count)B, Key=\(isKey))")
                                }
                                onVideoFrame(annexB, frameDurationMs)
                            }
                        }
                        frameIndex += 1
                    }

                    let now = DispatchTime.now().uptimeNanoseconds
                    if nextTick > now {
                        try? await Task.sleep(nanoseconds: nextTick - now)
                    } else if now - nextTick > 200_000_000 {
                        nextTick = now
                    }
                }
            } else if let url = source.url {
                let probeAsset = AVURLAsset(url: url)
                guard let probeTrack = probeAsset.tracks(withMediaType: .video).first else {
                    onLog?("⚠️ File \(source.title) không có track video")
                    return
                }

                // NHÁNH A: DIRECT H.264 PASSTHROUGH (0% GPU — đọc thẳng H.264 từ file MP4/MOV gốc, Full Video 24/7!)
                if TreoMediaBroadcastEngine.canUseDirectH264Passthrough(asset: probeAsset, track: probeTrack, profile: profile) {
                    onLog?("⚡ H.264 Direct Passthrough (Full Video • 0% GPU chạy nền): \(source.title)")
                    var loggedFirst = false

                    while !Task.isCancelled {
                        let asset = AVURLAsset(url: url)
                        guard let videoTrack = asset.tracks(withMediaType: .video).first,
                              let reader = try? AVAssetReader(asset: asset) else {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            continue
                        }
                        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
                        output.alwaysCopiesSampleData = false
                        guard reader.canAdd(output) else { break }
                        reader.add(output)
                        guard reader.startReading() else {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            continue
                        }

                        let nominalFps = Double(videoTrack.nominalFrameRate)
                        let effFps = (nominalFps >= 5 && nominalFps <= 60) ? nominalFps : 30.0
                        let defaultStepMs = 1000.0 / effFps
                        var prevPtsSec: Double = -1.0
                        var nextTick = DispatchTime.now().uptimeNanoseconds

                        while !Task.isCancelled && reader.status == .reading {
                            guard let sb = output.copyNextSampleBuffer() else { break }
                            let isKey = HardwareH264Encoder.isKeyFrame(sb)
                            let curPts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
                            let deltaMs: Double
                            if prevPtsSec >= 0 && curPts.isFinite && curPts > prevPtsSec && (curPts - prevPtsSec) < 0.5 {
                                deltaMs = (curPts - prevPtsSec) * 1000.0
                            } else {
                                deltaMs = defaultStepMs
                            }
                            if curPts.isFinite { prevPtsSec = curPts }

                            let stepNs = UInt64(max(8.0, min(200.0, deltaMs)) * 1_000_000.0)
                            nextTick &+= stepNs

                            if let annexB = HardwareH264Encoder.extractAnnexB(from: sb, includeParameterSets: isKey),
                               !annexB.isEmpty {
                                if !loggedFirst {
                                    loggedFirst = true
                                    onLog?("🎬 H.264 Passthrough OK (\(Int(effFps))fps | Frame đầu: \(annexB.count)B, Key=\(isKey))")
                                }
                                onVideoFrame(annexB, deltaMs)
                            }

                            let now = DispatchTime.now().uptimeNanoseconds
                            if nextTick > now {
                                try? await Task.sleep(nanoseconds: nextTick - now)
                            } else if now - nextTick > 250_000_000 {
                                nextTick = now
                            }
                        }

                        reader.cancelReading()
                        self.requestKeyFrame()
                    }
                    return
                }

                // NHÁNH B: FULL-VIDEO PROGRESSIVE H.264 DISK STREAM (0% GPU — KHÔNG LẶP ĐOẠN NGẮN KHI THOÁT APP!)
                let cacheSession = H264FullVideoCacheManager.shared.getOrCreateSession(
                    url: url,
                    title: source.title,
                    profile: profile
                )
                cacheSession.startOrResumePreparation()

                // Đợi file cache được tạo & có ít nhất 1 khung đầu tiên (~50–150ms)
                while !Task.isCancelled && cacheSession.validByteLength <= H264FullVideoCacheSession.headerSize {
                    if let err = cacheSession.failedError {
                        onLog?("❌ Lỗi chuẩn bị video chạy nền: \(err)")
                        return
                    }
                    try? await Task.sleep(nanoseconds: 25_000_000)
                }
                guard !Task.isCancelled else { return }

                var readHandle: FileHandle? = try? FileHandle(forReadingFrom: cacheSession.cacheURL)
                defer { try? readHandle?.close() }

                var offset: Int64 = H264FullVideoCacheSession.headerSize
                var sentFirstKey = false
                var loggedFirst = false
                var nextTick = DispatchTime.now().uptimeNanoseconds

                while !Task.isCancelled {
                    if readHandle == nil {
                        readHandle = try? FileHandle(forReadingFrom: cacheSession.cacheURL)
                        if readHandle == nil {
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            continue
                        }
                    }

                    let validLen = cacheSession.validByteLength
                    if offset + 9 > validLen {
                        if cacheSession.isComplete {
                            // Đã phát hết FULL VIDEO từ đầu đến cuối -> lặp lại từ đầu!
                            offset = H264FullVideoCacheSession.headerSize
                            nextTick = DispatchTime.now().uptimeNanoseconds
                            continue
                        } else if cacheSession.isPreparing && !cacheSession.isBackgroundMode {
                            // Đang mã hóa tiếp ở tốc độ phần cứng (20x–50x) -> chờ 20ms cho khung mới
                            try? await Task.sleep(nanoseconds: 20_000_000)
                            nextTick = DispatchTime.now().uptimeNanoseconds
                            continue
                        } else if validLen > H264FullVideoCacheSession.headerSize {
                            // Người dùng thoát app giữa chừng khi video rất dài đang tối ưu -> lặp toàn bộ phần đã tối ưu
                            offset = H264FullVideoCacheSession.headerSize
                            nextTick = DispatchTime.now().uptimeNanoseconds
                            continue
                        } else {
                            if let err = cacheSession.failedError {
                                onLog?("❌ Dừng luồng video: \(err)")
                                break
                            }
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            continue
                        }
                    }

                    guard let fh = readHandle else { continue }
                    let record: (deltaMicros: UInt32, isKey: Bool, payload: Data)? = autoreleasepool {
                        do {
                            try fh.seek(toOffset: UInt64(offset))
                            guard let hdr = try fh.read(upToCount: 9), hdr.count == 9 else { return nil }
                            let deltaMicros = (UInt32(hdr[0]) << 24) | (UInt32(hdr[1]) << 16) | (UInt32(hdr[2]) << 8) | UInt32(hdr[3])
                            let isKey = (hdr[4] != 0)
                            let payloadLen = (UInt32(hdr[5]) << 24) | (UInt32(hdr[6]) << 16) | (UInt32(hdr[7]) << 8) | UInt32(hdr[8])
                            guard payloadLen > 0, payloadLen <= 4_000_000, offset + 9 + Int64(payloadLen) <= cacheSession.validByteLength else {
                                return nil
                            }
                            guard let payload = try fh.read(upToCount: Int(payloadLen)), payload.count == Int(payloadLen) else {
                                return nil
                            }
                            return (deltaMicros, isKey, payload)
                        } catch {
                            return nil
                        }
                    }

                    guard let rec = record else {
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        continue
                    }

                    offset += 9 + Int64(rec.payload.count)

                    if !sentFirstKey {
                        if !rec.isKey { continue }
                        sentFirstKey = true
                    }

                    let deltaMs = max(8.0, min(250.0, Double(rec.deltaMicros) / 1000.0))
                    let stepNs = UInt64(deltaMs * 1_000_000.0)
                    nextTick &+= stepNs

                    if !loggedFirst {
                        loggedFirst = true
                        onLog?("🎬 Full-Video 0% GPU Stream OK (Frame đầu: \(rec.payload.count)B, Key=\(rec.isKey) • Thoát app phát trọn video!)")
                    }
                    onVideoFrame(rec.payload, deltaMs)

                    let now = DispatchTime.now().uptimeNanoseconds
                    if nextTick > now {
                        try? await Task.sleep(nanoseconds: nextTick - now)
                    } else if now - nextTick > 250_000_000 {
                        nextTick = now
                    }
                }
            }
        }

        // 2. Luồng Audio cho Go Live (nếu includeAudio == true và có file thật)
        if includeAudio, let onAudio = onAudioFrame, let url = source.url, !source.isVirtualPattern {
            audioTask = Task.detached(priority: .userInitiated) {
                guard let decoder = AudioTrackDecoder(url: url), !decoder.leftSamples.isEmpty else {
                    return
                }
                guard let opusEnc = NativeOpusEncoder() else { return }

                let leftAll = decoder.leftSamples
                let rightAll = decoder.rightSamples
                let totalSamples = leftAll.count
                var samplePos = 0
                var nextTick = DispatchTime.now().uptimeNanoseconds

                while !Task.isCancelled {
                    nextTick &+= 20_000_000
                    if samplePos + 960 > totalSamples {
                        samplePos = 0
                    }
                    let chunkL = Array(leftAll[samplePos..<(samplePos + 960)])
                    let chunkR = Array(rightAll[samplePos..<(samplePos + 960)])
                    samplePos += 960

                    if let opus = opusEnc.encode(leftChannel: chunkL, rightChannel: chunkR) {
                        onAudio(opus)
                    }

                    let now = DispatchTime.now().uptimeNanoseconds
                    if nextTick > now {
                        try? await Task.sleep(nanoseconds: nextTick - now)
                    } else if now - nextTick > 100_000_000 {
                        nextTick = now
                    }
                }
            }
        }
    }
}
