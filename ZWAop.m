//
//  ZWAop.m
//  ZWAop
//
//  Created by Wei on 2018/11/10.
//  Copyright © 2018年 Wei. All rights reserved.
//

#import "ZWAop.h"

#if defined(__arm64__)
#import <objc/runtime.h>
#import <os/lock.h>
#import <pthread.h>


/*  选用NSDictionary字典作为关联容器，其查询插入效率很高。使用CFDictionaryRef替代意义不大，
 CFDictionaryCreateMutable创建效率比[NSMutableDictionary dictionary]低很多，使用
 也没有NSDictionary方便，效率也高不了多少。最重要的是CFDictionaryRef也要求key和value
 为对象，所以不能使用selector作为key，只能将selector封装成NSNumber再使用，所以无法通过
 避免创建对象来降低开销，不过好消息是NSNumber创建开销较小。（在队上分配内存是比较昂贵的操作，
 特别是大量分配（万次/秒），在这里频繁调用的场景尤其明显。）
 另外：CFDictionaryGetKeysAndValues这个函数似乎有bug，拿到的key和value数组不太对。
 目前该方案一半的开销开销在字典的查询上，想要再有明显优化就需要自定义容器了。或者想要再更大
 的提升，就得从实现原理入手了。
 */
static NSMutableDictionary  *_ZWBeforeIMP;
static NSMutableDictionary  *_ZWOriginIMP;
static NSMutableDictionary  *_ZWAfterIMP;
static NSMutableDictionary  *_ZWAllSigns;
static Class _ZWBlockClass;

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
API_AVAILABLE(ios(10.0))
static os_unfair_lock_t _ZWLock;
#else
static pthread_mutex_t _ZWLock;
#endif

__attribute__((constructor(2018))) void ZWInvocationInit() {
    
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
    if (@available(iOS 10.0, *)) {
        _ZWLock = malloc(sizeof(os_unfair_lock));
        _ZWLock->_os_unfair_lock_opaque = 0;
    }
#else
    pthread_mutex_init(&_ZWLock, NULL);
#endif
    _ZWOriginIMP = [NSMutableDictionary dictionary];
    _ZWBeforeIMP = [NSMutableDictionary dictionary];
    _ZWAfterIMP = [NSMutableDictionary dictionary];
    _ZWAllSigns = [NSMutableDictionary dictionary];
    _ZWBlockClass = NSClassFromString(@"NSBlock");
}

OS_ALWAYS_INLINE void ZWLock(void *lock) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
    if (@available(iOS 10.0, *)) {
        os_unfair_lock_lock((os_unfair_lock_t)lock);
    }
#else
    pthread_mutex_lock(&lock);
#endif
}

OS_ALWAYS_INLINE void ZWUnlock(void *lock) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
    if (@available(iOS 10.0, *)) {
        os_unfair_lock_unlock((os_unfair_lock_t)lock);
    }
#else
    pthread_mutex_unlock(&lock);
#endif
}

#pragma mark - erery invocation

OS_ALWAYS_INLINE void ZWStoreParams(void) {
    asm volatile("str    d7, [x11, #0x88]\n\
                 str    d6, [x11, #0x80]\n\
                 str    d5, [x11, #0x78]\n\
                 str    d4, [x11, #0x70]\n\
                 str    d3, [x11, #0x68]\n\
                 str    d2, [x11, #0x60]\n\
                 str    d1, [x11, #0x58]\n\
                 str    d0, [x11, #0x50]\n\
                 str    x8, [x11, #0x40]\n\
                 str    x7, [x11, #0x38]\n\
                 str    x6, [x11, #0x30]\n\
                 str    x5, [x11, #0x28]\n\
                 str    x4, [x11, #0x20]\n\
                 str    x3, [x11, #0x18]\n\
                 str    x2, [x11, #0x10]\n\
                 str    x1, [x11, #0x8]\n\
                 str    x0, [x11]\n\
                 ");
}
OS_ALWAYS_INLINE void ZWLoadParams(void) {
    asm volatile("ldr    d7, [x11, #0x88]\n\
                 ldr    d6, [x11, #0x80]\n\
                 ldr    d5, [x11, #0x78]\n\
                 ldr    d4, [x11, #0x70]\n\
                 ldr    d3, [x11, #0x68]\n\
                 ldr    d2, [x11, #0x60]\n\
                 ldr    d1, [x11, #0x58]\n\
                 ldr    d0, [x11, #0x50]\n\
                 ldr    x8, [x11, #0x40]\n\
                 ldr    x7, [x11, #0x38]\n\
                 ldr    x6, [x11, #0x30]\n\
                 ldr    x5, [x11, #0x28]\n\
                 ldr    x4, [x11, #0x20]\n\
                 ldr    x3, [x11, #0x18]\n\
                 ldr    x2, [x11, #0x10]\n\
                 ldr    x1, [x11, #0x8]\n\
                 ldr    x0, [x11]\n\
                 ");
}

