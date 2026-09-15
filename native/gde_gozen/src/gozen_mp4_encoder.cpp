#include "gozen_mp4_encoder.hpp"
#include <algorithm>
#include <cstring>
#include <string>
#include <cmath>
#include <godot_cpp/variant/packed_string_array.hpp>
using namespace godot;

bool GoZenMP4Encoder::fail(const String &m){ last_error=m; UtilityFunctions::printerr("GoZenMP4Encoder: ",m); release(); return false; }
void GoZenMP4Encoder::release(){
    if(sws_ctx){sws_freeContext(sws_ctx);sws_ctx=nullptr;} if(swr_ctx){swr_free(&swr_ctx);} if(video_frame){av_frame_free(&video_frame);} if(audio_frame){av_frame_free(&audio_frame);} if(packet){av_packet_free(&packet);} if(video_ctx){avcodec_free_context(&video_ctx);} if(audio_ctx){avcodec_free_context(&audio_ctx);} if(format_ctx){if(format_ctx->pb&&!(format_ctx->oformat->flags&AVFMT_NOFILE))avio_closep(&format_ctx->pb);avformat_free_context(format_ctx);} format_ctx=nullptr;video_stream=nullptr;audio_stream=nullptr;width=height=0;fps=24;audio_kbps=192;video_index=audio_samples=0;opened=header_written=audio_enabled=false; encoder_name="";
}
void GoZenMP4Encoder::close(){if(opened&&header_written)finish();else release();}
bool GoZenMP4Encoder::drain_video(){while(true){int r=avcodec_receive_packet(video_ctx,packet);if(r==AVERROR(EAGAIN)||r==AVERROR_EOF)return true;if(r<0)return false;av_packet_rescale_ts(packet,video_ctx->time_base,video_stream->time_base);packet->stream_index=video_stream->index;r=av_interleaved_write_frame(format_ctx,packet);av_packet_unref(packet);if(r<0)return false;}}
bool GoZenMP4Encoder::drain_audio(){while(true){int r=avcodec_receive_packet(audio_ctx,packet);if(r==AVERROR(EAGAIN)||r==AVERROR_EOF)return true;if(r<0)return false;av_packet_rescale_ts(packet,audio_ctx->time_base,audio_stream->time_base);packet->stream_index=audio_stream->index;r=av_interleaved_write_frame(format_ctx,packet);av_packet_unref(packet);if(r<0)return false;}}

