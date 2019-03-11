//
//  AudioPlayController.m
//  FFmpeg_Video
//
//  Created by ocean on 2018/9/10.
//  Copyright © 2018年 offcn_c. All rights reserved.
//

#import "AudioPlayController.h"
#import "KxAudioManager.h"
#import "NSString+Extension.h"

#import <CoreGraphics/CoreGraphics.h>
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#import "libavutil/pixdesc.h"
#import <Accelerate/Accelerate.h>

NSString * kxmovieErrorDomain = @"ru.kolyvan.kxmovie";
#define LOCAL_MIN_BUFFERED_DURATION   0.2
#define LOCAL_MAX_BUFFERED_DURATION   0.4
#define NETWORK_MIN_BUFFERED_DURATION 2.0
#define NETWORK_MAX_BUFFERED_DURATION 4.0
NSString * const KxMovieParameterMinBufferedDuration = @"KxMovieParameterMinBufferedDuration";
NSString * const KxMovieParameterMaxBufferedDuration = @"KxMovieParameterMaxBufferedDuration";
NSString * const KxMovieParameterDisableDeinterlacing = @"KxMovieParameterDisableDeinterlacing";

static NSString * errorMessage (kxMovieError errorCode)
{
    switch (errorCode) {
        case kxMovieErrorNone:
            return @"";
            
        case kxMovieErrorOpenFile:
            return NSLocalizedString(@"Unable to open file", nil);
            
        case kxMovieErrorStreamInfoNotFound:
            return NSLocalizedString(@"Unable to find stream information", nil);
            
        case kxMovieErrorStreamNotFound:
            return NSLocalizedString(@"Unable to find stream", nil);
            
        case kxMovieErrorCodecNotFound:
            return NSLocalizedString(@"Unable to find codec", nil);
            
        case kxMovieErrorOpenCodec:
            return NSLocalizedString(@"Unable to open codec", nil);
            
        case kxMovieErrorAllocateFrame:
            return NSLocalizedString(@"Unable to allocate frame", nil);
            
        case kxMovieErroSetupScaler:
            return NSLocalizedString(@"Unable to setup scaler", nil);
            
        case kxMovieErroReSampler:
            return NSLocalizedString(@"Unable to setup resampler", nil);
            
        case kxMovieErroUnsupported:
            return NSLocalizedString(@"The ability is not supported", nil);
    }
}
static NSError * kxmovieError (NSInteger code, id info)
{
    NSDictionary *userInfo = nil;
    
    if ([info isKindOfClass: [NSDictionary class]]) {
        
        userInfo = info;
        
    } else if ([info isKindOfClass: [NSString class]]) {
        
        userInfo = @{ NSLocalizedDescriptionKey : info };
    }
    
    return [NSError errorWithDomain:kxmovieErrorDomain
                               code:code
                           userInfo:userInfo];
}
static NSArray *collectStreams(AVFormatContext *formatCtx, enum AVMediaType codecType)
{
    NSMutableArray *ma = [NSMutableArray array];
    for (NSInteger i = 0; i < formatCtx->nb_streams; ++i)
        if (codecType == formatCtx->streams[i]->codec->codec_type)
            [ma addObject: [NSNumber numberWithInteger: i]];
    return [ma copy];
}
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
static int interrupt_callback(void *ctx)
{
    if (!ctx)
        return 0;
    const BOOL r = NO;
    if (r) NSLog(@"DEBUG: INTERRUPT_CALLBACK!");
    return r;
}




@interface AudioPlayController ()
{
    AVFormatContext     *_formatCtx;
    
    CGFloat             _moviePosition;
    NSInteger           _audioStream;
    NSMutableArray      *_audioFrames;
    NSArray             *_audioStreams;
    AVFrame             *_audioFrame;
    CGFloat             _audioTimeBase;
    
    dispatch_queue_t    _dispatchQueue;
    
    CGFloat             _minBufferedDuration;
    CGFloat             _maxBufferedDuration;
    
    NSDictionary        *_parameters;
    
    void                *_swrBuffer;
    NSUInteger          _swrBufferSize;
    SwrContext          *_swrContext;
    struct SwrContext   *_swsContext;
    AVCodecContext      *_audioCodecCtx;
    
    CGFloat             _bufferedDuration;
    BOOL                _buffered;
    NSData              *_currentAudioFrame;
    NSUInteger          _currentAudioFramePos;
}
@property (nonatomic, copy) NSString *videoPath;
@property (readonly, nonatomic) BOOL isNetwork;
@property (readonly, nonatomic) BOOL isEOF;

