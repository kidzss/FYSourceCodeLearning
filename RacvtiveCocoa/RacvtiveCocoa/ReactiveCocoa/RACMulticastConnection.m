//
//  RACMulticastConnection.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 4/11/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACMulticastConnection.h"
#import "RACMulticastConnection+Private.h"
#import "RACDisposable.h"
#import "RACSerialDisposable.h"
#import "RACSubject.h"
#import <libkern/OSAtomic.h>

@interface RACMulticastConnection () {
	RACSubject *_signal;

	// When connecting, a caller should attempt to atomically swap the value of this
	// from `0` to `1`.
	//
	// If the swap is successful the caller is resposible for subscribing `_signal`
	// to `sourceSignal` and storing the returned disposable in `serialDisposable`.
	//
	// If the swap is unsuccessful it means that `_sourceSignal` has already been
	// connected and the caller has no action to take.
	int32_t volatile _hasConnected;
}

@property (nonatomic, readonly, strong) RACSignal *sourceSignal;
@property (strong) RACSerialDisposable *serialDisposable;
@end

@implementation RACMulticastConnection

#pragma mark Lifecycle

// 不应该直接使用 -initWithSourceSignal:subject: 来初始化一个对象，我们应该通过 RACSignal 的实例方法初始化 RACMulticastConnection 实例

// 传入源 signal
// subject 用于广播的信号
- (id)initWithSourceSignal:(RACSignal *)source subject:(RACSubject *)subject {
	NSCParameterAssert(source != nil);
	NSCParameterAssert(subject != nil);

	self = [super init];
	if (self == nil) return nil;

	_sourceSignal = source;
	_serialDisposable = [[RACSerialDisposable alloc] init];
	_signal = subject;
	
	return self;
}

#pragma mark Connecting

// 只有在调用 -connect 方法之后，RACSubject 才会订阅源信号 sourceSignal
// -connect 方法通过 -subscribe: 实际上建立了 RACSignal 和 RACSubject 之间的连接，这种方式保证了 RACSignal 中的 didSubscribe 代码块只执行了一次。
// 所有的订阅者不再订阅原信号，而是订阅 RACMulticastConnection 持有的热信号 RACSubject，实现对冷信号的一对多传播。
- (RACDisposable *)connect {
	BOOL shouldConnect = OSAtomicCompareAndSwap32Barrier(0, 1, &_hasConnected);

    // 订阅源信号，这时源信号的 didSubscribe 代码块才会执行
	if (shouldConnect) {
		self.serialDisposable.disposable = [self.sourceSignal subscribe:_signal];
	}

	return self.serialDisposable;
}


// 保证了在 -autoconnect 方法返回的对象被第一次订阅时，就会建立源信号与热信号之间的连接
- (RACSignal *)autoconnect {
	__block volatile int32_t subscriberCount = 0;

	return [[RACSignal
		createSignal:^(id<RACSubscriber> subscriber) {
			OSAtomicIncrement32Barrier(&subscriberCount);

			RACDisposable *subscriptionDisposable = [self.signal subscribe:subscriber];
			RACDisposable *connectionDisposable = [self connect];

			return [RACDisposable disposableWithBlock:^{
				[subscriptionDisposable dispose];

				if (OSAtomicDecrement32Barrier(&subscriberCount) == 0) {
					[connectionDisposable dispose];
				}
			}];
		}]
		setNameWithFormat:@"[%@] -autoconnect", self.signal.name];
}

@end
