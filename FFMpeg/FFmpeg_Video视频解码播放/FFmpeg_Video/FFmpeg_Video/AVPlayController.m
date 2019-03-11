//
//  AVPlayController.m
//  FFmpeg_Video
//
//  Created by ocean on 2018/9/11.
//  Copyright © 2018年 offcn_c. All rights reserved.
//

#import "AVPlayController.h"
#import "TEVideoFrame.h"
#import "WTFFmpegPlayView.h"

@interface AVPlayController ()
{
    float lastFrameTime;
}
@property (nonatomic, strong) TEVideoFrame *video;


@property (weak, nonatomic) IBOutlet UIImageView *videoImageView;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet UIButton *timeButton;
@property (weak, nonatomic) IBOutlet UILabel *fpsLabel;

@property (weak, nonatomic) IBOutlet UIButton *playButton2;
- (IBAction)playButton2Action:(UIButton *)sender;
@property (nonatomic, strong) WTFFmpegPlayView *playView;

@property (nonatomic, copy) NSString *videoPath;

@end

@implementation AVPlayController

- (void)viewDidLoad {
    [super viewDidLoad];
    //
    
    _videoPath = [[NSBundle mainBundle]pathForResource:@"sophie" ofType:@"mov"];
    _videoPath = @"http://media.fantv.hk/m3u8/archive/channel2_stream1.m3u8";//@"http://livecdn.cdbs.com.cn/fmvideo.flv";  //
    self.video = [[TEVideoFrame alloc]initWithVideo:_videoPath];
    
    NSLog(@"video duration: %f\n video size: %d × %d",_video.duration,_video.sourceWidth,_video.sourceHeight);
    _videoImageView.image = _video.currentImage;
    
    
    //
    self.playView.frame = CGRectMake(30, _playButton2.frame.origin.y+150, [UIScreen mainScreen].bounds.size.width-60, 150);
    
}

- (IBAction)playButtonClick:(UIButton *)sender {
    _playButton.enabled = false;
    lastFrameTime = -1;
    
    //跳到0s
    [_video seekTime:0.0];
    [NSTimer scheduledTimerWithTimeInterval:1.0/30 target:self selector:@selector(displayNextFrame:) userInfo:nil repeats:true];
}

- (IBAction)timeButtonClick:(UIButton *)sender {
    NSLog(@"current time: %f s",_video.currentTime);
}

#define LERP(A,B,C) ((A)*(1.0-C)+(B)*C)

- (void)displayNextFrame:(NSTimer *)timer {
    NSTimeInterval startTime = [NSDate timeIntervalSinceReferenceDate];
    
    if (![_video stepFrame]) {
        [timer invalidate];
        [_playButton setEnabled:YES];
        return;
    }
    _videoImageView.image = _video.currentImage;
    float frameTime = 1.0/([NSDate timeIntervalSinceReferenceDate] - startTime);
    if (lastFrameTime < 0) {
        lastFrameTime = frameTime;
    } else {
        lastFrameTime = LERP(frameTime, lastFrameTime, 0.8);
    }
    
    [_fpsLabel setText:[NSString stringWithFormat:@"%.0f",lastFrameTime]];
    
}

- (IBAction)playButton2Action:(UIButton *)sender {
    
    [self.playView play];
}
-(WTFFmpegPlayView*)playView {
    
    if (!_playView) {
        _playView = [[WTFFmpegPlayView alloc]initWithFrame:CGRectMake(30, _playButton2.frame.origin.y+150, [UIScreen mainScreen].bounds.size.width-60, 150)];
        _playView.backgroundColor = [UIColor lightGrayColor];
        [self.view addSubview:_playView];
        [_playView openInput:_videoPath];
    }
    return _playView;
}








- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}
@end
