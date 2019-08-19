//
//  AshBacktrackC.h
//  AshBacktrackDemo
//
//  Created by hefuwei on 2019/8/19.
//  Copyright © 2019 CrimsonHo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <mach/thread_act.h>
#import <mach/mach_init.h>

#ifdef __LP64__
typedef uint64_t uint_t;
#else
typedef uint32_t uint_t;
#endif

typedef struct AshBacktrackCInfo {
    uint_t threadId;
    char **methodNames;
    unsigned long methodNamesCount;
    bool isMainThread;
}AshBacktrackCInfo;

@interface AshBacktrackC : NSObject

char* machoImageWithAddress(uintptr_t address);
AshBacktrackCInfo threadBacktrackOnlyMainThread(unsigned long frameMaxCount);
AshBacktrackCInfo getThreadBacktrackInfo(thread_act_t threadAct,unsigned long frameMaxCount);
AshBacktrackCInfo* threadBacktrackWithFrameMaxCount(unsigned long frameMaxCount, int *threadCount);

@end
