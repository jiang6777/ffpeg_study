//
//  WTFFmpegPlayView.m
//  FFmpeg_Video
//
//  Created by ocean on 2018/9/9.
//  Copyright © 2018年 offcn_c. All rights reserved.
//

#import "WTFFmpegPlayView.h"
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#import "NSString+Extension.h"
#import "libswresample/swresample.h"
#import "KxAudioManager.h"
#import <Accelerate/Accelerate.h>

#define LOCAL_MIN_BUFFERED_DURATION   0.2
#define LOCAL_MAX_BUFFERED_DURATION   0.4
#define NETWORK_MIN_BUFFERED_DURATION 2.0
#define NETWORK_MAX_BUFFERED_DURATION 4.0

@interface WTFFmpegPlayView ()
{
    AVFormatContext *avFormatContext;
    //视频
    AVCodecContext    *videoCodecContext;
    int videoStream;
    AVFrame *videoFrame;
    AVPacket packet;
    struct SwsContext *img_convert_context;
    AVPicture picture;
    
    //音频
    AVCodecContext *audioCodecContex;
    int audioStream;
    AVFrame *audioFrame;
    SwrContext          *swrContext;
    CGFloat             audioTimeBase;
    NSMutableArray      *_audioFrames;
    dispatch_queue_t    _dispatchQueue;
    void                *_swrBuffer;
    NSUInteger          _swrBufferSize;
    CGFloat             _audioTimeBase;
    CGFloat             bufferedDuration;
    CGFloat             maxBufferedDuration;
    CGFloat             minBufferedDuration;
    BOOL                _buffered;
    NSData              *_currentAudioFrame;
    CGFloat             _moviePosition;
    CGFloat             _bufferedDuration;
    NSUInteger          _currentAudioFramePos;
}
@property (nonatomic, strong) UIImage *currentImage;
/*输出图片的尺寸**/
@property (nonatomic) int outputWidth, outputHeight;
@property (nonatomic, copy) NSString *videoPath;

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) NSTimer *timer;

//音频
@property (readwrite) BOOL decoding;
@property (readonly) BOOL playing;

@end


#pragma mark static methods
static BOOL audioCodecIsSupported(AVCodecContext *audioCodecCtx) {
    if (audioCodecCtx->sample_fmt == AV_SAMPLE_FMT_S16) {
        
        id<KxAudioManager> audioManager = [KxAudioManager audioManager];
        return (int)audioManager.samplingRate == audioCodecCtx->sample_rate &&
        audioManager.numOutputChannels==audioCodecCtx->channels;
    }
    return NO;
}
static void avStreamFPSTimeBase(AVStream *st, CGFloat defaultTimeBase, CGFloat *pFPS, CGFloat *pTimeBase) {
    
    CGFloat fps, timebase;
    if (st->time_base.den && st->time_base.num) {
        timebase = av_q2d(st->time_base);
    }else if (st->codec->time_base.den && st->codec->time_base.num) {
        timebase = av_q2d(st->codec->time_base);
    }else {
        timebase = defaultTimeBase;
    }
    
    if (st->avg_frame_rate.den && st->avg_frame_rate.num) {
        fps = av_q2d(st->avg_frame_rate);
    }else if (st->r_frame_rate.den && st->r_frame_rate.num) {
        fps = av_q2d(st->r_frame_rate);
    }else {
        fps =  1.0/timebase;
    }
    
    if (pFPS) {
        *pFPS = fps;
    }
    if (pTimeBase) {
        *pTimeBase = timebase;
    }
}




@implementation WTFFmpegPlayView


-(instancetype)initWithFrame:(CGRect)frame {
    
    if (self = [super initWithFrame:frame]) {
        
    }
    return self;
}
-(void)setFrame:(CGRect)frame {
    
    [super setFrame:frame];
    _imageView.frame = self.bounds;
}

