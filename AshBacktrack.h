//
//  AshBacktrack.h
//
//  Created by Harry Houdini on 2019/4/6.
//  Copyright © 2019年 Harry Houdini. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <mach/thread_act.h>
#import <mach/mach_init.h>

@interface AshBacktrackInfo : NSObject

@property (nonatomic, assign) NSUInteger threadId;
@property (nonatomic, copy) NSArray *methodNames;
@property (nonatomic, assign) BOOL isMainThread;

@end

@interface AshBacktrack : NSObject

+(NSString*)machoImageWithAddress:(uintptr_t)address;
+(AshBacktrackInfo*)threadBacktrackOnlyMainThreadWithFrameMaxCount:(NSUInteger)frameMaxCount;
+(AshBacktrackInfo*)getThreadBacktrackInfoWithFrameMaxCount:(NSUInteger)frameMaxCount thread:(thread_act_t)threadAct;
+(NSArray<AshBacktrackInfo*>*)threadBacktrackWithFrameMaxCount:(NSUInteger)frameMaxCount;

@end
