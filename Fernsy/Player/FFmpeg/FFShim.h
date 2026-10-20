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

// MARK: - MPEG-TS muxing (timeshift buffer and recordings)

typedef int (*ffs_write_cb)(void *opaque, const uint8_t *buf, int size);
typedef struct FFSMuxer FFSMuxer;

/// MPEG-TS muxer writing through `write`. Timestamps come out shifted by ffs_mux_delay().
FFSMuxer *ffs_mux_alloc(void *opaque, ffs_write_cb write);
/// Adds a stream copying `par`; returns its index or a negative error.
int ffs_mux_add_stream(FFSMuxer *m, const AVCodecParameters *par, const char *language);
/// Adds an ADTS AAC stream (audio we demux ourselves).
int ffs_mux_add_aac(FFSMuxer *m, int sample_rate, int channels);
int ffs_mux_begin(FFSMuxer *m);
/// Writes the packet (timestamps in `tb`; the caller still owns and unrefs it). With
/// `resync_point`, buffered bytes are written out first and PAT/PMT are repeated, so a
/// reader starting at the byte offset reached before this call can decode from there.
int ffs_mux_write(FFSMuxer *m, AVPacket *pkt, int out_index, AVRational tb, int resync_point);
void ffs_mux_flush(FFSMuxer *m);
/// Writes the trailer (when started) and frees everything.
void ffs_mux_free(FFSMuxer **m);
double ffs_mux_delay(void);

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

/// One picture of a bitmap subtitle (PGS, VobSub, DVB): premultiplied BGRA, `stride` = w * 4.
typedef struct {
    int x, y, w, h;
    uint8_t *pixels;
} FFSBitmapRect;

/// Decodes one bitmap subtitle packet. Returns the number of pictures (0 = the subtitle is
/// cleared), or -1 when nothing was produced. start/end are seconds relative to the packet
/// time (end < 0 = until the next subtitle); canvas is the codec's display size (0 = unknown).
int ffs_decode_bitmap_subtitle(AVCodecContext *ctx, AVPacket *pkt, FFSBitmapRect **rects,
                               double *start, double *end, int *canvas_w, int *canvas_h);
void ffs_free_bitmap_rects(FFSBitmapRect *rects, int count);

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