AVPixelFormat GoZenMP4Encoder::preferred_pixel_format(const AVCodec *codec) const {
    if(!codec||!codec->pix_fmts) return AV_PIX_FMT_YUV420P;
    for(const AVPixelFormat *p=codec->pix_fmts; *p!=AV_PIX_FMT_NONE; ++p) if(*p==AV_PIX_FMT_YUV420P) return *p;
    return codec->pix_fmts[0];
}
const AVCodec *GoZenMP4Encoder::find_video_encoder(){
    const char *names[] = {
        codec_name.utf8().get_data(),
        video_kind==VIDEO_H264?"h264_mediacodec":"",
        video_kind==VIDEO_HEVC?"hevc_mediacodec":"",
        video_kind==VIDEO_H264?"libx264":(video_kind==VIDEO_HEVC?"libx265":(video_kind==VIDEO_VP9?"libvpx-vp9":"libaom-av1")),
        ""
    };
    for(const char *n:names) if(n[0]) { const AVCodec *c=avcodec_find_encoder_by_name(n); if(c) return c; }
    const AVCodecID id = video_kind==VIDEO_H264?AV_CODEC_ID_H264:(video_kind==VIDEO_HEVC?AV_CODEC_ID_HEVC:(video_kind==VIDEO_VP9?AV_CODEC_ID_VP9:AV_CODEC_ID_AV1));
    return avcodec_find_encoder(id);
}
const AVCodec *GoZenMP4Encoder::find_audio_encoder(){
    if(audio_kind==AUDIO_OPUS){ const AVCodec *c=avcodec_find_encoder_by_name("libopus"); if(c) return c; c=avcodec_find_encoder_by_name("opus"); if(c) return c; return avcodec_find_encoder(AV_CODEC_ID_OPUS); }
    return avcodec_find_encoder(AV_CODEC_ID_AAC);
}
bool GoZenMP4Encoder::container_allows_codec(const char *c, VideoKind k) const{
    if(!c||!c[0]) return false;
    if(!std::strcmp(c,"webm")) return k==VIDEO_VP9||k==VIDEO_AV1;
    if(!std::strcmp(c,"mp4")||!std::strcmp(c,"mov")||!std::strcmp(c,"mkv")||!std::strcmp(c,"avi")) return true;
    return k==VIDEO_H264;
}
int GoZenMP4Encoder::open_video_codec(int bitrate,int crf){
    const AVCodec *c=find_video_encoder(); if(!c){last_error="Requested video encoder is not available in this FFmpeg build";return -1;}
    video_ctx=avcodec_alloc_context3(c); if(!video_ctx) return -2;
    video_ctx->codec_id=c->id; video_ctx->codec_type=AVMEDIA_TYPE_VIDEO; video_ctx->width=width; video_ctx->height=height; video_ctx->pix_fmt=preferred_pixel_format(c); video_ctx->time_base={1,fps}; video_ctx->framerate={fps,1}; video_ctx->gop_size=std::max(fps*2,24); video_ctx->max_b_frames=(video_kind==VIDEO_H264&&profile!="baseline")?2:0; video_ctx->thread_count=0;
    if(bitrate>0) video_ctx->bit_rate=bitrate;
    const bool x264=std::strstr(c->name,"264")!=nullptr, x265=std::strstr(c->name,"265")!=nullptr, vpx=std::strstr(c->name,"vpx")!=nullptr, aom=std::strstr(c->name,"aom")!=nullptr;
    if(x264||x265){av_opt_set(video_ctx->priv_data,"preset",preset.is_empty()?"fast":preset.utf8().get_data(),0);av_opt_set(video_ctx->priv_data,"tune","animation",0); if(x264) av_opt_set(video_ctx->priv_data,"profile",profile.utf8().get_data(),0); if(x264) av_opt_set(video_ctx->priv_data,"crf",std::to_string(std::clamp(crf,10,40)).c_str(),0); else if(x265) av_opt_set(video_ctx->priv_data,"crf",std::to_string(std::clamp(crf,10,40)).c_str(),0);}
    else if(vpx) {av_opt_set(video_ctx->priv_data,"deadline","good",0); av_opt_set_int(video_ctx->priv_data,"cpu-used",std::clamp(preset=="slow"?1:(preset=="medium"?3:5),0,8),0); if(bitrate<=0) video_ctx->bit_rate=std::clamp((int64_t)width*height*fps/8,800000,50000000);}
    else if(aom) {av_opt_set_int(video_ctx->priv_data,"cpu-used",std::clamp(preset=="slow"?4:(preset=="medium"?6:8),0,9),0); if(bitrate<=0) video_ctx->bit_rate=std::clamp((int64_t)width*height*fps/10,1000000,60000000);}
    if(bitrate<=0 && !x264 && !x265 && !vpx && !aom) video_ctx->bit_rate=std::clamp((int64_t)width*height*fps/8,800000,50000000);
    if(format_ctx->oformat->flags&AVFMT_GLOBALHEADER) video_ctx->flags|=AV_CODEC_FLAG_GLOBAL_HEADER;
    if(avcodec_open2(video_ctx,c,nullptr)>=0){encoder_name=c->name;return 0;} avcodec_free_context(&video_ctx); video_ctx=nullptr; return -3;
}
int GoZenMP4Encoder::open_audio_codec(){
    const AVCodec *ac=find_audio_encoder(); if(!ac) return -1; audio_ctx=avcodec_alloc_context3(ac); if(!audio_ctx)return -2; audio_ctx->codec_id=ac->id;audio_ctx->codec_type=AVMEDIA_TYPE_AUDIO;audio_ctx->sample_rate=audio_rate;audio_ctx->sample_fmt=ac->sample_fmts?ac->sample_fmts[0]:AV_SAMPLE_FMT_FLTP;audio_ctx->time_base={1,audio_rate};audio_ctx->bit_rate=int64_t(audio_kbps)*1000;av_channel_layout_default(&audio_ctx->ch_layout,audio_channels);if(format_ctx->oformat->flags&AVFMT_GLOBALHEADER)audio_ctx->flags|=AV_CODEC_FLAG_GLOBAL_HEADER;if(avcodec_open2(audio_ctx,ac,nullptr)<0){avcodec_free_context(&audio_ctx);return -3;}audio_codec_name=avcodec_get_name(ac->id); return 0;
}
int GoZenMP4Encoder::open(const String&output_path,int p_width,int p_height,int p_fps,int p_bitrate,int p_crf,const String&p_profile,bool p_audio,int p_audio_rate,int p_audio_channels,const String&p_preset,int p_audio_kbps,const String&p_container,const String&p_codec){
    release();last_error="";container_name=p_container.to_lower();codec_name=p_codec.to_lower(); if(container_name.is_empty())container_name="mp4"; if(codec_name.is_empty())codec_name="h264";
    if(output_path.is_empty()||p_width<2||p_height<2||(p_width&1)||(p_height&1)){last_error="Unsupported resolution";return -1;} if(p_fps<1||p_fps>120){last_error="Unsupported FPS";return -2;}
    if(codec_name=="h264")video_kind=VIDEO_H264;else if(codec_name=="hevc"||codec_name=="h265")video_kind=VIDEO_HEVC;else if(codec_name=="vp9")video_kind=VIDEO_VP9;else if(codec_name=="av1")video_kind=VIDEO_AV1;else{last_error="Unknown video codec";return -3;}
    if(!container_allows_codec(container_name.utf8().get_data(),video_kind)){last_error="This container does not support the selected video codec";return -4;}
    audio_kind=(container_name=="webm")?AUDIO_OPUS:AUDIO_AAC; width=p_width;height=p_height;fps=p_fps;profile=p_profile.to_lower();preset=p_preset.is_empty()?String("fast"):p_preset.to_lower();audio_kbps=std::clamp(p_audio_kbps,64,512);
    AVFormatContext*raw=nullptr;if(avformat_alloc_output_context2(&raw,nullptr,container_name.utf8().get_data(),output_path.utf8().get_data())<0||!raw){last_error="Could not create video container";return -5;}format_ctx=raw;
    if(open_video_codec(p_bitrate,p_crf)!=0){release();return -6;}
    video_stream=avformat_new_stream(format_ctx,nullptr);if(!video_stream||avcodec_parameters_from_context(video_stream->codecpar,video_ctx)<0){fail("Could not create video stream");return -7;}video_stream->time_base=video_ctx->time_base;
    audio_enabled=p_audio;if(audio_enabled){audio_rate=p_audio_rate>0?p_audio_rate:48000;audio_channels=std::clamp(p_audio_channels,1,2);if(open_audio_codec()!=0){fail("Audio encoder initialization failed");return -8;}audio_stream=avformat_new_stream(format_ctx,nullptr);if(!audio_stream||avcodec_parameters_from_context(audio_stream->codecpar,audio_ctx)<0){fail("Could not create audio stream");return -9;}audio_stream->time_base=audio_ctx->time_base;audio_frame=av_frame_alloc();if(!audio_frame){fail("Insufficient memory: audio frame");return -10;}audio_frame->format=audio_ctx->sample_fmt;audio_frame->sample_rate=audio_rate;audio_frame->ch_layout=audio_ctx->ch_layout;audio_frame->nb_samples=audio_ctx->frame_size>0?audio_ctx->frame_size:1024;if(av_frame_get_buffer(audio_frame,0)<0){fail("Insufficient memory: audio buffer");return -11;}swr_ctx=swr_alloc();if(!swr_ctx){fail("Audio resampler allocation failed");return -12;}AVChannelLayout in_layout;av_channel_layout_default(&in_layout,audio_channels);av_opt_set_chlayout(swr_ctx,"in_chlayout",&in_layout,0);av_opt_set_int(swr_ctx,"in_sample_rate",audio_rate,0);av_opt_set_sample_fmt(swr_ctx,"in_sample_fmt",AV_SAMPLE_FMT_S16,0);av_opt_set_chlayout(swr_ctx,"out_chlayout",&audio_ctx->ch_layout,0);av_opt_set_int(swr_ctx,"out_sample_rate",audio_rate,0);av_opt_set_sample_fmt(swr_ctx,"out_sample_fmt",audio_ctx->sample_fmt,0);if(swr_init(swr_ctx)<0){fail("Audio resampler initialization failed");return -13;}}
    packet=av_packet_alloc();video_frame=av_frame_alloc();if(!packet||!video_frame){fail("Insufficient memory: encoder buffers");return -14;}video_frame->format=video_ctx->pix_fmt;video_frame->width=width;video_frame->height=height;video_frame->time_base=video_ctx->time_base;if(av_frame_get_buffer(video_frame,32)<0){fail("Insufficient memory: video buffer");return -15;}
    const AVPixelFormat in_fmt=AV_PIX_FMT_RGBA; sws_ctx=sws_getContext(width,height,in_fmt,width,height,video_ctx->pix_fmt,SWS_FAST_BILINEAR,nullptr,nullptr,nullptr);if(!sws_ctx){fail("Could not initialize pixel converter");return -16;}
    if(!(format_ctx->oformat->flags&AVFMT_NOFILE)&&avio_open(&format_ctx->pb,output_path.utf8().get_data(),AVIO_FLAG_WRITE)<0){fail("Output file is not writable");return -17;}
    AVDictionary*opts=nullptr; if(container_name=="mp4"||container_name=="mov") av_dict_set(&opts,"movflags","+faststart",0); if(avformat_write_header(format_ctx,&opts)<0){av_dict_free(&opts);fail("Container header initialization failed");return -18;}av_dict_free(&opts);opened=header_written=true;return 0;
}
int GoZenMP4Encoder::add_frame(const PackedByteArray&rgba8){if(!opened||rgba8.size()!=int64_t(width)*height*4){last_error="Invalid frame buffer";return -1;}if(av_frame_make_writable(video_frame)<0){last_error="Insufficient memory: video buffer";return -2;}const uint8_t*src[4]={rgba8.ptr(),nullptr,nullptr,nullptr};int lines[4]={width*4,0,0,0};sws_scale(sws_ctx,src,lines,0,height,video_frame->data,video_frame->linesize);video_frame->pts=video_index++;if(avcodec_send_frame(video_ctx,video_frame)<0||!drain_video()){last_error="Video encoding failed";return -3;}return 0;}
int GoZenMP4Encoder::add_audio_s16(const PackedByteArray&pcm,int samples){if(!audio_enabled||!audio_ctx||samples<=0)return audio_enabled?-1:0;int need=samples*audio_channels*2;if(pcm.size()<need){last_error="Invalid audio buffer";return -2;}int offset=0;while(offset<samples){if(av_frame_make_writable(audio_frame)<0){last_error="Insufficient memory: audio buffer";return -3;}int n=std::min(audio_frame->nb_samples,samples-offset);const uint8_t*chunk[1]={pcm.ptr()+int64_t(offset)*audio_channels*2};int converted=swr_convert(swr_ctx,audio_frame->data,n,chunk,n);if(converted<=0){last_error="Audio conversion failed";return -4;}audio_frame->nb_samples=converted;audio_frame->pts=audio_samples;audio_samples+=converted;if(avcodec_send_frame(audio_ctx,audio_frame)<0||!drain_audio()){last_error="Audio encoding failed";return -5;}offset+=n;}return 0;}
int GoZenMP4Encoder::finish(){if(!opened||!header_written){release();return -1;}if(avcodec_send_frame(video_ctx,nullptr)<0||!drain_video()){last_error="Video finalization failed";release();return -2;}if(audio_enabled){if(avcodec_send_frame(audio_ctx,nullptr)<0||!drain_audio()){last_error="Audio finalization failed";release();return -3;}}int r=av_write_trailer(format_ctx);if(r<0){last_error="Container finalization failed";release();return -4;}release();return 0;}
Dictionary GoZenMP4Encoder::capabilities()const{Dictionary d;d["hardware_h264"]=avcodec_find_encoder_by_name("h264_mediacodec")!=nullptr;d["hardware_hevc"]=avcodec_find_encoder_by_name("hevc_mediacodec")!=nullptr;d["h264"]=avcodec_find_encoder(AV_CODEC_ID_H264)!=nullptr;d["hevc"]=avcodec_find_encoder(AV_CODEC_ID_HEVC)!=nullptr;d["vp9"]=avcodec_find_encoder(AV_CODEC_ID_VP9)!=nullptr;d["av1"]=avcodec_find_encoder(AV_CODEC_ID_AV1)!=nullptr;d["aac"]=avcodec_find_encoder(AV_CODEC_ID_AAC)!=nullptr;d["opus"]=avcodec_find_encoder(AV_CODEC_ID_OPUS)!=nullptr;d["faststart"]=true;d["tuned"]=true;PackedStringArray containers; containers.push_back("mp4"); containers.push_back("mov"); containers.push_back("mkv"); containers.push_back("webm"); d["containers"]=containers;d["max_audio_kbps"]=512;return d;}
Dictionary GoZenMP4Encoder::inspect_file(const String&path){Dictionary d;AVFormatContext*c=nullptr;if(avformat_open_input(&c,path.utf8().get_data(),nullptr,nullptr)<0){d["ok"]=false;d["error"]="Video cannot be opened";return d;}if(avformat_find_stream_info(c,nullptr)<0){avformat_close_input(&c);d["ok"]=false;d["error"]="Stream info unavailable";return d;}int vi=-1,ai=-1;for(unsigned i=0;i<c->nb_streams;i++){if(c->streams[i]->codecpar->codec_type==AVMEDIA_TYPE_VIDEO&&vi<0)vi=i;if(c->streams[i]->codecpar->codec_type==AVMEDIA_TYPE_AUDIO&&ai<0)ai=i;}if(vi>=0){auto*s=c->streams[vi];d["width"]=s->codecpar->width;d["height"]=s->codecpar->height;d["video_codec"]=String(avcodec_get_name(s->codecpar->codec_id));d["video_duration_us"]=s->duration==AV_NOPTS_VALUE?0:av_rescale_q(s->duration,s->time_base,{1,1000000});d["frames"]=s->nb_frames;}if(ai>=0){auto*s=c->streams[ai];d["audio_codec"]=String(avcodec_get_name(s->codecpar->codec_id));d["audio_duration_us"]=s->duration==AV_NOPTS_VALUE?0:av_rescale_q(s->duration,s->time_base,{1,1000000});}d["has_video"]=vi>=0;d["has_audio"]=ai>=0;d["format"]=String(c->iformat->name);d["ok"]=vi>=0;avformat_close_input(&c);return d;}
void GoZenMP4Encoder::_bind_methods(){ClassDB::bind_method(D_METHOD("open","output_path","width","height","fps","bitrate","crf","profile","audio","audio_rate","audio_channels","preset","audio_kbps","container","codec"),&GoZenMP4Encoder::open,DEFVAL(0),DEFVAL(20),DEFVAL("high"),DEFVAL(false),DEFVAL(48000),DEFVAL(2),DEFVAL("fast"),DEFVAL(192),DEFVAL("mp4"),DEFVAL("h264"));ClassDB::bind_method(D_METHOD("add_frame","rgba8"),&GoZenMP4Encoder::add_frame);ClassDB::bind_method(D_METHOD("add_audio_s16","pcm","samples"),&GoZenMP4Encoder::add_audio_s16);ClassDB::bind_method(D_METHOD("finish"),&GoZenMP4Encoder::finish);ClassDB::bind_method(D_METHOD("close"),&GoZenMP4Encoder::close);ClassDB::bind_method(D_METHOD("is_open"),&GoZenMP4Encoder::is_open);ClassDB::bind_method(D_METHOD("get_last_error"),&GoZenMP4Encoder::get_last_error);ClassDB::bind_method(D_METHOD("get_encoder_name"),&GoZenMP4Encoder::get_encoder_name);ClassDB::bind_method(D_METHOD("is_hardware"),&GoZenMP4Encoder::is_hardware);ClassDB::bind_method(D_METHOD("capabilities"),&GoZenMP4Encoder::capabilities);ClassDB::bind_static_method("GoZenMP4Encoder",D_METHOD("inspect_file","path"),&GoZenMP4Encoder::inspect_file);}
