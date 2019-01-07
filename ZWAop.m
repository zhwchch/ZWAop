//
//  ZWAop.m
//  ZWAop
//
//  Created by Wei on 2018/11/10.
//  Copyright © 2018年 Wei. All rights reserved.
//

#import "ZWAop.h"
#import <objc/runtime.h>



#if defined(__arm64__)

static NSMutableDictionary  *_ZWBeforeIMP;
static NSMutableDictionary  *_ZWOriginIMP;
static NSMutableDictionary  *_ZWAfterIMP;
static NSMutableDictionary  *_ZWAllSigns;
static NSLock  *_ZWLock;

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

OS_ALWAYS_INLINE NSString *ZWGetMetaSelName(SEL sel) {
    return [@"__META_" stringByAppendingString:NSStringFromSelector(sel)];
}

/*  0xe0是基础大小，其中包含9个寄存器共0x48，8浮点寄存器共0x80，还有0x18是额外信息，比如frameLength,
    超过0xe0的部分为栈参数大小
 */
int ZWFrameLength(void **sp) {
    id obj = (__bridge id)(*sp);
    SEL sel = *(sp + 1);
    Class class = object_getClass(obj);
    if (!class || !sel) return 0xe0;
    
    [_ZWLock lock];
    NSMutableDictionary *methodSigns = _ZWAllSigns[NSStringFromClass(class)];
    [_ZWLock unlock];
    NSString *selName = class_isMetaClass(class) ? ZWGetMetaSelName(sel) : NSStringFromSelector(sel);
    NSMethodSignature *sign = methodSigns[selName];
    if (sign) {
        return (int)[sign frameLength];
    }
    
    Method method = class_isMetaClass(class) ? class_getClassMethod(class, sel) : class_getInstanceMethod(class, sel);
    const char *type = method_getTypeEncoding(method);
    sign = [NSMethodSignature signatureWithObjCTypes:type];
    [_ZWLock lock];
    if (!methodSigns) {
        _ZWAllSigns[NSStringFromClass(class)] = [NSMutableDictionary dictionaryWithObject:sign forKey:selName];
    } else {
        methodSigns[selName] = sign;
    }
    [_ZWLock unlock];
    return (int)[sign frameLength];
}

OS_ALWAYS_INLINE id ZWGetInvocation(NSDictionary *dict, id obj, SEL sel) {
    if (!dict || !obj || !sel) return nil;
    Class class = object_getClass(obj);
    NSString *className = NSStringFromClass(class);
    NSString *selName = class_isMetaClass(class) ? ZWGetMetaSelName(sel) : NSStringFromSelector(sel);
    [_ZWLock lock];
    id Invocation = dict[className][selName];
    [_ZWLock unlock];
    return Invocation;
}

OS_ALWAYS_INLINE NSUInteger ZWGetInvocationCount(NSDictionary *dict, id obj, SEL sel) {
    id ret = ZWGetInvocation(dict, obj, sel);
    if ([ret isKindOfClass:[NSArray class]]) {
        return [ret count];
    } else if ([ret isKindOfClass:NSClassFromString(@"NSBlock")]) {
        return 1;
    }
    return 0;
}

IMP ZWGetOriginImp(id obj, SEL sel) {
    id Invocation = ZWGetInvocation(_ZWOriginIMP, obj, sel);
    if ([Invocation isKindOfClass:[NSValue class]]) {
        return [Invocation pointerValue];
    }
    return NULL;
}

IMP ZWGetCurrentImp(id obj, SEL sel) {
    id Invocation = ZWGetInvocation(_ZWOriginIMP, obj, sel);
    if ([Invocation isKindOfClass:NSClassFromString(@"NSBlock")]) {
        
        if (!Invocation) return NULL;
        uint64_t *p = (__bridge void *)(Invocation);
        return (IMP)*(p + 2);
    }
    return NULL;
}

IMP ZWGetAopImp(NSDictionary *Invocation, id obj, SEL sel, NSUInteger index) {
    id block = ZWGetInvocation(Invocation, obj, sel);
    if ([block isKindOfClass:[NSArray class]]) {
        block = block[index];
    }
    if (!block) return NULL;
    uint64_t *p = (__bridge void *)(block);
    return (IMP)*(p + 2);
}


void ZWAopInvocation(void **sp, NSDictionary *Invocation, ZWAopOption option) {
    id obj = (__bridge id)(*sp);
    SEL sel = *(sp + 1);
    if (!obj || !sel) return;
    NSInteger count = ZWGetInvocationCount(Invocation, obj, sel);
    __autoreleasing NSArray *arr = @[obj, [NSValue valueWithPointer:sel], @(option)];
    NSInteger frameLenth = ZWFrameLength(sp) - 0xe0;
    for (int i = 0; i < count; ++i) {
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
        asm volatile("sub    sp, x29, 0x1e0");
        asm volatile("LZW_20181107:");
    }
}

