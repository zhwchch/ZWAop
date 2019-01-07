# ZWAop
类似于Aspect的库，但可以添加多个切面，使用汇编完成参数传递和函数调用，效率较高。

#用法
- (void)test {

    ZWAddAop(self, @selector(aMethod1:), ZWAopOptionBefore | ZWAopOptionReplace  | ZWAopOptionAfter , ^(NSArray *info, int a){
        NSLog(@"before1 | after1 : %d", a);
    });

    ZWAddAop(self, @selector(aMethod2::::::::), ZWAopOptionAfter, ^(NSArray *info, NSString *str ,NSString *a2 ,NSString *a3 ,NSString *a4 ,NSString *a5 ,NSString *a6 ,NSString *a7 ,NSString *a8){
        NSLog(@"after2: %@\n%@\n%@\n%@\n%@", str, a5, a6, a7, a8);
    });

    ZWAddAop(self, @selector(aMethod2::::::::), ZWAopOptionReplace | ZWAopOptionOnly, ^(NSArray *info, NSString *str,NSString *a2 ,NSString *a3 ,NSString *a4 ,NSString *a5 ,NSString *a6 ,NSString *a7 ,NSString *a8){
        NSLog(@"replace2 | after2: %@\n%@\n%@\n%@\n%@", str, a5, a6, a7, a8);
    });

    ZWAddAop(self, @selector(aMethod3::), ZWAopOptionReplace, ^int (NSArray *info, NSString *str){
        NSLog(@"replace3: %@", str);
        return 11034;
    });

    ZWAddAop(self, @selector(aMethod3::), ZWAopOptionAfter, ^int (NSArray *info, NSString *str){
        NSLog(@"after31: %@ \n %@", info, str);
        return 11034;
    });

    id handle1 = ZWAddAop(self, @selector(aMethod3::), ZWAopOptionAfter, ^int (NSArray *info, NSString *str){
        NSLog(@"after32: %@", str);
        return 11034;
    });
    ZWRemoveAop(self, handle1, ZWAopOptionAfter | ZWAopOptionRemoveAop);
//    ZWRemoveAop(self, nil, ZWAopOptionAfter);

    ZWAddAop(self, @selector(aMethod3::), ZWAopOptionAfter, ^int (NSArray *info, NSString *str, NSArray *ar){
        NSLog(@"after33: %@", str);
        return 11034;
    });

    ZWAddAop([self class], @selector(aMethod4:), ZWAopOptionReplace, ^(id info , int a, int b){
        NSLog(@"META replace4:");
    });



    [self aMethod1:8848];
    [self aMethod2:@"test str" :@"this is a test" :@"this is a test":@"this is a test":@"this is a test":@"this is a test":@"this is a test a7":@"this is a test a8"];
    int r = [self aMethod3:@"你咋不上天呢" :@[@1,@2]];
    NSLog(@"%d",r);

    [ViewController aMethod4:12358];

    ZWAddAop(self, @selector(viewWillAppear:), ZWAopOptionBefore, ^(NSArray *info, BOOL animated){
        NSLog(@"after viewWillAppear: %d", animated);
    });

}
- (void)viewWillAppear:(BOOL)animated {

    ZWAddAop(self, @selector(aMethod4::::::::), ZWAopOptionAfter, ^int (NSArray *info,NSInteger str, NSInteger a2,  NSInteger a3, NSInteger a4, NSInteger a5, NSInteger a6, NSInteger a7, NSInteger a8){
        NSLog(@"after43: %ld %ld %ld %ld %ld",str, a5, a6, a7, a8);
        return 11034;
    });
    
    [self aMethod4:1 :2 :3 :4 :5 :6 :7 :8];
}

- (NSRange)aMethod1:(int)a {
    NSLog(@"method1: %d",a);
    return (NSRange){0,1};
}

- (void)aMethod2:(NSString *)str :(NSString *)a2 :(NSString *)a3 :(NSString *)a4 :(NSString *)a5 :(NSString *)a6 :(NSString *)a7 :(NSString *)a8 {
    NSLog(@"method2: %@\n%@\n%@\n%@\n%@", str, a5, a6, a7, a8);
}

- (int )aMethod3:(NSString *)str :(NSArray *)array{
    NSLog(@"method3: %@", str);
    return 11;
}

+ (void)aMethod4:(int )obj {
    NSLog(@"method4: %d", obj);
}

- (void)aMethod4:(NSInteger)str :(NSInteger)a2 :(NSInteger)a3 :(NSInteger)a4 :(NSInteger)a5 :(NSInteger)a6 :(NSInteger)a7 :(NSInteger)a8 {
    NSLog(@"method4: %ld %ld %ld %ld %ld",str, a5, a6, a7, a8);
}
