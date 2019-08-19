//
//  AshBacktrack.m
//
//  Created by Harry Houdini on 2019/4/6.
//  Copyright © 2019年 Harry Houdini. All rights reserved.
//

#import "AshBacktrackOC.h"

#import <mach/task.h>
#import <mach/vm_map.h>
#import <mach/mach_init.h>
#import <mach/thread_info.h>

#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

/**
 
 线程函数地址获取小结
 
 1.找到目标 thread，方法：API函数 task_threads
 
 2.获得 thread 的内存上下文 _STRUCT_CONTEXT ，方法：API函数 thread_get_state
 
 3.获取指针栈帧结构体 _STRUCT_CONTEXT._ss ，解析得到对应指令指针 _STRUCT_CONTEXT._ss.rip ;首次个栈帧指针_STRUCT_CONTEXT._ss.rbp；栈顶指针_STRUCT_CONTEXT._ss.rsp
 
 首个栈帧结构体赋值，方法：API函数vm_read_overwrite()，完成首个栈帧结构体赋值StackFrame
 
 */

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct section_64 section_t;
typedef struct nlist_64 nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT_64
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct section section_t;
typedef struct nlist nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT
#endif

typedef struct StackFrame{
    const struct StackFrame *const previous;  //前一个栈帧地址
    const uintptr_t return_address;  //栈帧的函数返回地址
} StackFrame;

static mach_port_t mainThread;

@implementation AshBacktrackOC

+(void)load {
    mainThread = mach_thread_self();
}

+(AshBacktrackOCInfo*)threadBacktrackOnlyMainThreadWithFrameMaxCount:(NSUInteger)frameMaxCount {
    return [self getThreadBacktrackInfoWithFrameMaxCount:frameMaxCount thread:mainThread];
}

+(NSArray<AshBacktrackOCInfo*>*)threadBacktrackWithFrameMaxCount:(NSUInteger)frameMaxCount {
    NSMutableArray *array = [NSMutableArray new];
    
    thread_act_array_t threadList;
    mach_msg_type_number_t listCount = 0;
    task_threads(mach_task_self(), &threadList, &listCount);
    
    for (int i = 0; i < listCount; ++i) {
        thread_act_t threadAct = threadList[i];
        AshBacktrackOCInfo *info = [self getThreadBacktrackInfoWithFrameMaxCount:frameMaxCount thread:threadAct];
        [array addObject:info];
    }
    
    return array.copy;
}

+(AshBacktrackOCInfo*)getThreadBacktrackInfoWithFrameMaxCount:(NSUInteger)frameMaxCount thread:(thread_act_t)threadAct {
    
    AshBacktrackOCInfo *info = [AshBacktrackOCInfo new];
    
    thread_info_data_t theThreadInfo;
    thread_identifier_info_t identifierInfo = NULL;
    mach_msg_type_number_t threadIdentifierInfoOutCount = THREAD_INFO_MAX;
    kern_return_t identifierResult = thread_info(threadAct, THREAD_IDENTIFIER_INFO, (thread_info_t)&theThreadInfo, &threadIdentifierInfoOutCount);
    if (identifierResult == KERN_SUCCESS) {
        identifierInfo = (thread_identifier_info_t)theThreadInfo;
        info.threadId = identifierInfo->thread_id;
    }
    
    NSArray *methodNames = [self threadStackBacktrackWithThread:threadAct frameMaxCount:frameMaxCount];
    info.methodNames = methodNames;
    
    info.isMainThread = (threadAct == mainThread);
    
    return info;
}