OS_ALWAYS_INLINE void ZWCopyStackParams(void) {
    //x11=sp，x12=原始栈参数地址，
    asm volatile("mov    x15, sp");
    asm volatile("LZW_20181108:");
    asm volatile("cbz    x13, LZW_20181109");
    asm volatile("ldr    x0, [x12]");
    asm volatile("str    x0, [x15]");
    asm volatile("add    x15, x15, #0x8");
    asm volatile("add    x12, x12, #0x8");
    asm volatile("sub    x13, x13, #0x8");
    asm volatile("cbnz   x13, LZW_20181108");
    asm volatile("LZW_20181109:");
}


OS_ALWAYS_INLINE void ZWGlobalOCSwizzle(void) {
    asm volatile("stp    x29, x30, [sp, #-0x10]!");
    
    asm volatile("mov    x29, sp\n\
                 sub    sp, sp, #0xb0");
    
    asm volatile("mov    x11, sp");
    asm volatile("bl    _ZWStoreParams");
    
    asm volatile("mov    x0, sp");
    asm volatile("bl    _ZWBeforeInvocation");
    
    asm volatile("mov    x1, x0");
    asm volatile("mov    x0, sp");
    asm volatile("bl    _ZWInvocation");
    
    asm volatile("str    x0, [sp, #0xa0]");
    asm volatile("str    d0, [sp, #0xa8]");
    
    asm volatile("mov    x1, x9");
    asm volatile("mov    x0, sp");
    asm volatile("bl    _ZWAfterInvocation");
    
    asm volatile("ldr    x0, [sp, #0xa0]");
    asm volatile("ldr    d0, [sp, #0xa8]");
    
    asm volatile("mov    sp, x29");
    asm volatile("ldp    x29, x30, [sp], #0x10");
}

/*  0xe0是基础大小，其中包含9个寄存器共0x48，8浮点寄存器共0x80，还有0x18是额外信息，比如frameLength,
 超过0xe0的部分为栈参数大小
 */
OS_ALWAYS_INLINE NSUInteger ZWFrameLength(__unsafe_unretained id obj, SEL sel) {
    Class class = object_getClass(obj);
    if (OS_EXPECT(!class || !sel, 0)) return 0xe0;
    
    ZWLock(_ZWLock);
    __unsafe_unretained NSMutableDictionary *methodSigns = _ZWAllSigns[(id<NSCopying>)class];
    //利用Tagged Pointer机制，选用NSNumber包裹selector地址常量作为key，效率比使用字符串高很多
    id selKey = @((NSUInteger)(void *)sel);
    __unsafe_unretained NSNumber *num = methodSigns[selKey];
    ZWUnlock(_ZWLock);
    if (OS_EXPECT(num != nil, 1))  return [num unsignedLongLongValue];
    
    Method method = class_isMetaClass(class) ? class_getClassMethod(class, sel) : class_getInstanceMethod(class, sel);
    const char *type = method_getTypeEncoding(method);
    NSMethodSignature *sign = [NSMethodSignature signatureWithObjCTypes:type];
    NSUInteger frameLength = [sign frameLength];
    
    ZWLock(_ZWLock);
    if (OS_EXPECT(!methodSigns, 0)) {
        _ZWAllSigns[(id<NSCopying>)class] = [NSMutableDictionary dictionaryWithObject:@(frameLength) forKey:selKey];
    } else {
        methodSigns[selKey] = @(frameLength);
    }
    ZWUnlock(_ZWLock);
    return frameLength;
}

