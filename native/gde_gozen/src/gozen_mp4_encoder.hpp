#pragma once
#include "ffmpeg.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/dictionary.hpp>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
}

class GoZenMP4Encoder : public godot::RefCounted {
    GDCLASS(GoZenMP4Encoder, godot::RefCounted)
    AVFormatContext *format_ctx=nullptr; AVStream *video_stream=nullptr,*audio_stream=nullptr;
    AVCodecContext *video_ctx=nullptr,*audio_ctx=nullptr; AVFrame *video_frame=nullptr,*audio_frame=nullptr; AVPacket *packet=nullptr;
    SwsContext *sws_ctx=nullptr; SwrContext *swr_ctx=nullptr;
    int width=0,height=0,fps=24,audio_rate=48000,audio_channels=2,audio_kbps=192;
    int64_t video_index=0,audio_samples=0; bool opened=false,header_written=false,audio_enabled=false;
    godot::String profile="high", preset="fast", encoder_name="", container_name="mp4", codec_name="h264", audio_codec_name="aac",last_error="";
    bool fail(const godot::String&); bool drain_video(); bool drain_audio(); void release();
    int open_video_codec(int bitrate,int crf);
    int open_audio_codec();
    enum VideoKind { VIDEO_H264, VIDEO_HEVC, VIDEO_VP9, VIDEO_AV1 } video_kind=VIDEO_H264;
    enum AudioKind { AUDIO_AAC, AUDIO_OPUS } audio_kind=AUDIO_AAC;
    AVPixelFormat preferred_pixel_format(const AVCodec *codec) const;
    const AVCodec *find_video_encoder();
    const AVCodec *find_audio_encoder();
    bool container_allows_codec(const char *container, VideoKind kind) const;
protected:
    static void _bind_methods();
public:
    GoZenMP4Encoder()=default; ~GoZenMP4Encoder() override{close();}
    int open(const godot::String&,int,int,int,int=0,int=20,const godot::String& p_profile="high",bool=false,int=48000,int=2,const godot::String& p_preset="fast",int p_audio_kbps=192,const godot::String& p_container="mp4",const godot::String& p_codec="h264");
    int add_frame(const godot::PackedByteArray&); int add_audio_s16(const godot::PackedByteArray&,int); int finish(); void close(); bool is_open()const{return opened;}
    godot::String get_last_error()const{return last_error;} godot::String get_encoder_name()const{return encoder_name;} bool is_hardware()const{return encoder_name.find("mediacodec")>=0;}
    godot::Dictionary capabilities() const; static godot::Dictionary inspect_file(const godot::String& path);
};
