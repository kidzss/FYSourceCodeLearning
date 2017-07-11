//
//  RACBehaviorSubject.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/16/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACBehaviorSubject.h"
#import "RACDisposable.h"
#import "RACScheduler+Private.h"

@interface RACBehaviorSubject ()

// 内部会保存一个 currentValue 对象，也就是最后一次发送的消息
// This property should only be used while synchronized on self.
@property (nonatomic, strong) id currentValue;

@end

@implementation RACBehaviorSubject

#pragma mark Lifecycle


+ (instancetype)behaviorSubjectWithDefaultValue:(id)value {
	RACBehaviorSubject *subject = [self subject];
	subject.currentValue = value;
	return subject;
}

#pragma mark RACSignal

// 订阅后，发送最新的一个消息
// 通过 RACScheduler 调度之前的消息
- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	RACDisposable *subscriptionDisposable = [super subscribe:subscriber];

	RACDisposable *schedulingDisposable = [RACScheduler.subscriptionScheduler schedule:^{
		@synchronized (self) {
			[subscriber sendNext:self.currentValue];
		}
	}];
	
	return [RACDisposable disposableWithBlock:^{
		[subscriptionDisposable dispose];
		[schedulingDisposable dispose];
	}];
}

#pragma mark RACSubscriber

// 更新最近的一个消息
- (void)sendNext:(id)value {
	@synchronized (self) {
		self.currentValue = value;
		[super sendNext:value];
	}
}

@end