OS_ALWAYS_INLINE void *ZWGetInvocation(__unsafe_unretained NSDictionary *dict, __unsafe_unretained id obj, SEL sel) {
    if (!obj || !sel) return nil;
    ZWLock(_ZWLock);
    __unsafe_unretained id invocation = dict[(id<NSCopying>)object_getClass(obj)][@((NSUInteger)(void *)sel)];
    ZWUnlock(_ZWLock);
    return (__bridge void *)invocation;
}

OS_ALWAYS_INLINE NSUInteger ZWGetInvocationCount(__unsafe_unretained NSDictionary *dict,
                                                 __unsafe_unretained id *retValue,
                                                 __unsafe_unretained id obj,
                                                 SEL sel) {
    __unsafe_unretained id ret = (__bridge id)ZWGetInvocation(dict, obj, sel);
    if (OS_EXPECT(retValue != nil, 1)) *retValue = ret;
    
    if (OS_EXPECT([ret isKindOfClass:[NSArray class]], 0)) {
        return [ret count];
    } else if (OS_EXPECT([ret isKindOfClass:_ZWBlockClass], 1)) {
        return 1;
    }
    return 0;
}

OS_ALWAYS_INLINE IMP ZWGetOriginImp(__unsafe_unretained id obj, SEL sel) {
    __unsafe_unretained id invocation = (__bridge id)ZWGetInvocation(_ZWOriginIMP, obj, sel);
    if (OS_EXPECT([invocation isKindOfClass:[NSValue class]], 1)) {
        return [invocation pointerValue];
    }
    return NULL;
}

OS_ALWAYS_INLINE IMP ZWGetCurrentImp(__unsafe_unretained id obj, SEL sel) {
    __unsafe_unretained id invocation = (__bridge id)ZWGetInvocation(_ZWOriginIMP, obj, sel);
    if (OS_EXPECT([invocation isKindOfClass:_ZWBlockClass], 1)) {
        uint64_t *p = (__bridge void *)(invocation);
        return (IMP)*(p + 2);
    }
    return NULL;
}

IMP ZWGetAopImp(__unsafe_unretained NSDictionary *invocation,
                __unsafe_unretained id blocks,
                void **block,
                __unsafe_unretained id obj,
                SEL sel,
                NSUInteger index) {
    if (OS_EXPECT(!blocks, 0)) {
        blocks = (__bridge id)ZWGetInvocation(invocation, obj, sel);
    }
    if (OS_EXPECT([blocks isKindOfClass:[NSArray class]], 0)) {
        blocks = blocks[index];
    }
    if (OS_EXPECT(!blocks, 0)) return NULL;
    uint64_t *p = (__bridge void *)(blocks);
    if (block) *block = (__bridge void *)blocks;
    
    return (IMP)*(p + 2);
}

void ZWAopInvocationCall(void **sp,
                         __unsafe_unretained id allInvocation,
                         __unsafe_unretained id invocations,
                         __unsafe_unretained id obj,
                         SEL sel,
                         ZWAopInfo *infoP,
                         int i,
                         NSInteger frameLenth) __attribute__((optnone)) {
    void *block = NULL;
    ZWGetAopImp(allInvocation, invocations, &block, obj, sel, i);
    
    asm volatile("cbz    x0, LZW_20181107");
    asm volatile("mov    x17, x0");
    asm volatile("ldr    x14, %0": "=m"(infoP));
    asm volatile("ldr    x11, %0": "=m"(sp));
    asm volatile("ldr    x13, %0": "=m"(frameLenth));
    asm volatile("ldr    x15, %0": "=m"(block));
    asm volatile("cbz    x13, LZW_20181110");
    asm volatile("add    x12, x11, 0xc0");
    
    asm volatile("sub    sp, sp, x13");
    asm volatile("bl     _ZWCopyStackParams");
    asm volatile("LZW_20181110:");
    asm volatile("bl     _ZWLoadParams");
    asm volatile("mov    x1, x14");
    asm volatile("mov    x0, x15");
    asm volatile("blr    x17");
    asm volatile("sub    sp, x29, 0x50");
    asm volatile("LZW_20181107:");
}