@property (readwrite, nonatomic) BOOL disableDeinterlacing;

@property (nonatomic) BOOL playing;
@property (readwrite) BOOL decoding;

@end

@implementation AudioPlayController

- (void)viewDidLoad {
    [super viewDidLoad];
    //
    _videoPath = [[NSBundle mainBundle]pathForResource:@"sophie" ofType:@"mov"];
    _videoPath = @"http://media.fantv.hk/m3u8/archive/channel2_stream1.m3u8";//@"http://livecdn.cdbs.com.cn/fmvideo.flv";
    NSDictionary *parameters = @{@"KxMovieParameterDisableDeinterlacing":@"1"};
    
    [self audioWithContentPath:_videoPath params:parameters];
}

-(void)audioWithContentPath:(NSString*)path params:(NSDictionary*)params {
  
    _videoPath = path;
    _parameters = params;
    _moviePosition = 0;
    
    //音频
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    [audioManager activateAudioSession];
    
    
    __weak AudioPlayController *weakSelf = self;
    
    av_register_all();
    avformat_network_init();
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        NSError *error = nil;
        [weakSelf openFile:path error:&error];
        
        __strong AudioPlayController *strongSelf = weakSelf;
        if (strongSelf) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf setMovieDecoder:self withError:error];
                
                [strongSelf play];
            });
        }
    });
}

#pragma mark private
-(void)play {
    
    if (self.playing) {
        return;
    }
    
    if (_audioStream==-1) {
        return;
    }
    
    self.playing = YES;
    
    [self asyncDecodeFrames];
    
    if (_audioStream!=-1) {
        [self enableAudio:YES];
    }
}
-(void)pause {
    
    if (!self.playing) {
        return;
    }
    
    self.playing = NO;
    [self enableAudio:NO];
}

