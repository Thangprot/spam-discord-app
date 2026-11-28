import Foundation
import Darwin
import AVFoundation
import Accelerate
import SwiftUI
import UIKit

// ==============================================================================
// MARK: - AUDIO SOURCE, VOICE CHANGER & STEREO PANNING MODELS
// ==============================================================================

enum AudioSourceMode: String, CaseIterable, Identifiable {
    case musicOnly = "Xả Nhạc"
    case liveMicOnly = "Nói Qua Mic"
    case musicAndMic = "Nhạc + Mic"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .musicOnly: return "music.note.list"
        case .liveMicOnly: return "mic.fill"
        case .musicAndMic: return "waveform.and.mic"
        }
    }

    var subtitle: String {
        switch self {
        case .musicOnly: return "Phát file nhạc / âm thanh trong danh sách"
        case .liveMicOnly: return "Thu giọng trực tiếp từ Mic iPhone phát qua dàn Token"
        case .musicAndMic: return "Vừa phát nhạc nền vừa nói qua Mic đè lên cùng lúc"
        }
    }

    var usesMicrophone: Bool {
        self == .liveMicOnly || self == .musicAndMic
    }
}

enum VoiceChangerPreset: String, CaseIterable, Identifiable {
    case normal = "Giọng Gốc"
    case deep = "Giọng Trầm"
    case superDeep = "Trầm Nặng (Boss)"
    case female = "Giọng Nữ / Cao"
    case chipmunk = "Chipmunk"
    case robot = "Robot Máy Móc"
    case demon = "Ác Quỷ (Demon)"
    case megaphone = "Loa Phóng Thanh"
    case echoKaraoke = "Vang Phòng Thu"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .normal: return "person.wave.2.fill"
        case .deep: return "waveform.path.ecg"
        case .superDeep: return "speaker.zzz.fill"
        case .female: return "sparkles"
        case .chipmunk: return "hare.fill"
        case .robot: return "cpu.fill"
        case .demon: return "flame.fill"
        case .megaphone: return "megaphone.fill"
        case .echoKaraoke: return "music.mic"
        }
    }

    var defaultPitchSemitones: Float {
        switch self {
        case .normal: return 0
        case .deep: return -4.5
        case .superDeep: return -7.5
        case .female: return 4.5
        case .chipmunk: return 8.0
        case .robot: return 0
        case .demon: return -5.5
        case .megaphone: return 0
        case .echoKaraoke: return 0
        }
    }
}

enum StereoEarMode: String, CaseIterable, Identifiable {
    case left = "Tai Trái"
    case center = "Ở Giữa"
    case right = "Tai Phải"
    case auto8D = "Đảo 8D"
    case custom = "Tùy Chỉnh"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .left: return "ear.badge.waveform"
        case .center: return "headphones"
        case .right: return "ear.fill"
        case .auto8D: return "infinity.circle.fill"
        case .custom: return "slider.horizontal.below.rectangle"
        }
    }
}

// ==============================================================================
// MARK: - LOW-LATENCY REALTIME MICROPHONE CAPTURE ENGINE (48kHz FLOAT32)
// ==============================================================================

final class LiveMicCaptureEngine {
    static let shared = LiveMicCaptureEngine()

    private var lock = os_unfair_lock_s()
    private let capacity = 48000 // 1.0s circular buffer @ 48kHz
    private var ringBuffer: [Float]
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private var availableCount: Int = 0
    private var latestInputRMS: Float = 0

    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private(set) var isCapturing: Bool = false
    private var hasPrimedJitterBuffer: Bool = false

    private init() {
        self.ringBuffer = [Float](repeating: 0, count: capacity)
    }

    var currentInputLevel: Float {
        os_unfair_lock_lock(&lock)
        let v = latestInputRMS
        os_unfair_lock_unlock(&lock)
        return v
    }

