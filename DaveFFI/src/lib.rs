use std::num::NonZeroU16;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::slice;
use std::sync::Mutex;

use chacha20poly1305::{
    XChaCha20Poly1305, XNonce,
    aead::{Aead, KeyInit, Payload},
};
use davey::{Codec, DAVE_PROTOCOL_VERSION, DaveSession, MediaType, ProposalsOperationType};
use ropus::{Application as OpusApplication, Bitrate as OpusBitrate, Channels as OpusChannels, Encoder as OpusEncoder};

pub struct DaveSessionHandle {
    inner: Mutex<DaveSession>,
}

pub struct DaveOpusEncoderHandle {
    inner: Mutex<OpusEncoder>,
    channels: usize,
}

#[repr(C)]
pub struct DaveByteBuffer {
    pub ptr: *mut u8,
    pub len: usize,
    pub cap: usize,
}

impl DaveByteBuffer {
    fn empty() -> Self {
        Self {
            ptr: std::ptr::null_mut(),
            len: 0,
            cap: 0,
        }
    }

    fn from_vec(mut v: Vec<u8>) -> Self {
        if v.is_empty() {
            return Self::empty();
        }
        v.shrink_to_fit();
        let ptr = v.as_mut_ptr();
        let len = v.len();
        let cap = v.capacity();
        std::mem::forget(v);
        Self { ptr, len, cap }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_buffer_free(buf: DaveByteBuffer) {
    let _ = catch_unwind(|| {
        if !buf.ptr.is_null() && buf.cap > 0 {
            unsafe {
                let _ = Vec::from_raw_parts(buf.ptr, buf.len, buf.cap);
            }
        }
    });
}

#[unsafe(no_mangle)]
pub extern "C" fn dave_max_protocol_version() -> u16 {
    DAVE_PROTOCOL_VERSION
}

#[unsafe(no_mangle)]
pub extern "C" fn dave_session_new(
    protocol_version: u16,
    user_id: u64,
    channel_id: u64,
) -> *mut DaveSessionHandle {
    catch_unwind(|| {
        let Some(ver) = NonZeroU16::new(protocol_version) else {
            return std::ptr::null_mut();
        };
        match DaveSession::new(ver, user_id, channel_id, None) {
            Ok(session) => Box::into_raw(Box::new(DaveSessionHandle {
                inner: Mutex::new(session),
            })),
            Err(_) => std::ptr::null_mut(),
        }
    })
    .unwrap_or(std::ptr::null_mut())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_free(handle: *mut DaveSessionHandle) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !handle.is_null() {
            unsafe {
                drop(Box::from_raw(handle));
            }
        }
    }));
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_reinit(
    handle: *mut DaveSessionHandle,
    protocol_version: u16,
    user_id: u64,
    channel_id: u64,
) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return false;
        }
        let Some(ver) = NonZeroU16::new(protocol_version) else {
            return false;
        };
        let session_handle = unsafe { &*handle };
        let Ok(mut guard) = session_handle.inner.lock() else {
            return false;
        };
        guard.reinit(ver, user_id, channel_id, None).is_ok()
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_reset(handle: *mut DaveSessionHandle) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return false;
        }
        let session_handle = unsafe { &*handle };
        let Ok(mut guard) = session_handle.inner.lock() else {
            return false;
        };
        guard.reset().is_ok()
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_is_ready(handle: *const DaveSessionHandle) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return false;
        }
        let session_handle = unsafe { &*handle };
        let Ok(guard) = session_handle.inner.lock() else {
            return false;
        };
        guard.is_ready()
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_can_encrypt(handle: *const DaveSessionHandle) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return false;
        }
        let session_handle = unsafe { &*handle };
        let Ok(guard) = session_handle.inner.lock() else {
            return false;
        };
        guard.can_encrypt()
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_protocol_version(handle: *const DaveSessionHandle) -> u16 {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return 0;
        }
        let session_handle = unsafe { &*handle };
        let Ok(guard) = session_handle.inner.lock() else {
            return 0;
        };
        guard.protocol_version().get()
    }))
    .unwrap_or(0)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_create_key_package(
    handle: *mut DaveSessionHandle,
) -> DaveByteBuffer {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return DaveByteBuffer::empty();
        }
        let session_handle = unsafe { &*handle };
        let Ok(mut guard) = session_handle.inner.lock() else {
            return DaveByteBuffer::empty();
        };
        match guard.create_key_package() {
            Ok(kp) => DaveByteBuffer::from_vec(kp),
            Err(_) => DaveByteBuffer::empty(),
        }
    }))
    .unwrap_or_else(|_| DaveByteBuffer::empty())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_set_external_sender(
    handle: *mut DaveSessionHandle,
    data: *const u8,
    len: usize,
) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || data.is_null() || len == 0 {
            return false;
        }
        let session_handle = unsafe { &*handle };
        let bytes = unsafe { slice::from_raw_parts(data, len) };
        let Ok(mut guard) = session_handle.inner.lock() else {
            return false;
        };
        guard.set_external_sender(bytes).is_ok()
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_process_proposals(
    handle: *mut DaveSessionHandle,
    operation_type: u8,
    proposals: *const u8,
    proposals_len: usize,
    expected_user_ids: *const u64,
    expected_user_ids_len: usize,
    out_commit_welcome: *mut DaveByteBuffer,
) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        if !out_commit_welcome.is_null() {
            unsafe {
                *out_commit_welcome = DaveByteBuffer::empty();
            }
        }
        if handle.is_null() || proposals.is_null() || proposals_len == 0 {
            return false;
        }
        let op = match operation_type {
            0 => ProposalsOperationType::APPEND,
            1 => ProposalsOperationType::REVOKE,
            _ => return false,
        };
        let session_handle = unsafe { &*handle };
        let prop_bytes = unsafe { slice::from_raw_parts(proposals, proposals_len) };
        let ids: Option<&[u64]> = if !expected_user_ids.is_null() && expected_user_ids_len > 0 {
            Some(unsafe { slice::from_raw_parts(expected_user_ids, expected_user_ids_len) })
        } else {
            None
        };
        let Ok(mut guard) = session_handle.inner.lock() else {
            return false;
        };
        match guard.process_proposals(op, prop_bytes, ids) {
            Ok(Some(cw)) => {
                let mut combined = cw.commit;
                if let Some(welcome) = cw.welcome {
                    combined.extend_from_slice(&welcome);
                }
                if !out_commit_welcome.is_null() {
                    unsafe {
                        *out_commit_welcome = DaveByteBuffer::from_vec(combined);
                    }
                }
                true
            }
            Ok(None) => true,
            Err(_) => false,
        }
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_process_commit(
    handle: *mut DaveSessionHandle,
    commit: *const u8,
    commit_len: usize,
) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || commit.is_null() || commit_len == 0 {
            return -1;
        }
        let session_handle = unsafe { &*handle };
        let commit_bytes = unsafe { slice::from_raw_parts(commit, commit_len) };
        let Ok(mut guard) = session_handle.inner.lock() else {
            return -1;
        };
        match guard.process_commit(commit_bytes) {
            Ok(true) => 1,
            Ok(false) => 0,
            Err(_) => -1,
        }
    }))
    .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_process_welcome(
    handle: *mut DaveSessionHandle,
    welcome: *const u8,
    welcome_len: usize,
    recognized_user_ids: *const u64,
    recognized_user_ids_len: usize,
) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || welcome.is_null() || welcome_len == 0 {
            return false;
        }
        let session_handle = unsafe { &*handle };
        let welcome_bytes = unsafe { slice::from_raw_parts(welcome, welcome_len) };
        let ids: Option<&[u64]> = if !recognized_user_ids.is_null() && recognized_user_ids_len > 0 {
            Some(unsafe { slice::from_raw_parts(recognized_user_ids, recognized_user_ids_len) })
        } else {
            None
        };
        let Ok(mut guard) = session_handle.inner.lock() else {
            return false;
        };
        guard.process_welcome(welcome_bytes, ids).is_ok()
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_prepare_transition(
    handle: *mut DaveSessionHandle,
    transition_id: u16,
    protocol_version: u16,
) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return false;
        }
        let session_handle = unsafe { &*handle };
        let Ok(mut guard) = session_handle.inner.lock() else {
            return false;
        };
        guard
            .prepare_transition(transition_id, protocol_version)
            .is_ok()
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_execute_transition(
    handle: *mut DaveSessionHandle,
    transition_id: u16,
) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return -1;
        }
        let session_handle = unsafe { &*handle };
        let Ok(mut guard) = session_handle.inner.lock() else {
            return -1;
        };
        match guard.execute_transition(transition_id) {
            Ok(true) => 1,
            Ok(false) => 0,
            Err(_) => -1,
        }
    }))
    .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_set_passthrough_mode(
    handle: *mut DaveSessionHandle,
    passthrough: bool,
    transition_expiry: u32,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return;
        }
        let session_handle = unsafe { &*handle };
        if let Ok(mut guard) = session_handle.inner.lock() {
            guard.set_passthrough_mode(passthrough, Some(transition_expiry));
        }
    }));
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_encrypt_opus(
    handle: *mut DaveSessionHandle,
    opus_data: *const u8,
    opus_len: usize,
) -> DaveByteBuffer {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || opus_data.is_null() || opus_len == 0 {
            return DaveByteBuffer::empty();
        }
        let session_handle = unsafe { &*handle };
        let bytes = unsafe { slice::from_raw_parts(opus_data, opus_len) };
        let Ok(mut guard) = session_handle.inner.lock() else {
            return DaveByteBuffer::empty();
        };
        match guard.encrypt_opus(bytes) {
            Ok(cow) => DaveByteBuffer::from_vec(cow.into_owned()),
            Err(_) => DaveByteBuffer::empty(),
        }
    }))
    .unwrap_or_else(|_| DaveByteBuffer::empty())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_session_encrypt_video_h264(
    handle: *mut DaveSessionHandle,
    annexb_data: *const u8,
    annexb_len: usize,
) -> DaveByteBuffer {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || annexb_data.is_null() || annexb_len == 0 {
            return DaveByteBuffer::empty();
        }
        let session_handle = unsafe { &*handle };
        let bytes = unsafe { slice::from_raw_parts(annexb_data, annexb_len) };
        let Ok(mut guard) = session_handle.inner.lock() else {
            return DaveByteBuffer::empty();
        };
        match guard.encrypt(MediaType::VIDEO, Codec::H264, bytes) {
            Ok(cow) => DaveByteBuffer::from_vec(cow.into_owned()),
            Err(_) => DaveByteBuffer::empty(),
        }
    }))
    .unwrap_or_else(|_| DaveByteBuffer::empty())
}

