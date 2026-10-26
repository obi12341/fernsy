#include "FFShim.h"

#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#include <libavutil/opt.h>
#include <libavutil/dovi_meta.h>
#include <string.h>
#include <stdlib.h>

// MARK: - Custom I/O

AVIOContext *ffs_avio_alloc(void *opaque, int buffer_size, int seekable, ffs_read_cb read, ffs_seek_cb seek) {
    unsigned char *buffer = av_malloc(buffer_size);
    if (!buffer) return NULL;
    AVIOContext *pb = avio_alloc_context(buffer, buffer_size, 0, opaque, read, NULL, seekable ? seek : NULL);
    if (!pb) {
        av_free(buffer);
        return NULL;
    }
    pb->seekable = seekable ? AVIO_SEEKABLE_NORMAL : 0;
    return pb;
}

void ffs_avio_free(AVIOContext **pb) {
    if (!pb || !*pb) return;
    av_freep(&(*pb)->buffer);
    avio_context_free(pb);
}

void ffs_set_interrupt(AVFormatContext *fmt, ffs_interrupt_cb cb, void *opaque) {
    fmt->interrupt_callback.callback = cb;
    fmt->interrupt_callback.opaque = opaque;
}

// MARK: - MPEG-TS muxing

struct FFSMuxer {
    AVFormatContext *fmt;
    AVIOContext *pb;
    int started;
};

// max_delay; the mpegts muxer offsets every timestamp by twice this.
static const int64_t ffs_max_delay = 350000;

double ffs_mux_delay(void) { return 2.0 * ffs_max_delay / AV_TIME_BASE; }

FFSMuxer *ffs_mux_alloc(void *opaque, ffs_write_cb write) {
    FFSMuxer *m = av_mallocz(sizeof(*m));
    if (!m) return NULL;
    if (avformat_alloc_output_context2(&m->fmt, NULL, "mpegts", NULL) < 0 || !m->fmt) {
        av_free(m);
        return NULL;
    }
    const int size = 64 * 1024;
    unsigned char *buffer = av_malloc(size);
    m->pb = buffer ? avio_alloc_context(buffer, size, 1, opaque, NULL, write, NULL) : NULL;
    if (!m->pb) {
        av_free(buffer);
        avformat_free_context(m->fmt);
        av_free(m);
        return NULL;
    }
    m->fmt->pb = m->pb;
    m->fmt->flags |= AVFMT_FLAG_CUSTOM_IO;
    m->fmt->max_delay = ffs_max_delay;
    return m;
}

int ffs_mux_add_stream(FFSMuxer *m, const AVCodecParameters *par, const char *language) {
    AVStream *st = avformat_new_stream(m->fmt, NULL);
    if (!st) return AVERROR(ENOMEM);
    int ret = avcodec_parameters_copy(st->codecpar, par);
    if (ret < 0) return ret;
    st->codecpar->codec_tag = 0;
    st->time_base = (AVRational){ 1, 90000 };
    if (language && *language) av_dict_set(&st->metadata, "language", language, 0);
    return st->index;
}

int ffs_mux_add_aac(FFSMuxer *m, int sample_rate, int channels) {
    AVStream *st = avformat_new_stream(m->fmt, NULL);
    if (!st) return AVERROR(ENOMEM);
    st->codecpar->codec_type = AVMEDIA_TYPE_AUDIO;
    st->codecpar->codec_id = AV_CODEC_ID_AAC;
    st->codecpar->sample_rate = sample_rate > 0 ? sample_rate : 48000;
    av_channel_layout_default(&st->codecpar->ch_layout, channels > 0 ? channels : 2);
    st->time_base = (AVRational){ 1, 90000 };
    return st->index;
}

int ffs_mux_begin(FFSMuxer *m) {
    AVDictionary *opts = NULL;
    // Frequent PAT/PMT so recordings cut out of the stream start quickly.
    av_dict_set(&opts, "pat_period", "0.2", 0);
    int ret = avformat_write_header(m->fmt, &opts);
    av_dict_free(&opts);
    if (ret >= 0) m->started = 1;
    return ret;
}

