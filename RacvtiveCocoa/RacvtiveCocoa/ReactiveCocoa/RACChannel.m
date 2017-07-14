//
//  RACChannel.m
//  ReactiveCocoa
//
//  Created by Uri Baghin on 01/01/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACChannel.h"
#import "RACDisposable.h"
#import "RACReplaySubject.h"
#import "RACSignal+Operations.h"

@interface RACChannelTerminal ()

// The values for this terminal.
@property (nonatomic, strong, readonly) RACSignal *values;

// A subscriber will will send values to the other terminal.
@property (nonatomic, strong, readonly) id<RACSubscriber> otherTerminal;

- (id)initWithValues:(RACSignal *)values otherTerminal:(id<RACSubscriber>)otherTerminal;

@end


// RACChannel 中包装的其实是两个 RACSubject 热信号
// 它们既可以作为订阅者，也可以接收其他对象发送的消息

@implementation RACChannel

- (id)init {
	self = [super init];
	if (self == nil) return nil;

	// We don't want any starting value from the leadingSubject, but we do want
	// error and completion to be replayed.
	RACReplaySubject *leadingSubject = [[RACReplaySubject replaySubjectWithCapacity:0] setNameWithFormat:@"leadingSubject"];
	RACReplaySubject *followingSubject = [[RACReplaySubject replaySubjectWithCapacity:1] setNameWithFormat:@"followingSubject"];

	// Propagate errors and completion to everything.
    // 不希望有任何初始化，只需要 error 和 completed 信息可以被重播
    // 通过 -ignoreValues 和 -subscribe: 方法，leadingSubject 和 followingSubject 两个热信号中产生的错误会互相发送，这是为了防止连接的两端一边发生了错误，另一边还继续工作的情况的出现。
	[[leadingSubject ignoreValues] subscribe:followingSubject];
	[[followingSubject ignoreValues] subscribe:leadingSubject];

	_leadingTerminal = [[[RACChannelTerminal alloc] initWithValues:leadingSubject otherTerminal:followingSubject] setNameWithFormat:@"leadingTerminal"];
	_followingTerminal = [[[RACChannelTerminal alloc] initWithValues:followingSubject otherTerminal:leadingSubject] setNameWithFormat:@"followingTerminal"];

	return self;
}

@end

@implementation RACChannelTerminal

#pragma mark Lifecycle

// values 表示当前断点，otherTerminal 表示远程端点
- (id)initWithValues:(RACSignal *)values otherTerminal:(id<RACSubscriber>)otherTerminal {
	NSCParameterAssert(values != nil);
	NSCParameterAssert(otherTerminal != nil);

	self = [super init];
	if (self == nil) return nil;

	_values = values;
	_otherTerminal = otherTerminal;

	return self;
}

#pragma mark RACSignal

// 在订阅者调用 -subscribeNext: 等方法发起订阅时，实际上订阅的是当前端点；如果向当前端点发送消息，会被转发到远程端点上，而这也就是当前端点的订阅者不会接收到向当前端点发送消息的原因

- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	return [self.values subscribe:subscriber];
}

#pragma mark <RACSubscriber>

// 在订阅者调用 -subscribeNext: 等方法发起订阅时，实际上订阅的是当前端点；如果向当前端点发送消息，会被转发到远程端点上，而这也就是当前端点的订阅者不会接收到向当前端点发送消息的原因
- (void)sendNext:(id)value {
	[self.otherTerminal sendNext:value];
}

- (void)sendError:(NSError *)error {
	[self.otherTerminal sendError:error];
}

- (void)sendCompleted {
	[self.otherTerminal sendCompleted];
}

- (void)didSubscribeWithDisposable:(RACCompoundDisposable *)disposable {
	[self.otherTerminal didSubscribeWithDisposable:disposable];
}

@end