// ============================================================================
// H.264 SPS VUI Rewriter (port of WebRTC sps_vui_rewriter / Discord-video-stream)
// Ensures max_num_reorder_frames = 0 and strips video_signal_type so Chrome /
// Discord Desktop WebRTC H.264 decoder never stalls on a loading spinner.
// ============================================================================

struct AnnexBReader<'a> {
    buf: &'a [u8],
    byte_off: usize,
    bit_off: u8,
}

impl<'a> AnnexBReader<'a> {
    fn new(buf: &'a [u8]) -> Self {
        Self {
            buf,
            byte_off: 0,
            bit_off: 0,
        }
    }

    fn read_bits(&mut self, mut count: u8) -> Option<u32> {
        if count == 0 {
            return Some(0);
        }
        let mut result: u32 = 0;
        while count > 0 {
            if self.byte_off >= self.buf.len() {
                return None;
            }
            if self.bit_off == 0
                && self.byte_off >= 2
                && self.buf[self.byte_off - 2] == 0
                && self.buf[self.byte_off - 1] == 0
                && self.buf[self.byte_off] == 3
            {
                self.byte_off += 1;
                if self.byte_off >= self.buf.len() {
                    return None;
                }
            }
            if self.bit_off == 0 && count >= 8 {
                result = (result << 8) | (self.buf[self.byte_off] as u32);
                self.byte_off += 1;
                count -= 8;
            } else {
                let n = count.min(8 - self.bit_off);
                let mask = (1u32 << n) - 1;
                let shift = 8 - self.bit_off - n;
                let bits = ((self.buf[self.byte_off] as u32) >> shift) & mask;
                result = (result << n) | bits;
                count -= n;
                self.bit_off += n;
                if self.bit_off == 8 {
                    self.bit_off = 0;
                    self.byte_off += 1;
                }
            }
        }
        Some(result)
    }