int ffs_mux_write(FFSMuxer *m, AVPacket *pkt, int out_index, AVRational tb, int resync_point) {
    if (out_index < 0 || out_index >= (int)m->fmt->nb_streams) return AVERROR(EINVAL);
    if (resync_point) {
        avio_flush(m->pb);
        av_opt_set(m->fmt->priv_data, "mpegts_flags", "+resend_headers", 0);
    }
    pkt->stream_index = out_index;
    pkt->pos = -1;
    av_packet_rescale_ts(pkt, tb, m->fmt->streams[out_index]->time_base);
    return av_write_frame(m->fmt, pkt);
}

void ffs_mux_flush(FFSMuxer *m) {
    if (m && m->pb) avio_flush(m->pb);
}

void ffs_mux_free(FFSMuxer **pm) {
    if (!pm || !*pm) return;
    FFSMuxer *m = *pm;
    if (m->started) av_write_trailer(m->fmt);
    if (m->pb) {
        avio_flush(m->pb);
        av_freep(&m->pb->buffer);
        avio_context_free(&m->pb);
    }
    avformat_free_context(m->fmt);
    av_freep(pm);
}

// MARK: - Stream helpers

const char *ffs_metadata(AVDictionary *dict, const char *key) {
    const AVDictionaryEntry *e = av_dict_get(dict, key, NULL, 0);
    return e ? e->value : NULL;
}

int ffs_is_text_subtitle(enum AVCodecID codec_id) {
    const AVCodecDescriptor *d = avcodec_descriptor_get(codec_id);
    return d && (d->props & AV_CODEC_PROP_TEXT_SUB);
}

int ffs_is_attached_pic(const AVStream *st) {
    return (st->disposition & AV_DISPOSITION_ATTACHED_PIC) != 0;
}

// MARK: - Decoders

static enum AVPixelFormat ffs_get_format(AVCodecContext *ctx, const enum AVPixelFormat *fmts) {
    const enum AVPixelFormat *p;
    if (ctx->hw_device_ctx) {
        for (p = fmts; *p != AV_PIX_FMT_NONE; p++) {
            if (*p == AV_PIX_FMT_VIDEOTOOLBOX) return *p;
        }
    }
    // Hwaccel unavailable or failed to initialise: first software format.
    for (p = fmts; *p != AV_PIX_FMT_NONE; p++) {
        const AVPixFmtDescriptor *desc = av_pix_fmt_desc_get(*p);
        if (desc && !(desc->flags & AV_PIX_FMT_FLAG_HWACCEL)) return *p;
    }
    return AV_PIX_FMT_NONE;
}

AVCodecContext *ffs_open_decoder(const AVStream *st, int try_hw) {
    const AVCodec *codec = avcodec_find_decoder(st->codecpar->codec_id);
    if (!codec) return NULL;
    AVCodecContext *ctx = avcodec_alloc_context3(codec);
    if (!ctx) return NULL;
    if (avcodec_parameters_to_context(ctx, st->codecpar) < 0) {
        avcodec_free_context(&ctx);
        return NULL;
    }
    ctx->pkt_timebase = st->time_base;

    if (codec->type == AVMEDIA_TYPE_VIDEO) {
        ctx->get_format = ffs_get_format;
        ctx->thread_count = 0;
        ctx->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;
        if (try_hw) {
            AVBufferRef *device = NULL;
            if (av_hwdevice_ctx_create(&device, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, NULL, NULL, 0) == 0) {
                ctx->hw_device_ctx = device;
            }
        }
    } else if (codec->type == AVMEDIA_TYPE_AUDIO) {
        ctx->thread_count = 1;
    }

    if (avcodec_open2(ctx, codec, NULL) < 0) {
        avcodec_free_context(&ctx);
        return NULL;
    }
    return ctx;
}

