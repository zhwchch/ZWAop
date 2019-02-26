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

__attribute__((constructor(2018))) void JOInvocationInit() {
    
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

//MARK:erery invocation

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
    
    asm volatile("mov    x0, sp");
    asm volatile("bl    _ZWInvocation");
    
    asm volatile("str    x0, [sp, #0xa0]");
    asm volatile("str    d0, [sp, #0xa8]");
    
    asm volatile("mov    x0, sp");
    asm volatile("bl    _ZWAfterInvocation");
    
    asm volatile("ldr    x0, [sp, #0xa0]");
    asm volatile("ldr    d0, [sp, #0xa8]");
    
    asm volatile("mov    sp, x29");
    asm volatile("ldp    x29, x30, [sp], #0x10");
}

OS_ALWAYS_INLINE id ZWGetSelectorKey(SEL sel) {
    return @((NSUInteger)(void *)sel);
}
/*  0xe0是基础大小，其中包含9个寄存器共0x48，8浮点寄存器共0x80，还有0x18是额外信息，比如frameLength,
 超过0xe0的部分为栈参数大小
 */
int ZWFrameLength(void **sp) {
    id obj = (__bridge id)(*sp);
    SEL sel = *(sp + 1);
    Class class = object_getClass(obj);
    if (!class || !sel) return 0xe0;
    
    ZWLock(_ZWLock);
    __unsafe_unretained NSMutableDictionary *methodSigns = _ZWAllSigns[(id<NSCopying>)class];
    id selKey = ZWGetSelectorKey(sel);
    __unsafe_unretained NSMethodSignature *sign = methodSigns[selKey];
    ZWUnlock(_ZWLock);
    if (sign)  return (int)[sign frameLength];
    
    Method method = class_isMetaClass(class) ? class_getClassMethod(class, sel) : class_getInstanceMethod(class, sel);
    const char *type = method_getTypeEncoding(method);
    sign = [NSMethodSignature signatureWithObjCTypes:type];
    ZWLock(_ZWLock);
    if (!methodSigns) {
        _ZWAllSigns[(id<NSCopying>)class] = [NSMutableDictionary dictionaryWithObject:sign forKey:selKey];
    } else {
        methodSigns[selKey] = sign;
    }
    ZWUnlock(_ZWLock);
    return (int)[sign frameLength];
}

OS_ALWAYS_INLINE id ZWGetInvocation(__unsafe_unretained NSDictionary *dict, __unsafe_unretained id obj, SEL sel) {
    if (!obj || !sel) return nil;
    ZWLock(_ZWLock);
    __unsafe_unretained id Invocation = dict[(id<NSCopying>)object_getClass(obj)][ZWGetSelectorKey(sel)];
    ZWUnlock(_ZWLock);
    return Invocation;
}

OS_ALWAYS_INLINE NSUInteger ZWGetInvocationCount(__unsafe_unretained NSDictionary *dict,
                                                 __unsafe_unretained id obj,
                                                 SEL sel) {
    __unsafe_unretained id ret = ZWGetInvocation(dict, obj, sel);
    if ([ret isKindOfClass:[NSArray class]]) {
        return [ret count];
    } else if ([ret isKindOfClass:_ZWBlockClass]) {
        return 1;
    }
    return 0;
}

IMP ZWGetOriginImp(id obj, SEL sel) {
    __unsafe_unretained id Invocation = ZWGetInvocation(_ZWOriginIMP, obj, sel);
    if ([Invocation isKindOfClass:[NSValue class]]) {
        return [Invocation pointerValue];
    }
    return NULL;
}

IMP ZWGetCurrentImp(id obj, SEL sel) {
    __unsafe_unretained id Invocation = ZWGetInvocation(_ZWOriginIMP, obj, sel);
    if ([Invocation isKindOfClass:_ZWBlockClass]) {
        
        if (!Invocation) return NULL;
        uint64_t *p = (__bridge void *)(Invocation);
        return (IMP)*(p + 2);
    }
    return NULL;
}

IMP ZWGetAopImp(__unsafe_unretained NSDictionary *Invocation, id obj, SEL sel, NSUInteger index) {
    __unsafe_unretained id block = ZWGetInvocation(Invocation, obj, sel);
    if ([block isKindOfClass:[NSArray class]]) {
        block = block[index];
    }
    if (!block) return NULL;
    uint64_t *p = (__bridge void *)(block);
    return (IMP)*(p + 2);
}

void ZWAopInvocationCall(void **sp,
                         __unsafe_unretained id Invocation,
                         __unsafe_unretained id obj,
                         __unsafe_unretained id arr,
                         SEL sel,
                         int i,
                         NSInteger frameLenth) __attribute__((optnone)) {
    ZWGetAopImp(Invocation, obj, sel, i);
    asm volatile("cbz    x0, LZW_20181107");
    asm volatile("mov    x17, x0");
    asm volatile("ldr    x14, %0": "=m"(arr));
    asm volatile("ldr    x11, %0": "=m"(sp));
    asm volatile("ldr    x13, %0": "=m"(frameLenth));
    asm volatile("cbz    x13, LZW_20181110");
    asm volatile("add    x12, x11, 0xc0");
    
    asm volatile("sub    sp, sp, x13");
    asm volatile("bl     _ZWCopyStackParams");
    asm volatile("LZW_20181110:");
    asm volatile("bl     _ZWLoadParams");
    asm volatile("mov    x1, x14");
    asm volatile("blr    x17");
    asm volatile("sub    sp, x29, 0x40");
    asm volatile("LZW_20181107:");
}