    fn read_ue(&mut self) -> Option<u32> {
        let mut leading_zeros: u8 = 0;
        while self.read_bits(1)? == 0 {
            leading_zeros += 1;
            if leading_zeros > 31 {
                return None;
            }
        }
        if leading_zeros == 0 {
            return Some(0);
        }
        let rest = self.read_bits(leading_zeros)?;
        Some((1u32 << leading_zeros).wrapping_sub(1).wrapping_add(rest))
    }

    fn read_se(&mut self) -> Option<i32> {
        let u = self.read_ue()?;
        if u % 2 == 0 {
            Some(-((u / 2) as i32))
        } else {
            Some(((u + 1) / 2) as i32)
        }
    }
}

struct AnnexBWriter {
    out: Vec<u8>,
    pending: u8,
    bit_off: u8,
}

impl AnnexBWriter {
    fn new(cap: usize) -> Self {
        Self {
            out: Vec::with_capacity(cap),
            pending: 0,
            bit_off: 0,
        }
    }

    fn flush_byte(&mut self) {
        let len = self.out.len();
        if self.pending <= 3 && len >= 2 && self.out[len - 1] == 0 && self.out[len - 2] == 0 {
            self.out.push(3);
        }
        self.out.push(self.pending);
        self.pending = 0;
        self.bit_off = 0;
    }

    fn write_bits(&mut self, bits: u32, mut count: u8) {
        while count > 0 {
            if self.bit_off == 0 {
                if count >= 8 {
                    self.pending = ((bits >> (count - 8)) & 0xFF) as u8;
                    count -= 8;
                    self.flush_byte();
                } else {
                    let mask = (1u32 << count) - 1;
                    self.pending |= ((bits & mask) << (8 - count)) as u8;
                    self.bit_off = count;
                    count = 0;
                }
            } else {
                let n = count.min(8 - self.bit_off);
                let mask = (1u32 << n) - 1;
                let part = (bits >> (count - n)) & mask;
                self.pending |= (part << (8 - self.bit_off - n)) as u8;
                count -= n;
                self.bit_off += n;
                if self.bit_off == 8 {
                    self.flush_byte();
                }
            }
        }
    }