AVCodecContext *ffs_open_decoder_id(enum AVCodecID codec_id, AVRational pkt_timebase) {
    const AVCodec *codec = avcodec_find_decoder(codec_id);
    if (!codec) return NULL;
    AVCodecContext *ctx = avcodec_alloc_context3(codec);
    if (!ctx) return NULL;
    ctx->pkt_timebase = pkt_timebase;
    ctx->thread_count = 1;
    if (avcodec_open2(ctx, codec, NULL) < 0) {
        avcodec_free_context(&ctx);
        return NULL;
    }
    return ctx;
}

AVPacket *ffs_packet_from_bytes(const uint8_t *data, int size, int64_t pts, int64_t duration) {
    AVPacket *pkt = av_packet_alloc();
    if (!pkt) return NULL;
    if (av_new_packet(pkt, size) < 0) {
        av_packet_free(&pkt);
        return NULL;
    }
    memcpy(pkt->data, data, size);
    pkt->pts = pts;
    pkt->dts = pts;
    pkt->duration = duration;
    return pkt;
}

// MARK: - Subtitles

static char *ffs_strip_ass(const char *ass) {
    // Dialogue payload: ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text
    const char *text = ass;
    for (int commas = 0; commas < 8 && text; commas++) {
        text = strchr(text, ',');
        if (text) text++;
    }
    if (!text) text = ass;

    size_t len = strlen(text);
    char *out = malloc(len + 1);
    if (!out) return NULL;
    size_t o = 0;
    int in_tag = 0;
    for (size_t i = 0; i < len; i++) {
        char c = text[i];
        if (in_tag) {
            if (c == '}') in_tag = 0;
            continue;
        }
        if (c == '{') { in_tag = 1; continue; }
        if (c == '\\' && i + 1 < len && (text[i + 1] == 'N' || text[i + 1] == 'n')) {
            out[o++] = '\n';
            i++;
            continue;
        }
        if (c == '\\' && i + 1 < len && text[i + 1] == 'h') {
            out[o++] = ' ';
            i++;
            continue;
        }
        if (c == '\r') continue;
        out[o++] = c;
    }
    while (o > 0 && (out[o - 1] == '\n' || out[o - 1] == ' ')) o--;
    out[o] = 0;
    return out;
}

int ffs_decode_text_subtitle(AVCodecContext *ctx, AVPacket *pkt, char **text, double *start, double *end) {
    AVSubtitle sub;
    int got = 0;
    *text = NULL;
    if (avcodec_decode_subtitle2(ctx, &sub, &got, pkt) < 0 || !got) return 0;

    size_t cap = 0, used = 0;
    char *joined = NULL;
    for (unsigned i = 0; i < sub.num_rects; i++) {
        AVSubtitleRect *r = sub.rects[i];
        char *piece = NULL;
        if (r->type == SUBTITLE_ASS && r->ass) piece = ffs_strip_ass(r->ass);
        else if (r->type == SUBTITLE_TEXT && r->text) piece = strdup(r->text);
        if (!piece) continue;
        size_t plen = strlen(piece);
        if (plen == 0) { free(piece); continue; }
        if (used + plen + 2 > cap) {
            cap = (used + plen + 2) * 2;
            joined = realloc(joined, cap);
        }
        if (used > 0) joined[used++] = '\n';
        memcpy(joined + used, piece, plen);
        used += plen;
        joined[used] = 0;
        free(piece);
    }

    *start = sub.start_display_time / 1000.0;
    *end = (sub.end_display_time > 0 && sub.end_display_time != UINT32_MAX) ? sub.end_display_time / 1000.0 : -1;
    avsubtitle_free(&sub);

    if (!joined) {
        // An empty cue clears the current subtitle.
        joined = strdup("");
    }
    *text = joined;
    return 1;
}

