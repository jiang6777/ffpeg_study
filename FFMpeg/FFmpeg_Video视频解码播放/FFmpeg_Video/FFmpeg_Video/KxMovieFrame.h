//
//  KxMovieFrame.h
//  FFmpeg_Video
//
//  Created by ocean on 2018/9/12.
//  Copyright © 2018年 offcn_c. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef enum {
    
    KxMovieFrameTypeAudio,
    KxMovieFrameTypeVideo,
    KxMovieFrameTypeArtwork,
    KxMovieFrameTypeSubtitle,
    
} KxMovieFrameType;

@interface KxMovieFrame : NSObject
@property (nonatomic) KxMovieFrameType type;
@property (nonatomic) CGFloat duration;
@property (nonatomic) CGFloat position;
@end

@interface KxAudioFrame : KxMovieFrame
@property (nonatomic, strong) NSData *samples;
@end