OS_ALWAYS_INLINE NSInteger ZWAopInvocation(void **sp,
                                           __unsafe_unretained NSDictionary *allInvocation,
                                           ZWAopOption option,
                                           NSInteger *frameLengthPtr) {
    __unsafe_unretained id obj = (__bridge id)(*sp);
    SEL sel = *(sp + 1);
    if (OS_EXPECT(!obj || !sel, 0)) return 0;
    __unsafe_unretained id invocations = nil;
    NSInteger count = ZWGetInvocationCount(allInvocation, &invocations, obj, sel);
    //这里最好保持一个强引用，如果在调用过程中，调用正好被移除，可能会crash。
    id invocationsStrong = invocations;
    
    //以前是用NSArray来作为容器，但使用结构体后，可以大幅提高性能
    ZWAopInfo info = {obj, sel, option};
    NSInteger frameLength = frameLengthPtr ? *frameLengthPtr : ZWFrameLength(obj, sel) - 0xe0;
    for (int i = 0; i < count; ++i) {
        ZWAopInvocationCall(sp, allInvocation, invocationsStrong, obj, sel, &info, i, frameLength);
    }
    return frameLength;
}

OS_ALWAYS_INLINE NSInteger ZWBeforeInvocation(void **sp) {
    return ZWAopInvocation(sp, _ZWBeforeIMP, ZWAopOptionBefore, NULL);
}

void ZWManualPlaceholder() __attribute__((optnone)) {}
/*  本函数关闭编译优化，如果不关闭，sp寄存器的回溯值在不同的优化情况下是不同的，还需要区分比较麻烦，
 而且即使开启优化也只有一丢丢的提升，还不如关闭图个方便。ZWManualPlaceholder占位函数，仅为触发
 Xcode插入x29, x30, [sp, #-0x10]!记录fp, lr。
 */
void ZWInvocation(void **sp, NSInteger frameLenth) __attribute__((optnone)) {
    __unsafe_unretained id obj;
    SEL sel;
    void *obj_p = &obj;
    void *sel_p = &sel;
    ZWManualPlaceholder();
    
    asm volatile("ldr    x11, %0": "=m"(sp));
    asm volatile("ldr    x10, %0": "=m"(obj_p));
    asm volatile("ldr    x0, [x11]");
    asm volatile("str    x0, [x10]");
    asm volatile("ldr    x10, %0": "=m"(sel_p));
    asm volatile("ldr    x0, [x11, #0x8]");
    asm volatile("str    x0, [x10]");
    
    asm volatile("ldr    x11, %0": "=m"(sp));
    asm volatile("ldr    x0, [x11]");
    asm volatile("ldr    x1, [x11, #0x8]");
    asm volatile("bl     _ZWGetOriginImp");
    asm volatile("cbnz   x0, LZW_20181105");
    
    //以前是用NSArray来作为容器，但使用结构体后，可以大幅提高性能
    ZWAopInfo info = {obj, sel, ZWAopOptionReplace};
    void *infoP = &info;
    asm volatile("ldr    x11, %0": "=m"(sp));
    asm volatile("ldr    x0, [x11]");
    asm volatile("ldr    x1, [x11, #0x8]");
    asm volatile("bl     _ZWGetCurrentImp");
    asm volatile("cbz    x0, LZW_20181106");
    
    asm volatile("mov    x17, x0");
    asm volatile("ldr    x14, %0": "=m"(infoP));
    asm volatile("ldr    x11, %0": "=m"(sp));
    asm volatile("ldr    x13, %0": "=m"(frameLenth));
    asm volatile("cbz    x13, LZW_20181111");
    asm volatile("add    x12, x11, 0xc0");//0xb0 + 0x10
    
    asm volatile("sub    sp, sp, x13");
    asm volatile("bl     _ZWCopyStackParams");
    asm volatile("LZW_20181111:");
    asm volatile("bl     _ZWLoadParams");
    asm volatile("mov    x1, x14");
    asm volatile("blr    x17");
    asm volatile("sub    sp, x29, 0x50");
    asm volatile("b      LZW_20181106");
    
    asm volatile("LZW_20181105:");
    asm volatile("mov    x17, x0");
    asm volatile("ldr    x11, %0": "=m"(sp));
    asm volatile("ldr    x13, %0": "=m"(frameLenth));
    asm volatile("cbz    x13, LZW_20181112");
    asm volatile("add    x12, x11, 0xc0");
    asm volatile("sub    sp, sp, x13");
    asm volatile("bl     _ZWCopyStackParams");
    asm volatile("LZW_20181112:");
    asm volatile("bl     _ZWLoadParams");
    asm volatile("blr    x17");
    asm volatile("sub    sp, x29, 0x50");
    asm volatile("LZW_20181106:");
    asm volatile("ldr    x9, [x29, #-0x10]");//回传frameLength给ZWAfterInvocation使用
}


