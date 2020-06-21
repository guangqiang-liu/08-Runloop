# 08-Runloop的本质

我们在探究Runloop的本质前首先要知道什么是Runloop?

> runloop定义：iOS程序中的运行循环机制，它能够保证程序一直处于运行中状态而不是执行完任务后就立即退出

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-115543@2x.png)

那么在项目的实际开发过程中，我们又有哪些开发场景中使用到了runloop的循环机制尼？，这里列举runloop的常用场景如下：

* 定时器
* PerformSelector()
* GCD Async
* 所有的事件响应，手势，列表滚动
* 多线程
* Autoreleasepool
* ...


当我们新建一个iOS程序时，系统就会默认在主线程给我们创建了一个runloop对象，代码如下：

```
int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    
    // 在UIApplicationMain函数内部，系统会自动创建一个runloop对象，并添加到主线程中
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
```

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-115624@2x.png)


当我们创建一个MacOs的命令行项目，系统没有默认为我们创建runloop对象，我们发现程序执行完语句后，就会立即退出，代码如下：

```
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        NSLog(@"Hello, World!");
        NSLog(@"111");
    }
    
    NSLog(@"2222");
    return 0;
}
```

上面的代码当执行完`NSLog(@"2222");`打印后，程序就直接退出了。也就是说当前主线程没有runloop时程序执行完任务就直接退出，不能够一直保持运行状态。

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-115557@2x.png)

我们如何才能获取到当前的runloop对象尼？

苹果为开发者提供了2套框架来访问和使用runloop对象

* NSRunloop：Foundation框架API
* CFRunLoopRef：Core Foundation框架API

其中`NSRunloop`是对`CFRunLoopRef`进行的一层更加面向对象的OC语法封装

```
	// 获取当前runloop
	NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
	CFRunLoopRef currentRunLoop2 = CFRunLoopGetCurrent();
	    
	// 获取主线程runloop
	NSRunLoop *mainRunLoop = [NSRunLoop mainRunLoop];
	CFRunLoopRef mainRunLoop2 = CFRunLoopGetMain();
```

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-115422@2x.png)

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-160132@2x.png)

接下来我们来探究下runloop相关API的底层源码，源码查看路径：`CF框架 -> CFRunLoop.c文件 -> _CFRunLoopGet0`

我们跟踪下runloop的核心函数代码流程如下：