void ZWAfterInvocation(void **sp) {
    ZWAopInvocation(sp, _ZWAfterIMP, ZWAopOptionAfter);
}
void ZWInvocation(void **sp) {
    __autoreleasing id obj;
    SEL sel;
    void *obj_p = &obj;
    void *sel_p = &sel;
    NSInteger frameLenth = ZWFrameLength(sp)- 0xe0;
    
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

OS_ALWAYS_INLINE void ZWAddInvocation(NSMutableDictionary *dict, NSString *className, NSString *selName, id block,  ZWAopOption options) {
    NSArray *tmp = dict[className][selName];
    if (options & ZWAopOptionOnly) {
        dict[className][selName] = block;
    } else {
        if ([tmp isKindOfClass:[NSArray class]]) {
            dict[className][selName] = [tmp arrayByAddingObject:block];
        } else if (!tmp) {
            dict[className][selName] = @[block];
        }
    }
}

id ZWAddAop(id obj, SEL sel, ZWAopOption options, id block) {
    if (!obj || !sel || !block) return nil;
    if (options == ZWAopOptionOnly
        || options == ZWAopOptionMeta
        || options == (ZWAopOptionMeta | ZWAopOptionOnly)) return nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _ZWOriginIMP = [NSMutableDictionary dictionary];
        _ZWBeforeIMP = [NSMutableDictionary dictionary];
        _ZWAfterIMP = [NSMutableDictionary dictionary];
        _ZWAllSigns = [NSMutableDictionary dictionary];
        _ZWLock = [[NSLock alloc] init];
    });
    
    Class class = object_isClass(obj) ? obj : object_getClass(obj);
    if (options & ZWAopOptionMeta) {
        class = class_isMetaClass(class) ? class : object_getClass(obj);
    }
    
    NSString *className = NSStringFromClass(class);
    Method method = ZWGetMethod(class, sel);//class_getInstanceMethod(class, sel)会获取父类的方法
    IMP originImp = method_getImplementation(method);
    NSString *selName = class_isMetaClass(class) ? ZWGetMetaSelName(sel) : NSStringFromSelector(sel);
    if (!className || !selName) return nil;
    
    [_ZWLock lock];
    if (!_ZWOriginIMP[className]) {
        _ZWOriginIMP[className] = [NSMutableDictionary dictionary];
        _ZWBeforeIMP[className] = [NSMutableDictionary dictionary];
        _ZWAfterIMP[className] = [NSMutableDictionary dictionary];
    }
    
    if (options & ZWAopOptionReplace) {
        _ZWOriginIMP[className][selName] = block;
    } else {
        if (originImp != ZWGlobalOCSwizzle) {
            _ZWOriginIMP[className][selName] = [NSValue valueWithPointer:originImp];
        }
    }
    
    if (options & ZWAopOptionBefore) {
        ZWAddInvocation(_ZWBeforeIMP, className, selName, block, options);
    }
    if (options & ZWAopOptionAfter) {
        ZWAddInvocation(_ZWAfterIMP, className, selName, block, options);
    }
    [_ZWLock unlock];
    method_setImplementation(method, ZWGlobalOCSwizzle);
    
    return block;
}

OS_ALWAYS_INLINE void ZWRemoveInvocation(NSMutableDictionary *dict, NSString *className, id identifier, ZWAopOption options) {
    if (!identifier) {
        dict[className] = [NSMutableDictionary dictionary];
        return;
    }
    
    NSArray *allKeys = [dict[className] allKeys];
    for (NSString *key in allKeys) {
        id obj = dict[className][key];
        if ([obj isKindOfClass:NSClassFromString(@"NSBlock")]) {
            if (obj == identifier) {
                dict[className][key] = nil;
            }
        } else if ([obj isKindOfClass:[NSArray class]]) {
            NSMutableArray *arr = [NSMutableArray array];
            for (id block in obj) {
                if (block != identifier) {
                    if (options & ZWAopOptionRemoveAop) {
                        dict[className][key] = nil;
                        break;
                    }
                    [arr addObject:block];
                }
            }
            dict[className][key] = [arr copy];;
        }
    }
}

void ZWRemoveAop(id obj, id identifier, ZWAopOption options) {
    if (!obj) return;
    
    Class class = object_isClass(obj) ? obj : object_getClass(obj);
    if (options & ZWAopOptionMeta) {
        class = class_isMetaClass(class) ? class : object_getClass(obj);
    }
    NSString *className = NSStringFromClass(class);

    [_ZWLock lock];
    if (options & ZWAopOptionReplace) {
        ZWRemoveInvocation(_ZWOriginIMP, className, identifier, options);
    }
    
    if (options & ZWAopOptionBefore) {
        ZWRemoveInvocation(_ZWBeforeIMP, className, identifier, options);
    }
    
    if (options & ZWAopOptionAfter) {
        ZWRemoveInvocation(_ZWAfterIMP, className, identifier, options);
    }
    [_ZWLock unlock];
}


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
    return ZWAddAop(obj, sel, ZWAopOptionDefault, block);
}

void ZWRemoveAopClass(id obj, ZWAopOption options) {
    return ZWRemoveAop(obj, nil, options);
}
void ZWRemoveAopClassMethod(id obj, id identifier, ZWAopOption options) {
    return ZWRemoveAop(obj, identifier, options | ZWAopOptionRemoveAop);
}
#else
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
