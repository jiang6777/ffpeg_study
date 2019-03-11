//
//  NSString+Extension.m
//  FFmpeg_Video
//
//  Created by ocean on 2018/9/9.
//  Copyright © 2018年 offcn_c. All rights reserved.
//

#import "NSString+Extension.h"

@implementation NSString (Extension)

-(BOOL)isNetworkPath
{
    NSRange r = [self rangeOfString:@":"];
    if (r.location == NSNotFound) {
        return NO;
    }
    NSString *scheme = [self substringFromIndex:r.length];
    if ([scheme isEqualToString:@"file"]) {
        return NO;
    }
    
    return YES;
}

@end