-(void)openInput:(NSString*)path {
    
    _videoPath = path;
    //初始化解码器
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self initDecode];
        
        //同步队列
        _dispatchQueue = dispatch_queue_create("KxMovie", DISPATCH_QUEUE_SERIAL);
        _audioFrames = [NSMutableArray array];
        if ([_videoPath isNetworkPath]) {
            minBufferedDuration = NETWORK_MIN_BUFFERED_DURATION;
            maxBufferedDuration = NETWORK_MAX_BUFFERED_DURATION;
        } else {
            minBufferedDuration = LOCAL_MIN_BUFFERED_DURATION;
            maxBufferedDuration = LOCAL_MAX_BUFFERED_DURATION;
        }
    });
}
-(void)play {
    
    if (avFormatContext != NULL) {
        
        //视频
        [self seekTime:0.0];
        if (_timer) {
            [_timer invalidate];
            _timer = nil;
        }
        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0/30 target:self selector:@selector(displayNextFrame:) userInfo:nil repeats:true];
        
        //音频
        [self asyncDecodeFrames];
        [self enableAudio:YES];
        
    }else {
        
        NSLog(@"播放失败。。。");
    }
    
}



#pragma mark private methdos
-(void)initDecode {
    
    if ([_videoPath isNetworkPath]) {
        avformat_network_init();
    }
    //注册所有的文件格式和编解码器
    avcodec_register_all();
    av_register_all();
    
    if (avformat_open_input(&avFormatContext, [_videoPath cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL)) {
        NSLog(@"Couldn't open file.");
        goto initError;
    }
    
    if (avformat_find_stream_info(avFormatContext, NULL)<0) {
        NSLog(@"Couldn't find a media stream in the input.");
        goto initError;
    }
    
    
    // *** 视频 start ***
    AVCodec *videoCodec;
    if ((videoStream=av_find_best_stream(avFormatContext, AVMEDIA_TYPE_VIDEO, -1, -1, &videoCodec, 0))<0) {
        NSLog(@"Cannot find a video stream in the input file");
        goto initError;
    }
    
    videoCodecContext = avFormatContext->streams[videoStream]->codec;
    
    //find the decoder for the video stream
    videoCodec = avcodec_find_decoder(videoCodecContext->codec_id);
    
    if (videoCodec==NULL) {
        NSLog(@"Unsupported codec.");
        goto initError;
    }
    
    //open codec
    if (avcodec_open2(videoCodecContext, videoCodec, NULL)<0) {
        NSLog(@"Cannot open video decoder");
        goto initError;
    }
    
    videoFrame = av_frame_alloc();
    
    //视频宽高
    _outputWidth = videoCodecContext->width;
    self.outputHeight = videoCodecContext->height;
    // *** 视频 end ***
   
    
    
    
    
    // *** 音频 start ***
    AVCodec *audioCodec;
    if ((audioStream=av_find_best_stream(avFormatContext, AVMEDIA_TYPE_AUDIO, -1, -1, &audioCodec, 0))<0) {
        NSLog(@"Cannot find a audio stream in the input file.");
        goto initError;
    }
    
    audioCodecContex = avFormatContext->streams[audioStream]->codec;
    audioCodec = avcodec_find_decoder(audioCodecContex->codec_id);
    if (audioCodec==NULL) {
        NSLog(@"Unsupported codec.");
        goto initError;
    }
    
    if (avcodec_open2(audioCodecContex, audioCodec, NULL)<0) {
        NSLog(@"Cannot open audio decoder");
        goto initError;
    }
    
    if (!audioCodecIsSupported(audioCodecContex)) {
        id<KxAudioManager>audioManager = [KxAudioManager audioManager];
        swrContext = swr_alloc_set_opts(NULL,
                                        av_get_default_channel_layout(audioManager.numOutputChannels),
                                        AV_SAMPLE_FMT_S16,
                                        audioManager.samplingRate,
                                        av_get_default_channel_layout(audioCodecContex->channels),
                                        audioCodecContex->sample_fmt,
                                        audioCodecContex->sample_rate, 0, NULL);
        if (!swrContext || swr_init(swrContext)) {
            if (swrContext) {
                swr_free(&swrContext);
            }
            avcodec_close(audioCodecContex);
            NSLog(@"audio Codec Is not Supported");
            //goto initError;
        }
    }
    
    audioFrame = av_frame_alloc();
    
    AVStream *stream = avFormatContext->streams[audioStream];
    avStreamFPSTimeBase(stream, 0.025, 0, &audioTimeBase);
    // *** 音频 end ***
    
    
initError:
    return;
}

-(void)seekTime:(double)seconds {
    
    if (avFormatContext) {
        AVRational timebase = avFormatContext->streams[videoStream]->time_base;
        int64_t targetTime = (int64_t)((double)timebase.den/timebase.num * seconds);
        avformat_seek_file(avFormatContext, videoStream, targetTime, targetTime, targetTime, AVSEEK_FLAG_FRAME);
        avcodec_flush_buffers(videoCodecContext);
    }else{
        
        NSLog(@"播放失败");
    }
    
}

-(void)displayNextFrame:(NSTimer*)timer {
    
    if (![self stempFrame]) {
        [_timer invalidate];
        return;
    }
    
    self.imageView.image = self.currentImage;
}
-(BOOL)stempFrame {
    
    int frameFinished = 0;
    while (!frameFinished && av_read_frame(avFormatContext, &packet)>=0) {
        
        if (packet.stream_index == videoStream) {
            avcodec_decode_video2(videoCodecContext, videoFrame, &frameFinished, &packet);
        }
    }
    
    return frameFinished != 0;
}

- (void)convertFrameToRGB {
    
    sws_scale(img_convert_context, videoFrame->data, videoFrame->linesize, 0, videoCodecContext->height, picture.data, picture.linesize);
}
-(void)setupScaler {
    
    avpicture_free(&picture);
    sws_freeContext(img_convert_context);
    
    avpicture_alloc(&picture, AV_PIX_FMT_RGB24, _outputWidth, _outputHeight);
    
    static int sws_flags = SWS_FAST_BILINEAR;
    img_convert_context = sws_getContext(videoCodecContext->width,
                                         videoCodecContext->height,
                                         videoCodecContext->pix_fmt,
                                         _outputWidth,
                                         _outputHeight,
                                         AV_PIX_FMT_RGB24,
                                         sws_flags, NULL, NULL, NULL);
}
-(UIImage *)imageFromAVPicture:(AVPicture)pict width:(int)width height:(int)height {
    
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, pict.data[0], pict.linesize[0]*height, kCFAllocatorNull);
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    
    CGImageRef cgImageRef = CGImageCreate(width, height, 8, 24, pict.linesize[0], colorSpaceRef, bitmapInfo, provider, NULL, NO, kCGRenderingIntentDefault);
    UIImage *resImage = [UIImage imageWithCGImage:cgImageRef];
    
    CGImageRelease(cgImageRef);
    CGColorSpaceRelease(colorSpaceRef);
    CGDataProviderRelease(provider);
    CFRelease(data);
    return  resImage;
}


