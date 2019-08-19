//
//  ViewController.m
//  AshBacktrackDemo
//
//  Created by hefuwei on 2019/8/19.
//  Copyright © 2019 CrimsonHo. All rights reserved.
//

#import "ViewController.h"
#import "AshBacktrackC.h"
#import "AshBacktrackOC.h"

@interface ViewController ()

@end

@implementation ViewController

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
//    NSArray *array = [AshBacktrackOC threadBacktrackWithFrameMaxCount:50];
//    for (AshBacktrackOCInfo *info in array) {
//        for (NSString *string in info.methodNames) {
//            printf("%s\n",[string UTF8String]);
//        }
//    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    int threadCount = 0;
    AshBacktrackCInfo *cInfos = threadBacktrackWithFrameMaxCount(100, &threadCount);
    for (int i = 0; i < threadCount; ++i) {
        AshBacktrackCInfo cInfo = cInfos[i];
        for (int j = 0; j < cInfo.methodNamesCount; ++j) {
            if (cInfo.methodNames[j] != NULL) {
                printf("%s\n",cInfo.methodNames[j]);
            }
        }
    }
}


@end