```
// __CFRunLoops变量是CFMutableDictionaryRef类型的，它就是一个全局的字典类型对象，用来存储runloop和对应线程的集合
static CFMutableDictionaryRef __CFRunLoops = NULL;

static CFLock_t loopsLock = CFLockInit;

// 核心函数`_CFRunLoopGet0`，这个函数就是用来获取runloop对象的

// should only be called by Foundation
// t==0 is a synonym for "main thread" that always works
CF_EXPORT CFRunLoopRef _CFRunLoopGet0(pthread_t t) {
    
    // 判断线程是否为空
    if (pthread_equal(t, kNilPthreadT)) {
        // 如果线程为空，则将主线程作为传递进来的线程
        t = pthread_main_thread_np();
    }
    
    // 执行加锁操作
    __CFLock(&loopsLock);
    
    // 判断__CFRunLoops集合是否有值
    if (!__CFRunLoops) {
        
        // __CFRunLoops集合没有值，解锁，往集合中添加值
        __CFUnlock(&loopsLock);
        
        // 初始化__CFRunLoops字典对象
	CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorSystemDefault, 0, NULL, &kCFTypeDictionaryValueCallBacks);
        
        // 创建一个主线程的runloop：mainLoop
	CFRunLoopRef mainLoop = __CFRunLoopCreate(pthread_main_thread_np());
        
        // 设置CFMutableDictionaryRef字典的值，主线程作为key，根据主线程创建出来的mainLoop作为value
	CFDictionarySetValue(dict, pthreadPointer(pthread_main_thread_np()), mainLoop);
        
	if (!OSAtomicCompareAndSwapPtrBarrier(NULL, dict, (void * volatile *)&__CFRunLoops)) {
	    CFRelease(dict);
	}
        
    // 释放mainLoop
	CFRelease(mainLoop);
        __CFLock(&loopsLock);
    }
    
    // 根据参数线程`t`作为key，去CFMutableDictionaryRef字典中查找对应的runloop对象
    CFRunLoopRef loop = (CFRunLoopRef)CFDictionaryGetValue(__CFRunLoops, pthreadPointer(t));
    
    __CFUnlock(&loopsLock);
    
    if (!loop) {
        
        // 没有找到对应的runloop，根据传递进来的线程`t`，创建一个新的runloop对象
	CFRunLoopRef newLoop = __CFRunLoopCreate(t);
        
        // 加锁操作
        __CFLock(&loopsLock);
        
        // 再次根据参数线程`t`去全局字典中获取对应的runloop对象
	loop = (CFRunLoopRef)CFDictionaryGetValue(__CFRunLoops, pthreadPointer(t));
        
	if (!loop) {
        // 还是没有找到对应的runloop
        // 就将刚刚新建的newLoop作为value，参数线程`t`作为key，添加到全局字典中
	    CFDictionarySetValue(__CFRunLoops, pthreadPointer(t), newLoop);
        
	    loop = newLoop;
	}
        
        // don't release run loops inside the loopsLock, because CFRunLoopDeallocate may end up taking it
        __CFUnlock(&loopsLock);
        
	CFRelease(newLoop);
    }
    
    // 判断传递过来的线程是否为当前线程(pthread_self())
    if (pthread_equal(t, pthread_self())) {
        _CFSetTSD(__CFTSDKeyRunLoop, (void *)loop, NULL);
        if (0 == _CFGetTSD(__CFTSDKeyRunLoopCntr)) {
            _CFSetTSD(__CFTSDKeyRunLoopCntr, (void *)(PTHREAD_DESTRUCTOR_ITERATIONS-1), (void (*)(void *))__CFFinalizeRunLoop);
        }
    }
    
    // 返回runloop
    return loop;
}
```

通过上面函数`_CFRunLoopGet0`中的底层源码实现，我们可以知道runloop和线程的关系，得出如下结论：

* 每一个runloop对象中必定有一个与之对应的线程，因为程序中的所有runloop对象都保存在`CFMutableDictionaryRef`这个全局的字典集合中，并且是以线程作为`key`，runloop对象作为`value`存储在这个全局的集合中
* 手动新创建的子线程，默认是没有runloop的，从上面的底层源码可以知道，runloop是在调用`CFRunLoopRef`API获取runloop对象的时候创建的，通过判断使用线程作为key在全局字典中取出对应的runloop，如果没有取到对应的runloop就用传递的线程新创建一个runloop

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-160055@2x.png)

---

接下来我们再来看看runloop的底层数据结构，源码查找路径：`CF框架 -> CFRunLoop.c  -> struct __CFRunLoop`

`__CFRunLoop`结构体：

```
typedef struct __CFRunLoopMode *CFRunLoopModeRef;

struct __CFRunLoop {
    CFRuntimeBase _base;
    pthread_mutex_t _lock;			/* locked for accessing mode list */
    __CFPort _wakeUpPort;			// used for CFRunLoopWakeUp 
    Boolean _unused;
    volatile _per_run_data *_perRunData;              // reset for runs of the run loop
    uint32_t _winthread;
    
    pthread_t _pthread; // 与之对应的线程
    
    // commonMode集合，存储在_commonModes中的模式，都可以运行在kCFRunLoopCommonModes这种模式下
    CFMutableSetRef _commonModes;
    
    // 所有在commonModes这个模式下工作的`timer\source\observer等`都放到`_commonModeItems`集合中
    CFMutableSetRef _commonModeItems;
    
    CFRunLoopModeRef _currentMode; // runloop当前正在运行的Mode
    CFMutableSetRef _modes; // modes集合中存放的都是CFRunLoopModeRef对象
    
    struct _block_item *_blocks_head;
    struct _block_item *_blocks_tail;
    CFAbsoluteTime _runTime;
    CFAbsoluteTime _sleepTime;
    CFTypeRef _counterpart;
};
```