// *** 音频 start ***
-(void)asyncDecodeFrames {
    
    
    //decoding
    if (_decoding) {
        return;
    }
    
    //
    __weak WTFFmpegPlayView *weakSelf = self;
    
    const CGFloat duration = [_videoPath isNetworkPath]? .0f: 0.1f;
    self.decoding = YES;
    dispatch_async(_dispatchQueue, ^{
        
        __strong WTFFmpegPlayView *strongSelf = weakSelf;
        {
            if (!strongSelf.playing) {
                return;
            }
        }
        
        BOOL good = YES;
        while (good) {
            good = NO;
            @autoreleasepool {
                
                if (strongSelf && (videoStream!=-1 || audioStream!=-1)) {
                    
                    NSArray *frames = [strongSelf decodeFrames:duration];
                    __strong WTFFmpegPlayView *strongSelf = weakSelf;
                    if (strongSelf) {
                        good = [strongSelf addFrames:frames];
                    }
                }
            }
        }
        
        {
            __strong WTFFmpegPlayView *strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf.decoding = NO;
            }
        }
    });
}
-(BOOL)addFrames:(NSArray*)frames {
    
    if (audioStream!=-1) {
        
        @synchronized(_audioFrames) {
            for (KxMovieFrame *frame in frames) {
                if (frame.type == KxMovieFrameTypeAudio) {
                    [_audioFrames addObject:frame];
                    if (videoStream==-1) {
                        bufferedDuration += frame.duration;
                    }
                }
            }
        }
    }
    
    return self.playing && bufferedDuration<maxBufferedDuration;
}
-(NSArray*)decodeFrames:(CGFloat)minDuration {
    
    if (videoStream==-1 && audioStream==-1) {
        return nil;
    }
    
    NSMutableArray *result = [NSMutableArray array];
    AVPacket packet;
    CGFloat decodeDuration = 0;
    BOOL finished = NO;
    while (!finished) {
        
        if (av_read_frame(avFormatContext, &packet)<0) {
//            _isEOF = YES;
            break;
        }
        
        if (packet.stream_index == audioStream) {
            
            int pktSize = packet.size;
            while (pktSize>0) {
                
                int gotFrame = 0;
                int len = avcodec_decode_audio4(audioCodecContex,
                                                audioFrame,
                                                &gotFrame,
                                                &packet);
                if (len<0) {
                    NSLog(@"Error: decode audio error, skip packet");
                    break;
                }
                
                if (gotFrame) {
                    KxAudioFrame *frame = [self handleAudioFrame];
                    if (frame) {
                        [result addObject:frame];
                        
                        if (videoStream == -1) {
//                            _position = frame.position;
                            decodeDuration += frame.duration;
                            if (decodeDuration>minDuration) {
                                finished = YES;
                            }
                        }
                    }
                }
                
                if (0 == len) {
                    break;
                }
                
                pktSize -= len;
            }
        }
        
        av_free_packet(&packet);
    }
    
    return result;
}
-(KxAudioFrame*)handleAudioFrame {
    
    if (!audioFrame->data[0]) {
        return nil;
    }
    
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    const NSUInteger numChannels = audioManager.numOutputChannels;
    NSUInteger numFrames;
    void *audioData;
    if (swrContext) {
        
        const NSUInteger ratio = MAX(1, audioManager.samplingRate/audioCodecContex->sample_rate)*MAX(1, audioManager.numOutputChannels / audioCodecContex->channels)*2;
        const int bufSize = av_samples_get_buffer_size(NULL,
                                                       audioManager.numOutputChannels,
                                                       audioFrame->nb_samples*ratio,
                                                       AV_SAMPLE_FMT_S16,
                                                       1);
        if (!_swrBuffer || _swrBufferSize<bufSize) {
            _swrBufferSize = bufSize;
            _swrBuffer = realloc(_swrBuffer, _swrBufferSize);
        }
        
        Byte *outbuf[2] = {_swrBuffer, 0};
        numFrames = swr_convert(swrContext,
                                outbuf,
                                audioFrame->nb_samples*ratio,
                                (const uint8_t **)audioFrame->data,
                                audioFrame->nb_samples);
        if (numFrames<0) {
            NSLog(@"Error: fail resample audio");
            return nil;
        }
        
        audioData = _swrBuffer;
    }else {
        
        if (audioCodecContex->sample_fmt != AV_SAMPLE_FMT_S16) {
            NSLog(@"Error: bucheck, audio format is invalid");
            return nil;
        }
        audioData = audioFrame->data[0];
        numFrames = audioFrame->nb_samples;
    }
    
    const NSUInteger numElements = numFrames*numChannels;
    NSMutableData *data = [NSMutableData dataWithLength:numElements*sizeof(float)];
    
    float scale = 1.0/(float)INT16_MAX;
    vDSP_vflt16((SInt16*)audioData, 1, data.mutableBytes, 1, numElements);
    vDSP_vsmul(data.mutableBytes, 1, &scale, data.mutableBytes, 1, numElements);
    
    KxAudioFrame *frame = [[KxAudioFrame alloc]init];
    frame.position = av_frame_get_best_effort_timestamp(audioFrame)*_audioTimeBase;
    frame.duration = av_frame_get_pkt_duration(audioFrame)*_audioTimeBase;
    frame.samples = data;
    
    if (frame.duration==0) {
        frame.duration = frame.samples.length/(sizeof(float)*numChannels*audioManager.samplingRate);
    }
    
    return frame;
}
-(void)enableAudio:(BOOL)on {
    
    id <KxAudioManager> audioManager = [KxAudioManager audioManager];
    if (on && audioStream!=-1) {
        audioManager.outputBlock = ^(float *data, UInt32 numFrames, UInt32 numChannels) {
            [self audioCallbackFillData:data numFrames:numFrames numChannels:numChannels];
        };
        
        [audioManager play];
    }else {
        
        [audioManager pause];
        audioManager.outputBlock = nil;
    }
}
- (void) audioCallbackFillData: (float *) outData
                     numFrames: (UInt32) numFrames
                   numChannels: (UInt32) numChannels
{
    
    if (_buffered) {
        memset(outData, 0, numFrames*numChannels*sizeof(float));
    }
    
    @autoreleasepool {
        
        while (numFrames>0) {
            if (!_currentAudioFrame) {
                @synchronized(_audioFrames) {
                    NSUInteger count = _audioFrames.count;
                    
                    if (count>0) {
                        KxAudioFrame *frame = _audioFrames[0];
                        
                        if (videoStream!=-1) {
                            const CGFloat delta = _moviePosition - frame.position;
                            if (delta<-0.1) {
                                memset(outData, 0, numFrames*numChannels*sizeof(float));
                                
                                break;
                            }
                            
                            [_audioFrames removeObjectAtIndex:0];
                            
                            if (delta>0.1 && count>1) {
                                continue;
                            }
                        }else {
                            
                            [_audioFrames removeObjectAtIndex:0];
                            _moviePosition = frame.position;
                            _bufferedDuration -= frame.duration;
                        }
                        
                        _currentAudioFrame = frame.samples;
                        _currentAudioFramePos = 0;
                    }
                }
            }
            
            if (_currentAudioFrame) {
                const void *bytes = (Byte*)_currentAudioFrame.bytes+_currentAudioFramePos;
                const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
                const NSUInteger frameSizeOf = numChannels*sizeof(float);
                const NSUInteger bytesTOCopy = MIN(numFrames*frameSizeOf, bytesLeft);
                const NSUInteger framesToCopy = bytesTOCopy/frameSizeOf;
                
                memcpy(outData, bytes, bytesTOCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy*numChannels;
                
                if (bytesTOCopy<bytesLeft) {
                    _currentAudioFramePos += bytesTOCopy;
                }else{
                    _currentAudioFrame = nil;
                }
            }else{
                
                memset(outData, 0, numFrames*numChannels*sizeof(float));
                break;
            }
        }
    }
}
// *** 音频 end   ***


#pragma mark set/get
-(UIImageView*)imageView {
    
    if (!_imageView) {
        _imageView = [[UIImageView alloc]init];
        _imageView.frame = self.bounds;
        [self addSubview:_imageView];
    }
    return _imageView;
}
-(UIImage*)currentImage {
    
    if (!videoFrame->data[0]) {
        return nil;
    }
    
    [self convertFrameToRGB];
    
    UIImage *img = [self imageFromAVPicture:picture width:_outputWidth height:_outputHeight];
    return img;
}
-(void)setOutputHeight:(int)outputHeight {
    
    if (_outputHeight == outputHeight) return;
    _outputHeight = outputHeight;
    [self setupScaler];
}
-(void)setOutputWidth:(int)outputWidth {
    
    if (_outputWidth == outputWidth) return;
    _outputWidth = outputWidth;
    [self setupScaler];
}


@end