int ffs_decode_bitmap_subtitle(AVCodecContext *ctx, AVPacket *pkt, FFSBitmapRect **rects,
                               double *start, double *end, int *canvas_w, int *canvas_h) {
    AVSubtitle sub;
    int got = 0;
    *rects = NULL;
    if (avcodec_decode_subtitle2(ctx, &sub, &got, pkt) < 0 || !got) return -1;

    int count = 0;
    FFSBitmapRect *out = sub.num_rects ? calloc(sub.num_rects, sizeof(FFSBitmapRect)) : NULL;
    for (unsigned i = 0; i < sub.num_rects; i++) {
        AVSubtitleRect *r = sub.rects[i];
        if (r->type != SUBTITLE_BITMAP || r->w <= 0 || r->h <= 0 || !r->data[0] || !r->data[1]) continue;
        uint8_t *pixels = malloc((size_t)r->w * r->h * 4);
        if (!pixels) continue;
        // data[0]: palette indices, data[1]: up to 256 ARGB colours (native endian, straight alpha).
        const uint32_t *palette = (const uint32_t *)r->data[1];
        for (int y = 0; y < r->h; y++) {
            const uint8_t *src = r->data[0] + (size_t)y * r->linesize[0];
            uint8_t *dst = pixels + (size_t)y * r->w * 4;
            for (int x = 0; x < r->w; x++) {
                uint32_t c = palette[src[x]];
                uint32_t a = c >> 24, red = (c >> 16) & 0xff, green = (c >> 8) & 0xff, blue = c & 0xff;
                dst[x * 4 + 0] = (uint8_t)(blue * a / 255);
                dst[x * 4 + 1] = (uint8_t)(green * a / 255);
                dst[x * 4 + 2] = (uint8_t)(red * a / 255);
                dst[x * 4 + 3] = (uint8_t)a;
            }
        }
        out[count++] = (FFSBitmapRect){ r->x, r->y, r->w, r->h, pixels };
    }
    *start = sub.start_display_time / 1000.0;
    *end = (sub.end_display_time > 0 && sub.end_display_time != UINT32_MAX) ? sub.end_display_time / 1000.0 : -1;
    *canvas_w = ctx->width;
    *canvas_h = ctx->height;
    avsubtitle_free(&sub);
    if (count == 0) { free(out); out = NULL; }
    *rects = out;
    return count;
}

void ffs_free_bitmap_rects(FFSBitmapRect *rects, int count) {
    if (!rects) return;
    for (int i = 0; i < count; i++) free(rects[i].pixels);
    free(rects);
}

// MARK: - Dolby Vision

int ffs_dovi_config(const AVCodecParameters *par, int *level, int *compat_id, uint8_t dvcc[24]) {
    const AVPacketSideData *sd = av_packet_side_data_get(par->coded_side_data, par->nb_coded_side_data, AV_PKT_DATA_DOVI_CONF);
    if (!sd || sd->size < (int)sizeof(AVDOVIDecoderConfigurationRecord)) return 0;
    const AVDOVIDecoderConfigurationRecord *c = (const AVDOVIDecoderConfigurationRecord *)sd->data;
    memset(dvcc, 0, 24);
    dvcc[0] = c->dv_version_major;
    dvcc[1] = c->dv_version_minor;
    // profile(7) level(6) rpu(1) el(1) bl(1), then compatibility id(4) md_compression(2) reserved(2)
    uint16_t bits = (uint16_t)((c->dv_profile & 0x7f) << 9 | (c->dv_level & 0x3f) << 3 |
                               (c->rpu_present_flag & 1) << 2 | (c->el_present_flag & 1) << 1 | (c->bl_present_flag & 1));
    dvcc[2] = bits >> 8;
    dvcc[3] = bits & 0xff;
    dvcc[4] = (uint8_t)((c->dv_bl_signal_compatibility_id & 0x0f) << 4 | (c->dv_md_compression & 0x03) << 2);
    *level = c->dv_level;
    *compat_id = c->dv_bl_signal_compatibility_id;
    return c->dv_profile;
}

int ffs_extradata_is_hvcc(const AVCodecParameters *par) {
    return par->extradata && par->extradata_size >= 23 && par->extradata[0] == 1;
}