    static func requestPermission() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { cont in
                session.requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func startCapture() throws {
        if isCapturing, let eng = audioEngine, eng.isRunning {
            return
        }
        stopCapture()

        let session = AVAudioSession.sharedInstance()
        let opts: AVAudioSession.CategoryOptions = [
            .defaultToSpeaker,
            .allowBluetooth,
            .allowBluetoothA2DP,
            .allowAirPlay,
            .mixWithOthers
        ]
        try session.setCategory(.playAndRecord, mode: .default, options: opts)
        try? session.setPreferredSampleRate(48000.0)
        try? session.setPreferredIOBufferDuration(0.01) // 10ms low latency
        try session.setActive(true, options: [])

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw NSError(domain: "LiveMic", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không nhận diện được phần cứng Mic iPhone."])
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000.0,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "LiveMic", code: -2, userInfo: [NSLocalizedDescriptionKey: "Không tạo được định dạng 48kHz cho Mic."])
        }

        let conv = AVAudioConverter(from: hwFormat, to: targetFormat)
        self.converter = conv

        os_unfair_lock_lock(&lock)
        writeIndex = 0
        readIndex = 0
        availableCount = 0
        hasPrimedJitterBuffer = false
        latestInputRMS = 0
        os_unfair_lock_unlock(&lock)

        let ratio = 48000.0 / hwFormat.sampleRate
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] pcmBuf, _ in
            guard let self = self else { return }
            self.ingestHardwareBuffer(pcmBuf, targetFormat: targetFormat, ratio: ratio)
        }

        engine.prepare()
        try engine.start()
        self.audioEngine = engine
        self.isCapturing = true
    }

    func stopCapture(restorePlaybackSession: Bool = true) {
        if let eng = audioEngine {
            eng.inputNode.removeTap(onBus: 0)
            eng.stop()
        }
        audioEngine = nil
        converter = nil
        isCapturing = false

        os_unfair_lock_lock(&lock)
        writeIndex = 0
        readIndex = 0
        availableCount = 0
        hasPrimedJitterBuffer = false
        latestInputRMS = 0
        os_unfair_lock_unlock(&lock)

        if restorePlaybackSession {
            BackgroundManager.shared.applyAudioSessionCategory()
        }
    }

    private func ingestHardwareBuffer(_ pcmBuf: AVAudioPCMBuffer, targetFormat: AVAudioFormat, ratio: Double) {
        let inFrames = Int(pcmBuf.frameLength)
        guard inFrames > 0 else { return }

        // Nếu phần cứng đã là 48kHz Float32 thì copy trực tiếp siêu nhanh
        if abs(pcmBuf.format.sampleRate - 48000.0) < 1.0,
           pcmBuf.format.commonFormat == .pcmFormatFloat32,
           let ch = pcmBuf.floatChannelData {
            pushMonoSamples(UnsafeBufferPointer(start: ch[0], count: inFrames))
            return
        }

        guard let conv = self.converter else { return }
        let outCap = AVAudioFrameCount(ceil(Double(inFrames) * ratio)) + 128
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCap) else { return }

        var supplied = false
        var err: NSError?
        let status = conv.convert(to: outBuf, error: &err) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return pcmBuf
        }
        if status != .error, err == nil, outBuf.frameLength > 0, let outCh = outBuf.floatChannelData {
            pushMonoSamples(UnsafeBufferPointer(start: outCh[0], count: Int(outBuf.frameLength)))
        }
    }

    private func pushMonoSamples(_ samples: UnsafeBufferPointer<Float>) {
        let n = samples.count
        guard n > 0 else { return }

        var sumSq: Float = 0
        for i in 0..<n {
            let s = samples[i]
            sumSq += s * s
        }
        let rms = sqrt(sumSq / Float(n))

        os_unfair_lock_lock(&lock)
        latestInputRMS = latestInputRMS * 0.65 + rms * 0.35

        // Giữ độ trễ cực thấp (~20-60ms): nếu buffer dồn quá 4800 mẫu (100ms), xả bớt phần cũ để giọng nói luôn tức thời!
        let maxAllowedLatencySamples = 4800
        if availableCount + n > maxAllowedLatencySamples {
            let drop = (availableCount + n) - 2880 // giữ đúng 60ms gần nhất
            if drop > 0 && drop <= availableCount {
                readIndex = (readIndex + drop) % capacity
                availableCount -= drop
            }
        }

        for i in 0..<n {
            ringBuffer[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) % capacity
        }
        availableCount = min(capacity, availableCount + n)
        if availableCount >= 1440 { // Đệm tối thiểu 30ms trước khi xuất để chống khựng
            hasPrimedJitterBuffer = true
        }
        os_unfair_lock_unlock(&lock)
    }

    /// Đọc đúng 960 mẫu (20ms @ 48kHz) vào mảng đích không cấp phát bộ nhớ mới
    func popFrame960(into out: inout [Float], noiseGateThreshold: Float) -> Bool {
        os_unfair_lock_lock(&lock)
        guard isCapturing, hasPrimedJitterBuffer, availableCount >= 960 else {
            if availableCount == 0 {
                hasPrimedJitterBuffer = false
            }
            os_unfair_lock_unlock(&lock)
            for i in 0..<960 { out[i] = 0 }
            return false
        }

        var sumSq: Float = 0
        for i in 0..<960 {
            let v = ringBuffer[readIndex]
            readIndex = (readIndex + 1) % capacity
            out[i] = v
            sumSq += v * v
        }
        availableCount -= 960
        os_unfair_lock_unlock(&lock)

        let rms = sqrt(sumSq / 960.0)
        if noiseGateThreshold > 0 && rms < noiseGateThreshold {
            for i in 0..<960 { out[i] = 0 }
            return false
        }
        return true
    }
}

// ==============================================================================
// MARK: - ZERO-ALLOCATION REAL-TIME VOICE CHANGER, XẢ MIC PREAMP & STEREO PANNER
// ==============================================================================

final class RealtimeAudioDSPProcessor {
    // Dual-tap Hann-windowed pitch shifter buffer (power-of-two mask 2047)
    private let pitchBufSize = 2048
    private let pitchMask = 2047
    private var pitchBufL: [Float]
    private var pitchBufR: [Float]
    private var pitchWriteIdx: Int = 0
    private var pitchPhase: Float = 0
    private var demonPhase: Float = 0

    // Robot RingMod + Metallic Comb Resonator
    private var ringPhase1: Float = 0
    private var ringPhase2: Float = 0
    private let combSize = 256
    private var combBufL: [Float]
    private var combBufR: [Float]
    private var combIdx: Int = 0

    // Stereo Ping-Pong Echo / Karaoke Delay (up to 400ms = 19,200 samples @ 48kHz)
    private let echoSize = 19200
    private var echoBufL: [Float]
    private var echoBufR: [Float]
    private var echoIdx: Int = 0

    // EQ & Filter states
    private var hpStateL: Float = 0
    private var hpStateR: Float = 0
    private var prevInL: Float = 0
    private var prevInR: Float = 0
    private var lpStateL: Float = 0
    private var lpStateR: Float = 0
    private var bassStateL: Float = 0
    private var bassStateR: Float = 0
    private var midPresenceL: Float = 0
    private var midPresenceR: Float = 0

