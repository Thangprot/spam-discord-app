use std::io::ErrorKind;
use std::net::{IpAddr, Ipv4Addr, SocketAddr, UdpSocket};
use std::str::FromStr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use str0m::config::Fingerprint;
use str0m::format::{Codec, FormatParams};
use str0m::media::{Frequency, MediaKind, MediaTime, Mid, Pt};
use str0m::net::{Protocol, Receive};
use str0m::rtp::{Extension, ExtensionMap, ExtensionValues, SeqNo, Ssrc};
use str0m::{Candidate, Event, IceConnectionState, IceCreds, Input, Output, Rtc, RtcConfig};

const PT_OPUS: u8 = 120;
const PT_H264: u8 = 101;
const PT_H264_RTX: u8 = 102;
const VIDEO_RTP_MTU: usize = 1150;

enum WebRtcCmd {
    SetDiscordAnswer(String, mpsc::SyncSender<Result<(), String>>),
    SendOpus(Vec<u8>),
    SendH264(Vec<u8>, f64),
    Shutdown,
}

pub struct DiscordWebRtcTransport {
    offer_sdp: String,
    cmd_tx: mpsc::Sender<WebRtcCmd>,
    wake_sock: Option<UdpSocket>,
    wake_addr: SocketAddr,
    connected: Arc<AtomicBool>,
    closed: Arc<AtomicBool>,
    keyframe_requested: Arc<AtomicBool>,
    tx_video_packets: Arc<AtomicU64>,
    tx_audio_packets: Arc<AtomicU64>,
    worker: Option<JoinHandle<()>>,
}

fn discover_local_ipv4() -> Ipv4Addr {
    if let Ok(probe) = UdpSocket::bind("0.0.0.0:0") {
        if probe.connect("1.1.1.1:80").is_ok() {
            if let Ok(SocketAddr::V4(v4)) = probe.local_addr() {
                if !v4.ip().is_unspecified() {
                    return *v4.ip();
                }
            }
        }
    }
    Ipv4Addr::LOCALHOST
}

fn build_str0m_rtc(
    audio_ssrc: u32,
    video_ssrc: u32,
    rtx_ssrc: u32,
    local_cand_addr: SocketAddr,
) -> Result<(Rtc, String, String), String> {
    let mut cfg = RtcConfig::new()
        .set_rtp_mode(true)
        .set_send_buffer_audio(100)
        .set_send_buffer_video(2000)
        .clear_codecs()
        .clear_extension_map();

    cfg.codec_config().add_config(
        Pt::from(PT_OPUS),
        None,
        Codec::Opus,
        Frequency::FORTY_EIGHT_KHZ,
        Some(2),
        FormatParams {
            min_p_time: Some(10),
            use_inband_fec: Some(true),
            ..Default::default()
        },
    );
    cfg.codec_config().add_h264(
        Pt::from(PT_H264),
        Some(Pt::from(PT_H264_RTX)),
        true,
        0x42e01f,
    );

    let mut exts = ExtensionMap::empty();
    exts.set(1, Extension::AudioLevel);
    exts.set(2, Extension::AbsoluteSendTime);
    exts.set(3, Extension::TransportSequenceNumber);
    exts.set(5, Extension::PlayoutDelay);
    exts.set(13, Extension::VideoOrientation);
    exts.set(14, Extension::TransmissionTimeOffset);
    cfg = cfg.set_extension_map(exts);

    let mut rtc = cfg.build();

    let cand = Candidate::host(local_cand_addr, "udp")
        .map_err(|e| format!("Candidate::host failed: {e}"))?;
    rtc.add_local_candidate(cand);

    let (ufrag, pwd, fingerprint, cname) = {
        let mut direct = rtc.direct_api();
        direct.set_ice_controlling(true);
        direct.enable_twcc_feedback();

        let mid_audio = Mid::from("0");
        let mid_video = Mid::from("1");
        let audio_cname = direct
            .declare_media(mid_audio, MediaKind::Audio)
            .cname()
            .to_string();
        let _ = direct.declare_media(mid_video, MediaKind::Video);

        direct.declare_stream_tx(Ssrc::from(audio_ssrc), None, mid_audio, None);
        let rtx_opt = if rtx_ssrc != 0 && rtx_ssrc != video_ssrc {
            Some(Ssrc::from(rtx_ssrc))
        } else {
            None
        };
        direct.declare_stream_tx(Ssrc::from(video_ssrc), rtx_opt, mid_video, None);

        let creds = direct.local_ice_credentials();
        let fp = direct.local_dtls_fingerprint().to_string();
        (creds.ufrag, creds.pass, fp, audio_cname)
    };

    let offer_sdp = build_discord_offer_sdp(
        &ufrag,
        &pwd,
        &fingerprint,
        &cname,
        audio_ssrc,
        video_ssrc,
        rtx_ssrc,
        local_cand_addr,
    );

    Ok((rtc, offer_sdp, cname))
}