在`__CFRunLoop`结构体中有一个`CFMutableSetRef _modes`成员，`modes`集合中又包含了多个`CFRunLoopModeRef`对象

`__CFRunLoopMode`结构体：

```
typedef struct __CFRunLoopMode *CFRunLoopModeRef;

struct __CFRunLoopMode {
    CFRuntimeBase _base;
    pthread_mutex_t _lock;	/* must have the run loop locked before locking this */
    
    Boolean _stopped;
    char _padding[3];
    
    CFStringRef _name; // Mode的名称
    
    CFMutableSetRef _sources0; // _sources0集合中存放的都是CFRunLoopSourceRef
    CFMutableSetRef _sources1; // _sources1集合中存放的都是CFRunLoopSourceRef
    CFMutableArrayRef _observers; // _observers集合中存放的都是CFRunLoopObserverRef
    CFMutableArrayRef _timers; // _observers集合中存放的都是CFRunLoopTimerRef
    
    CFMutableDictionaryRef _portToV1SourceMap;
    __CFPortSet _portSet;
    CFIndex _observerMask;
#if USE_DISPATCH_SOURCE_FOR_TIMERS
    dispatch_source_t _timerSource;
    dispatch_queue_t _queue;
    Boolean _timerFired; // set to true by the source when a timer has fired
    Boolean _dispatchTimerArmed;
#endif
#if USE_MK_TIMER_TOO
    mach_port_t _timerPort;
    Boolean _mkTimerArmed;
#endif
#if DEPLOYMENT_TARGET_WINDOWS
    DWORD _msgQMask;
    void (*_msgPump)(void);
#endif
    uint64_t _timerSoftDeadline; /* TSR */
    uint64_t _timerHardDeadline; /* TSR */
};
```

在`__CFRunLoopMode`中又包含有`_sources0`、`_sources1`、`_observers`、`_timers`这四个集合对象

`__CFRunLoopSource`结构体 

```
typedef struct __CFRunLoopSource * CFRunLoopSourceRef;

struct __CFRunLoopSource {
    CFRuntimeBase _base;
    uint32_t _bits;
    pthread_mutex_t _lock;
    CFIndex _order;			/* immutable */
    
    CFMutableBagRef _runLoops;
    
    union {
	CFRunLoopSourceContext version0;	/* immutable, except invalidation */
        CFRunLoopSourceContext1 version1;	/* immutable, except invalidation */
    } _context;
};
```

`__CFRunLoopObserver`结构体 

```
typedef struct __CFRunLoopObserver * CFRunLoopObserverRef;

struct __CFRunLoopObserver {
    CFRuntimeBase _base;
    pthread_mutex_t _lock;
    
    // runloop
    CFRunLoopRef _runLoop;
    
    CFIndex _rlCount;
    CFOptionFlags _activities;		/* immutable */
    CFIndex _order;			/* immutable */
    CFRunLoopObserverCallBack _callout;	/* immutable */
    CFRunLoopObserverContext _context;	/* immutable, except invalidation */
};
```

`__CFRunLoopTimer`结构体 

```
typedef struct __CFRunLoopTimer * CFRunLoopTimerRef;

struct __CFRunLoopTimer {
    CFRuntimeBase _base;
    uint16_t _bits;
    pthread_mutex_t _lock;
    
    // runloop
    CFRunLoopRef _runLoop;
    
    CFMutableSetRef _rlModes;
    CFAbsoluteTime _nextFireDate;
    CFTimeInterval _interval;		/* immutable */
    CFTimeInterval _tolerance;          /* mutable */
    uint64_t _fireTSR;			/* TSR units */
    CFIndex _order;			/* immutable */
    CFRunLoopTimerCallBack _callout;	/* immutable */
    CFRunLoopTimerContext _context;	/* immutable, except invalidation */
};
```

