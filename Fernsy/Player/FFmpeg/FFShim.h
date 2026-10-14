//  Thin C layer over FFmpeg for the parts that are awkward from Swift:
//  macros, function-pointer callbacks, filter graphs and CVPixelBuffer plumbing.

#ifndef FFShim_h
#define FFShim_h

#include <libavformat/avformat.h>
#include <libavformat/avio.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_videotoolbox.h>
#include <libavutil/pixdesc.h>
#include <libavfilter/avfilter.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreVideo/CoreVideo.h>

// MARK: - Constants that are macros in FFmpeg

static inline int ffs_error_eagain(void) { return AVERROR(EAGAIN); }
static inline int ffs_error_eof(void) { return AVERROR_EOF; }
static inline int ffs_error_exit(void) { return AVERROR_EXIT; }
static inline int ffs_error_eio(void) { return AVERROR(EIO); }
static inline int64_t ffs_nopts(void) { return AV_NOPTS_VALUE; }
static inline int ffs_avseek_size(void) { return AVSEEK_SIZE; }
static inline int ffs_avseek_force(void) { return AVSEEK_FORCE; }
static inline int64_t ffs_time_base(void) { return AV_TIME_BASE; }

// MARK: - Custom I/O

typedef int (*ffs_read_cb)(void *opaque, uint8_t *buf, int size);
typedef int64_t (*ffs_seek_cb)(void *opaque, int64_t offset, int whence);
typedef int (*ffs_interrupt_cb)(void *opaque);

AVIOContext *ffs_avio_alloc(void *opaque, int buffer_size, int seekable, ffs_read_cb read, ffs_seek_cb seek);
void ffs_avio_free(AVIOContext **pb);
void ffs_set_interrupt(AVFormatContext *fmt, ffs_interrupt_cb cb, void *opaque);

// MARK: - Stream helpers

const char *ffs_metadata(AVDictionary *dict, const char *key);
int ffs_is_text_subtitle(enum AVCodecID codec_id);
int ffs_is_attached_pic(const AVStream *st);

// MARK: - Decoders

/// Opens a decoder for the stream. Video decoders get a VideoToolbox device when
/// `try_hw` is set; FFmpeg falls back to software if the hwaccel refuses the stream.
AVCodecContext *ffs_open_decoder(const AVStream *st, int try_hw);

/// Opens a decoder by codec id (for elementary streams we demux ourselves).
AVCodecContext *ffs_open_decoder_id(enum AVCodecID codec_id, AVRational pkt_timebase);

/// Allocates a packet holding a copy of `size` bytes.
AVPacket *ffs_packet_from_bytes(const uint8_t *data, int size, int64_t pts, int64_t duration);

/// Decodes one subtitle packet into plain text (ASS markup stripped).
/// Returns 1 and a malloc'd UTF-8 string in *text when a text cue was produced.
/// start/end are offsets in seconds relative to the packet PTS (end < 0 = unknown).
int ffs_decode_text_subtitle(AVCodecContext *ctx, AVPacket *pkt, char **text, double *start, double *end);

// MARK: - Frame -> CVPixelBuffer

typedef struct FFSPixConv FFSPixConv;
FFSPixConv *ffs_pixconv_alloc(void);
void ffs_pixconv_free(FFSPixConv **pc);

/// Hardware frames are returned zero-copy; software frames are converted into
/// IOSurface-backed NV12/P010 buffers. Colour attachments are set either way.
CVPixelBufferRef ffs_frame_to_pixbuf(FFSPixConv *pc, const AVFrame *frame) CF_RETURNS_RETAINED;

// MARK: - Deinterlacing (yadif_videotoolbox on the GPU, bwdif on the CPU)

typedef struct FFSDeint FFSDeint;
FFSDeint *ffs_deint_create(const AVFrame *frame, AVRational time_base);
int ffs_deint_matches(const FFSDeint *d, const AVFrame *frame);
int ffs_deint_is_hw(const FFSDeint *d);
/// Takes ownership of the frame's references (frame is reset). NULL flushes.
int ffs_deint_push(FFSDeint *d, AVFrame *frame);
int ffs_deint_pull(FFSDeint *d, AVFrame *out);
AVRational ffs_deint_time_base(const FFSDeint *d);
void ffs_deint_free(FFSDeint **d);

// MARK: - Audio resampling to interleaved float32

typedef struct FFSResampler FFSResampler;
FFSResampler *ffs_resampler_alloc(void);
void ffs_resampler_free(FFSResampler **r);
/// Channel count the renderer should receive for a given source (2 or 6).
int ffs_output_channels(int in_channels);
/// Returns the number of output frames; *out stays valid until the next call.
int ffs_resample(FFSResampler *r, const AVFrame *frame, int out_channels, const uint8_t **out);

#endif