#[allow(clippy::too_many_arguments)]
fn build_discord_offer_sdp(
    ufrag: &str,
    pwd: &str,
    fingerprint: &str,
    cname: &str,
    audio_ssrc: u32,
    video_ssrc: u32,
    rtx_ssrc: u32,
    local_addr: SocketAddr,
) -> String {
    let ip = local_addr.ip();
    let port = local_addr.port();
    let mut s = String::with_capacity(1400);
    s.push_str("v=0\r\n");
    s.push_str("o=- 428194810293 2 IN IP4 127.0.0.1\r\n");
    s.push_str("s=-\r\n");
    s.push_str("t=0 0\r\n");
    s.push_str("a=group:BUNDLE 0 1\r\n");
    s.push_str("a=extmap-allow-mixed\r\n");
    s.push_str("a=msid-semantic: WMS *\r\n");

    // m=audio (mid 0)
    s.push_str(&format!("m=audio 9 UDP/TLS/RTP/SAVPF {PT_OPUS}\r\n"));
    s.push_str("c=IN IP4 0.0.0.0\r\n");
    s.push_str("a=rtcp:9 IN IP4 0.0.0.0\r\n");
    s.push_str(&format!("a=ice-ufrag:{ufrag}\r\n"));
    s.push_str(&format!("a=ice-pwd:{pwd}\r\n"));
    s.push_str("a=ice-options:trickle\r\n");
    s.push_str(&format!("a=fingerprint:{fingerprint}\r\n"));
    s.push_str("a=setup:actpass\r\n");
    s.push_str("a=mid:0\r\n");
    s.push_str("a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level\r\n");
    s.push_str("a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\n");
    s.push_str("a=extmap:5 http://www.webrtc.org/experiments/rtp-hdrext/playout-delay\r\n");
    s.push_str("a=sendrecv\r\n");
    s.push_str("a=rtcp-mux\r\n");
    s.push_str(&format!("a=rtpmap:{PT_OPUS} opus/48000/2\r\n"));
    s.push_str(&format!("a=fmtp:{PT_OPUS} minptime=10;useinbandfec=1;usedtx=1\r\n"));
    s.push_str(&format!("a=rtcp-fb:{PT_OPUS} transport-cc\r\n"));
    s.push_str(&format!("a=rtcp-fb:{PT_OPUS} nack\r\n"));
    s.push_str(&format!("a=ssrc:{audio_ssrc} cname:{cname}\r\n"));
    s.push_str(&format!(
        "a=candidate:1 1 udp 2122260223 {ip} {port} typ host\r\n"
    ));

    // m=video (mid 1)
    s.push_str(&format!(
        "m=video 9 UDP/TLS/RTP/SAVPF {PT_H264} {PT_H264_RTX}\r\n"
    ));
    s.push_str("c=IN IP4 0.0.0.0\r\n");
    s.push_str("a=rtcp:9 IN IP4 0.0.0.0\r\n");
    s.push_str(&format!("a=ice-ufrag:{ufrag}\r\n"));
    s.push_str(&format!("a=ice-pwd:{pwd}\r\n"));
    s.push_str("a=ice-options:trickle\r\n");
    s.push_str(&format!("a=fingerprint:{fingerprint}\r\n"));
    s.push_str("a=setup:actpass\r\n");
    s.push_str("a=mid:1\r\n");
    s.push_str("a=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\n");
    s.push_str("a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\n");
    s.push_str("a=extmap:5 http://www.webrtc.org/experiments/rtp-hdrext/playout-delay\r\n");
    s.push_str("a=extmap:13 urn:3gpp:video-orientation\r\n");
    s.push_str("a=extmap:14 urn:ietf:params:rtp-hdrext:toffset\r\n");
    s.push_str("a=sendrecv\r\n");
    s.push_str("a=rtcp-mux\r\n");
    s.push_str("a=rtcp-rsize\r\n");
    s.push_str(&format!("a=rtpmap:{PT_H264} H264/90000\r\n"));
    s.push_str(&format!(
        "a=fmtp:{PT_H264} level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f\r\n"
    ));
    s.push_str(&format!("a=rtpmap:{PT_H264_RTX} rtx/90000\r\n"));
    s.push_str(&format!("a=fmtp:{PT_H264_RTX} apt={PT_H264}\r\n"));
    s.push_str(&format!("a=rtcp-fb:{PT_H264} ccm fir\r\n"));
    s.push_str(&format!("a=rtcp-fb:{PT_H264} nack\r\n"));
    s.push_str(&format!("a=rtcp-fb:{PT_H264} nack pli\r\n"));
    s.push_str(&format!("a=rtcp-fb:{PT_H264} goog-remb\r\n"));
    s.push_str(&format!("a=rtcp-fb:{PT_H264} transport-cc\r\n"));
    if rtx_ssrc != 0 && rtx_ssrc != video_ssrc {
        s.push_str(&format!("a=ssrc-group:FID {video_ssrc} {rtx_ssrc}\r\n"));
        s.push_str(&format!("a=ssrc:{video_ssrc} cname:{cname}\r\n"));
        s.push_str(&format!("a=ssrc:{rtx_ssrc} cname:{cname}\r\n"));
    } else {
        s.push_str(&format!("a=ssrc:{video_ssrc} cname:{cname}\r\n"));
    }
    s.push_str(&format!(
        "a=candidate:1 1 udp 2122260223 {ip} {port} typ host\r\n"
    ));
    s
}