+(NSArray<NSString*>*)threadStackBacktrackWithThread:(thread_act_t)thread_act frameMaxCount:(NSUInteger)frameMaxCount {
    
    int frameCount = 0;
    uintptr_t buffer[frameMaxCount];
    
    _STRUCT_MCONTEXT machineContext; //线程栈里所有的栈指针
    mach_msg_type_number_t stateCount = [self threadStateCount];
    kern_return_t result = thread_get_state(thread_act, [self threadState], (thread_state_t)&machineContext.__ss, &stateCount);
    if (result != KERN_SUCCESS) {
        return @[];
    }
    
    // 获取当前指令地址
    uintptr_t instructionPointer = [self machInstructionPointerWithContext:&machineContext];
    if (instructionPointer == 0) {
        return @[];
    }
    buffer[frameCount] = instructionPointer;
    ++frameCount;
    
    uintptr_t linkRegisterPointer = [self machThreadGetLinkRegisterPointerWithContext:&machineContext];
    if (linkRegisterPointer) {
        buffer[frameCount] = linkRegisterPointer;
        ++frameCount;
    }
    
    // 获取栈基地址
    uintptr_t stackBasePointer = [self machStackBasePointerWithContext:&machineContext];
    if (stackBasePointer == 0) {
        return @[];
    }
    // 获取栈帧
    vm_size_t outsize = 0;
    StackFrame stackFrame = {0};
    
    result = vm_read_overwrite(mach_task_self(), (vm_address_t)stackBasePointer, sizeof(stackFrame), (vm_address_t)&stackFrame, &outsize);
    if (result != KERN_SUCCESS) {
        return @[];
    }
    
    do {
        uintptr_t address = stackFrame.return_address;
//        if (buffer[frameCount-1] == address) {
//            break;
//        }
        buffer[frameCount] = address;
        if (buffer[frameCount] == 0) {
            break;
        }
        ++frameCount;
        result = vm_read_overwrite(mach_task_self(), (vm_address_t)stackFrame.previous, sizeof(stackFrame), (vm_address_t)&stackFrame, &outsize);
        if (result != KERN_SUCCESS) {
            break;
        }
    } while (stackFrame.previous != 0 && frameCount < frameMaxCount);
    
    NSMutableArray *methodNames = [NSMutableArray new];
    for (int i = 0; i < frameCount; ++i) {
        NSString *methodName = [self machoImageWithAddress:buffer[i]];
        [methodNames addObject:methodName];
    }
    return methodNames.copy;
}

+(NSString*)machoImageWithAddress:(uintptr_t)address {
    uint32_t imageCount = _dyld_image_count();
    uint32_t index = imageCount;
    //    const struct mach_header *machHeader = NULL;
    /// 确定 image index
    for (uint32_t theIndex = 0; theIndex < imageCount; ++theIndex) {
        const struct mach_header *machHeader = _dyld_get_image_header(theIndex);
        if (machHeader != NULL) {
            intptr_t slide = _dyld_get_image_vmaddr_slide(theIndex);
            // 虚拟地址 = 真实地址 - 偏移量
            uintptr_t frameAddress = address - (uintptr_t)slide;
            uintptr_t loadCommand = (uintptr_t)machHeader + sizeof(mach_header_t);
            for (uint32_t i = 0; i < machHeader->ncmds; ++i) {
                segment_command_t *segment = (segment_command_t*)loadCommand;
                if (segment->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
                    if (frameAddress >= segment->vmaddr && frameAddress < segment->vmaddr + segment->vmsize) {
                        index = theIndex;
                        break;
                    }
                }
                loadCommand += segment->cmdsize;
            }
        }else {
            #if DEBUG
                NSLog(@"machHeader == NULL");
            #endif
        }
    }
    
    const struct mach_header *machHeader = _dyld_get_image_header(index);
    if (machHeader != NULL) {
        intptr_t slide = _dyld_get_image_vmaddr_slide(index);
        // 虚拟地址 = 真实地址 - 偏移量
        uintptr_t frameAddress = address - slide;
        uintptr_t loadCommand = (uintptr_t)machHeader + sizeof(mach_header_t);
        segment_command_t *link = NULL;
        struct symtab_command *symtabCommand = NULL;
        //            struct dysymtab_command *dysymtabCommand;
        for (int i = 0; i < machHeader->ncmds; ++i) {
            segment_command_t *segment = (segment_command_t *)loadCommand;
            if (segment->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
                if (strcmp(segment->segname, SEG_LINKEDIT) == 0) {
                    link = segment;
                }
            }
            else if (segment->cmd == LC_SYMTAB) {
                symtabCommand = (struct symtab_command*)segment;
            }
            /// 由于不需要找跳转，所以不需要获取间接表
//            else if (segment->cmd == LC_DYSYMTAB) {
//                dysymtabCommand = (struct dysymtab_command*)segment;
//            }
            
            loadCommand += segment->cmdsize;
        }
        
        uintptr_t linkAddress = (uintptr_t)(link->vmaddr - link->fileoff + slide);
        nlist_t *symbolTable = (nlist_t *)(linkAddress + symtabCommand->symoff);
        char *stringTable = (char *)(linkAddress + symtabCommand->stroff);
        
        const nlist_t *bestSymbol = NULL;
        uintptr_t bestDistance = INT_MAX;
        for (uint32_t i = 0; i < symtabCommand->nsyms; ++i) {
            uintptr_t n_value = symbolTable[i].n_value;
            //如果 n_value 是0，symbol 指向外部对象
            if (n_value != 0) {
                // 地址距离
                uintptr_t distance = frameAddress - n_value;
                if ((frameAddress >= n_value) && (distance <= bestDistance)) {
                    bestDistance = distance;
                    bestSymbol = symbolTable + i;
                }
            }
        }
        
        if (bestSymbol != NULL) {
            char *name = (char*)((uintptr_t)stringTable + (uintptr_t)bestSymbol->n_un.n_strx);
            return [NSString stringWithUTF8String:name];
        }else {
            #if DEBUG
                NSLog(@"bestSymbol == NULL");
            #endif
        }
    }
    return @"";
}