    fn write_ue(&mut self, val: u32) {
        let v = val.saturating_add(1);
        let bit_count = (32 - v.leading_zeros()) as u8;
        if bit_count > 1 {
            self.write_bits(0, bit_count - 1);
        }
        self.write_bits(v, bit_count);
    }

    fn write_se(&mut self, val: i32) {
        if val <= 0 {
            self.write_ue((-2 * val) as u32);
        } else {
            self.write_ue((2 * val - 1) as u32);
        }
    }

    fn finish(mut self) -> Vec<u8> {
        self.write_bits(1, 1); // rbsp_stop_one_bit
        if self.bit_off > 0 {
            self.flush_byte();
        }
        self.out
    }
}

fn rewrite_sps_vui_internal(sps: &[u8]) -> Option<Vec<u8>> {
    if sps.len() < 4 || (sps[0] & 0x1F) != 7 {
        return None;
    }
    let mut r = AnnexBReader::new(&sps[1..]);
    let mut w = AnnexBWriter::new(sps.len() + 16);

    w.write_bits(sps[0] as u32, 8);
    let profile_idc = r.read_bits(8)?;
    w.write_bits(profile_idc, 8);
    let constraint_flags = r.read_bits(8)?;
    w.write_bits(constraint_flags, 8);
    let level_idc = r.read_bits(8)?;
    w.write_bits(level_idc, 8);

    let sps_id = r.read_ue()?;
    w.write_ue(sps_id);

    if matches!(
        profile_idc,
        100 | 110 | 122 | 244 | 44 | 83 | 86 | 118 | 128 | 138 | 144
    ) {
        let chroma_format_idc = r.read_ue()?;
        w.write_ue(chroma_format_idc);
        if chroma_format_idc == 3 {
            let sep = r.read_bits(1)?;
            w.write_bits(sep, 1);
        }
        let bd_luma = r.read_ue()?;
        w.write_ue(bd_luma);
        let bd_chroma = r.read_ue()?;
        w.write_ue(bd_chroma);
        let qpprime = r.read_bits(1)?;
        w.write_bits(qpprime, 1);
        let scaling_present = r.read_bits(1)?;
        w.write_bits(scaling_present, 1);
        if scaling_present != 0 {
            let scaling_count = if chroma_format_idc != 3 { 8 } else { 12 };
            for i in 0..scaling_count {
                let list_present = r.read_bits(1)?;
                w.write_bits(list_present, 1);
                if list_present != 0 {
                    let size = if i < 6 { 16 } else { 64 };
                    let mut last_scale: i32 = 8;
                    let mut next_scale: i32 = 8;
                    for _ in 0..size {
                        if next_scale != 0 {
                            let delta = r.read_se()?;
                            w.write_se(delta);
                            next_scale = (last_scale + delta + 256) % 256;
                        }
                        if next_scale != 0 {
                            last_scale = next_scale;
                        }
                    }
                }
            }
        }
    }

    let log2_max_frame_num_minus4 = r.read_ue()?;
    w.write_ue(log2_max_frame_num_minus4);

    let poc_type = r.read_ue()?;
    w.write_ue(poc_type);
    if poc_type == 0 {
        let v = r.read_ue()?;
        w.write_ue(v);
    } else if poc_type == 1 {
        let v = r.read_bits(1)?;
        w.write_bits(v, 1);
        let v2 = r.read_se()?;
        w.write_se(v2);
        let v3 = r.read_se()?;
        w.write_se(v3);
        let n_ref = r.read_ue()?;
        w.write_ue(n_ref);
        for _ in 0..n_ref {
            let off = r.read_se()?;
            w.write_se(off);
        }
    }

    let max_num_ref_frames = r.read_ue()?;
    w.write_ue(max_num_ref_frames);
    let gaps = r.read_bits(1)?;
    w.write_bits(gaps, 1);
    let pic_w = r.read_ue()?;
    w.write_ue(pic_w);
    let pic_h = r.read_ue()?;
    w.write_ue(pic_h);

    let frame_mbs_only = r.read_bits(1)?;
    w.write_bits(frame_mbs_only, 1);
    if frame_mbs_only == 0 {
        let mb_aff = r.read_bits(1)?;
        w.write_bits(mb_aff, 1);
    }
    let direct_8x8 = r.read_bits(1)?;
    w.write_bits(direct_8x8, 1);

    let cropping = r.read_bits(1)?;
    w.write_bits(cropping, 1);
    if cropping != 0 {
        for _ in 0..4 {
            let c = r.read_ue()?;
            w.write_ue(c);
        }
    }

    let write_restriction = |w: &mut AnnexBWriter| {
        w.write_bits(1, 1); // motion_vectors_over_pic_boundaries_flag
        w.write_ue(2); // max_bytes_per_pic_denom
        w.write_ue(1); // max_bits_per_mb_denom
        w.write_ue(16); // log2_max_mv_length_horizontal
        w.write_ue(16); // log2_max_mv_length_vertical
        w.write_ue(0); // max_num_reorder_frames = 0 (CRITICAL for WebRTC/Chrome!)
        w.write_ue(max_num_ref_frames.max(1)); // max_dec_frame_buffering
    };

    let copy_hrd = |r: &mut AnnexBReader, w: &mut AnnexBWriter| -> Option<()> {
        let cpb_cnt_minus1 = r.read_ue()?;
        w.write_ue(cpb_cnt_minus1);
        let br_scale = r.read_bits(4)?;
        w.write_bits(br_scale, 4);
        let cpb_scale = r.read_bits(4)?;
        w.write_bits(cpb_scale, 4);
        for _ in 0..=cpb_cnt_minus1 {
            let br_val = r.read_ue()?;
            w.write_ue(br_val);
            let cpb_val = r.read_ue()?;
            w.write_ue(cpb_val);
            let cbr = r.read_bits(1)?;
            w.write_bits(cbr, 1);
        }
        let a = r.read_bits(5)?;
        w.write_bits(a, 5);
        let b = r.read_bits(5)?;
        w.write_bits(b, 5);
        let c = r.read_bits(5)?;
        w.write_bits(c, 5);
        let d = r.read_bits(5)?;
        w.write_bits(d, 5);
        Some(())
    };

    let vui_present = r.read_bits(1)?;
    w.write_bits(1, 1);
    if vui_present == 0 {
        w.write_bits(0, 2); // aspect_ratio, overscan
        w.write_bits(0, 1); // video_signal_type
        w.write_bits(0, 5); // chroma_loc, timing_info, nal_hrd, vcl_hrd, pic_struct
        w.write_bits(1, 1); // bitstream_restriction_flag
        write_restriction(&mut w);
    } else {
        let ar = r.read_bits(1)?;
        w.write_bits(ar, 1);
        if ar != 0 {
            let idc = r.read_bits(8)?;
            w.write_bits(idc, 8);
            if idc == 255 {
                let sw = r.read_bits(16)?;
                w.write_bits(sw, 16);
                let sh = r.read_bits(16)?;
                w.write_bits(sh, 16);
            }
        }
        let overscan = r.read_bits(1)?;
        w.write_bits(overscan, 1);
        if overscan != 0 {
            let oa = r.read_bits(1)?;
            w.write_bits(oa, 1);
        }
        // Strip video_signal_type_present_flag (just like SPSVUIRewriter.ts)
        let vst = r.read_bits(1)?;
        w.write_bits(0, 1);
        if vst != 0 {
            let _ = r.read_bits(3)?;
            let _ = r.read_bits(1)?;
            let cd = r.read_bits(1)?;
            if cd != 0 {
                let _ = r.read_bits(8)?;
                let _ = r.read_bits(8)?;
                let _ = r.read_bits(8)?;
            }
        }
        let cloc = r.read_bits(1)?;
        w.write_bits(cloc, 1);
        if cloc != 0 {
            let t = r.read_ue()?;
            w.write_ue(t);
            let b = r.read_ue()?;
            w.write_ue(b);
        }
        let timing = r.read_bits(1)?;
        w.write_bits(timing, 1);
        if timing != 0 {
            let num = r.read_bits(32)?;
            w.write_bits(num, 32);
            let ts = r.read_bits(32)?;
            w.write_bits(ts, 32);
            let ffr = r.read_bits(1)?;
            w.write_bits(ffr, 1);
        }
        let nal_hrd = r.read_bits(1)?;
        w.write_bits(nal_hrd, 1);
        if nal_hrd != 0 {
            copy_hrd(&mut r, &mut w)?;
        }
        let vcl_hrd = r.read_bits(1)?;
        w.write_bits(vcl_hrd, 1);
        if vcl_hrd != 0 {
            copy_hrd(&mut r, &mut w)?;
        }
        if nal_hrd != 0 || vcl_hrd != 0 {
            let ld = r.read_bits(1)?;
            w.write_bits(ld, 1);
        }
        let ps = r.read_bits(1)?;
        w.write_bits(ps, 1);
        let br = r.read_bits(1)?;
        w.write_bits(1, 1);
        if br == 0 {
            write_restriction(&mut w);
        } else {
            let mv = r.read_bits(1)?;
            w.write_bits(mv, 1);
            let mbp = r.read_ue()?;
            w.write_ue(mbp);
            let mbm = r.read_ue()?;
            w.write_ue(mbm);
            let lh = r.read_ue()?;
            w.write_ue(lh);
            let lv = r.read_ue()?;
            w.write_ue(lv);
            let _old_reorder = r.read_ue()?;
            w.write_ue(0); // max_num_reorder_frames = 0
            let _old_dpb = r.read_ue()?;
            w.write_ue(max_num_ref_frames.max(1));
        }
    }

    Some(w.finish())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_h264_rewrite_sps_vui(
    sps_nalu: *const u8,
    sps_len: usize,
) -> DaveByteBuffer {
    catch_unwind(AssertUnwindSafe(|| {
        if sps_nalu.is_null() || sps_len < 4 {
            return DaveByteBuffer::empty();
        }
        let bytes = unsafe { slice::from_raw_parts(sps_nalu, sps_len) };
        match rewrite_sps_vui_internal(bytes) {
            Some(out) => DaveByteBuffer::from_vec(out),
            None => DaveByteBuffer::empty(),
        }
    }))
    .unwrap_or_else(|_| DaveByteBuffer::empty())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_xchacha20_poly1305_encrypt(
    key: *const u8,
    nonce24: *const u8,
    aad: *const u8,
    aad_len: usize,
    plaintext: *const u8,
    plaintext_len: usize,
) -> DaveByteBuffer {
    catch_unwind(AssertUnwindSafe(|| {
        if key.is_null() || nonce24.is_null() || plaintext.is_null() {
            return DaveByteBuffer::empty();
        }
        let key_slice = unsafe { slice::from_raw_parts(key, 32) };
        let nonce_slice = unsafe { slice::from_raw_parts(nonce24, 24) };
        let aad_slice = if aad.is_null() || aad_len == 0 {
            &[]
        } else {
            unsafe { slice::from_raw_parts(aad, aad_len) }
        };
        let pt_slice = unsafe { slice::from_raw_parts(plaintext, plaintext_len) };

        let Ok(cipher) = XChaCha20Poly1305::new_from_slice(key_slice) else {
            return DaveByteBuffer::empty();
        };
        let nonce = XNonce::from_slice(nonce_slice);
        match cipher.encrypt(
            nonce,
            Payload {
                msg: pt_slice,
                aad: aad_slice,
            },
        ) {
            Ok(ct) => DaveByteBuffer::from_vec(ct),
            Err(_) => DaveByteBuffer::empty(),
        }
    }))
    .unwrap_or_else(|_| DaveByteBuffer::empty())
}

#[unsafe(no_mangle)]
pub extern "C" fn dave_opus_encoder_new(
    sample_rate: i32,
    channels: i32,
    bitrate: i32,
) -> *mut DaveOpusEncoderHandle {
    catch_unwind(|| {
        let ch = match channels {
            1 => OpusChannels::Mono,
            2 => OpusChannels::Stereo,
            _ => return std::ptr::null_mut(),
        };
        let mut builder = OpusEncoder::builder(sample_rate as u32, ch, OpusApplication::Audio);
        if bitrate > 0 {
            builder = builder.bitrate(OpusBitrate::Bits(bitrate as u32));
        }
        match builder.build() {
            Ok(enc) => Box::into_raw(Box::new(DaveOpusEncoderHandle {
                inner: Mutex::new(enc),
                channels: channels as usize,
            })),
            Err(_) => std::ptr::null_mut(),
        }
    })
    .unwrap_or(std::ptr::null_mut())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_opus_encoder_free(handle: *mut DaveOpusEncoderHandle) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !handle.is_null() {
            unsafe {
                drop(Box::from_raw(handle));
            }
        }
    }));
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dave_opus_encoder_encode_float(
    handle: *mut DaveOpusEncoderHandle,
    left: *const f32,
    right: *const f32,
    frame_size: usize,
) -> DaveByteBuffer {
    catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || left.is_null() || frame_size == 0 {
            return DaveByteBuffer::empty();
        }
        let enc_handle = unsafe { &*handle };
        let l_slice = unsafe { slice::from_raw_parts(left, frame_size) };
        let r_slice = if !right.is_null() {
            unsafe { slice::from_raw_parts(right, frame_size) }
        } else {
            l_slice
        };

        let mut pcm = Vec::with_capacity(frame_size * enc_handle.channels);
        if enc_handle.channels == 2 {
            for i in 0..frame_size {
                let lv = (l_slice[i].clamp(-1.0, 1.0) * 32767.0) as i16;
                let rv = (r_slice[i].clamp(-1.0, 1.0) * 32767.0) as i16;
                pcm.push(lv);
                pcm.push(rv);
            }
        } else {
            for i in 0..frame_size {
                let mv = (((l_slice[i] + r_slice[i]) * 0.5).clamp(-1.0, 1.0) * 32767.0) as i16;
                pcm.push(mv);
            }
        }

        let Ok(mut guard) = enc_handle.inner.lock() else {
            return DaveByteBuffer::empty();
        };
        let mut out = vec![0u8; 4000];
        match guard.encode(&pcm, &mut out) {
            Ok(len) if len > 0 => {
                out.truncate(len);
                DaveByteBuffer::from_vec(out)
            }
            _ => DaveByteBuffer::empty(),
        }
    }))
    .unwrap_or_else(|_| DaveByteBuffer::empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use ropus::{DecodeMode, Decoder as OpusDecoder};

    #[test]
    fn test_session_lifecycle_and_key_package() {
        assert_eq!(dave_max_protocol_version(), 1);
        let handle = dave_session_new(1, 1042665958503886918, 123456789012345678);
        assert!(!handle.is_null());

        unsafe {
            assert_eq!(dave_session_protocol_version(handle), 1);
            assert!(!dave_session_is_ready(handle));
            assert!(!dave_session_can_encrypt(handle));

            let kp = dave_session_create_key_package(handle);
            assert!(!kp.ptr.is_null());
            assert!(kp.len > 64);
            dave_buffer_free(kp);

            assert!(dave_session_reinit(handle, 1, 1042665958503886918, 123456789012345678));
            let dummy_h264 = [0x00u8, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x00];
            let not_ready_vid = dave_session_encrypt_video_h264(handle, dummy_h264.as_ptr(), dummy_h264.len());
            assert!(not_ready_vid.ptr.is_null());
            dave_buffer_free(not_ready_vid);
            assert!(dave_session_reset(handle));
            dave_session_free(handle);
        }
    }

    #[test]
    fn test_xchacha20_poly1305_encrypt() {
        let key = [0x42u8; 32];
        let nonce = [0x01u8; 24];
        let aad = [0x80u8, 0x78, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1];
        let pt = [0xF8u8, 0xFF, 0xFE];
        unsafe {
            let out = dave_xchacha20_poly1305_encrypt(
                key.as_ptr(),
                nonce.as_ptr(),
                aad.as_ptr(),
                aad.len(),
                pt.as_ptr(),
                pt.len(),
            );
            assert!(!out.ptr.is_null());
            assert_eq!(out.len, pt.len() + 16);
            dave_buffer_free(out);
        }
    }

    #[test]
    fn test_opus_encode_decode_48k_stereo() {
        let enc = dave_opus_encoder_new(48000, 2, 96000);
        assert!(!enc.is_null());

        // Generate 20ms (960 samples) of 440Hz stereo sine wave
        let mut left = vec![0.0f32; 960];
        let mut right = vec![0.0f32; 960];
        for i in 0..960 {
            let t = i as f32 / 48000.0;
            left[i] = (2.0 * std::f32::consts::PI * 440.0 * t).sin() * 0.5;
            right[i] = (2.0 * std::f32::consts::PI * 880.0 * t).sin() * 0.5;
        }

        unsafe {
            let mut dec = OpusDecoder::new(48000, OpusChannels::Stereo).unwrap();
            let mut decoded_pcm = vec![0i16; 1920];
            // Encode 5 frames to let Opus warm up
            let mut max_amp = 0i32;
            for _ in 0..5 {
                let pkt = dave_opus_encoder_encode_float(enc, left.as_ptr(), right.as_ptr(), 960);
                assert!(!pkt.ptr.is_null());
                assert!(pkt.len > 10 && pkt.len < 1275);
                let bytes = slice::from_raw_parts(pkt.ptr, pkt.len);
                let samples = dec.decode(bytes, &mut decoded_pcm, DecodeMode::Normal).unwrap();
                assert_eq!(samples, 960);
                for &s in &decoded_pcm {
                    max_amp = max_amp.max((s as i32).abs());
                }
                dave_buffer_free(pkt);
            }
            assert!(max_amp > 5000, "Decoded audio amplitude too low: {max_amp}");
            dave_opus_encoder_free(enc);
        }
    }

    #[test]
    fn test_h264_sps_vui_rewriter() {
        // Helper to build a valid H.264 Baseline 1280x720 SPS with or without VUI
        fn build_baseline_sps(with_vui_and_color: bool) -> Vec<u8> {
            let mut w = AnnexBWriter::new(32);
            w.write_bits(0x67, 8); // NAL header (SPS)
            w.write_bits(66, 8);   // profile_idc = Baseline (0x42)
            w.write_bits(0xC0, 8); // constraint_set0 + constraint_set1
            w.write_bits(31, 8);   // level_idc = 3.1
            w.write_ue(0);         // sps_id
            w.write_ue(0);         // log2_max_frame_num_minus4
            w.write_ue(2);         // poc_type = 2
            w.write_ue(1);         // max_num_ref_frames = 1
            w.write_bits(0, 1);    // gaps_in_frame_num_value_allowed_flag
            w.write_ue(79);        // pic_width_in_mbs_minus1 (1280)
            w.write_ue(44);        // pic_height_in_map_units_minus1 (720)
            w.write_bits(1, 1);    // frame_mbs_only_flag
            w.write_bits(1, 1);    // direct_8x8_inference_flag
            w.write_bits(0, 1);    // frame_cropping_flag
            if !with_vui_and_color {
                w.write_bits(0, 1); // vui_parameters_present_flag = 0
            } else {
                w.write_bits(1, 1); // vui_parameters_present_flag = 1
                w.write_bits(0, 1); // aspect_ratio = 0
                w.write_bits(0, 1); // overscan = 0
                // Apple VideoToolbox style video_signal_type + colour_description
                w.write_bits(1, 1); // video_signal_type_present_flag = 1
                w.write_bits(5, 3); // video_format
                w.write_bits(0, 1); // video_full_range_flag
                w.write_bits(1, 1); // colour_description_present_flag = 1
                w.write_bits(1, 8); // colour_primaries (BT.709)
                w.write_bits(1, 8); // transfer_characteristics
                w.write_bits(1, 8); // matrix_coeffs
                w.write_bits(0, 1); // chroma_loc_info = 0
                w.write_bits(1, 1); // timing_info_present_flag = 1
                w.write_bits(1, 32);  // num_units_in_tick
                w.write_bits(60, 32); // time_scale
                w.write_bits(1, 1);   // fixed_frame_rate_flag
                w.write_bits(0, 1); // nal_hrd = 0
                w.write_bits(0, 1); // vcl_hrd = 0
                w.write_bits(0, 1); // pic_struct = 0
                w.write_bits(1, 1); // bitstream_restriction = 1
                w.write_bits(1, 1); // motion_vectors_over_pic_boundaries
                w.write_ue(2);
                w.write_ue(1);
                w.write_ue(16);
                w.write_ue(16);
                w.write_ue(2); // old max_num_reorder_frames = 2 (causes Chrome stall!)
                w.write_ue(4); // old max_dec_frame_buffering = 4
            }
            w.finish()
        }

        // Parse rewritten Baseline SPS and verify VUI fields
        fn verify_rewritten_baseline(out: &[u8], expect_timing: bool) {
            assert_eq!(out[0], 0x67);
            let mut r = AnnexBReader::new(&out[1..]);
            assert_eq!(r.read_bits(8), Some(66));
            assert_eq!(r.read_bits(8), Some(0xC0));
            assert_eq!(r.read_bits(8), Some(31));
            assert_eq!(r.read_ue(), Some(0));
            assert_eq!(r.read_ue(), Some(0));
            assert_eq!(r.read_ue(), Some(2));
            assert_eq!(r.read_ue(), Some(1));
            assert_eq!(r.read_bits(1), Some(0));
            assert_eq!(r.read_ue(), Some(79));
            assert_eq!(r.read_ue(), Some(44));
            assert_eq!(r.read_bits(1), Some(1));
            assert_eq!(r.read_bits(1), Some(1));
            assert_eq!(r.read_bits(1), Some(0));
            // VUI must be present
            assert_eq!(r.read_bits(1), Some(1));
            assert_eq!(r.read_bits(1), Some(0)); // aspect_ratio
            assert_eq!(r.read_bits(1), Some(0)); // overscan
            assert_eq!(r.read_bits(1), Some(0)); // video_signal_type MUST be stripped (0)!
            assert_eq!(r.read_bits(1), Some(0)); // chroma_loc
            let timing = r.read_bits(1).unwrap();
            assert_eq!(timing, if expect_timing { 1 } else { 0 });
            if timing != 0 {
                assert_eq!(r.read_bits(32), Some(1));
                assert_eq!(r.read_bits(32), Some(60));
                assert_eq!(r.read_bits(1), Some(1));
            }
            assert_eq!(r.read_bits(1), Some(0)); // nal_hrd
            assert_eq!(r.read_bits(1), Some(0)); // vcl_hrd
            assert_eq!(r.read_bits(1), Some(0)); // pic_struct
            assert_eq!(r.read_bits(1), Some(1)); // bitstream_restriction MUST be 1
            assert_eq!(r.read_bits(1), Some(1)); // mv_over_pic_boundaries
            assert_eq!(r.read_ue(), Some(2));
            assert_eq!(r.read_ue(), Some(1));
            assert_eq!(r.read_ue(), Some(16));
            assert_eq!(r.read_ue(), Some(16));
            assert_eq!(r.read_ue(), Some(0)); // max_num_reorder_frames MUST be 0!
            assert_eq!(r.read_ue(), Some(1)); // max_dec_frame_buffering
        }

        // Case 1: Baseline SPS without VUI
        let sps_no_vui = build_baseline_sps(false);
        unsafe {
            let rewritten = dave_h264_rewrite_sps_vui(sps_no_vui.as_ptr(), sps_no_vui.len());
            assert!(!rewritten.ptr.is_null());
            let out = slice::from_raw_parts(rewritten.ptr, rewritten.len);
            verify_rewritten_baseline(out, false);
            dave_buffer_free(rewritten);
        }

        // Case 2: Apple VideoToolbox-style SPS with video_signal_type + reorder_frames=2
        let sps_vt = build_baseline_sps(true);
        unsafe {
            let rewritten = dave_h264_rewrite_sps_vui(sps_vt.as_ptr(), sps_vt.len());
            assert!(!rewritten.ptr.is_null());
            let out = slice::from_raw_parts(rewritten.ptr, rewritten.len);
            verify_rewritten_baseline(out, true);
            dave_buffer_free(rewritten);
        }
    }
}