OS_ALWAYS_INLINE NSInteger ZWAfterInvocation(void **sp, NSInteger frameLength) {
    return ZWAopInvocation(sp, _ZWAfterIMP, ZWAopOptionAfter, &frameLength);
}

#pragma mark - register or remove

OS_ALWAYS_INLINE Method ZWGetMethod(Class cls, SEL sel) {
    unsigned int count = 0;
    Method retMethod = NULL;
    Method *list = class_copyMethodList(cls, &count);
    for (int i = 0; i < count; ++i) {
        Method m = list[i];
        SEL s = method_getName(m);
        if (OS_EXPECT(sel_isEqual(s, sel), 0)) {
            retMethod = m;
        }
    }
    
    free(list);
    return retMethod;
}

OS_ALWAYS_INLINE void ZWAddInvocation(__unsafe_unretained NSMutableDictionary *dict,
                                      __unsafe_unretained Class class,
                                      __unsafe_unretained NSNumber *selKey,
                                      __unsafe_unretained id block,
                                      ZWAopOption options) {
    NSMutableDictionary *invocations = dict[(id<NSCopying>)class];
    NSArray *tmp = invocations[selKey];
    if (OS_EXPECT(options & ZWAopOptionOnly, 0)) {
        invocations[selKey] = block;
    } else {
        if ([tmp isKindOfClass:[NSArray class]]) {
            invocations[selKey] = [tmp arrayByAddingObject:block];
        } else if (!tmp) {
            invocations[selKey] = @[block];
        }
    }
}

id ZWAddAop(id obj, SEL sel, ZWAopOption options, id block) {
    if (OS_EXPECT(!obj || !sel || !block, 0)) return nil;
    if (OS_EXPECT(options == ZWAopOptionOnly
                  || options == ZWAopOptionMeta
                  || options == (ZWAopOptionMeta | ZWAopOptionOnly), 0)) return nil;
    
    
    Class class = object_isClass(obj) ? obj : object_getClass(obj);
    if (options & ZWAopOptionMeta) {
        class = class_isMetaClass(class) ? class : object_getClass(obj);
    }
    
    Method method = ZWGetMethod(class, sel);//class_getInstanceMethod(class, sel)会获取父类的方法
    IMP originImp = method_getImplementation(method);
    NSNumber *selKey = @((NSUInteger)(void *)sel);
    
    
    ZWLock(_ZWLock);
    if (!_ZWOriginIMP[(id<NSCopying>)class]) {
        _ZWOriginIMP[(id<NSCopying>)class] = [NSMutableDictionary dictionary];
        _ZWBeforeIMP[(id<NSCopying>)class] = [NSMutableDictionary dictionary];
        _ZWAfterIMP[(id<NSCopying>)class] = [NSMutableDictionary dictionary];
    }
    
    if (options & ZWAopOptionReplace) {
        _ZWOriginIMP[(id<NSCopying>)class][selKey] = block;
    } else {
        if (OS_EXPECT(originImp != ZWGlobalOCSwizzle, 1)) {
            _ZWOriginIMP[(id<NSCopying>)class][selKey] = [NSValue valueWithPointer:originImp];
        }
    }
    
    if (options & ZWAopOptionBefore) {
        ZWAddInvocation(_ZWBeforeIMP, class, selKey, block, options);
    }
    if (options & ZWAopOptionAfter) {
        ZWAddInvocation(_ZWAfterIMP, class, selKey, block, options);
    }
    ZWUnlock(_ZWLock);
    method_setImplementation(method, ZWGlobalOCSwizzle);
    
    //这里可以提前调用ZWFrameLength预缓存frameLength
    return block;
}

