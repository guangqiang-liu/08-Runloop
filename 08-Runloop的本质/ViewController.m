//
//  ViewController.m
//  08-Runloop的本质
//
//  Created by 刘光强 on 2020/2/9.
//  Copyright © 2020 guangqiang.liu. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()


@end

@implementation ViewController

void test1() {
    // 创建一个Observe
    CFRunLoopObserverRef observer = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopAllActivities, YES, 0, observerHandler, NULL);
    
    // 创建一个runloop
    CFRunLoopRef loop = CFRunLoopGetMain();
    
    // 将observere添加到runloop
    CFRunLoopAddObserver(loop, observer, kCFRunLoopDefaultMode);
    
    // 释放observer
    CFRelease(observer);
}

void test2() {
    // 创建一个runloop
    CFRunLoopRef loop = CFRunLoopGetMain();
    
    // 创建一个Observe
    CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopAllActivities, YES, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        switch (activity) {
            case kCFRunLoopEntry:
            {
                CFRunLoopMode mode = CFRunLoopCopyCurrentMode(loop);
                NSLog(@"kCFRunLoopEntry == %@", mode);
                CFRelease(mode);
            }
            break;
            case kCFRunLoopExit:
            {
                CFRunLoopMode mode = CFRunLoopCopyCurrentMode(loop);
                NSLog(@"kCFRunLoopExit == %@", mode);
                CFRelease(mode);
            }
            break;
            default:
                break;
        }
    });
    
    // 将observere添加到runloop
    CFRunLoopAddObserver(loop, observer, kCFRunLoopCommonModes);
    
    // 释放observer
    CFRelease(observer);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    // 监听点击
    test1();
    
    // 监听滚动
//    test2();
    
    // 处理block
//    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
//        NSLog(@"====");
//    });
    
    
//    dispatch_async(dispatch_get_global_queue(0, 0), ^{
//        dispatch_async(dispatch_get_main_queue(), ^{
//
//        });
//    });
}

void observerHandler(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    switch (activity) {
        case kCFRunLoopEntry:
            NSLog(@"kCFRunLoopEntry");
        break;
        case kCFRunLoopBeforeTimers:
            NSLog(@"kCFRunLoopBeforeTimers");
        break;
        case kCFRunLoopBeforeSources:
            NSLog(@"kCFRunLoopBeforeSources");
        break;
        case kCFRunLoopBeforeWaiting:
            NSLog(@"kCFRunLoopBeforeWaiting");
        break;
        case kCFRunLoopAfterWaiting:
            NSLog(@"kCFRunLoopAfterWaiting");
        break;
        case kCFRunLoopExit:
            NSLog(@"kCFRunLoopExit");
        break;
        default:
            break;
    }
}

-  (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // 处理timer
    [NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer * _Nonnull timer) {
        NSLog(@"");
    }];
    
    // 处理点击事件
    NSLog(@"%s", __func__);
}
@end