上面的这些runloop相关的类的对应关系如图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-163618@2x.png)

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-164742@2x.png)

runloop的运行模式，最常用的就两种模式：

* kCFRunLoopDefaultMode
* UITrackingRunLoopMode

我们在平时的开发过程中也有使用过`kCFRunLoopCommonModes`这种模式，但是需要注意：

> **kCFRunLoopCommonModes**并不是真正意义是上的mode，它只是一个标记符，也就是说`kCFRunLoopDefaultMode`和`UITrackingRunLoopMode`这两种mode都被标记为`common`，存储在`CFMutableSetRef _commonModes`集合中，当我们设置runloop的模式为`kCFRunLoopCommonModes`时，系统就会在`_commonModes`这个集合中查找所有可以运行的模式来使用

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-164837@2x.png)

我们从上面的`CFRunLoopModeRef`结构体成员中知道，runloop的modes集合中含有`_sources0`、`_sources1`、`_observers`、`_timers`这四个，那么这些`_sources0`、`_sources1`、`_observers`、`_timers`到底有什么作用？

> runloop在运行循环中不停的处理的任务就是这些`_sources0`、`_sources1`、`_observers`、`_timers`

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-170415@2x.png)

runloop中循环处理`_observers`，也可以理解为runloop在运行循环中一直监听着`_observers`的以下这几种状态的变化

```
/* Run Loop Observer Activities */
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {

    kCFRunLoopEntry = (1UL << 0), 		   // 准备进入runloop
    kCFRunLoopBeforeTimers = (1UL << 1),   // 即将处理Timer事件
    kCFRunLoopBeforeSources = (1UL << 2),  // 即将处理Sources事件
    kCFRunLoopBeforeWaiting = (1UL << 5),  // 准备进入休眠状态
    kCFRunLoopAfterWaiting = (1UL << 6),   // 即将从休眠状态唤醒
    kCFRunLoopExit = (1UL << 7),			   // 退出runloop状态
    kCFRunLoopAllActivities = 0x0FFFFFFFU  // 所有的状态
};
```

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-171509@2x.png)

下面我们通过代码来验证下在runloop中手动添加`observer`，来观察`observer`的状态变化，代码如下：

```
	// 创建一个Observe
    CFRunLoopObserverRef observer = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopAllActivities, YES, 0, observerHandler, NULL);
    
    // 创建一个runloop
    CFRunLoopRef loop = CFRunLoopGetMain();
    
    // 将observere添加到runloop
    CFRunLoopAddObserver(loop, observer, kCFRunLoopDefaultMode);
    
    // 释放observer
    CFRelease(observer);
```

`observerHandler`监听函数

```
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
```

我们通过打印可以看出，runloop确实是在各种`observer`的状态间不停的切换

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-182139@2x.png)

接下来我们再通过滚动列表示例，验证runloop的mode的切换过程，代码如下：

```
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
```

我们通过打印可以看到，当我们拖动列表时，runloop的`mode`从`kCFRunLoopDefaultMode`切换至`UITrackingRunLoopMode`

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-182701@2x.png)

当我们停止列表拖动后，runloop的`mode`又从`UITrackingRunLoopMode`切换至`kCFRunLoopDefaultMode`

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-182736@2x.png)

---

接下来我们通过底层源码来研究runloop的整个循环执行过程，底层源码查找路径：`CF框架 -> CFRunLoop.c文件 -> CFRunLoopRunSpecific -> __CFRunLoopRun`，底层核心源码如下：

`CFRunLoopRunSpecific`函数核心代码

