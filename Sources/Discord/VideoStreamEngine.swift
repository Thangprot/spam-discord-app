import Foundation
import AVFoundation
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
    private var hasLoggedEncodeErr = false

    init?(width: Int, height: Int, fps: Int, bitrateKbps: Int, maxBitrateKbps: Int) {
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

        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: NSNumber(value: 0))
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: self.fps * 2))
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 2.0))
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
        if encStatus != noErr && !hasLoggedEncodeErr {
            hasLoggedEncodeErr = true
            onError?(encStatus)
        }
    }

    private static func isKeyFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
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

    private static func extractAnnexB(from sampleBuffer: CMSampleBuffer, includeParameterSets: Bool) -> Data? {
        let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]
        var output = Data()

        if includeParameterSets, let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var paramCount: Int = 0
            let cntStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                fmt,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &paramCount,
                nalUnitHeaderLengthOut: nil
            )
            if cntStatus == noErr && paramCount > 0 {
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

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return output.isEmpty ? nil : output
        }

        let totalLength = CMBlockBufferGetDataLength(blockBuffer)
        guard totalLength > 4 else {
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
        while offset + 4 <= totalLength {
            let naluLen = Int(
                (UInt32(contiguousBytes[offset]) << 24)
                | (UInt32(contiguousBytes[offset + 1]) << 16)
                | (UInt32(contiguousBytes[offset + 2]) << 8)
                | UInt32(contiguousBytes[offset + 3])
            )
            offset += 4
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
// MARK: - DISCORD GO-LIVE STREAM MEDIA SESSION (STREAM CONNECTION + DAVE E2EE)
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
    private var udpKeepAliveTask: Task<Void, Never>?

    private let udpClient = DiscordVoiceUDPClient()
    private let videoPacketizer = DiscordRtpVideoPacketizer()
    private let transportNonce = TransportNonceBox()
    private let packetLock = NSLock()

    private var audioSsrc: Int = 0
    private var videoSsrc: Int = 0
    private var rtxSsrc: Int = 0
    private var secretKey: Data?
    private var encryptionMode: String = "aead_aes256_gcm_rtpsize"
    private var voiceSeq: Int = -1
    private var daveSession: DaveE2EESession?

    private var rtpAudioSeq: UInt16 = UInt16.random(in: 0...65535)
    private var rtpAudioTs: UInt32 = UInt32.random(in: 0...4_000_000)
    private var udpKeepAliveCounter: UInt32 = 0

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
        hasSentIdentify = false
        hasSentSelectProtocol = false
        hasLoggedDaveReady = false
        hasLoggedVideoStart = false
        hasLoggedDaveVidErr = false
        hasLoggedWaitingDave = false
        voiceSeq = -1
        transportNonce.reset()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 604800
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.urlSession = session

        let ws = session.webSocketTask(with: vUrl)
        ws.maximumMessageSize = 32 * 1024 * 1024
        self.wsTask = ws
        ws.resume()
        log("Bắt tay Stream Gateway v8: \(vUrl.absoluteString)")

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
                self.videoPacketizer.configure(ssrc: UInt32(truncatingIfNeeded: self.videoSsrc))

                let ip = d["ip"] as? String ?? ""
                let port = (d["port"] as? Int) ?? (d["port"] as? NSNumber)?.intValue ?? 0
                let modes = d["modes"] as? [String] ?? []
                if modes.contains("aead_aes256_gcm_rtpsize") {
                    self.encryptionMode = "aead_aes256_gcm_rtpsize"
                } else if modes.contains("aead_xchacha20_poly1305_rtpsize") {
                    self.encryptionMode = "aead_xchacha20_poly1305_rtpsize"
                } else {
                    self.encryptionMode = "aead_aes256_gcm_rtpsize"
                }

                // Gửi Op 12 VIDEO ban đầu (tắt) giống BaseMediaConnection.ts rồi mới mở sau Op 4
                await sendJSON([
                    "op": 12,
                    "d": ["audio_ssrc": audioSsrc, "video_ssrc": 0, "rtx_ssrc": 0, "streams": []]
                ])

                log("Stream Ready! AudioSSRC=\(audioSsrc), VideoSSRC=\(videoSsrc), UDP=\(ip):\(port)")
                startUDPHandshake(ip: ip, port: port)
            }
        case 4: // Session Description
            if let d = json["d"] as? [String: Any] {
                if let mode = d["mode"] as? String, !mode.isEmpty {
                    self.encryptionMode = mode
                }
                let vCodec = d["video_codec"] as? String ?? "?"
                let aCodec = d["audio_codec"] as? String ?? "?"
                if let keyArr = d["secret_key"] as? [Int] {
                    self.secretKey = Data(keyArr.map { UInt8($0 & 0xFF) })
                } else if let keyArr = d["secret_key"] as? [UInt8] {
                    self.secretKey = Data(keyArr)
                }

                let daveVer = (d["dave_protocol_version"] as? Int)
                    ?? (d["dave_protocol_version"] as? NSNumber)?.intValue
                    ?? 0
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

                self.isReady = true
                await setVideoAttributes(
                    enabled: true,
                    width: targetWidth,
                    height: targetHeight,
                    fps: targetFps,
                    maxBitrateKbps: targetMaxBitrateKbps
                )
                await setSpeaking(true)
                let silence = Data([0xF8, 0xFF, 0xFE])
                for _ in 0..<5 { sendOpusPacket(silence) }
                log("✅ Go Live sẵn sàng (\(encryptionMode) | A:\(aCodec) V:\(vCodec) | DAVE v\(daveVer))!")
                onReady?()
                onRequestKeyFrame?()
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

    private func startUDPKeepAlive() {
        udpKeepAliveTask?.cancel()
        udpKeepAliveCounter = 0
        udpKeepAliveTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                guard let self = self, !self.isStopped else { break }
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

    private func startUDPHandshake(ip: String, port: Int) {
        guard udpClient.connect(ip: ip, port: UInt16(port)) else {
            log("Lỗi mở UDP socket cho Stream")
            return
        }
        Task.detached { [weak self] in
            guard let self = self, !self.isStopped else { return }
            var extIP = ip
            var extPort = port
            if let disc = self.udpClient.discoverIP(ssrc: UInt32(truncatingIfNeeded: self.audioSsrc)) {
                extIP = disc.ip
                extPort = Int(disc.port)
            }
            self.startUDPKeepAlive()
            await self.sendSelectProtocol(ip: extIP, port: extPort)
        }
    }

    private func sendSelectProtocol(ip: String, port: Int) async {
        guard !hasSentSelectProtocol else { return }
        hasSentSelectProtocol = true
        let codecs: [[String: Any]] = [
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
        let payload: [String: Any] = [
            "op": 1,
            "d": [
                "protocol": "udp",
                "codecs": codecs,
                "data": [
                    "address": ip,
                    "port": port,
                    "mode": self.encryptionMode
                ]
            ]
        ]
        await sendJSON(payload)
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
        guard isReady, !isStopped, let key = secretKey, key.count == 32 else { return }

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

        let pkts = videoPacketizer.sendFrame(
            annexBFrame: frameToSend,
            frametimeMs: frametimeMs,
            secretKey: key,
            encryptionMode: encryptionMode,
            nonceBox: transportNonce,
            udpClient: udpClient
        )

        if !hasLoggedVideoStart && pkts > 0 {
            hasLoggedVideoStart = true
            log("📺 Đang phát hình H.264 Go Live (\(targetWidth)x\(targetHeight)@\(targetFps)fps | \(frameToSend.count)B → \(pkts) gói RTP)!")
        }
    }

    func sendOpusPacket(_ opusPayload: Data) {
        guard isReady, !isStopped, let key = secretKey, key.count == 32 else { return }

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

        packetLock.lock()
        let seq = rtpAudioSeq
        let ts = rtpAudioTs
        rtpAudioSeq = rtpAudioSeq &+ 1
        rtpAudioTs = rtpAudioTs &+ 960
        packetLock.unlock()

        let nonceVal = transportNonce.next()

        var header = [UInt8](repeating: 0, count: 12)
        header[0] = 0x80
        header[1] = 0x78
        header[2] = UInt8((seq >> 8) & 0xFF)
        header[3] = UInt8(seq & 0xFF)
        header[4] = UInt8((ts >> 24) & 0xFF)
        header[5] = UInt8((ts >> 16) & 0xFF)
        header[6] = UInt8((ts >> 8) & 0xFF)
        header[7] = UInt8(ts & 0xFF)
        header[8] = UInt8((audioSsrc >> 24) & 0xFF)
        header[9] = UInt8((audioSsrc >> 16) & 0xFF)
        header[10] = UInt8((audioSsrc >> 8) & 0xFF)
        header[11] = UInt8(audioSsrc & 0xFF)

        let noncePrefix: [UInt8] = [
            UInt8((nonceVal >> 24) & 0xFF),
            UInt8((nonceVal >> 16) & 0xFF),
            UInt8((nonceVal >> 8) & 0xFF),
            UInt8(nonceVal & 0xFF)
        ]

        if encryptionMode == "aead_xchacha20_poly1305_rtpsize" {
            var nonce24 = [UInt8](repeating: 0, count: 24)
            nonce24[0] = noncePrefix[0]
            nonce24[1] = noncePrefix[1]
            nonce24[2] = noncePrefix[2]
            nonce24[3] = noncePrefix[3]

            let ct: Data? = key.withUnsafeBytes { keyRaw in
                header.withUnsafeBufferPointer { aadBuf in
                    mediaPayload.withUnsafeBytes { ptRaw in
                        guard let kPtr = keyRaw.bindMemory(to: UInt8.self).baseAddress,
                              let pPtr = ptRaw.bindMemory(to: UInt8.self).baseAddress else { return nil }
                        let out = dave_xchacha20_poly1305_encrypt(kPtr, nonce24, aadBuf.baseAddress, header.count, pPtr, mediaPayload.count)
                        defer { dave_buffer_free(out) }
                        guard let ptr = out.ptr, out.len > 0 else { return nil }
                        return Data(bytes: ptr, count: out.len)
                    }
                }
            }
            if let ctData = ct {
                var packet = Data(header)
                packet.append(ctData)
                packet.append(contentsOf: noncePrefix)
                udpClient.sendPacket(packet)
            }
        } else {
            var nonce12 = [UInt8](repeating: 0, count: 12)
            nonce12[0] = noncePrefix[0]
            nonce12[1] = noncePrefix[1]
            nonce12[2] = noncePrefix[2]
            nonce12[3] = noncePrefix[3]

            if let nonce = try? AES.GCM.Nonce(data: nonce12),
               let sealed = try? AES.GCM.seal(mediaPayload, using: SymmetricKey(data: key), nonce: nonce, authenticating: Data(header)) {
                var packet = Data(header)
                packet.append(sealed.ciphertext)
                packet.append(sealed.tag)
                packet.append(contentsOf: noncePrefix)
                udpClient.sendPacket(packet)
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        log("Stream WS đóng [Mã \(closeCode.rawValue)]: \(reasonStr)")
    }

    func stop() {
        isStopped = true
        isReady = false
        heartbeatTask?.cancel(); heartbeatTask = nil
        udpKeepAliveTask?.cancel(); udpKeepAliveTask = nil
        listenTask?.cancel(); listenTask = nil
        wsTask?.cancel(with: .goingAway, reason: nil); wsTask = nil
        urlSession?.invalidateAndCancel(); urlSession = nil
        daveSession?.destroy(); daveSession = nil
        udpClient.close()
    }
}

// ==============================================================================
// MARK: - SHARED MEDIA BROADCAST ENGINE (LOOP ∞ VIDEO + AUDIO -> ALL TOKENS)
// ==============================================================================

final class TreoMediaBroadcastEngine {
    private var videoTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private let keyFrameLock = NSLock()
    private var pendingKeyFrame = true

    func requestKeyFrame() {
        keyFrameLock.lock()
        pendingKeyFrame = true
        keyFrameLock.unlock()
    }

    private func consumeKeyFrameRequest() -> Bool {
        keyFrameLock.lock()
        let v = pendingKeyFrame
        pendingKeyFrame = false
        keyFrameLock.unlock()
        return v
    }

    func stop() {
        videoTask?.cancel()
        videoTask = nil
        audioTask?.cancel()
        audioTask = nil
    }

    /// Tính kích thước chẵn vừa trong profile mà vẫn giữ đúng tỷ lệ gốc (không làm méo video hoặc lệch kích thước encoder)
    private static func computeTargetSize(naturalSize: CGSize, maxWidth: Int, maxHeight: Int) -> (Int, Int) {
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

    /// Phát lặp vô hạn (Loop ∞) file Video (.mp4/.mov), Audio (.mp3/.m4a/.wav -> màn hình đen), hoặc mẫu ảo
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

        // 1. Luồng Video (H.264 Hardware VideoToolbox)
        videoTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            if source.isVirtualPattern || source.isAudioOnly || source.url == nil {
                let encFps = source.isAudioOnly ? min(profile.fps, 15) : min(profile.fps, 30)
                let encW = source.isAudioOnly ? 1280 : profile.width
                let encH = source.isAudioOnly ? 720 : profile.height
                let encBitrate = source.isAudioOnly ? 500 : profile.bitrateKbps
                let encMaxBitrate = source.isAudioOnly ? 800 : profile.maxBitrateKbps

                guard let encoder = HardwareH264Encoder(
                    width: encW,
                    height: encH,
                    fps: encFps,
                    bitrateKbps: encBitrate,
                    maxBitrateKbps: encMaxBitrate
                ) else {
                    onLog?("❌ Không thể khởi tạo Hardware H.264 Encoder (\(encW)x\(encH))")
                    return
                }
                defer { encoder.invalidate() }

                let frameDurationMs = 1000.0 / Double(encFps)
                let frameDurationNs = UInt64(frameDurationMs * 1_000_000.0)
                let cmDuration = CMTime(value: 1, timescale: CMTimeScale(encFps))
                var frameIndex: Int64 = 0
                var nextTick = DispatchTime.now().uptimeNanoseconds
                var loggedFirst = false

                let staticBlackPB = source.isAudioOnly
                    ? HardwareH264Encoder.makeSyntheticPixelBuffer(width: encW, height: encH, frameIndex: 0, blackOnly: true)
                    : nil

                while !Task.isCancelled {
                    nextTick &+= frameDurationNs
                    let pb = staticBlackPB ?? HardwareH264Encoder.makeSyntheticPixelBuffer(
                        width: encW,
                        height: encH,
                        frameIndex: Int(frameIndex),
                        blackOnly: false
                    )
                    if let pixelBuffer = pb {
                        let forceKey = (frameIndex % Int64(encFps * 2) == 0) || self.consumeKeyFrameRequest()
                        let pts = CMTime(value: frameIndex, timescale: CMTimeScale(encFps))
                        encoder.encode(
                            pixelBuffer: pixelBuffer,
                            pts: pts,
                            duration: cmDuration,
                            forceKeyFrame: forceKey,
                            onError: { st in onLog?("❌ Lỗi VideoToolbox H.264 (OSStatus \(st))") }
                        ) { annexB, isKey in
                            if !loggedFirst {
                                loggedFirst = true
                                onLog?("🎬 H.264 Encoder OK (\(encW)x\(encH)@\(encFps)fps | Frame đầu: \(annexB.count)B, Key=\(isKey))")
                            }
                            onVideoFrame(annexB, frameDurationMs)
                        }
                    }
                    frameIndex += 1

                    let now = DispatchTime.now().uptimeNanoseconds
                    if nextTick > now {
                        try? await Task.sleep(nanoseconds: nextTick - now)
                    } else if now - nextTick > 200_000_000 {
                        nextTick = now
                    }
                }
            } else if let url = source.url {
                // File Video thật (.mp4, .mov, .m4v): Khớp đúng kích thước AVAssetReaderTrackOutput == VTCompressionSession
                let probeAsset = AVURLAsset(url: url)
                guard let probeTrack = probeAsset.tracks(withMediaType: .video).first else {
                    onLog?("⚠️ File \(source.title) không có track video")
                    return
                }
                let (encW, encH) = TreoMediaBroadcastEngine.computeTargetSize(
                    naturalSize: probeTrack.naturalSize,
                    maxWidth: profile.width,
                    maxHeight: profile.height
                )

                guard let encoder = HardwareH264Encoder(
                    width: encW,
                    height: encH,
                    fps: profile.fps,
                    bitrateKbps: profile.bitrateKbps,
                    maxBitrateKbps: profile.maxBitrateKbps
                ) else {
                    onLog?("❌ Không thể khởi tạo Hardware H.264 Encoder (\(encW)x\(encH)) cho \(source.title)")
                    return
                }
                defer { encoder.invalidate() }

                let targetFps = Double(profile.fps)
                let minFrameMs = 1000.0 / targetFps
                let minFrameNs = UInt64(minFrameMs * 1_000_000.0)
                var globalFrameIndex: Int64 = 0
                var loggedFirst = false

                while !Task.isCancelled {
                    let asset = AVURLAsset(url: url)
                    guard let videoTrack = asset.tracks(withMediaType: .video).first,
                          let reader = try? AVAssetReader(asset: asset) else {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }

                    // Ép AVAssetReader xuất NV12 đúng kích thước encW x encH để khớp 100% với HardwareH264Encoder
                    let outputSettings: [String: Any] = [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
                        kCVPixelBufferWidthKey as String: encW,
                        kCVPixelBufferHeightKey as String: encH,
                        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
                    ]
                    let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
                    trackOutput.alwaysCopiesSampleData = false
                    guard reader.canAdd(trackOutput) else { break }
                    reader.add(trackOutput)
                    guard reader.startReading() else {
                        onLog?("❌ AVAssetReader lỗi mở video: \(reader.error?.localizedDescription ?? "unknown")")
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }

                    let nominalFps = Double(videoTrack.nominalFrameRate)
                    let effFps = (nominalFps >= 5 && nominalFps <= 60) ? min(nominalFps, targetFps) : min(30.0, targetFps)
                    let stepMs = max(minFrameMs, 1000.0 / effFps)
                    let stepNs = max(minFrameNs, UInt64(stepMs * 1_000_000.0))
                    let cmDur = CMTime(seconds: stepMs / 1000.0, preferredTimescale: 90_000)

                    var nextTick = DispatchTime.now().uptimeNanoseconds
                    var lastEmittedPtsSec: Double = -1.0

                    while !Task.isCancelled && reader.status == .reading {
                        guard let sb = trackOutput.copyNextSampleBuffer() else { break }
                        guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }

                        let srcPts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
                        if lastEmittedPtsSec >= 0 && srcPts >= lastEmittedPtsSec && (srcPts - lastEmittedPtsSec) < (minFrameMs / 1000.0) * 0.75 {
                            continue
                        }
                        lastEmittedPtsSec = srcPts
                        nextTick &+= stepNs

                        let forceKey = (globalFrameIndex % Int64(max(15, Int(effFps * 2))) == 0) || self.consumeKeyFrameRequest()
                        let outPts = CMTime(value: globalFrameIndex * Int64(90_000.0 / effFps), timescale: 90_000)
                        encoder.encode(
                            pixelBuffer: pb,
                            pts: outPts,
                            duration: cmDur,
                            forceKeyFrame: forceKey,
                            onError: { st in onLog?("❌ Lỗi VideoToolbox H.264 (OSStatus \(st))") }
                        ) { annexB, isKey in
                            if !loggedFirst {
                                loggedFirst = true
                                onLog?("🎬 H.264 Encoder OK (\(encW)x\(encH)@\(Int(effFps))fps | Frame đầu: \(annexB.count)B, Key=\(isKey))")
                            }
                            onVideoFrame(annexB, stepMs)
                        }
                        globalFrameIndex += 1

                        let now = DispatchTime.now().uptimeNanoseconds
                        if nextTick > now {
                            try? await Task.sleep(nanoseconds: nextTick - now)
                        } else if now - nextTick > 200_000_000 {
                            nextTick = now
                        }
                    }

                    reader.cancelReading()
                    self.requestKeyFrame()
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