    // 8D Auto-Pan LFO
    private var autoPanPhase: Float = 0
    // Anti-click seek / mute envelope
    private var fadeGain: Float = 1.0

    init() {
        self.pitchBufL = [Float](repeating: 0, count: pitchBufSize)
        self.pitchBufR = [Float](repeating: 0, count: pitchBufSize)
        self.combBufL = [Float](repeating: 0, count: combSize)
        self.combBufR = [Float](repeating: 0, count: combSize)
        self.echoBufL = [Float](repeating: 0, count: echoSize)
        self.echoBufR = [Float](repeating: 0, count: echoSize)
    }

    func triggerSeekMicroFade() {
        fadeGain = 0.0
    }

    @inline(__always)
    private func readFractional(_ buf: [Float], writeIdx: Int, delaySamples: Float) -> Float {
        let clampedDelay = max(2.0, min(Float(pitchBufSize - 4), delaySamples))
        let readPos = Float(writeIdx) - clampedDelay
        let i0 = Int(floor(readPos))
        let frac = readPos - Float(i0)
        let idx0 = (i0 & pitchMask + pitchBufSize) & pitchMask
        let idx1 = ((i0 + 1) & pitchMask + pitchBufSize) & pitchMask
        return buf[idx0] * (1.0 - frac) + buf[idx1] * frac
    }

    /// Xử lý hiệu ứng Đổi Giọng (Trầm, Nữ, Robot, Ác Quỷ, Loa Phường, Echo...) cho khung 960 mẫu
    func applyVoiceChanger(
        left: inout [Float],
        right: inout [Float],
        preset: VoiceChangerPreset,
        pitchOffsetSemitones: Float,
        echoAmount: Float
    ) {
        let totalSemis = preset.defaultPitchSemitones + pitchOffsetSemitones
        let needPitchShift = abs(totalSemis) > 0.08
        let pitchRatio: Float = needPitchShift ? pow(2.0, totalSemis / 12.0) : 1.0
        let grainSize: Float = 1440.0 // 30ms grain @ 48kHz

        if needPitchShift || preset == .demon {
            let phaseStep = (1.0 - pitchRatio) / grainSize
            let demonStep = (1.0 - pow(2.0, -9.0 / 12.0)) / grainSize

            for i in 0..<960 {
                let inL = left[i]
                let inR = right[i]
                pitchBufL[pitchWriteIdx] = inL
                pitchBufR[pitchWriteIdx] = inR

                pitchPhase += phaseStep
                if pitchPhase >= 1.0 { pitchPhase -= floor(pitchPhase) }
                if pitchPhase < 0.0 { pitchPhase += ceil(-pitchPhase) }

                let p2 = pitchPhase >= 0.5 ? (pitchPhase - 0.5) : (pitchPhase + 0.5)
                let d1 = pitchPhase * grainSize + 4.0
                let d2 = p2 * grainSize + 4.0
                let w1: Float = 0.5 * (1.0 - cos(2.0 * Float.pi * pitchPhase))
                let w2: Float = 1.0 - w1

                var outL = readFractional(pitchBufL, writeIdx: pitchWriteIdx, delaySamples: d1) * w1
                         + readFractional(pitchBufL, writeIdx: pitchWriteIdx, delaySamples: d2) * w2
                var outR = readFractional(pitchBufR, writeIdx: pitchWriteIdx, delaySamples: d1) * w1
                         + readFractional(pitchBufR, writeIdx: pitchWriteIdx, delaySamples: d2) * w2

                if preset == .demon {
                    demonPhase += demonStep
                    if demonPhase >= 1.0 { demonPhase -= floor(demonPhase) }
                    if demonPhase < 0.0 { demonPhase += ceil(-demonPhase) }
                    let dp2 = demonPhase >= 0.5 ? (demonPhase - 0.5) : (demonPhase + 0.5)
                    let dw1: Float = 0.5 * (1.0 - cos(2.0 * Float.pi * demonPhase))
                    let dw2: Float = 1.0 - dw1
                    let subL = readFractional(pitchBufL, writeIdx: pitchWriteIdx, delaySamples: demonPhase * grainSize + 4.0) * dw1
                             + readFractional(pitchBufL, writeIdx: pitchWriteIdx, delaySamples: dp2 * grainSize + 4.0) * dw2
                    let subR = readFractional(pitchBufR, writeIdx: pitchWriteIdx, delaySamples: demonPhase * grainSize + 4.0) * dw1
                             + readFractional(pitchBufR, writeIdx: pitchWriteIdx, delaySamples: dp2 * grainSize + 4.0) * dw2
                    outL = tanh((outL * 0.85 + subL * 0.55) * 1.6)
                    outR = tanh((outR * 0.85 + subR * 0.55) * 1.6)
                }

                left[i] = outL
                right[i] = outR
                pitchWriteIdx = (pitchWriteIdx + 1) & pitchMask
            }
        }

        // Robot Metallic Vocoder / Ring Modulator
        if preset == .robot {
            let step1: Float = 2.0 * Float.pi * 58.0 / 48000.0
            let step2: Float = 2.0 * Float.pi * 116.0 / 48000.0
            let combDelay = 178 // ~270Hz metallic resonance
            for i in 0..<960 {
                ringPhase1 += step1
                if ringPhase1 > 2.0 * Float.pi { ringPhase1 -= 2.0 * Float.pi }
                ringPhase2 += step2
                if ringPhase2 > 2.0 * Float.pi { ringPhase2 -= 2.0 * Float.pi }

                let mod = 0.68 * sin(ringPhase1) + 0.32 * sin(ringPhase2)
                let readComb = (combIdx - combDelay + combSize) % combSize
                let cL = left[i] * mod + combBufL[readComb] * 0.52
                let cR = right[i] * mod + combBufR[readComb] * 0.52
                combBufL[combIdx] = max(-1.2, min(1.2, cL))
                combBufR[combIdx] = max(-1.2, min(1.2, cR))
                combIdx = (combIdx + 1) % combSize

                left[i] = tanh(cL * 1.45)
                right[i] = tanh(cR * 1.45)
            }
        }

        // Loa Phóng Thanh / Bộ Đàm (Bandpass + Crunch Overdrive)
        if preset == .megaphone {
            var bpHpL: Float = 0, bpHpR: Float = 0, bpPrevL: Float = 0, bpPrevR: Float = 0
            var bpLpL: Float = 0, bpLpR: Float = 0
            for i in 0..<960 {
                bpHpL = 0.92 * (bpHpL + left[i] - bpPrevL)
                bpPrevL = left[i]
                bpLpL += 0.38 * (bpHpL - bpLpL)
                left[i] = tanh(bpLpL * 3.2)

                bpHpR = 0.92 * (bpHpR + right[i] - bpPrevR)
                bpPrevR = right[i]
                bpLpR += 0.38 * (bpHpR - bpLpR)
                right[i] = tanh(bpLpR * 3.2)
            }
        }

        // Echo / Vang Phòng Thu
        let effEcho = max(echoAmount, preset == .echoKaraoke ? 0.42 : (preset == .demon ? 0.25 : 0.0))
        if effEcho > 0.01 {
            let delayL = 8640  // 180ms
            let delayR = 12960 // 270ms ping-pong
            let fb: Float = min(0.62, 0.22 + effEcho * 0.38)
            let wet: Float = min(0.65, effEcho * 0.65)
            for i in 0..<960 {
                let rIdxL = (echoIdx - delayL + echoSize) % echoSize
                let rIdxR = (echoIdx - delayR + echoSize) % echoSize
                let delayedL = echoBufL[rIdxL]
                let delayedR = echoBufR[rIdxR]

                let inL = left[i]
                let inR = right[i]
                echoBufL[echoIdx] = max(-1.0, min(1.0, inL + delayedR * fb))
                echoBufR[echoIdx] = max(-1.0, min(1.0, inR + delayedL * fb))
                echoIdx = (echoIdx + 1) % echoSize

                left[i] = inL + delayedL * wet
                right[i] = inR + delayedR * wet
            }
        }
    }