OS_ALWAYS_INLINE void ZWRemoveInvocation(__unsafe_unretained NSMutableDictionary *dict,
                                         __unsafe_unretained Class class,
                                         __unsafe_unretained id identifier,
                                         ZWAopOption options) {
    if (!identifier) {
        dict[(id<NSCopying>)class] = [NSMutableDictionary dictionary];
        return;
    }
    NSMutableDictionary *invocations = dict[(id<NSCopying>)class];
    
    NSArray *allKeys = [invocations allKeys];
    for (NSNumber *key in allKeys) {
        id obj = invocations[key];
        if ([obj isKindOfClass:_ZWBlockClass]) {
            if (obj == identifier) {
                invocations[key] = nil;
            }
        } else if ([obj isKindOfClass:[NSArray class]]) {
            NSMutableArray *arr = [NSMutableArray array];
            for (id block in obj) {
                if (block != identifier) {
                    if (options & ZWAopOptionRemoveAop) {
                        invocations[key] = nil;
                        break;
                    }
                    [arr addObject:block];
                }
            }
            invocations[key] = [arr copy];;
        }
    }
}

void ZWRemoveAop(id obj, id identifier, ZWAopOption options) {
    if (!obj) return;
    
    Class class = object_isClass(obj) ? obj : object_getClass(obj);
    if (options & ZWAopOptionMeta) {
        class = class_isMetaClass(class) ? class : object_getClass(obj);
    }
    
    ZWLock(_ZWLock);
    if (options & ZWAopOptionReplace) {
        ZWRemoveInvocation(_ZWOriginIMP, class, identifier, options);
    }
    
    if (options & ZWAopOptionBefore) {
        ZWRemoveInvocation(_ZWBeforeIMP, class, identifier, options);
    }
    
    if (options & ZWAopOptionAfter) {
        ZWRemoveInvocation(_ZWAfterIMP, class, identifier, options);
    }
    ZWUnlock(_ZWLock);
}
#pragma mark - convenient api

id ZWAddAopBefore(id obj, SEL sel, id block) {
    return ZWAddAop(obj, sel, ZWAopOptionBefore, block);
}
id ZWAddAopAfter(id obj, SEL sel, id block) {
    return ZWAddAop(obj, sel, ZWAopOptionAfter, block);
}
id ZWAddAopReplace(id obj, SEL sel, id block) {
    return ZWAddAop(obj, sel, ZWAopOptionReplace, block);
}

id ZWAddAopBeforeAndAfter(id obj, SEL sel, id block) {
    return ZWAddAop(obj, sel, ZWAopOptionBefore | ZWAopOptionAfter, block);
}
id ZWAddAopAll(id obj, SEL sel, id block) {
    return ZWAddAop(obj, sel, ZWAopOptionAll, block);
}

void ZWRemoveAopClass(id obj, ZWAopOption options) {
    return ZWRemoveAop(obj, nil, options);
}
void ZWRemoveAopClassMethod(id obj, id identifier, ZWAopOption options) {
    return ZWRemoveAop(obj, identifier, options | ZWAopOptionRemoveAop);
}

#else
#pragma mark - placeholder
id ZWAddAop(id obj, SEL sel, ZWAopOption options, id block) {}
void ZWRemoveAop(id obj, id identifier, ZWAopOption options) {}
id ZWAddAopBefore(id obj, SEL sel, id block){}
id ZWAddAopAfter(id obj, SEL sel, id block){}
id ZWAddAopReplace(id obj, SEL sel, id block){}
id ZWAddAopBeforeAndAfter(id obj, SEL sel, id block){}
id ZWAddAopAll(id obj, SEL sel, id block){}
void ZWRemoveAopClassMethod(id obj, id identifier, ZWAopOption options){}
void ZWRemoveAopClass(id obj, ZWAopOption options){}
#endif
