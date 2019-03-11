//
//  WTRootController.m
//  FFmpeg_Video
//
//  Created by ocean on 2018/9/10.
//  Copyright © 2018年 offcn_c. All rights reserved.
//

#import "WTRootController.h"
#import "AVPlayController.h"
#import "AudioPlayController.h"

@interface WTRootController ()
- (IBAction)avButtonAction:(UIButton *)sender;
- (IBAction)audioButtonAction:(UIButton *)sender;


@end

@implementation WTRootController

- (void)viewDidLoad {
    [super viewDidLoad];
    //
    
    
}

- (IBAction)avButtonAction:(UIButton *)sender {
    
    AVPlayController *vc = [AVPlayController new];
    [self.navigationController pushViewController:vc animated:YES];
}

- (IBAction)audioButtonAction:(UIButton *)sender {
    
    AudioPlayController *vc = [AudioPlayController new];
    [self.navigationController pushViewController:vc animated:YES];
}










- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}
@end