    /// Xử lý EQ, Khuếch Đại Xả Mic Siêu To (lên tới 2000%!) và Định Vị Tai Trái / Phải / Giữa / 8D
    func applyMasterLoudnessAndStereoPan(
        left: inout [Float],
        right: inout [Float],
        volume: Float,
        boostMultiplier: Float,
        bassAmount: Float,
        isCleanMode: Bool,
        isMaxMode: Bool,
        audioFX: SpamAudioFX,
        earMode: StereoEarMode,
        manualPan: Float, // -1.0 (100% Trái) ... 0.0 (Giữa) ... +1.0 (100% Phải)
        auto8DSpeedHz: Float = 0.22
    ) -> Float {
        // 1. Lọc ồn chủ động (150Hz – 10kHz)
        if isCleanMode {
            for i in 0..<960 {
                hpStateL = 0.98 * (hpStateL + left[i] - prevInL)
                prevInL = left[i]
                lpStateL += 0.75 * (hpStateL - lpStateL)
                left[i] = lpStateL

                hpStateR = 0.98 * (hpStateR + right[i] - prevInR)
                prevInR = right[i]
                lpStateR += 0.75 * (hpStateR - lpStateR)
                right[i] = lpStateR
            }
        }

        // 2. Tăng cường dải Bass & Presence độ rõ lời (2.5kHz - 3.5kHz giúp tai người nghe to gấp 3 lần!)
        let wantMax = isMaxMode || audioFX == .earrape
        if wantMax || bassAmount > 0 || audioFX == .bassBoost {
            let bassFactor: Float = wantMax
                ? (2.2 + bassAmount / 45.0)
                : ((bassAmount / 45.0) + (audioFX == .bassBoost ? 1.15 : 0.0))
            let presenceFactor: Float = wantMax ? 1.75 : (boostMultiplier > 2.0 ? min(1.4, (boostMultiplier - 1.0) * 0.25) : 0.0)

            for i in 0..<960 {
                bassStateL += 0.26 * (left[i] - bassStateL)
                bassStateR += 0.26 * (right[i] - bassStateR)
                midPresenceL += 0.58 * (left[i] - midPresenceL)
                midPresenceR += 0.58 * (right[i] - midPresenceR)

                let hiMidL = midPresenceL - bassStateL
                let hiMidR = midPresenceR - bassStateR

                left[i] = left[i] + bassStateL * bassFactor + hiMidL * presenceFactor
                right[i] = right[i] + bassStateR * bassFactor + hiMidR * presenceFactor
            }
        }

        // 3. Bộ Khuếch Đại Xả Mic Đa Tầng (0% -> 2000% + Brickwall Hard/Soft Clipper đẩy kịch trần 0 dBFS!)
        let fxDrive: Float = (audioFX == .earrape) ? 3.5 : (isMaxMode ? 2.2 : 1.0)
        let totalDrive = max(0.0, volume * boostMultiplier * fxDrive)
        let hardClipBlend: Float = totalDrive > 3.0 ? min(0.78, (totalDrive - 3.0) / 14.0) : 0.0

        // 4. Tính toán góc Pan Trái / Phải / Giữa / 8D
        let step8D: Float = 2.0 * Float.pi * auto8DSpeedHz / 48000.0
        var peakAbs: Float = 0

        for i in 0..<960 {
            if fadeGain < 1.0 {
                fadeGain = min(1.0, fadeGain + 0.004) // ~5ms anti-click ramp khi tua nhạc
            }

            var sL = left[i] * totalDrive * fadeGain
            var sR = right[i] * totalDrive * fadeGain

            if totalDrive > 1.05 {
                // Kết hợp Soft Saturator (tanh) + Hard Brickwall Clipper để đạt công suất RMS cực đại kiểu Xả Mic!
                let softL = tanh(sL)
                let softR = tanh(sR)
                let hardL = max(-0.992, min(0.992, sL))
                let hardR = max(-0.992, min(0.992, sR))
                sL = softL * (1.0 - hardClipBlend) + hardL * hardClipBlend
                sR = softR * (1.0 - hardClipBlend) + hardR * hardClipBlend
            } else {
                sL = max(-0.995, min(0.995, sL))
                sR = max(-0.995, min(0.995, sR))
            }

            let pan: Float
            switch earMode {
            case .left:
                pan = -1.0
            case .center:
                pan = 0.0
            case .right:
                pan = 1.0
            case .auto8D:
                autoPanPhase += step8D
                if autoPanPhase > 2.0 * Float.pi { autoPanPhase -= 2.0 * Float.pi }
                pan = sin(autoPanPhase)
            case .custom:
                pan = max(-1.0, min(1.0, manualPan))
            }

            if abs(pan) > 0.005 {
                // Gom cả 2 kênh sang đúng bên tai chọn (khi pan = -1.0 thì tai phải = 0 tuyệt đối, 100% âm thanh dồn sang tai trái!)
                let monoSum = (sL + sR) * 0.58
                let absP = abs(pan)
                let baseL = sL * (1.0 - absP) + monoSum * absP
                let baseR = sR * (1.0 - absP) + monoSum * absP
                if pan < 0 {
                    sL = max(-0.995, min(0.995, baseL * (1.0 + absP * 0.25)))
                    sR = baseR * max(0.0, 1.0 + pan) // pan = -1.0 => sR = 0.0!
                } else {
                    sL = baseL * max(0.0, 1.0 - pan) // pan = +1.0 => sL = 0.0!
                    sR = max(-0.995, min(0.995, baseR * (1.0 + absP * 0.25)))
                }
            }

            left[i] = sL
            right[i] = sR

            let m = max(abs(sL), abs(sR))
            if m > peakAbs { peakAbs = m }
        }

        return min(1.0, peakAbs)
    }
}


