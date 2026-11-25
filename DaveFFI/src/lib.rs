use std::num::NonZeroU16;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::slice;
use std::sync::Mutex;

use chacha20poly1305::{
    XChaCha20Poly1305, XNonce,
    aead::{Aead, KeyInit, Payload},
};
use davey::{DAVE_PROTOCOL_VERSION, DaveSession, ProposalsOperationType};
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
}