struct ParsedDiscordAnswer {
    ufrag: String,
    pwd: String,
    fingerprint: Fingerprint,
    candidates: Vec<Candidate>,
}

fn parse_discord_answer_sdp(raw_sdp: &str) -> Result<ParsedDiscordAnswer, String> {
    let mut ufrag = String::new();
    let mut pwd = String::new();
    let mut fp_str = String::new();
    let mut c_ip: Option<IpAddr> = None;
    let mut rtcp_port: Option<u16> = None;
    let mut candidates: Vec<Candidate> = Vec::new();

    for raw_line in raw_sdp.lines() {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }
        if let Some(v) = line.strip_prefix("a=ice-ufrag:") {
            ufrag = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("a=ice-pwd:") {
            pwd = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("a=fingerprint:") {
            fp_str = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("c=IN IP4 ") {
            if let Ok(ip) = v.trim().parse::<Ipv4Addr>() {
                c_ip = Some(IpAddr::V4(ip));
            }
        } else if let Some(v) = line.strip_prefix("c=IN IP6 ") {
            if let Ok(ip) = v.trim().parse::<IpAddr>() {
                c_ip = Some(ip);
            }
        } else if let Some(v) = line.strip_prefix("a=rtcp:") {
            if let Some(first) = v.split_whitespace().next() {
                if let Ok(p) = first.parse::<u16>() {
                    rtcp_port = Some(p);
                }
            }
        } else if line.starts_with("a=candidate:") || line.starts_with("candidate:") {
            if let Ok(cand) = Candidate::from_sdp_string(line) {
                if !candidates.contains(&cand) {
                    candidates.push(cand);
                }
            } else {
                // Manual fallback parse for Discord compact candidates:
                // a=candidate:1 1 UDP 2130706431 <ip> <port> typ host
                let body = line.strip_prefix("a=").unwrap_or(line);
                let parts: Vec<&str> = body.split_whitespace().collect();
                if parts.len() >= 6 {
                    if let (Ok(ip), Ok(port)) = (parts[4].parse::<IpAddr>(), parts[5].parse::<u16>()) {
                        if let Ok(cand) = Candidate::host(SocketAddr::new(ip, port), "udp") {
                            if !candidates.contains(&cand) {
                                candidates.push(cand);
                            }
                        }
                    }
                }
            }
        }
    }

    if candidates.is_empty() {
        if let (Some(ip), Some(port)) = (c_ip, rtcp_port) {
            if let Ok(cand) = Candidate::host(SocketAddr::new(ip, port), "udp") {
                candidates.push(cand);
            }
        }
    }

    if ufrag.is_empty() || pwd.is_empty() {
        return Err("Missing a=ice-ufrag or a=ice-pwd in Discord SDP answer".into());
    }
    if fp_str.is_empty() {
        return Err("Missing a=fingerprint in Discord SDP answer".into());
    }
    if candidates.is_empty() {
        return Err("Missing remote ICE candidate in Discord SDP answer".into());
    }

    let mut fingerprint = Fingerprint::from_str(&fp_str)
        .map_err(|e| format!("Invalid fingerprint '{fp_str}': {e}"))?;
    fingerprint.hash_func = fingerprint.hash_func.to_ascii_lowercase();

    Ok(ParsedDiscordAnswer {
        ufrag,
        pwd,
        fingerprint,
        candidates,
    })
}

/// Split an H.264 Annex-B buffer (3-byte or 4-byte start codes) into raw NAL units.
fn split_annexb_nalus(data: &[u8]) -> Vec<&[u8]> {
    let count = data.len();
    if count < 4 {
        return Vec::new();
    }

    let mut starts: Vec<(usize, usize)> = Vec::new();
    let mut i = 0;
    while i + 2 < count {
        if data[i] == 0 && data[i + 1] == 0 {
            if data[i + 2] == 1 {
                starts.push((i + 3, i));
                i += 3;
                continue;
            } else if i + 3 < count && data[i + 2] == 0 && data[i + 3] == 1 {
                starts.push((i + 4, i));
                i += 4;
                continue;
            }
        }
        i += 1;
    }

    if starts.is_empty() {
        return vec![data];
    }

    let mut nalus = Vec::with_capacity(starts.len());
    for idx in 0..starts.len() {
        let start = starts[idx].0;
        let end = if idx + 1 < starts.len() {
            starts[idx + 1].1
        } else {
            count
        };
        if end > start {
            nalus.push(&data[start..end]);
        }
    }
    nalus
}

/// Packetize an H.264 Annex-B frame into RFC 6184 RTP payloads (STAP-A, Single NALU, FU-A).
fn packetize_h264_annexb(frame: &[u8], mtu: usize) -> Vec<Vec<u8>> {
    let nalus = split_annexb_nalus(frame);
    if nalus.is_empty() {
        return Vec::new();
    }

    let mut payloads = Vec::with_capacity(nalus.len() + frame.len() / mtu);
    let mut idx = 0;
    while idx < nalus.len() {
        let nalu = nalus[idx];
        if nalu.is_empty() {
            idx += 1;
            continue;
        }

        if nalu.len() > mtu {
            let nal0 = nalu[0];
            let nal_type = nal0 & 0x1F;
            let fnri = nal0 & 0xE0;
            let fu_indicator = 0x1C | fnri;

            let body = &nalu[1..];
            let mut offset = 0;
            while offset < body.len() {
                let chunk_len = mtu.min(body.len() - offset);
                let is_first = offset == 0;
                let is_final = offset + chunk_len >= body.len();

                let mut fu_header = nal_type;
                if is_first {
                    fu_header |= 0x80;
                } else if is_final {
                    fu_header |= 0x40;
                }

                let mut pkt = Vec::with_capacity(2 + chunk_len);
                pkt.push(fu_indicator);
                pkt.push(fu_header);
                pkt.extend_from_slice(&body[offset..offset + chunk_len]);
                payloads.push(pkt);
                offset += chunk_len;
            }
            idx += 1;
        } else {
            let mut group: Vec<&[u8]> = vec![nalu];
            let mut stap_size = 1 + 2 + nalu.len();
            let mut next_idx = idx + 1;
            while next_idx < nalus.len() {
                let cand = nalus[next_idx];
                if cand.is_empty() {
                    next_idx += 1;
                    continue;
                }
                let added = 2 + cand.len();
                if stap_size + added <= mtu {
                    group.push(cand);
                    stap_size += added;
                    next_idx += 1;
                } else {
                    break;
                }
            }

            if group.len() > 1 {
                let mut max_nri: u8 = 0;
                for g in &group {
                    let nri = g[0] & 0x60;
                    if nri > max_nri {
                        max_nri = nri;
                    }
                }
                let mut stap = Vec::with_capacity(stap_size);
                stap.push(max_nri | 24); // STAP-A (Type 24)
                for g in &group {
                    let len = g.len() as u16;
                    stap.push((len >> 8) as u8);
                    stap.push((len & 0xFF) as u8);
                    stap.extend_from_slice(g);
                }
                payloads.push(stap);
            } else {
                payloads.push(nalu.to_vec());
            }
            idx = next_idx;
        }
    }
    payloads
}

impl DiscordWebRtcTransport {
    pub fn new(audio_ssrc: u32, video_ssrc: u32, rtx_ssrc: u32) -> Result<Self, String> {
        Self::new_with_bind_ip(audio_ssrc, video_ssrc, rtx_ssrc, None)
    }

    pub fn new_with_bind_ip(
        audio_ssrc: u32,
        video_ssrc: u32,
        rtx_ssrc: u32,
        override_ip: Option<Ipv4Addr>,
    ) -> Result<Self, String> {
        let bind_addr = match override_ip {
            Some(ip) => SocketAddr::new(IpAddr::V4(ip), 0),
            None => SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), 0),
        };
        let socket =
            UdpSocket::bind(bind_addr).map_err(|e| format!("UDP bind failed: {e}"))?;
        let bound_port = socket
            .local_addr()
            .map_err(|e| format!("local_addr failed: {e}"))?
            .port();

        let cand_ip = override_ip.unwrap_or_else(discover_local_ipv4);
        let local_cand_addr = SocketAddr::new(IpAddr::V4(cand_ip), bound_port);
        let wake_addr = SocketAddr::new(
            IpAddr::V4(override_ip.unwrap_or(Ipv4Addr::LOCALHOST)),
            bound_port,
        );
        let wake_sock = UdpSocket::bind("127.0.0.1:0").ok();

        let (rtc, offer_sdp, _cname) =
            build_str0m_rtc(audio_ssrc, video_ssrc, rtx_ssrc, local_cand_addr)?;

        let (cmd_tx, cmd_rx) = mpsc::channel::<WebRtcCmd>();
        let connected = Arc::new(AtomicBool::new(false));
        let closed = Arc::new(AtomicBool::new(false));
        let keyframe_requested = Arc::new(AtomicBool::new(false));
        let tx_video_packets = Arc::new(AtomicU64::new(0));
        let tx_audio_packets = Arc::new(AtomicU64::new(0));

        let c_connected = Arc::clone(&connected);
        let c_closed = Arc::clone(&closed);
        let c_keyframe = Arc::clone(&keyframe_requested);
        let c_tx_vid = Arc::clone(&tx_video_packets);
        let c_tx_aud = Arc::clone(&tx_audio_packets);

        let worker = thread::Builder::new()
            .name("dave-webrtc".into())
            .spawn(move || {
                run_webrtc_loop(
                    rtc,
                    socket,
                    local_cand_addr,
                    audio_ssrc,
                    video_ssrc,
                    cmd_rx,
                    c_connected,
                    c_closed,
                    c_keyframe,
                    c_tx_vid,
                    c_tx_aud,
                );
            })
            .map_err(|e| format!("Failed to spawn WebRTC thread: {e}"))?;

        Ok(Self {
            offer_sdp,
            cmd_tx,
            wake_sock,
            wake_addr,
            connected,
            closed,
            keyframe_requested,
            tx_video_packets,
            tx_audio_packets,
            worker: Some(worker),
        })
    }

    fn wake(&self) {
        if let Some(ref s) = self.wake_sock {
            let _ = s.send_to(&[0xFF], self.wake_addr);
        }
    }

    pub fn offer_sdp(&self) -> &str {
        &self.offer_sdp
    }

    pub fn set_discord_answer(&self, answer_sdp: String) -> Result<(), String> {
        let (reply_tx, reply_rx) = mpsc::sync_channel(1);
        self.cmd_tx
            .send(WebRtcCmd::SetDiscordAnswer(answer_sdp, reply_tx))
            .map_err(|_| "WebRTC worker closed".to_string())?;
        self.wake();
        reply_rx
            .recv_timeout(Duration::from_secs(5))
            .map_err(|_| "Timed out waiting for set_discord_answer".to_string())?
    }

    pub fn is_connected(&self) -> bool {
        self.connected.load(Ordering::Acquire) && !self.closed.load(Ordering::Acquire)
    }

    pub fn take_keyframe_request(&self) -> bool {
        self.keyframe_requested.swap(false, Ordering::AcqRel)
    }

    pub fn tx_video_packets(&self) -> u64 {
        self.tx_video_packets.load(Ordering::Relaxed)
    }

    #[allow(dead_code)]
    pub fn tx_audio_packets(&self) -> u64 {
        self.tx_audio_packets.load(Ordering::Relaxed)
    }

    pub fn send_opus(&self, opus_payload: Vec<u8>) -> bool {
        if !self.is_connected() || opus_payload.is_empty() {
            return false;
        }
        let ok = self.cmd_tx.send(WebRtcCmd::SendOpus(opus_payload)).is_ok();
        if ok {
            self.wake();
        }
        ok
    }

    pub fn send_h264(&self, annexb_frame: Vec<u8>, frametime_ms: f64) -> bool {
        if !self.is_connected() || annexb_frame.is_empty() {
            return false;
        }
        let ok = self
            .cmd_tx
            .send(WebRtcCmd::SendH264(annexb_frame, frametime_ms))
            .is_ok();
        if ok {
            self.wake();
        }
        ok
    }
}