// ==============================================================================
// MARK: - THREAD-SAFE SESSION & REALTIME MUSIC STATE BOXES (ZERO MAINACTOR STALL)
// ==============================================================================

final class ThreadSafeVoiceSessionBox {
    private var lock = os_unfair_lock_s()
    private var items: [VoiceGatewaySession] = []

    func set(_ list: [VoiceGatewaySession]) {
        os_unfair_lock_lock(&lock)
        items = list
        os_unfair_lock_unlock(&lock)
    }

    func get() -> [VoiceGatewaySession] {
        os_unfair_lock_lock(&lock)
        let copy = items
        os_unfair_lock_unlock(&lock)
        return copy
    }
}

final class RealtimeMusicEngineState {
    private var lock = os_unfair_lock_s()

    struct Config {
        var sourceMode: AudioSourceMode = .musicOnly
        var isPaused: Bool = false
        var isMicMuted: Bool = false
        var autoDuckMusic: Bool = true
        var volume: Float = 1.0
        var boostMultiplier: Float = 1.0
        var micGainMultiplier: Float = 3.0
        var micNoiseGate: Float = 0.0035
        var bassAmount: Float = 0.0
        var isCleanMode: Bool = false
        var isMaxMode: Bool = false
        var playbackSpeed: Float = 1.0
        var audioFX: SpamAudioFX = .normal
        var voicePreset: VoiceChangerPreset = .normal
        var pitchSemitones: Float = 0.0
        var echoAmount: Float = 0.0
        var earMode: StereoEarMode = .center
        var manualPan: Float = 0.0
        var decoder: AudioTrackDecoder? = nil
        var trackGeneration: UInt64 = 0
        var sessions: [VoiceGatewaySession] = []
    }

    private var cfg = Config()
    private var pendingSeekSample: Double? = nil
    private var stopRequested: Bool = false

    func resetForStart(_ block: (inout Config) -> Void) {
        os_unfair_lock_lock(&lock)
        stopRequested = false
        pendingSeekSample = 0
        block(&cfg)
        os_unfair_lock_unlock(&lock)
    }

    func update(_ block: (inout Config) -> Void) {
        os_unfair_lock_lock(&lock)
        block(&cfg)
        os_unfair_lock_unlock(&lock)
    }

    func requestSeek(sampleIndex: Double) {
        os_unfair_lock_lock(&lock)
        pendingSeekSample = max(0, sampleIndex)
        os_unfair_lock_unlock(&lock)
    }

