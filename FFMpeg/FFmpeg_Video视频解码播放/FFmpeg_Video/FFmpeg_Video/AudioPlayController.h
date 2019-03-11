//
//  AudioPlayController.h
//  FFmpeg_Video
//
//  Created by ocean on 2018/9/10.
//  Copyright © 2018年 offcn_c. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "KxMovieFrame.h"

typedef enum {
    
    kxMovieErrorNone,
    kxMovieErrorOpenFile,
    kxMovieErrorStreamInfoNotFound,
    kxMovieErrorStreamNotFound,
    kxMovieErrorCodecNotFound,
    kxMovieErrorOpenCodec,
    kxMovieErrorAllocateFrame,
    kxMovieErroSetupScaler,
    kxMovieErroReSampler,
    kxMovieErroUnsupported,
    
} kxMovieError;




typedef BOOL(^KxMovieDecoderInterruptCallback)();

@interface AudioPlayController : UIViewController

@property (readwrite, nonatomic, strong) KxMovieDecoderInterruptCallback interruptCallback;

@end