```
SInt32 CFRunLoopRunSpecific(CFRunLoopRef rl, CFStringRef modeName, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {     /* DOES CALLOUT */
    
    CHECK_FOR_FORK();
        
    __CFRunLoopLock(rl);
    
    // 获取当前的Mode
    CFRunLoopModeRef currentMode = __CFRunLoopFindMode(rl, modeName, false);
    
    if (NULL == currentMode || __CFRunLoopModeIsEmpty(rl, currentMode, rl->_currentMode)) {
        Boolean did = false;
        if (currentMode) __CFRunLoopModeUnlock(currentMode);
        __CFRunLoopUnlock(rl);
        return did ? kCFRunLoopRunHandledSource : kCFRunLoopRunFinished;
    }
    
    volatile _per_run_data *previousPerRun = __CFRunLoopPushPerRunData(rl);
    
    CFRunLoopModeRef previousMode = rl->_currentMode;
    rl->_currentMode = currentMode;
    int32_t result = kCFRunLoopRunFinished;

    // 判断是否进入runloop
	if (currentMode->_observerMask & kCFRunLoopEntry)
	
        // 通知observer，进入runloop
        __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopEntry);
    
        // __CFRunLoopRun：此函数中真正的开始处理runnloop中的任务
        result = __CFRunLoopRun(rl, currentMode, seconds, returnAfterSourceHandled, previousMode);
    
    
    // 判断是否退出runloop
	if (currentMode->_observerMask & kCFRunLoopExit )
	
        // 通知observer，退出runloop
        __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopExit);

        __CFRunLoopModeUnlock(currentMode);
        __CFRunLoopPopPerRunData(rl, previousPerRun);
        rl->_currentMode = previousMode;
        __CFRunLoopUnlock(rl);
    
    return result;
}
```

`__CFRunLoopRun`函数核心代码，此函数内代码经过了优化删除，只保留了核心流程的关键代码