    func requestStop() {
        os_unfair_lock_lock(&lock)
        stopRequested = true
        cfg.sessions = []
        os_unfair_lock_unlock(&lock)
    }

    func pollTick() -> (shouldStop: Bool, seekSample: Double?, config: Config) {
        os_unfair_lock_lock(&lock)
        let stop = stopRequested
        let seek = pendingSeekSample
        pendingSeekSample = nil
        let snap = cfg
        os_unfair_lock_unlock(&lock)
        return (stop, seek, snap)
    }
}

// ==============================================================================
// MARK: - REAL-TIME MACH PACED CLOCK HELPER (CHỐNG GIẬT TIẾNG 100% — 20.000ms)
// ==============================================================================

enum MachRealtimeClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t(numer: 1, denom: 1)
        mach_timebase_info(&info)
        return info
    }()

    @inline(__always)
    static func nanosToAbs(_ nanos: UInt64) -> UInt64 {
        let denom = UInt64(max(1, timebase.denom))
        let numer = UInt64(max(1, timebase.numer))
        let (hi, lo) = nanos.multipliedFullWidth(by: denom)
        return numer > 0 ? ((hi == 0) ? (lo / numer) : UInt64((Double(nanos) * Double(denom)) / Double(numer))) : nanos
    }

    @inline(__always)
    static func absToNanos(_ absTicks: UInt64) -> UInt64 {
        let numer = UInt64(max(1, timebase.numer))
        let denom = UInt64(max(1, timebase.denom))
        let (hi, lo) = absTicks.multipliedFullWidth(by: numer)
        return (hi == 0) ? (lo / denom) : UInt64((Double(absTicks) * Double(numer)) / Double(denom))
    }
}

// ==============================================================================
// MARK: - PARALLEL LIVE MIC FOR TREO ROOM 24/7 (NÓI QUA MIC VÀO PHÒNG ĐANG TREO)
// ==============================================================================

final class TreoRoomLiveMicParams {
    private var lock = os_unfair_lock_s()
    private var _micGain: Float = 3.0
    private var _boost: Float = 2.0
    private var _bass: Float = 20.0
    private var _noiseGate: Float = 0.004
    private var _isMaxMode: Bool = false
    private var _isMuted: Bool = false
    private var _voicePreset: VoiceChangerPreset = .normal
    private var _pitchSemis: Float = 0.0
    private var _echoAmt: Float = 0.0
    private var _earMode: StereoEarMode = .center
    private var _manualPan: Float = 0.0

    struct Snapshot {
        let micGain: Float
        let boost: Float
        let bass: Float
        let noiseGate: Float
        let isMaxMode: Bool
        let isMuted: Bool
        let voicePreset: VoiceChangerPreset
        let pitchSemis: Float
        let echoAmt: Float
        let earMode: StereoEarMode
        let manualPan: Float
    }

    func update(_ block: (inout SnapshotMutable) -> Void) {
        os_unfair_lock_lock(&lock)
        var m = SnapshotMutable(
            micGain: _micGain, boost: _boost, bass: _bass, noiseGate: _noiseGate,
            isMaxMode: _isMaxMode, isMuted: _isMuted, voicePreset: _voicePreset,
            pitchSemis: _pitchSemis, echoAmt: _echoAmt, earMode: _earMode, manualPan: _manualPan
        )
        block(&m)
        _micGain = m.micGain; _boost = m.boost; _bass = m.bass; _noiseGate = m.noiseGate
        _isMaxMode = m.isMaxMode; _isMuted = m.isMuted; _voicePreset = m.voicePreset
        _pitchSemis = m.pitchSemis; _echoAmt = m.echoAmt; _earMode = m.earMode; _manualPan = m.manualPan
        os_unfair_lock_unlock(&lock)
    }

    struct SnapshotMutable {
        var micGain: Float
        var boost: Float
        var bass: Float
        var noiseGate: Float
        var isMaxMode: Bool
        var isMuted: Bool
        var voicePreset: VoiceChangerPreset
        var pitchSemis: Float
        var echoAmt: Float
        var earMode: StereoEarMode
        var manualPan: Float
    }

    func read() -> Snapshot {
        os_unfair_lock_lock(&lock)
        let s = Snapshot(
            micGain: _micGain, boost: _boost, bass: _bass, noiseGate: _noiseGate,
            isMaxMode: _isMaxMode, isMuted: _isMuted, voicePreset: _voicePreset,
            pitchSemis: _pitchSemis, echoAmt: _echoAmt, earMode: _earMode, manualPan: _manualPan
        )
        os_unfair_lock_unlock(&lock)
        return s
    }
}

@MainActor
final class TreoRoomLiveMicManager: ObservableObject {
    static let shared = TreoRoomLiveMicManager()

    @Published var isEnabled: Bool = false
    @Published var isMuted: Bool = false { didSet { syncParams() } }
    @Published var micGain: Float = 3.0 { didSet { syncParams() } }        // 100% -> 1500%
    @Published var boostMultiplier: Float = 2.0 { didSet { syncParams() } } // 100% -> 2000%
    @Published var bassAmount: Float = 20.0 { didSet { syncParams() } }
    @Published var isMaxMode: Bool = false { didSet { syncParams() } }
    @Published var voicePreset: VoiceChangerPreset = .normal { didSet { syncParams() } }
    @Published var pitchSemitones: Float = 0.0 { didSet { syncParams() } }
    @Published var echoAmount: Float = 0.0 { didSet { syncParams() } }
    @Published var earMode: StereoEarMode = .center { didSet { syncParams() } }
    @Published var manualPan: Float = 0.0 { didSet { syncParams() } }
    @Published var inputLevel: Float = 0.0
    @Published var errorMessage: String? = nil

