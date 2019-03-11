//
//  ViewController.m
//  LearnAudioUnit
//
//  Created by loyinglin on 2017/12/6.
//  Copyright © 2017年 loyinglin. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/ALAssetsLibrary.h>
#import "LYOpenGLView.h"
#import "XYQMovieObject.h"

@interface ViewController ()

// about ui
@property (nonatomic, strong) IBOutlet UIButton *mPlayButton;

@property (nonatomic, copy) NSString *filePath;

// avfoudation
@property (nonatomic , strong) AVAsset *mAsset;
@property (nonatomic , strong) AVAssetReader *mReader;
@property (nonatomic , strong) AVAssetReaderTrackOutput *mReaderAudioTrackOutput;
@property (nonatomic , assign) AudioStreamBasicDescription fileFormat;


//@property (nonatomic, strong) LYPlayer *mLYPlayer;
@property (nonatomic, assign) CMBlockBufferRef blockBufferOut;
@property (nonatomic, assign) AudioBufferList audioBufferList;


// gl
@property (nonatomic, strong) IBOutlet LYOpenGLView *mGLView;
@property (nonatomic , strong) AVAssetReaderTrackOutput *mReaderVideoTrackOutput;
@property (nonatomic , strong) CADisplayLink *mDisplayLink;

// 时间戳
@property (nonatomic, assign) long mAudioTimeStamp;
@property (nonatomic, assign) long mVideoTimeStamp;


@property (nonatomic, strong) XYQMovieObject *video;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.mGLView setupGL];
    [self.view addSubview:self.mGLView];
    
    //_filePath = @"http://wvideo.spriteapp.cn/video/2016/0328/56f8ec01d9bfe_wpd.mp4";
    _filePath = [[NSBundle mainBundle] pathForResource:@"abc" ofType:@"mp4"];
    //_filePath = @"rtmp://live.hkstv.hk.lxdns.com/live/hks"; //香港直播频道
}

- (void)displayLinkCallback:(CADisplayLink *)sender {
    //    if (self.mVideoTimeStamp < self.mAudioTimeStamp) {
    //        [self renderVideo];
    //    }
    [self readFrame];
}

- (void)readFrame {
    if (![self.video stepFrame]) {
        [self.mDisplayLink setPaused:YES];
        return;
    }
    
    CVPixelBufferRef pixelBuffer = [self.video getCurrentCVPixelBuffer];
    if (pixelBuffer) {
        self.mGLView.isFullYUVRange = YES;
        [self.mGLView displayPixelBuffer:pixelBuffer];
    }
    
    CFRelease(pixelBuffer);
    
}

-(IBAction)onclick:(UIButton*)sender {
    
    [self playMovie];
}

-(void)playMovie {
    
    self.mDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
    self.mDisplayLink.preferredFramesPerSecond = 20;
    [[self mDisplayLink] addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    //[[self mDisplayLink] setPaused:YES];
    
    
    self.video = [[XYQMovieObject alloc] initWithVideo:_filePath];
    [self.video seekTime:0.0];
}


@end