-(void)asyncDecodeFrames {
    
    
    //decoding
    if (_decoding) {
        return;
    }
    
    //
    __weak AudioPlayController *weakSelf = self;
    
    const CGFloat duration = [_videoPath isNetworkPath]? .0f: 0.1f;
    self.decoding = YES;
    dispatch_async(_dispatchQueue, ^{
        
        __strong AudioPlayController *strongSelf = weakSelf;
        {
            if (!strongSelf.playing) {
                return;
            }
        }
        
        BOOL good = YES;
        while (good) {
            good = NO;
            @autoreleasepool {
                
                if (strongSelf && ([strongSelf isValidateAudio])) {
                    
                    NSArray *frames = [strongSelf decodeFrames:duration];
                    if (strongSelf) {
                        good = [strongSelf addFrames:frames];
                    }
                }
            }
        }
        
        {
            __strong AudioPlayController *strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf.decoding = NO;
            }
        }
    });
}
-(NSArray*)decodeFrames:(CGFloat)minDuration {
    
    if (_audioStream==-1) {
        return nil;
    }
    
    NSMutableArray *result = [NSMutableArray array];
    AVPacket packet;
    CGFloat decodeDuration = 0;
    BOOL finished = NO;
    while (!finished) {
        
        if (av_read_frame(_formatCtx, &packet)<0) {
            _isEOF = YES;
            break;
        }
        
        if (packet.stream_index == _audioStream) {
            
            int pktSize = packet.size;
            while (pktSize>0) {
                
                int gotFrame = 0;
                int len = avcodec_decode_audio4(_audioCodecCtx,
                                                _audioFrame,
                                                &gotFrame,
                                                &packet);
                if (len<0) {
                    NSLog(@"Error: decode audio error, skip packet");
                    break;
                }
                
                NSLog(@"2");
                if (gotFrame) {
                    KxAudioFrame *frame = [self handleAudioFrame];
                    if (frame) {
                        [result addObject:frame];
                        
                        if (result.count>20) {
                            finished = YES;
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
    
    NSLog(@"3 result=%ld", result.count);
    return result;
}
-(KxAudioFrame*)handleAudioFrame {
    
    if (!_audioFrame->data[0]) {
        return nil;
    }
    
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    const NSUInteger numChannels = audioManager.numOutputChannels;
    NSUInteger numFrames;
    void *audioData;
    if (_swrContext) {
        
        const NSUInteger ratio = MAX(1, audioManager.samplingRate/_audioCodecCtx->sample_rate)*MAX(1, audioManager.numOutputChannels / _audioCodecCtx->channels)*2;
        const int bufSize = av_samples_get_buffer_size(NULL,
                                                       audioManager.numOutputChannels,
                                                       _audioFrame->nb_samples*ratio,
                                                       AV_SAMPLE_FMT_S16,
                                                       1);
        if (!_swrBuffer || _swrBufferSize<bufSize) {
            _swrBufferSize = bufSize;
            _swrBuffer = realloc(_swrBuffer, _swrBufferSize);
        }
        
        Byte *outbuf[2] = {_swrBuffer, 0};
        numFrames = swr_convert(_swrContext,
                                outbuf,
                                _audioFrame->nb_samples*ratio,
                                (const uint8_t **)_audioFrame->data,
                                _audioFrame->nb_samples);
        if (numFrames<0) {
            NSLog(@"Error: fail resample audio");
            return nil;
        }
        
        audioData = _swrBuffer;
    }else {
        
        if (_audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_S16) {
            NSLog(@"Error: bucheck, audio format is invalid");
            return nil;
        }
        audioData = _audioFrame->data[0];
        numFrames = _audioFrame->nb_samples;
    }
    
    const NSUInteger numElements = numFrames*numChannels;
    NSMutableData *data = [NSMutableData dataWithLength:numElements*sizeof(float)];
    
    float scale = 1.0/(float)INT16_MAX;
    vDSP_vflt16((SInt16*)audioData, 1, data.mutableBytes, 1, numElements);
    vDSP_vsmul(data.mutableBytes, 1, &scale, data.mutableBytes, 1, numElements);
    
    KxAudioFrame *frame = [[KxAudioFrame alloc]init];
    frame.position = av_frame_get_best_effort_timestamp(_audioFrame)*_audioTimeBase;
    frame.duration = av_frame_get_pkt_duration(_audioFrame)*_audioTimeBase;
    frame.samples = data;
    
    if (frame.duration==0) {
        frame.duration = frame.samples.length/(sizeof(float)*numChannels*audioManager.samplingRate);
    }
    
    return frame;
}
-(BOOL)isValidateAudio {
    
    return _audioStream!=-1;
}
-(BOOL)addFrames:(NSArray*)frames {
    
    if ([self isValidateAudio]) {
        
        @synchronized(_audioFrames) {
            for (KxMovieFrame *frame in frames) {
                if (frame.type == KxMovieFrameTypeAudio) {
                    [_audioFrames addObject:frame];
                    if (![self isValidateAudio]) {
                        _bufferedDuration += frame.duration;
                    }
                    
                }
            }
        }
    }
    
    return self.playing && _bufferedDuration<_maxBufferedDuration;
}

-(void)enableAudio:(BOOL)on {
    
    id <KxAudioManager> audioManager = [KxAudioManager audioManager];
    if (on && [self isValidateAudio]) {
        __weak typeof(self) weakSelf = self;
        audioManager.outputBlock = ^(float *data, UInt32 numFrames, UInt32 numChannels) {
            NSLog(@"1");
            [weakSelf audioCallbackFillData:data numFrames:numFrames numChannels:numChannels];
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
                        
                        if ([self isValidateAudio]) {
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


-(void)setMovieDecoder:(AudioPlayController*)decoder
             withError:(NSError*)error {
    
    if (!error && decoder) {
        
       
        //同步队列
        _dispatchQueue = dispatch_queue_create("KxMovie", DISPATCH_QUEUE_SERIAL);
        _audioFrames = [NSMutableArray array];
        
        if ([_videoPath isNetworkPath]) {
            
            _minBufferedDuration = NETWORK_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = NETWORK_MAX_BUFFERED_DURATION;
            
        } else {
            
            _minBufferedDuration = LOCAL_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = LOCAL_MAX_BUFFERED_DURATION;
        }
        
        
        
        if (_parameters.count) {
            id val;
            
            val = [_parameters valueForKey: KxMovieParameterMinBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _minBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey: KxMovieParameterMaxBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _maxBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey: KxMovieParameterDisableDeinterlacing];
            if ([val isKindOfClass:[NSNumber class]])
                self.disableDeinterlacing = [val boolValue];
            
            if (_maxBufferedDuration < _minBufferedDuration) {
                _maxBufferedDuration = _minBufferedDuration*2;
            }
        }
        
    }else {
        
        
    }
}
-(BOOL)openFile: (NSString *) path
          error: (NSError **) perror {
    
//    _isNetwork = [path isNetworkPath];
//    static BOOL needNetworkInit = YES;
//    if (needNetworkInit && _isNetwork) {
//        needNetworkInit = NO;
//        avformat_network_init();
//    }
    
    kxMovieError errCode = [self openInput:path];
    
    if (errCode == kxMovieErrorNone) {
        kxMovieError audioErr = [self openAudioStream];
        
        if (audioErr != kxMovieErrorNone) {
            errCode = audioErr;
        }
    }
    
    if (errCode != kxMovieErrorNone) {
        
        [self closeFile];
        
        NSString *errMsg = errorMessage(errCode);
        if (perror) {
            *perror = kxmovieError(errCode, errMsg);
        }
        
        return NO;
    }
    
    return YES;
}
-(void)closeFile {
    
    [self closeAudioStream];
    
    _audioStreams = nil;
    
    if (_formatCtx) {
        _formatCtx->interrupt_callback.opaque = NULL;
        _formatCtx->interrupt_callback.callback = NULL;
        
        avformat_close_input(&_formatCtx);
        _formatCtx = NULL;
    }
}
-(void)closeAudioStream {
    
    _audioStream = -1;
    
    if (_swrBuffer) {
        free(_swrBuffer);
        _swrBuffer = NULL;
        _swrBufferSize = 0;
    }
    
    if (_swrContext) {
        swr_free(&_swrContext);
        _swrContext = NULL;
    }
    
    if (_audioFrame) {
        av_free(_audioFrame);
        _audioFrame = NULL;
    }
    
    if (_audioCodecCtx) {
        avcodec_close(_audioCodecCtx);
        _audioCodecCtx = NULL;
    }
}

-(kxMovieError)openAudioStream {
    
    kxMovieError errCode = kxMovieErrorStreamNotFound;
    _audioStream = -1;
    _audioStreams = collectStreams(_formatCtx, AVMEDIA_TYPE_AUDIO);
    for (NSNumber *n in _audioStreams) {
        errCode = [self openAudioStream:n.integerValue];
        if (errCode == kxMovieErrorNone) {
            break;
        }
    }
    
    return errCode;
}
-(kxMovieError)openAudioStream:(NSInteger)audioStream {
    
    AVCodecContext *codecCtx = _formatCtx->streams[audioStream]->codec;
    AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
    
    SwrContext *swrContex = NULL;
    if (!codec) {
        return kxMovieErrorCodecNotFound;
    }
    if (avcodec_open2(codecCtx, codec, NULL)<0) {
        return kxMovieErrorOpenCodec;
    }
    
    if (!audioCodecIsSupported(codecCtx)) {
        id<KxAudioManager> audioManager = [KxAudioManager audioManager];
        swrContex = swr_alloc_set_opts(NULL,
                                       av_get_default_channel_layout(audioManager.numOutputChannels),
                                       AV_SAMPLE_FMT_S16,
                                       audioManager.samplingRate,
                                       av_get_default_channel_layout(codecCtx->channels),
                                       codecCtx->sample_fmt,
                                       codecCtx->sample_rate,
                                       0,
                                       NULL);
        if (!swrContex || swr_init(swrContex)) {
            if (swrContex) {
                swr_free(&swrContex);
            }
            avcodec_close(codecCtx);
            
            return kxMovieErroReSampler;
        }
    }
    
    _audioFrame = av_frame_alloc();
    
    if (!_audioFrame) {
        if (swrContex) {
            swr_free(&swrContex);
        }
        avcodec_close(codecCtx);
        return kxMovieErrorAllocateFrame;
    }
    
    _audioStream = audioStream;
    _audioCodecCtx = codecCtx;
    _swrContext = swrContex;
    
    AVStream *st = _formatCtx->streams[_audioStream];
    avStreamFPSTimeBase(st, 0.025, 0, &_audioTimeBase);
    
    return kxMovieErrorNone;
}

-(kxMovieError)openInput:(NSString*)path {
    
    AVFormatContext *formatCtx = NULL;
//    if (_interruptCallback) {
        formatCtx = avformat_alloc_context();
        if (!formatCtx) {
            return kxMovieErrorOpenFile;
        }
        
        AVIOInterruptCB cb = {interrupt_callback, (__bridge void*)(self)};
        formatCtx->interrupt_callback = cb;
//    }
    
    if (avformat_open_input(&formatCtx, [path cStringUsingEncoding:NSUTF8StringEncoding], NULL, NULL)<0) {
        if (formatCtx) {
            avformat_free_context(formatCtx);
        }
        return kxMovieErrorOpenFile;
    }
    
    if (avformat_find_stream_info(formatCtx, NULL)<0) {
        avformat_close_input(&formatCtx);
        return kxMovieErrorOpenFile;
    }
    
    av_dump_format(formatCtx, 0, [path.lastPathComponent cStringUsingEncoding:NSUTF8StringEncoding], false);
    
    _formatCtx = formatCtx;
    return kxMovieErrorNone;
}







- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}
@end