// MARK: - Frame -> CVPixelBuffer

struct FFSPixConv {
    struct SwsContext *sws;
    CVPixelBufferPoolRef pool;
    int width, height;
    OSType cv_format;
};

FFSPixConv *ffs_pixconv_alloc(void) {
    return calloc(1, sizeof(FFSPixConv));
}

void ffs_pixconv_free(FFSPixConv **pc) {
    if (!pc || !*pc) return;
    sws_freeContext((*pc)->sws);
    if ((*pc)->pool) CVPixelBufferPoolRelease((*pc)->pool);
    free(*pc);
    *pc = NULL;
}

static void ffs_set_pixel_aspect(CVPixelBufferRef pb, AVRational sar) {
    if (sar.num <= 0 || sar.den <= 0 || sar.num == sar.den) return;
    CFNumberRef h = CFNumberCreate(NULL, kCFNumberIntType, &sar.num);
    CFNumberRef v = CFNumberCreate(NULL, kCFNumberIntType, &sar.den);
    const void *keys[] = { kCVImageBufferPixelAspectRatioHorizontalSpacingKey, kCVImageBufferPixelAspectRatioVerticalSpacingKey };
    const void *values[] = { h, v };
    CFDictionaryRef dict = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CVBufferSetAttachment(pb, kCVImageBufferPixelAspectRatioKey, dict, kCVAttachmentMode_ShouldPropagate);
    CFRelease(dict);
    CFRelease(h);
    CFRelease(v);
}