```
static int32_t __CFRunLoopRun(CFRunLoopRef rl, CFRunLoopModeRef rlm, CFTimeInterval seconds, Boolean stopAfterHandle, CFRunLoopModeRef previousMode) {
    
    int32_t retVal = 0;
    
    // 此do-while循环就是runloop能够保证程序一直运行而不退出的的核心
    do {
        
        if (rlm->_observerMask & kCFRunLoopBeforeTimers) {
            // 通知observer，处理timers
            __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeTimers);
        }
            
        if (rlm->_observerMask & kCFRunLoopBeforeSources) {
            // 通知observer，处理Sources
            __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeSources);

            // 处理blocks
            __CFRunLoopDoBlocks(rl, rlm);
                        
            // 处理sources0
            __CFRunLoopDoSources0(rl, rlm, stopAfterHandle);
            
            Boolean sourceHandledThisLoop = __CFRunLoopDoSources0(rl, rlm, stopAfterHandle);
            if (sourceHandledThisLoop) {
                // 处理blocks
                __CFRunLoopDoBlocks(rl, rlm);
            }
            
            // 判断是否有source1
            if (__CFRunLoopServiceMachPort(dispatchPort, &msg, sizeof(msg_buffer), &livePort, 0, &voucherState, NULL)) {
                // 如果有source1，则跳转到`handle_msg`标记处，执行标记后的代码
                goto handle_msg;
            }
        }
            
        if (!poll && (rlm->_observerMask & kCFRunLoopBeforeWaiting)) {
            // 通知observer，即将进入休眠
            __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeWaiting);
            
            // 设置runloop开始休眠
            __CFRunLoopSetSleeping(rl);
        
            // runloop在此处就开始处于休眠状态，等待消息来唤醒runloop，使用内核机制来进行线程阻塞，而不是死循环
            __CFRunLoopServiceMachPort(waitSet, &msg, sizeof(msg_buffer), &livePort, poll ? 0 : TIMEOUT_INFINITY, &voucherState, &voucherCopy);

            // runloop 取消休眠设置
            // user callouts now OK again
            __CFRunLoopUnsetSleeping(rl);
            
           // 通知observer，即将唤醒runloop
           __CFRunLoopDoObservers(rl, rlm, kCFRunLoopAfterWaiting);
        }
            
    // `handle_msg`标记
    handle_msg:;
        
        if (!__CFRunLoopDoTimers(rl, rlm, mach_absolute_time())) {
            // 1、runloop被timer唤醒
            CFRUNLOOP_WAKEUP_FOR_TIMER();
            
            // 处理timers
            __CFRunLoopDoTimers(rl, rlm, mach_absolute_time())
        } else if (livePort == dispatchPort) {
            // 2、runloop被dispatch唤醒
            CFRUNLOOP_WAKEUP_FOR_DISPATCH();
            
            // 处理gcd相关事情
            __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__(msg);
        } else {
            // 3、runloop被source唤醒
            CFRUNLOOP_WAKEUP_FOR_SOURCE();
            
            // 处理source1
            __CFRunLoopDoSource1(rl, rlm, rls, msg, msg->msgh_size, &reply) || sourceHandledThisLoop;
        }

        // 处理blocks
        __CFRunLoopDoBlocks(rl, rlm);
        
        // 判断retVal的值
        if (sourceHandledThisLoop && stopAfterHandle) {
            retVal = kCFRunLoopRunHandledSource;
            } else if (timeout_context->termTSR < mach_absolute_time()) {
                retVal = kCFRunLoopRunTimedOut;
        } else if (__CFRunLoopIsStopped(rl)) {
                __CFRunLoopUnsetStopped(rl);
            retVal = kCFRunLoopRunStopped;
        } else if (rlm->_stopped) {
            rlm->_stopped = false;
            retVal = kCFRunLoopRunStopped;
        } else if (__CFRunLoopModeIsEmpty(rl, rlm, previousMode)) {
            retVal = kCFRunLoopRunFinished;
        }

    } while (0 == retVal);

    return retVal;
}
```

我们在对上面的核心流程进行一个简要的梳理总结：

* 通知observer，进入runloop
* 执行`__CFRunLoopRun`函数
	1. 通知observer，处理timers
	2. 通知observer，处理sources
	3. 处理blocks
	4. 处理sources0
	5. 如果`sourceHandledThisLoop`条件满足，处理blocks
	6. 判断是否有sources1，有则跳转到`handle_msg`
	7. 通知observer，runloop即将进入休眠
	8. 通知observer，runloop即将结束休眠
		* 如果runloop被timer唤醒，处理timers
		* 如果runloop被dispatch唤醒，处理gcd(dispatch_async(dispatch_get_main_queue(), ^{})
		* 如果runloop被source唤醒，处理source1
	9. 处理blocks
	10. 判断retVal的值，决定是跳到循环第一步还是退出runloop
* 通知observer，退出runloop

上面runloop的循环执行流程图如下图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200209-233256@2x.png)


讲解示例Demo地址：[https://github.com/guangqiang-liu/08-Runloop]()


## 更多文章
* ReactNative开源项目OneM(1200+star)：**[https://github.com/guangqiang-liu/OneM](https://github.com/guangqiang-liu/OneM)**：欢迎小伙伴们 **star**
* iOS组件化开发实战项目(500+star)：**[https://github.com/guangqiang-liu/iOS-Component-Pro]()**：欢迎小伙伴们 **star**
* 简书主页：包含多篇iOS和RN开发相关的技术文章[http://www.jianshu.com/u/023338566ca5](http://www.jianshu.com/u/023338566ca5) 欢迎小伙伴们：**多多关注，点赞**
* ReactNative QQ技术交流群(2000人)：**620792950** 欢迎小伙伴进群交流学习
* iOS QQ技术交流群：**678441305** 欢迎小伙伴进群交流学习