    private let rtParams = TreoRoomLiveMicParams()
    private var workerThread: Thread?
    private var stopFlag = NSLock()
    private var _shouldStop = false
    private var previousRoomMute: Bool? = nil

    private init() {
        syncParams()
    }

    private func syncParams() {
        let mg = micGain, bm = boostMultiplier, ba = bassAmount
        let mx = isMaxMode, mt = isMuted, vp = voicePreset
        let ps = pitchSemitones, ec = echoAmount, em = earMode, mp = manualPan
        rtParams.update { s in
            s.micGain = mg
            s.boost = bm
            s.bass = ba
            s.isMaxMode = mx
            s.isMuted = mt
            s.voicePreset = vp
            s.pitchSemis = ps
            s.echoAmt = ec
            s.earMode = em
            s.manualPan = mp
        }
    }

    func setLiveMicEnabled(_ on: Bool) {
        if on {
            startInTreoRoom()
        } else {
            stopInTreoRoom()
        }
    }

    private func startInTreoRoom() {
        let room = VoiceRoomManager.shared
        guard room.isRunning, !room.sessions.isEmpty else {
            errorMessage = "Hãy bấm Bắt Đầu Treo Room trước khi bật Nói Qua Mic!"
            isEnabled = false
            return
        }
        if MusicStreamManager.shared.isPlaying && MusicStreamManager.shared.sourceMode.usesMicrophone {
            errorMessage = "Mic đang được sử dụng bên tab Xả Mic & Nhạc."
            isEnabled = false
            return
        }

        Task { @MainActor in
            let granted = await LiveMicCaptureEngine.requestPermission()
            guard granted else {
                self.errorMessage = "Chưa cấp quyền Microphone trong Cài đặt iPhone!"
                self.isEnabled = false
                return
            }
            do {
                try LiveMicCaptureEngine.shared.startCapture()
            } catch {
                self.errorMessage = error.localizedDescription
                self.isEnabled = false
                return
            }

            self.errorMessage = nil
            self.isEnabled = true
            self.previousRoomMute = room.selfMute
            if room.selfMute {
                room.updateToggles(mute: false, deaf: room.selfDeaf, video: room.selfVideo)
            }
            room.setSpeaking(true)
            room.addLog("🎙️ Đã BẬT Nói Qua Mic trực tiếp qua dàn Token Treo Room!")
            self.launchRealtimeWorker()
        }
    }

    func stopInTreoRoom() {
        stopFlag.lock()
        _shouldStop = true
        stopFlag.unlock()
        workerThread?.cancel()
        workerThread = nil

        if !(MusicStreamManager.shared.isPlaying && MusicStreamManager.shared.sourceMode.usesMicrophone) {
            LiveMicCaptureEngine.shared.stopCapture()
        }

        let wasEnabled = isEnabled
        isEnabled = false
        inputLevel = 0

        let room = VoiceRoomManager.shared
        if wasEnabled && room.isRunning {
            let silence = Data([0xF8, 0xFF, 0xFE])
            for _ in 0..<4 { room.broadcastOpusPacket(silence) }
            room.setSpeaking(false)
            if let prevMute = previousRoomMute {
                room.updateToggles(mute: prevMute, deaf: room.selfDeaf, video: room.selfVideo)
            }
            room.addLog("⏹ Đã TẮT Nói Qua Mic trong Treo Room.")
        }
        previousRoomMute = nil
    }

