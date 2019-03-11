//
//  WTPlayView.m
//  VideoToolBoxDecodeH264
//
//  Created by ocean on 2018/8/22.
//  Copyright © 2018年 AnDong. All rights reserved.
//

#import "WTPlayView.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

@interface WTPlayView ()

@property(nonatomic, strong) AVSampleBufferDisplayLayer *videoPlay_videoToolBox;
@property CVPixelBufferRef pixelBuffer;

@end

@implementation WTPlayView

-(instancetype)initWithFrame:(CGRect)frame {
    
    if (self = [super initWithFrame:frame]) {
        
        [self createSampleBufferLayer];
    }
    return self;
}

-(void)dealloc {
    
    [self removeSampleBufferLayer];
}

-(void)showWityPixelBuffer:(CVPixelBufferRef)pixelBuffer{
    
    if(_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
        //_pixelBuffer = NULL;
    }
    _pixelBuffer = CVPixelBufferRetain(pixelBuffer);
    
    //不设置具体时间信息
    __weak typeof(self)weakSelf=self;
    
    CMSampleTimingInfo timing = {kCMTimeInvalid, kCMTimeInvalid, kCMTimeInvalid};
    //获取视频信息
    CMVideoFormatDescriptionRef videoInfo = NULL;
    OSStatus result = CMVideoFormatDescriptionCreateForImageBuffer(NULL, _pixelBuffer, &videoInfo);
    NSParameterAssert(result == 0 && videoInfo != NULL);
    
    CMSampleBufferRef sampleBuffer = NULL;
    result = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,_pixelBuffer, true, NULL, NULL, videoInfo, &timing, &sampleBuffer);
    NSParameterAssert(result == 0 && sampleBuffer != NULL);
    
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    [weakSelf.videoPlay_videoToolBox enqueueSampleBuffer:sampleBuffer];
    
    //CFRelease(_pixelBuffer);
    CFRelease(videoInfo);
    
    CFRelease(sampleBuffer);
    
    if (weakSelf.videoPlay_videoToolBox.status == AVQueuedSampleBufferRenderingStatusFailed){
        [weakSelf.videoPlay_videoToolBox flush];
        
        //后台唤醒重启渲染层
        if (-11847 == weakSelf.videoPlay_videoToolBox.error.code){
            [weakSelf rebuildSampleBufferDisplayLayer];
        }
    }
}

#pragma mark - 重启渲染layer
- (void)rebuildSampleBufferDisplayLayer{
    [self removeSampleBufferLayer];
    [self createSampleBufferLayer];
}

#pragma mark create/remove AVSampleBufferDisplayLayer
- (void)createSampleBufferLayer{
    if (!self.videoPlay_videoToolBox){
        self.videoPlay_videoToolBox = [[AVSampleBufferDisplayLayer alloc] init];
        self.videoPlay_videoToolBox.frame =self.bounds;
        self.videoPlay_videoToolBox.position = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
        self.videoPlay_videoToolBox.videoGravity = AVLayerVideoGravityResizeAspect;
        self.videoPlay_videoToolBox.opaque = YES;
        [self.layer addSublayer:self.videoPlay_videoToolBox];
    }
}

- (void)removeSampleBufferLayer{
    if (self.videoPlay_videoToolBox){
        [self.videoPlay_videoToolBox stopRequestingMediaData];
        [self.videoPlay_videoToolBox removeFromSuperlayer];
        self.videoPlay_videoToolBox = nil;
    }
}

@end
