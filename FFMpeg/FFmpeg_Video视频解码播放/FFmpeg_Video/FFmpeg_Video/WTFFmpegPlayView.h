//
//  WTFFmpegPlayView.h
//  FFmpeg_Video
//
//  Created by ocean on 2018/9/9.
//  Copyright © 2018年 offcn_c. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "KxMovieFrame.h"


@interface WTFFmpegPlayView : UIView

-(void)openInput:(NSString*)path;
-(void)play;

@end