static int ffs_ensure_pool(FFSPixConv *pc, int w, int h, OSType fmt) {
    if (pc->pool && pc->width == w && pc->height == h && pc->cv_format == fmt) return 0;
    if (pc->pool) CVPixelBufferPoolRelease(pc->pool);
    pc->pool = NULL;

    int32_t fmt32 = (int32_t)fmt;
    CFNumberRef cfFmt = CFNumberCreate(NULL, kCFNumberSInt32Type, &fmt32);
    CFNumberRef cfW = CFNumberCreate(NULL, kCFNumberIntType, &w);
    CFNumberRef cfH = CFNumberCreate(NULL, kCFNumberIntType, &h);
    CFDictionaryRef ioSurface = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    const void *keys[] = {
        kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferWidthKey, kCVPixelBufferHeightKey,
        kCVPixelBufferIOSurfacePropertiesKey, kCVPixelBufferMetalCompatibilityKey,
    };
    const void *values[] = { cfFmt, cfW, cfH, ioSurface, kCFBooleanTrue };
    CFDictionaryRef attrs = CFDictionaryCreate(NULL, keys, values, 5, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CVReturn ret = CVPixelBufferPoolCreate(NULL, NULL, attrs, &pc->pool);
    CFRelease(attrs);
    CFRelease(ioSurface);
    CFRelease(cfFmt);
    CFRelease(cfW);
    CFRelease(cfH);
    if (ret != kCVReturnSuccess) {
        pc->pool = NULL;
        return -1;
    }
    pc->width = w;
    pc->height = h;
    pc->cv_format = fmt;
    return 0;
}

CVPixelBufferRef ffs_frame_to_pixbuf(FFSPixConv *pc, const AVFrame *frame) {
    if (frame->format == AV_PIX_FMT_VIDEOTOOLBOX) {
        CVPixelBufferRef pb = (CVPixelBufferRef)frame->data[3];
        if (!pb) return NULL;
        CVPixelBufferRetain(pb);
        av_vt_pixbuf_set_attachments(NULL, pb, frame);
        ffs_set_pixel_aspect(pb, frame->sample_aspect_ratio);
        return pb;
    }

    const AVPixFmtDescriptor *desc = av_pix_fmt_desc_get(frame->format);
    if (!desc) return NULL;
    int high_depth = desc->comp[0].depth > 8;
    OSType cv_fmt = high_depth ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                               : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    enum AVPixelFormat dst_fmt = high_depth ? AV_PIX_FMT_P010LE : AV_PIX_FMT_NV12;
    int w = frame->width, h = frame->height;

    if (ffs_ensure_pool(pc, w, h, cv_fmt) < 0) return NULL;
    pc->sws = sws_getCachedContext(pc->sws, w, h, frame->format, w, h, dst_fmt, SWS_BICUBIC, NULL, NULL, NULL);
    if (!pc->sws) return NULL;

    CVPixelBufferRef pb = NULL;
    if (CVPixelBufferPoolCreatePixelBuffer(NULL, pc->pool, &pb) != kCVReturnSuccess) return NULL;

    CVPixelBufferLockBaseAddress(pb, 0);
    uint8_t *dst[4] = {
        CVPixelBufferGetBaseAddressOfPlane(pb, 0),
        CVPixelBufferGetBaseAddressOfPlane(pb, 1),
        NULL, NULL,
    };
    int dst_stride[4] = {
        (int)CVPixelBufferGetBytesPerRowOfPlane(pb, 0),
        (int)CVPixelBufferGetBytesPerRowOfPlane(pb, 1),
        0, 0,
    };
    sws_scale(pc->sws, (const uint8_t *const *)frame->data, frame->linesize, 0, h, dst, dst_stride);
    CVPixelBufferUnlockBaseAddress(pb, 0);

    av_vt_pixbuf_set_attachments(NULL, pb, frame);
    ffs_set_pixel_aspect(pb, frame->sample_aspect_ratio);
    return pb;
}

// MARK: - Deinterlacing

struct FFSDeint {
    AVFilterGraph *graph;
    AVFilterContext *src;
    AVFilterContext *sink;
    int width, height, format;
    int hw;
};

FFSDeint *ffs_deint_create(const AVFrame *frame, AVRational time_base) {
    int hw = frame->format == AV_PIX_FMT_VIDEOTOOLBOX;
    if (hw && !frame->hw_frames_ctx) return NULL;

    FFSDeint *d = calloc(1, sizeof(FFSDeint));
    if (!d) return NULL;
    d->graph = avfilter_graph_alloc();
    d->width = frame->width;
    d->height = frame->height;
    d->format = frame->format;
    d->hw = hw;
    if (!d->graph) goto fail;

    AVRational sar = frame->sample_aspect_ratio;
    if (sar.num <= 0 || sar.den <= 0) sar = (AVRational){1, 1};

    char args[256];
    snprintf(args, sizeof(args), "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d",
             frame->width, frame->height, frame->format, time_base.num, time_base.den, sar.num, sar.den);
    if (avfilter_graph_create_filter(&d->src, avfilter_get_by_name("buffer"), "in", args, NULL, d->graph) < 0) goto fail;

    if (hw) {
        AVBufferSrcParameters *par = av_buffersrc_parameters_alloc();
        if (!par) goto fail;
        par->hw_frames_ctx = frame->hw_frames_ctx;
        int ret = av_buffersrc_parameters_set(d->src, par);
        av_free(par);
        if (ret < 0) goto fail;
    }

    // send_field: one output frame per field, so 50i becomes smooth 50p.
    const char *name = hw ? "yadif_videotoolbox" : "bwdif";
    AVFilterContext *deint = NULL;
    if (avfilter_graph_create_filter(&deint, avfilter_get_by_name(name), "deint",
                                     "mode=send_field:parity=auto:deint=interlaced", NULL, d->graph) < 0) goto fail;
    if (avfilter_graph_create_filter(&d->sink, avfilter_get_by_name("buffersink"), "out", NULL, NULL, d->graph) < 0) goto fail;
    if (avfilter_link(d->src, 0, deint, 0) < 0) goto fail;
    if (avfilter_link(deint, 0, d->sink, 0) < 0) goto fail;
    if (avfilter_graph_config(d->graph, NULL) < 0) goto fail;
    return d;

fail:
    ffs_deint_free(&d);
    return NULL;
}

int ffs_deint_matches(const FFSDeint *d, const AVFrame *frame) {
    return d->width == frame->width && d->height == frame->height && d->format == frame->format;
}

int ffs_deint_is_hw(const FFSDeint *d) {
    return d->hw;
}

int ffs_deint_push(FFSDeint *d, AVFrame *frame) {
    return av_buffersrc_add_frame_flags(d->src, frame, 0);
}

int ffs_deint_pull(FFSDeint *d, AVFrame *out) {
    return av_buffersink_get_frame(d->sink, out);
}

AVRational ffs_deint_time_base(const FFSDeint *d) {
    return av_buffersink_get_time_base(d->sink);
}

void ffs_deint_free(FFSDeint **d) {
    if (!d || !*d) return;
    avfilter_graph_free(&(*d)->graph);
    free(*d);
    *d = NULL;
}

// MARK: - Audio

struct FFSResampler {
    SwrContext *swr;
    AVChannelLayout in_layout;
    int in_rate;
    int in_format;
    int out_channels;
    uint8_t *buffer;
    unsigned int buffer_size;
};

FFSResampler *ffs_resampler_alloc(void) {
    return calloc(1, sizeof(FFSResampler));
}

void ffs_resampler_free(FFSResampler **r) {
    if (!r || !*r) return;
    swr_free(&(*r)->swr);
    av_channel_layout_uninit(&(*r)->in_layout);
    av_freep(&(*r)->buffer);
    free(*r);
    *r = NULL;
}

int ffs_output_channels(int in_channels) {
    return in_channels >= 6 ? 6 : 2;
}

int ffs_resample(FFSResampler *r, const AVFrame *frame, int out_channels, const uint8_t **out) {
    AVChannelLayout in_layout = {0};
    if (frame->ch_layout.order == AV_CHANNEL_ORDER_UNSPEC || frame->ch_layout.nb_channels == 0) {
        av_channel_layout_default(&in_layout, frame->ch_layout.nb_channels > 0 ? frame->ch_layout.nb_channels : 2);
    } else {
        av_channel_layout_copy(&in_layout, &frame->ch_layout);
    }

    int changed = !r->swr || r->in_rate != frame->sample_rate || r->in_format != frame->format ||
                  r->out_channels != out_channels || av_channel_layout_compare(&r->in_layout, &in_layout) != 0;
    if (changed) {
        swr_free(&r->swr);
        AVChannelLayout out_layout = {0};
        av_channel_layout_default(&out_layout, out_channels);
        if (swr_alloc_set_opts2(&r->swr, &out_layout, AV_SAMPLE_FMT_FLT, frame->sample_rate,
                                &in_layout, frame->format, frame->sample_rate, 0, NULL) < 0) {
            av_channel_layout_uninit(&in_layout);
            av_channel_layout_uninit(&out_layout);
            return -1;
        }
        // Normalise downmix matrices so 5.1 -> stereo does not clip.
        av_opt_set_double(r->swr, "rematrix_maxval", 1.0, 0);
        av_channel_layout_uninit(&out_layout);
        if (swr_init(r->swr) < 0) {
            swr_free(&r->swr);
            av_channel_layout_uninit(&in_layout);
            return -1;
        }
        av_channel_layout_uninit(&r->in_layout);
        av_channel_layout_copy(&r->in_layout, &in_layout);
        r->in_rate = frame->sample_rate;
        r->in_format = frame->format;
        r->out_channels = out_channels;
    }
    av_channel_layout_uninit(&in_layout);

    int max_out = swr_get_out_samples(r->swr, frame->nb_samples);
    if (max_out <= 0) return 0;
    av_fast_malloc(&r->buffer, &r->buffer_size, (size_t)max_out * out_channels * sizeof(float));
    if (!r->buffer) return -1;
    uint8_t *dst[1] = { r->buffer };
    int n = swr_convert(r->swr, dst, max_out, (const uint8_t **)frame->extended_data, frame->nb_samples);
    *out = r->buffer;
    return n;
}