impl Drop for DiscordWebRtcTransport {
    fn drop(&mut self) {
        self.closed.store(true, Ordering::Release);
        let _ = self.cmd_tx.send(WebRtcCmd::Shutdown);
        self.wake();
        if let Some(h) = self.worker.take() {
            let _ = h.join();
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn run_webrtc_loop(
    mut rtc: Rtc,
    socket: UdpSocket,
    local_cand_addr: SocketAddr,
    audio_ssrc: u32,
    video_ssrc: u32,
    cmd_rx: mpsc::Receiver<WebRtcCmd>,
    connected: Arc<AtomicBool>,
    closed: Arc<AtomicBool>,
    keyframe_requested: Arc<AtomicBool>,
    tx_video_packets: Arc<AtomicU64>,
    tx_audio_packets: Arc<AtomicU64>,
) {
    let mut recv_buf = vec![0u8; 2048];
    let mut audio_seq: u64 = 1;
    let mut video_seq: u64 = 1;
    let mut audio_ts: u32 = 1000;
    let mut video_ts: u32 = 90_000;

    // Phase 1: Wait for SetDiscordAnswer (or Shutdown) before polling str0m / dimpl DTLS
    loop {
        if closed.load(Ordering::Acquire) {
            return;
        }
        match cmd_rx.recv() {
            Ok(WebRtcCmd::Shutdown) | Err(_) => {
                rtc.disconnect();
                closed.store(true, Ordering::Release);
                return;
            }
            Ok(WebRtcCmd::SetDiscordAnswer(sdp, reply)) => {
                let res = (|| -> Result<(), String> {
                    let parsed = parse_discord_answer_sdp(&sdp)?;
                    {
                        let mut direct = rtc.direct_api();
                        direct.set_remote_ice_credentials(IceCreds {
                            ufrag: parsed.ufrag,
                            pass: parsed.pwd,
                        });
                        direct.set_remote_fingerprint(parsed.fingerprint);
                    }
                    for cand in parsed.candidates {
                        rtc.add_remote_candidate(cand);
                    }
                    {
                        let mut direct = rtc.direct_api();
                        direct
                            .start_dtls(true)
                            .map_err(|e| format!("start_dtls failed: {e:?}"))?;
                    }
                    let _ = rtc.handle_input(Input::Timeout(Instant::now()));
                    Ok(())
                })();
                let ok = res.is_ok();
                let _ = reply.send(res);
                if ok {
                    break;
                }
            }
            Ok(_) => {}
        }
    }

    // Phase 2: Active ICE + DTLS-SRTP + RTP/RTCP loop
    loop {
        if closed.load(Ordering::Acquire) || !rtc.is_alive() {
            break;
        }

        // 1. Drain all queued outbound commands before polling outputs
        let mut had_cmd = false;
        while let Ok(cmd) = cmd_rx.try_recv() {
            had_cmd = true;
            match cmd {
                WebRtcCmd::Shutdown => {
                    rtc.disconnect();
                    closed.store(true, Ordering::Release);
                    return;
                }
                WebRtcCmd::SetDiscordAnswer(_sdp, reply) => {
                    let _ = reply.send(Ok(()));
                }
                WebRtcCmd::SendOpus(opus_data) => {
                    if !connected.load(Ordering::Acquire) {
                        continue;
                    }
                    let now = Instant::now();
                    let mut ext_vals = ExtensionValues::default();
                    ext_vals.play_delay_min = Some(MediaTime::from_hundredths(0));
                    ext_vals.play_delay_max = Some(MediaTime::from_hundredths(1));
                    let ssrc = Ssrc::from(audio_ssrc);
                    if let Some(stream) = rtc.direct_api().stream_tx(&ssrc) {
                        let seq = SeqNo::from(audio_seq);
                        audio_seq = audio_seq.wrapping_add(1);
                        let ts = audio_ts;
                        audio_ts = audio_ts.wrapping_add(960);
                        if stream
                            .write_rtp(
                                Pt::from(PT_OPUS),
                                seq,
                                ts,
                                now,
                                true,
                                ext_vals,
                                false,
                                opus_data,
                            )
                            .is_ok()
                        {
                            tx_audio_packets.fetch_add(1, Ordering::Relaxed);
                        }
                    }
                }
                WebRtcCmd::SendH264(annexb_frame, frametime_ms) => {
                    if !connected.load(Ordering::Acquire) {
                        continue;
                    }
                    let payloads = packetize_h264_annexb(&annexb_frame, VIDEO_RTP_MTU);
                    if payloads.is_empty() {
                        continue;
                    }
                    let now = Instant::now();
                    let cur_ts = video_ts;
                    let ts_inc = ((90_000.0 * frametime_ms) / 1000.0).round().max(1.0) as u32;
                    video_ts = video_ts.wrapping_add(ts_inc);

                    let total = payloads.len();
                    let ssrc = Ssrc::from(video_ssrc);
                    if let Some(stream) = rtc.direct_api().stream_tx(&ssrc) {
                        for (idx, payload) in payloads.into_iter().enumerate() {
                            let is_last = idx + 1 == total;
                            let mut ext_vals = ExtensionValues::default();
                            ext_vals.play_delay_min = Some(MediaTime::from_hundredths(0));
                            ext_vals.play_delay_max = Some(MediaTime::from_hundredths(10));
                            let seq = SeqNo::from(video_seq);
                            video_seq = video_seq.wrapping_add(1);
                            if stream
                                .write_rtp(
                                    Pt::from(PT_H264),
                                    seq,
                                    cur_ts,
                                    now,
                                    is_last,
                                    ext_vals,
                                    true,
                                    payload,
                                )
                                .is_ok()
                            {
                                tx_video_packets.fetch_add(1, Ordering::Relaxed);
                            }
                        }
                    }
                }
            }
        }

        if had_cmd {
            let _ = rtc.handle_input(Input::Timeout(Instant::now()));
        }

        // 2. Poll all str0m outputs (Transmits, Events, next Timeout)
        let timeout = loop {
            match rtc.poll_output() {
                Ok(Output::Timeout(v)) => break v,
                Ok(Output::Transmit(t)) => {
                    let _ = socket.send_to(&t.contents, t.destination);
                }
                Ok(Output::Event(ev)) => match ev {
                    Event::Connected => {
                        connected.store(true, Ordering::Release);
                        keyframe_requested.store(true, Ordering::Release);
                    }
                    Event::KeyframeRequest(_) => {
                        keyframe_requested.store(true, Ordering::Release);
                    }
                    Event::IceConnectionStateChange(IceConnectionState::Disconnected) => {
                        connected.store(false, Ordering::Release);
                    }
                    _ => {}
                },
                Err(_) => {
                    connected.store(false, Ordering::Release);
                    closed.store(true, Ordering::Release);
                    return;
                }
            }
        };

        // 3. Wait for incoming UDP packet (or wake byte) up to timeout
        let now = Instant::now();
        let wait = if timeout <= now {
            let _ = rtc.handle_input(Input::Timeout(now));
            continue;
        } else {
            (timeout - now).min(Duration::from_millis(20))
        };

        let _ = socket.set_read_timeout(Some(wait.max(Duration::from_millis(1))));
        match socket.recv_from(&mut recv_buf) {
            Ok((n, source)) => {
                // Ignore our internal 1-byte loopback wake signal
                if n == 1 && recv_buf[0] == 0xFF && source.ip().is_loopback() {
                    continue;
                }
                if n == 0 {
                    continue;
                }
                let pkt = &recv_buf[..n];
                if let Ok(contents) = pkt.try_into() {
                    let input = Input::Receive(
                        Instant::now(),
                        Receive {
                            proto: Protocol::Udp,
                            source,
                            destination: local_cand_addr,
                            contents,
                        },
                    );
                    let _ = rtc.handle_input(input);
                }
            }
            Err(e) => match e.kind() {
                ErrorKind::WouldBlock | ErrorKind::TimedOut | ErrorKind::Interrupted => {
                    let _ = rtc.handle_input(Input::Timeout(Instant::now()));
                }
                _ => {
                    // Transient ICMP unreachable or mobile route switch: do not kill loop
                    thread::sleep(Duration::from_millis(5));
                }
            },
        }
    }

    connected.store(false, Ordering::Release);
    closed.store(true, Ordering::Release);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_discord_webrtc_full_dtls_srtp_h264_opus_loopback() {
        // 1. Create client transport (exactly how iOS app calls it)
        let audio_ssrc = 11111u32;
        let video_ssrc = 22222u32;
        let rtx_ssrc = 22223u32;

        let client = DiscordWebRtcTransport::new_with_bind_ip(
            audio_ssrc,
            video_ssrc,
            rtx_ssrc,
            Some(Ipv4Addr::LOCALHOST),
        )
        .expect("create client webrtc");

        let offer = client.offer_sdp().to_string();
        assert!(offer.contains("a=group:BUNDLE 0 1"));
        assert!(offer.contains("a=rtpmap:120 opus/48000/2"));
        assert!(offer.contains("a=rtpmap:101 H264/90000"));
        assert!(offer.contains("a=rtpmap:102 rtx/90000"));
        assert!(offer.contains("playout-delay"));
        assert!(offer.contains(&format!("a=ssrc:{audio_ssrc}")));
        assert!(offer.contains(&format!("a=ssrc-group:FID {video_ssrc} {rtx_ssrc}")));

        // 2. Create simulated Discord SFU (ICE-Lite + DTLS passive + RTP mode)
        let sfu_sock = UdpSocket::bind("127.0.0.1:0").unwrap();
        let sfu_addr = sfu_sock.local_addr().unwrap();

        let mut sfu_cfg = RtcConfig::new()
            .set_ice_lite(true)
            .set_rtp_mode(true)
            .clear_codecs()
            .clear_extension_map();
        sfu_cfg.codec_config().add_config(
            Pt::from(PT_OPUS),
            None,
            Codec::Opus,
            Frequency::FORTY_EIGHT_KHZ,
            Some(2),
            FormatParams::default(),
        );
        sfu_cfg.codec_config().add_h264(
            Pt::from(PT_H264),
            Some(Pt::from(PT_H264_RTX)),
            true,
            0x42e01f,
        );
        let mut sfu_exts = ExtensionMap::empty();
        sfu_exts.set(1, Extension::AudioLevel);
        sfu_exts.set(2, Extension::AbsoluteSendTime);
        sfu_exts.set(3, Extension::TransportSequenceNumber);
        sfu_exts.set(5, Extension::PlayoutDelay);
        sfu_cfg = sfu_cfg.set_extension_map(sfu_exts);

        let mut sfu = sfu_cfg.build();
        sfu.add_local_candidate(Candidate::host(sfu_addr, "udp").unwrap());

        // Parse client offer creds/fp/cand into SFU
        let parsed_offer = parse_discord_answer_sdp(&offer).expect("parse client offer");
        let (sfu_ufrag, sfu_pwd, sfu_fp) = {
            let mut d = sfu.direct_api();
            d.set_ice_controlling(false);
            d.set_remote_ice_credentials(IceCreds {
                ufrag: parsed_offer.ufrag,
                pass: parsed_offer.pwd,
            });
            d.set_remote_fingerprint(parsed_offer.fingerprint);
            let m0 = Mid::from("0");
            let m1 = Mid::from("1");
            d.declare_media(m0, MediaKind::Audio);
            d.declare_media(m1, MediaKind::Video);
            d.expect_stream_rx(Ssrc::from(audio_ssrc), None, m0, None);
            d.expect_stream_rx(
                Ssrc::from(video_ssrc),
                Some(Ssrc::from(rtx_ssrc)),
                m1,
                None,
            );
            d.start_dtls(false).unwrap(); // passive DTLS server like Discord!
            let creds = d.local_ice_credentials();
            let fp = d.local_dtls_fingerprint().to_string();
            (creds.ufrag, creds.pass, fp)
        };
        for c in parsed_offer.candidates {
            sfu.add_remote_candidate(c);
        }

        // Build exact Discord compact Op 4 SDP answer!
        let discord_compact_sdp = format!(
            "m=audio {port} ICE/SDP\nc=IN IP4 {ip}\na=rtcp:{port}\na=ice-ufrag:{sfu_ufrag}\na=ice-pwd:{sfu_pwd}\na=fingerprint:{sfu_fp}\na=candidate:1 1 UDP 2130706431 {ip} {port} typ host\n",
            ip = sfu_addr.ip(),
            port = sfu_addr.port(),
        );
        client
            .set_discord_answer(discord_compact_sdp)
            .expect("set discord answer");

        // Drive initial timeout for SFU before polling (required by dimpl DTLS)
        let _ = sfu.handle_input(Input::Timeout(Instant::now()));

        // 3. Drive SFU loop until ICE + DTLS completes and we receive Opus + H.264 STAP-A + FU-A
        let deadline = Instant::now() + Duration::from_secs(6);
        let mut sfu_buf = vec![0u8; 2048];
        let mut sent_media = false;
        let mut got_opus = false;
        let mut got_stap_a = false;
        let mut got_fua_last = false;
        let mut got_playout_delay = false;
        let mut pli_sent = false;
        let mut client_saw_pli = false;

        while Instant::now() < deadline {
            let timeout = loop {
                match sfu.poll_output().unwrap() {
                    Output::Timeout(t) => break t,
                    Output::Transmit(t) => {
                        let _ = sfu_sock.send_to(&t.contents, t.destination);
                    }
                    Output::Event(Event::RtpPacket(pkt)) => {
                        if pkt.header.ssrc == Ssrc::from(audio_ssrc)
                            && pkt.header.payload_type == Pt::from(PT_OPUS)
                        {
                            assert_eq!(pkt.payload, vec![0xF8, 0xFF, 0xFE]);
                            got_opus = true;
                        } else if pkt.header.ssrc == Ssrc::from(video_ssrc)
                            && pkt.header.payload_type == Pt::from(PT_H264)
                        {
                            let nal_type = pkt.payload[0] & 0x1F;
                            if nal_type == 24 {
                                got_stap_a = true; // SPS + PPS STAP-A!
                            }
                            if nal_type == 28 && pkt.header.marker {
                                got_fua_last = true; // IDR FU-A last packet with M=1!
                            }
                            if pkt.header.ext_vals.play_delay_max.is_some() {
                                got_playout_delay = true;
                            }
                            if !pli_sent {
                                if let Some(rx) =
                                    sfu.direct_api().stream_rx(&Ssrc::from(video_ssrc))
                                {
                                    rx.request_keyframe(str0m::media::KeyframeRequestKind::Pli);
                                    pli_sent = true;
                                }
                            }
                        }
                    }
                    _ => {}
                }
            };

            if client.is_connected() && !sent_media {
                // Consume initial connect keyframe flag
                let _ = client.take_keyframe_request();
                assert!(client.send_opus(vec![0xF8, 0xFF, 0xFE]));

                // Build realistic Annex-B H.264 Keyframe: SPS + PPS + 2600B IDR
                let mut h264 = Vec::new();
                h264.extend_from_slice(&[0, 0, 0, 1, 0x67, 0x42, 0xC0, 0x1F, 0xD9, 0x00]);
                h264.extend_from_slice(&[0, 0, 0, 1, 0x68, 0xCE, 0x3C, 0x80]);
                h264.extend_from_slice(&[0, 0, 0, 1, 0x65]);
                h264.extend(std::iter::repeat_n(0xABu8, 2600));
                assert!(client.send_h264(h264, 33.333));
                sent_media = true;
            }

            if pli_sent && client.take_keyframe_request() {
                client_saw_pli = true;
            }

            if got_opus && got_stap_a && got_fua_last && got_playout_delay && client_saw_pli {
                break;
            }

            let now = Instant::now();
            let wait = if timeout <= now {
                Duration::from_millis(1)
            } else {
                (timeout - now).min(Duration::from_millis(15))
            };
            let _ = sfu_sock.set_read_timeout(Some(wait));
            match sfu_sock.recv_from(&mut sfu_buf) {
                Ok((n, source)) if n > 0 => {
                    if let Ok(contents) = (&sfu_buf[..n]).try_into() {
                        let _ = sfu.handle_input(Input::Receive(
                            Instant::now(),
                            Receive {
                                proto: Protocol::Udp,
                                source,
                                destination: sfu_addr,
                                contents,
                            },
                        ));
                    }
                }
                _ => {
                    let _ = sfu.handle_input(Input::Timeout(Instant::now()));
                }
            }
        }

        assert!(client.is_connected(), "WebRTC client failed to connect DTLS/ICE");
        assert!(got_opus, "SFU did not receive Opus SRTP packet");
        assert!(got_stap_a, "SFU did not receive H.264 STAP-A (SPS+PPS) SRTP packet");
        assert!(got_fua_last, "SFU did not receive H.264 FU-A last packet with M=1");
        assert!(got_playout_delay, "SFU did not receive playout-delay RTP extension");
        assert!(client_saw_pli, "Client did not receive RTCP PLI KeyframeRequest from SFU");
        assert!(client.tx_video_packets() >= 4);
    }
}
