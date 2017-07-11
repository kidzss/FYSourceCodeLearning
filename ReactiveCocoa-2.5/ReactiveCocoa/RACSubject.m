//
//  RACSubject.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/9/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSubject.h"
#import "EXTScope.h"
#import "RACCompoundDisposable.h"
#import "RACPassthroughSubscriber.h"

@interface RACSubject ()

// Contains all current subscribers to the receiver.
//
// This should only be used while synchronized on `self`.
@property (nonatomic, strong, readonly) NSMutableArray *subscribers;

// Contains all of the receiver's subscriptions to other signals.
@property (nonatomic, strong, readonly) RACCompoundDisposable *disposable;

// Enumerates over each of the receiver's `subscribers` and invokes `block` for
// each.
- (void)enumerateSubscribersUsingBlock:(void (^)(id<RACSubscriber> subscriber))block;

@end

@implementation RACSubject

#pragma mark Lifecycle

+ (instancetype)subject {
	return [[self alloc] init];
}

- (id)init {
	self = [super init];
	if (self == nil) return nil;

	_disposable = [RACCompoundDisposable compoundDisposable];
	_subscribers = [[NSMutableArray alloc] initWithCapacity:1];
	
	return self;
}

- (void)dealloc {
	[self.disposable dispose];
}

#pragma mark Subscription

// 重写订阅的方法
// 可变』的特性都来源于持有的订阅者数组 subscribers，在每次执行 subscribeNext:error:completed: 一类便利方法时，都会将传入的 id<RACSubscriber> 对象加入数组

- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	NSCParameterAssert(subscriber != nil);

    
    // 创建一个 RACDisposable 对象，在当前 subscriber 销毁时，将自身从数组中移除
	RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];
    
    // 初始化一个 RACPassthroughSubscriber 实例
	subscriber = [[RACPassthroughSubscriber alloc] initWithSubscriber:subscriber signal:self disposable:disposable];

    // 将 subscriber 加入 RACSubject 持有的数组中
	NSMutableArray *subscribers = self.subscribers;
	@synchronized (subscribers) {
		[subscribers addObject:subscriber];
	}
	
	return [RACDisposable disposableWithBlock:^{
		@synchronized (subscribers) {
			// Since newer subscribers are generally shorter-lived, search
			// starting from the end of the list.
			NSUInteger index = [subscribers indexOfObjectWithOptions:NSEnumerationReverse passingTest:^ BOOL (id<RACSubscriber> obj, NSUInteger index, BOOL *stop) {
				return obj == subscriber;
			}];

			if (index != NSNotFound) [subscribers removeObjectAtIndex:index];
		}
	}];
}

- (void)enumerateSubscribersUsingBlock:(void (^)(id<RACSubscriber> subscriber))block {
	NSArray *subscribers;
	@synchronized (self.subscribers) {
		subscribers = [self.subscribers copy];
	}

	for (id<RACSubscriber> subscriber in subscribers) {
		block(subscriber);
	}
}

#pragma mark RACSubscriber

- (void)sendNext:(id)value {
	[self enumerateSubscribersUsingBlock:^(id<RACSubscriber> subscriber) {
		[subscriber sendNext:value];
	}];
}

- (void)sendError:(NSError *)error {
	[self.disposable dispose];
	
	[self enumerateSubscribersUsingBlock:^(id<RACSubscriber> subscriber) {
		[subscriber sendError:error];
	}];
}

- (void)sendCompleted {
	[self.disposable dispose];
	
	[self enumerateSubscribersUsingBlock:^(id<RACSubscriber> subscriber) {
		[subscriber sendCompleted];
	}];
}

- (void)didSubscribeWithDisposable:(RACCompoundDisposable *)d {
	if (d.disposed) return;
	[self.disposable addDisposable:d];

	@weakify(self, d);
	[d addDisposable:[RACDisposable disposableWithBlock:^{
		@strongify(self, d);
		[self.disposable removeDisposable:d];
	}]];
}

@end
