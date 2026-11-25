#ifndef DAVE_FFI_H
#define DAVE_FFI_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DaveSessionHandle DaveSessionHandle;
typedef struct DaveOpusEncoderHandle DaveOpusEncoderHandle;
typedef struct DaveWebRtcHandle DaveWebRtcHandle;

typedef struct {
    uint8_t *ptr;
    size_t len;
    size_t cap;
} DaveByteBuffer;

void dave_buffer_free(DaveByteBuffer buf);

uint16_t dave_max_protocol_version(void);

DaveSessionHandle *dave_session_new(uint16_t protocol_version, uint64_t user_id, uint64_t channel_id);
void dave_session_free(DaveSessionHandle *handle);
bool dave_session_reinit(DaveSessionHandle *handle, uint16_t protocol_version, uint64_t user_id, uint64_t channel_id);
bool dave_session_reset(DaveSessionHandle *handle);

bool dave_session_is_ready(const DaveSessionHandle *handle);
bool dave_session_can_encrypt(const DaveSessionHandle *handle);
uint16_t dave_session_protocol_version(const DaveSessionHandle *handle);

DaveByteBuffer dave_session_create_key_package(DaveSessionHandle *handle);
bool dave_session_set_external_sender(DaveSessionHandle *handle, const uint8_t *data, size_t len);

bool dave_session_process_proposals(
    DaveSessionHandle *handle,
    uint8_t operation_type,
    const uint8_t *proposals,
    size_t proposals_len,
    const uint64_t *expected_user_ids,
    size_t expected_user_ids_len,
    DaveByteBuffer *out_commit_welcome
);

/* Returns: 1 = processed (should prepare transition), 0 = ignored, -1 = error */
int32_t dave_session_process_commit(DaveSessionHandle *handle, const uint8_t *commit, size_t commit_len);

bool dave_session_process_welcome(
    DaveSessionHandle *handle,
    const uint8_t *welcome,
    size_t welcome_len,
    const uint64_t *recognized_user_ids,
    size_t recognized_user_ids_len
);

bool dave_session_prepare_transition(DaveSessionHandle *handle, uint16_t transition_id, uint16_t protocol_version);

/* Returns: 1 = executed, 0 = no pending transition, -1 = error */
int32_t dave_session_execute_transition(DaveSessionHandle *handle, uint16_t transition_id);

void dave_session_set_passthrough_mode(DaveSessionHandle *handle, bool passthrough, uint32_t transition_expiry);

DaveByteBuffer dave_session_encrypt_opus(DaveSessionHandle *handle, const uint8_t *opus_data, size_t opus_len);
DaveByteBuffer dave_session_encrypt_video_h264(DaveSessionHandle *handle, const uint8_t *annexb_data, size_t annexb_len);
DaveByteBuffer dave_h264_rewrite_sps_vui(const uint8_t *sps_nalu, size_t sps_len);

/* Transport AEAD helper: XChaCha20-Poly1305 (key = 32 bytes, nonce = 24 bytes) */
DaveByteBuffer dave_xchacha20_poly1305_encrypt(
    const uint8_t *key,
    const uint8_t *nonce24,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t *plaintext,
    size_t plaintext_len
);

/* Pure-Rust Xiph Opus Encoder (48kHz Stereo, 20ms = 960 frames/channel) */
DaveOpusEncoderHandle *dave_opus_encoder_new(int32_t sample_rate, int32_t channels, int32_t bitrate);
void dave_opus_encoder_free(DaveOpusEncoderHandle *handle);
DaveByteBuffer dave_opus_encoder_encode_float(
    DaveOpusEncoderHandle *handle,
    const float *left,
    const float *right,
    size_t frame_size
);

/* Pure-Rust WebRTC Transport (str0m + dimpl DTLS-SRTP + ICE + RTCP SR/NACK/RTX/PLI) */
DaveWebRtcHandle *dave_webrtc_new(uint32_t audio_ssrc, uint32_t video_ssrc, uint32_t rtx_ssrc);
void dave_webrtc_free(DaveWebRtcHandle *handle);
DaveByteBuffer dave_webrtc_get_offer_sdp(const DaveWebRtcHandle *handle);
bool dave_webrtc_set_discord_answer(DaveWebRtcHandle *handle, const uint8_t *sdp_utf8, size_t sdp_len);
bool dave_webrtc_is_connected(const DaveWebRtcHandle *handle);
bool dave_webrtc_take_keyframe_request(const DaveWebRtcHandle *handle);
uint64_t dave_webrtc_tx_video_packets(const DaveWebRtcHandle *handle);
bool dave_webrtc_send_opus(DaveWebRtcHandle *handle, const uint8_t *opus_data, size_t opus_len);
bool dave_webrtc_send_h264(DaveWebRtcHandle *handle, const uint8_t *annexb_data, size_t annexb_len, double frametime_ms);

#ifdef __cplusplus
}
#endif

#endif /* DAVE_FFI_H */