#pragma mark - CPU 相关

/*
 栈帧指针
 _STRUCT_MCONTEXT->__ss.LSL_FRAME_POINTER  //rbp 栈帧指针
 */
+(uintptr_t)machStackBasePointerWithContext:(mcontext_t const)machineContext {
    //Stack base pointer for holding the address of the current stack frame.
#if defined(__arm64__)
    return machineContext->__ss.__fp;
#elif defined(__arm__)
    return machineContext->__ss.__r[7];
#elif defined(__x86_64__)
    return machineContext->__ss.__rbp;
#elif defined(__i386__)
    return machineContext->__ss.__ebp;
#endif
}

/*
 _STRUCT_MCONTEXT->__ss.LSL_INSTRUCTION_ADDRESS //rip 指令指针
 */
+(uintptr_t)machInstructionPointerWithContext:(mcontext_t const)machineContext {
    //Instruction pointer. Holds the program counter, the current instruction address.
#if defined(__arm64__)
    return machineContext->__ss.__pc;
#elif defined(__arm__)
    return machineContext->__ss.__pc;
#elif defined(__x86_64__)
    return machineContext->__ss.__rip;
#elif defined(__i386__)
    return machineContext->__ss.__eip;
#endif
}

+(uintptr_t)instructionAddress:(const uintptr_t)address {
#if defined(__arm64__)
    const uintptr_t reAddress = ((address) & ~(3UL));
#elif defined(__arm__)
    const uintptr_t reAddress = ((address) & ~(1UL));
#elif defined(__x86_64__)
    const uintptr_t reAddress = (address);
#elif defined(__i386__)
    const uintptr_t reAddress = (address);
#endif
    return reAddress - 1;
}

+(mach_msg_type_number_t)threadStateCount {
#if defined(__arm64__)
    return ARM_THREAD_STATE64_COUNT;
#elif defined(__arm__)
    return ARM_THREAD_STATE_COUNT;
#elif defined(__x86_64__)
    return x86_THREAD_STATE64_COUNT;
#elif defined(__i386__)
    return x86_THREAD_STATE32_COUNT;
#endif
}

+(thread_state_flavor_t)threadState {
#if defined(__arm64__)
    return ARM_THREAD_STATE64;
#elif defined(__arm__)
    return ARM_THREAD_STATE;
#elif defined(__x86_64__)
    return x86_THREAD_STATE64;
#elif defined(__i386__)
    return x86_THREAD_STATE32;
#endif
}

+(uintptr_t)machThreadGetLinkRegisterPointerWithContext:(mcontext_t const)machineContext {
#if defined(__i386__)
    return 0;
#elif defined(__x86_64__)
    return 0;
#else
    return machineContext->__ss.__lr;
#endif
}

@end

@implementation AshBacktrackOCInfo


@end