    private func launchRealtimeWorker() {
        stopFlag.lock()
        _shouldStop = false
        stopFlag.unlock()

        let paramsRef = self.rtParams
        let sessionBox = VoiceRoomManager.shared.audioSessionsBox
        let thread = Thread { [weak self] in
            Thread.current.name = "QT.TreoLiveMic.20ms"
            Thread.current.qualityOfService = .userInteractive
            Thread.current.threadPriority = 1.0

            guard let encoder = NativeOpusEncoder(sampleRate: 48000, channels: 2, bitRate: 128000) else { return }
            let dsp = RealtimeAudioDSPProcessor()
            var mono = [Float](repeating: 0, count: 960)
            var left = [Float](repeating: 0, count: 960)
            var right = [Float](repeating: 0, count: 960)
            let silenceOpus = Data([0xF8, 0xFF, 0xFE])

            let stepTicks = MachRealtimeClock.nanosToAbs(20_000_000)
            let maxLagTicks = MachRealtimeClock.nanosToAbs(80_000_000)
            var nextDeadline = mach_absolute_time()
            var tickCounter = 0
            var holdoverFrames = 0

            while !Thread.current.isCancelled {
                if let strong = self {
                    strong.stopFlag.lock()
                    let stopNow = strong._shouldStop
                    strong.stopFlag.unlock()
                    if stopNow { break }
                } else {
                    break
                }

                nextDeadline &+= stepTicks
                let cfg = paramsRef.read()
                let hasVoice = !cfg.isMuted && LiveMicCaptureEngine.shared.popFrame960(into: &mono, noiseGateThreshold: cfg.noiseGate)

                if hasVoice {
                    holdoverFrames = 12 // giữ thêm 240ms đuôi câu nói để không bị cụt chữ cuối
                } else if holdoverFrames > 0 {
                    holdoverFrames -= 1
                }

                var peak: Float = 0
                if hasVoice || holdoverFrames > 0 {
                    for i in 0..<960 {
                        let v = mono[i] * cfg.micGain
                        left[i] = v
                        right[i] = v
                    }
                    if cfg.voicePreset != .normal || abs(cfg.pitchSemis) > 0.08 || cfg.echoAmt > 0.01 {
                        dsp.applyVoiceChanger(
                            left: &left,
                            right: &right,
                            preset: cfg.voicePreset,
                            pitchOffsetSemitones: cfg.pitchSemis,
                            echoAmount: cfg.echoAmt
                        )
                    }
                    peak = dsp.applyMasterLoudnessAndStereoPan(
                        left: &left,
                        right: &right,
                        volume: 1.0,
                        boostMultiplier: cfg.boost,
                        bassAmount: cfg.bass,
                        isCleanMode: false,
                        isMaxMode: cfg.isMaxMode,
                        audioFX: .normal,
                        earMode: cfg.earMode,
                        manualPan: cfg.manualPan
                    )
                    if let opus = encoder.encode(leftChannel: left, rightChannel: right) {
                        let sessions = sessionBox.get()
                        for s in sessions where s.isVoiceUDPReady {
                            s.sendOpusPacket(opus)
                        }
                    }
                } else {
                    // Gửi khung im lặng chuẩn để đồng hồ RTP mượt liên tục
                    let sessions = sessionBox.get()
                    for s in sessions where s.isVoiceUDPReady {
                        s.sendOpusPacket(silenceOpus)
                    }
                }

                tickCounter += 1
                if tickCounter % 5 == 0 {
                    let levelToReport = peak
                    DispatchQueue.main.async { [weak self] in
                        self?.inputLevel = levelToReport
                    }
                }

                let now = mach_absolute_time()
                if nextDeadline > now {
                    mach_wait_until(nextDeadline)
                } else if now - nextDeadline > maxLagTicks {
                    nextDeadline = now
                }
            }
        }
        self.workerThread = thread
        thread.start()
    }
}

struct ParallelLiveMicDeckCard: View {
    @ObservedObject var liveMic = TreoRoomLiveMicManager.shared
    @State private var expanded = false

    private let accent = Color(red: 0.96, green: 0.26, blue: 0.36)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                    Image(systemName: liveMic.isMuted ? "mic.slash.fill" : "mic.and.signal.meter.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Nói Qua Mic (Xả Mic Trực Tiếp)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Text(liveMic.isEnabled ? "● LIVE" : "TREO ROOM")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(liveMic.isEnabled ? accent : accent.opacity(0.14))
                            .foregroundColor(liveMic.isEnabled ? .white : accent)
                            .clipShape(Capsule())
                    }
                    Text("Nói vào iPhone -> cả dàn Token phát to + đổi giọng + trái/phải")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { liveMic.isEnabled },
                    set: { liveMic.setLiveMicEnabled($0) }
                ))
                .labelsHidden()
                .tint(accent)
            }

            if let err = liveMic.errorMessage {
                Text("⚠️ \(err)")
                    .font(.caption2.bold())
                    .foregroundColor(.red)
            }

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(UIColor.tertiarySystemGroupedBackground))
                        Capsule()
                            .fill(LinearGradient(colors: [.green, .orange, .red], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * CGFloat(min(1.0, liveMic.inputLevel))))
                    }
                }
                .frame(height: 10)

                if liveMic.isEnabled {
                    Button {
                        liveMic.isMuted.toggle()
                    } label: {
                        Text(liveMic.isMuted ? "Mở Mic" : "Tạm Ngắt")
                            .font(.caption2.bold())
                            .foregroundColor(liveMic.isMuted ? .green : .orange)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background((liveMic.isMuted ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Thu gọn" : "Chỉnh Giọng & Độ To")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Chọn Giọng
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(VoiceChangerPreset.allCases) { vp in
                                let sel = (liveMic.voicePreset == vp)
                                Button {
                                    liveMic.voicePreset = vp
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: vp.icon).font(.system(size: 10, weight: .bold))
                                        Text(vp.rawValue).font(.system(size: 11, weight: .bold, design: .rounded))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(sel ? accent : Color(UIColor.tertiarySystemGroupedBackground), in: Capsule())
                                    .foregroundColor(sel ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Chọn Tai Trái / Giữa / Phải / 8D
                    HStack(spacing: 6) {
                        ForEach([StereoEarMode.left, .center, .right, .auto8D]) { em in
                            let sel = (liveMic.earMode == em)
                            Button {
                                liveMic.earMode = em
                            } label: {
                                Text(em == .left ? "◀ Trái" : (em == .right ? "Phải ▶" : (em == .center ? "● Giữa" : "🎧 8D")))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(sel ? Color.indigo : Color(UIColor.tertiarySystemGroupedBackground), in: Capsule())
                                    .foregroundColor(sel ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Độ nhạy Mic + Khuếch đại Xả Mic
                    HStack {
                        Text("Độ To Xả Mic: \(Int(liveMic.micGain * liveMic.boostMultiplier * 100))%")
                            .font(.caption.bold())
                            .foregroundColor(accent)
                        Spacer()
                        Toggle("MAX V9", isOn: $liveMic.isMaxMode)
                            .font(.caption2.bold())
                            .fixedSize()
                            .tint(.red)
                    }
                    Slider(value: $liveMic.boostMultiplier, in: 1.0...20.0, step: 0.5).tint(accent)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(liveMic.isEnabled ? accent.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: liveMic.isEnabled ? 1.5 : 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }
}