void ZWAopInvocation(void **sp, __unsafe_unretained NSDictionary *Invocation, ZWAopOption option) {
    id obj = (__bridge id)(*sp);
    SEL sel = *(sp + 1);
    if (!obj || !sel) return;
    NSInteger count = ZWGetInvocationCount(Invocation, obj, sel);
    NSArray *arr = @[obj, [NSValue valueWithPointer:sel], @(option)];
    NSInteger frameLenth = ZWFrameLength(sp) - 0xe0;
    for (int i = 0; i < count; ++i) {
        ZWAopInvocationCall(sp, Invocation, obj, arr, sel, i, frameLenth);
    }
}

void ZWAfterInvocation(void **sp) {
    ZWAopInvocation(sp, _ZWAfterIMP, ZWAopOptionAfter);
}
/*  本函数关闭编译优化，如果不关闭，sp寄存器的回溯值在不同的优化情况下是不同的，还需要区分比较麻烦，
 而且即使开启优化也只有一丢丢的提升，还不如关闭图个方便
 */
void ZWInvocation(void **sp) __attribute__((optnone)) {
    __autoreleasing id obj;
    SEL sel;
    void *obj_p = &obj;
    void *sel_p = &sel;
    NSInteger frameLenth = ZWFrameLength(sp) - 0xe0;
    
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
    
    __autoreleasing NSArray *arr = @[obj, [NSValue valueWithPointer:sel], @(ZWAopOptionReplace)];
    
    asm volatile("ldr    x11, %0": "=m"(sp));
    asm volatile("ldr    x0, [x11]");
    asm volatile("ldr    x1, [x11, #0x8]");
    asm volatile("bl     _ZWGetCurrentImp");
    asm volatile("cbz    x0, LZW_20181106");
    
    asm volatile("mov    x17, x0");
    asm volatile("ldr    x14, %0": "=m"(arr));
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
    asm volatile("sub    sp, x29, 0x70");
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
    asm volatile("sub    sp, x29, 0x70");
    asm volatile("LZW_20181106:");
}

void ZWBeforeInvocation(void **sp) {
    ZWAopInvocation(sp, _ZWBeforeIMP, ZWAopOptionBefore);
}


//MARK:register or remove

OS_ALWAYS_INLINE Method ZWGetMethod(Class cls, SEL sel) {
    unsigned int count = 0;
    Method retMethod = NULL;
    Method *list = class_copyMethodList(cls, &count);
    for (int i = 0; i < count; ++i) {
        Method m = list[i];
        SEL s = method_getName(m);
        if (sel_isEqual(s, sel)) {
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
    NSArray *tmp = dict[(id<NSCopying>)class][selKey];
    if (options & ZWAopOptionOnly) {
        dict[(id<NSCopying>)class][selKey] = block;
    } else {
        if ([tmp isKindOfClass:[NSArray class]]) {
            dict[(id<NSCopying>)class][selKey] = [tmp arrayByAddingObject:block];
        } else if (!tmp) {
            dict[(id<NSCopying>)class][selKey] = @[block];
        }
    }
}

id ZWAddAop(id obj, SEL sel, ZWAopOption options, id block) {
    if (!obj || !sel || !block) return nil;
    if (options == ZWAopOptionOnly
        || options == ZWAopOptionMeta
        || options == (ZWAopOptionMeta | ZWAopOptionOnly)) return nil;
    
    
    Class class = object_isClass(obj) ? obj : object_getClass(obj);
    if (options & ZWAopOptionMeta) {
        class = class_isMetaClass(class) ? class : object_getClass(obj);
    }
    
    Method method = ZWGetMethod(class, sel);//class_getInstanceMethod(class, sel)会获取父类的方法
    IMP originImp = method_getImplementation(method);
    NSNumber *selKey = ZWGetSelectorKey(sel);
    
    
    ZWLock(_ZWLock);
    if (!_ZWOriginIMP[(id<NSCopying>)class]) {
        _ZWOriginIMP[(id<NSCopying>)class] = [NSMutableDictionary dictionary];
        _ZWBeforeIMP[(id<NSCopying>)class] = [NSMutableDictionary dictionary];
        _ZWAfterIMP[(id<NSCopying>)class] = [NSMutableDictionary dictionary];
    }
    
    if (options & ZWAopOptionReplace) {
        _ZWOriginIMP[(id<NSCopying>)class][selKey] = block;
    } else {
        if (originImp != ZWGlobalOCSwizzle) {
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
    
    NSArray *allKeys = [dict[(id<NSCopying>)class] allKeys];
    for (NSNumber *key in allKeys) {
        id obj = dict[(id<NSCopying>)class][key];
        if ([obj isKindOfClass:_ZWBlockClass]) {
            if (obj == identifier) {
                dict[(id<NSCopying>)class][key] = nil;
            }
        } else if ([obj isKindOfClass:[NSArray class]]) {
            NSMutableArray *arr = [NSMutableArray array];
            for (id block in obj) {
                if (block != identifier) {
                    if (options & ZWAopOptionRemoveAop) {
                        dict[(id<NSCopying>)class][key] = nil;
                        break;
                    }
                    [arr addObject:block];
                }
            }
            dict[(id<NSCopying>)class][key] = [arr copy];;
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

//MARK:convenient api

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
//MARK:placeholder
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
