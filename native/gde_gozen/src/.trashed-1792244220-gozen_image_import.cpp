#include "gozen_image_import.hpp"
#include <algorithm>
#include <cstring>
#include <cmath>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <libavutil/imgutils.h>

using namespace godot;

static Dictionary fail_image(const String &why) {
    Dictionary d; d["ok"]=false; d["error"]=why; return d;
}

Dictionary GoZenImageImport::decode(const String &path, int max_side) {
    if(path.is_empty()) return fail_image("Empty image path");
    max_side=std::clamp(max_side,16,16384);
    AVFormatContext *fmt=nullptr;
    if(avformat_open_input(&fmt,path.utf8().get_data(),nullptr,nullptr)<0) return fail_image("Image could not be opened");
    if(avformat_find_stream_info(fmt,nullptr)<0){avformat_close_input(&fmt);return fail_image("Image stream is unreadable");}
    int si=-1;
    for(unsigned i=0;i<fmt->nb_streams;i++) if(fmt->streams[i]->codecpar->codec_type==AVMEDIA_TYPE_VIDEO){si=(int)i;break;}
    if(si<0){avformat_close_input(&fmt);return fail_image("No image stream found");}
    AVCodecParameters *par=fmt->streams[si]->codecpar;
    const AVCodec *dec=avcodec_find_decoder(par->codec_id);
    if(!dec){avformat_close_input(&fmt);return fail_image("Image decoder is unavailable");}
    AVCodecContext *ctx=avcodec_alloc_context3(dec);
    if(!ctx){avformat_close_input(&fmt);return fail_image("Not enough memory for image decoder");}
    if(avcodec_parameters_to_context(ctx,par)<0||avcodec_open2(ctx,dec,nullptr)<0){avcodec_free_context(&ctx);avformat_close_input(&fmt);return fail_image("Image decoder initialization failed");}
    AVPacket *pkt=av_packet_alloc(); AVFrame *frame=av_frame_alloc(); AVFrame *rgba=av_frame_alloc();
    if(!pkt||!frame||!rgba){if(pkt)av_packet_free(&pkt);if(frame)av_frame_free(&frame);if(rgba)av_frame_free(&rgba);avcodec_free_context(&ctx);avformat_close_input(&fmt);return fail_image("Not enough memory for image buffers");}
    bool got=false;
    while(av_read_frame(fmt,pkt)>=0){
        if(pkt->stream_index==si){
            if(avcodec_send_packet(ctx,pkt)>=0){ if(avcodec_receive_frame(ctx,frame)>=0){got=true;av_packet_unref(pkt);break;} }
        }
        av_packet_unref(pkt);
    }
    if(!got){avcodec_send_packet(ctx,nullptr);got=avcodec_receive_frame(ctx,frame)>=0;}
    Dictionary out;
    if(!got){out=fail_image("Image contains no decodable frame");goto cleanup;}
    {
        int sw=frame->width, sh=frame->height;
        if(sw<1||sh<1){out=fail_image("Invalid image dimensions");goto cleanup;}
        double scale=std::min(1.0,(double)max_side/(double)std::max(sw,sh));
        int dw=std::max(1,(int)std::lround(sw*scale)), dh=std::max(1,(int)std::lround(sh*scale));
        rgba->format=AV_PIX_FMT_RGBA; rgba->width=dw; rgba->height=dh;
        if(av_frame_get_buffer(rgba,32)<0){out=fail_image("Could not allocate RGBA image buffer");goto cleanup;}
        SwsContext *sws=sws_getContext(sw,sh,(AVPixelFormat)frame->format,dw,dh,AV_PIX_FMT_RGBA,SWS_FAST_BILINEAR,nullptr,nullptr,nullptr);
        if(!sws){out=fail_image("Could not initialize image converter");goto cleanup;}
        sws_scale(sws,frame->data,frame->linesize,0,sh,rgba->data,rgba->linesize); sws_freeContext(sws);
        PackedByteArray bytes; bytes.resize((int64_t)dw*dh*4);
        uint8_t *dst=bytes.ptrw();
        const int row=dw*4;
        for(int y=0;y<dh;y++) std::memcpy(dst+(int64_t)y*row,rgba->data[0]+(int64_t)y*rgba->linesize[0],row);
        out["ok"]=true;out["width"]=dw;out["height"]=dh;out["rgba"]=bytes;out["codec"]=String(avcodec_get_name(par->codec_id));
    }
cleanup:
    av_packet_free(&pkt); av_frame_free(&frame); av_frame_free(&rgba); avcodec_free_context(&ctx); avformat_close_input(&fmt); return out;
}

Dictionary GoZenImageImport::inspect(const String &path){
    Dictionary d; AVFormatContext *fmt=nullptr;
    if(path.is_empty()||avformat_open_input(&fmt,path.utf8().get_data(),nullptr,nullptr)<0) return fail_image("Image could not be opened");
    if(avformat_find_stream_info(fmt,nullptr)<0){avformat_close_input(&fmt);return fail_image("Image stream is unreadable");}
    d["ok"]=true; d["format"]=String(fmt->iformat?fmt->iformat->name:""); d["streams"]=(int)fmt->nb_streams;
    avformat_close_input(&fmt); return d;
}
void GoZenImageImport::_bind_methods(){
    ClassDB::bind_static_method("GoZenImageImport",D_METHOD("decode","path","max_side"),&GoZenImageImport::decode,DEFVAL(8192));
    ClassDB::bind_static_method("GoZenImageImport",D_METHOD("inspect","path"),&GoZenImageImport::inspect);
}
