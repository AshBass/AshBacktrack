//
//  AshBacktrack.h
//
//  Created by Harry Houdini on 2019/4/6.
//  Copyright © 2019年 Harry Houdini. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <mach/thread_act.h>
#import <mach/mach_init.h>

@interface AshBacktrackOCInfo : NSObject

@property (nonatomic, assign) NSUInteger threadId;
@property (nonatomic, copy) NSArray *methodNames;
@property (nonatomic, assign) BOOL isMainThread;

@end

@interface AshBacktrackOC : NSObject

+(NSString*)machoImageWithAddress:(uintptr_t)address;
+(AshBacktrackOCInfo*)threadBacktrackOnlyMainThreadWithFrameMaxCount:(NSUInteger)frameMaxCount;
+(AshBacktrackOCInfo*)getThreadBacktrackInfoWithFrameMaxCount:(NSUInteger)frameMaxCount thread:(thread_act_t)threadAct;
+(NSArray<AshBacktrackOCInfo*>*)threadBacktrackWithFrameMaxCount:(NSUInteger)frameMaxCount;

@end
