//
//  RACCommand.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/3/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACCommand.h"
#import "EXTScope.h"
#import "NSArray+RACSequenceAdditions.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"
#import "NSObject+RACPropertySubscribing.h"
#import "RACMulticastConnection.h"
#import "RACReplaySubject.h"
#import "RACScheduler.h"
#import "RACSequence.h"
#import "RACSignal+Operations.h"
#import <libkern/OSAtomic.h>

NSString * const RACCommandErrorDomain = @"RACCommandErrorDomain";
NSString * const RACUnderlyingCommandErrorKey = @"RACUnderlyingCommandErrorKey";

const NSInteger RACCommandErrorNotEnabled = 1;

@interface RACCommand () {
	// The mutable array backing `activeExecutionSignals`.
	//
	// This should only be used while synchronized on `self`.
	NSMutableArray *_activeExecutionSignals;

	// Atomic backing variable for `allowsConcurrentExecution`.
	volatile uint32_t _allowsConcurrentExecution;
}

// An array of signals representing in-flight executions, in the order they
// began.
//
// This property is KVO-compliant.
@property (atomic, copy, readonly) NSArray *activeExecutionSignals;

// `enabled`, but without a hop to the main thread.
//
// Values from this signal may arrive on any thread.
@property (nonatomic, strong, readonly) RACSignal *immediateEnabled;

// The signal block that the receiver was initialized with.
@property (nonatomic, copy, readonly) RACSignal * (^signalBlock)(id input);

// Adds a signal to `activeExecutionSignals` and generates a KVO notification.
- (void)addActiveExecutionSignal:(RACSignal *)signal;

// Removes a signal from `activeExecutionSignals` and generates a KVO
// notification.
- (void)removeActiveExecutionSignal:(RACSignal *)signal;

@end

@implementation RACCommand

#pragma mark Properties

- (BOOL)allowsConcurrentExecution {
	return _allowsConcurrentExecution != 0;
}

- (void)setAllowsConcurrentExecution:(BOOL)allowed {
	[self willChangeValueForKey:@keypath(self.allowsConcurrentExecution)];

	if (allowed) {
		OSAtomicOr32Barrier(1, &_allowsConcurrentExecution);
	} else {
		OSAtomicAnd32Barrier(0, &_allowsConcurrentExecution);
	}

	[self didChangeValueForKey:@keypath(self.allowsConcurrentExecution)];
}

- (NSArray *)activeExecutionSignals {
	@synchronized (self) {
		return [_activeExecutionSignals copy];
	}
}

// 添加一个 signal
- (void)addActiveExecutionSignal:(RACSignal *)signal {
	NSCParameterAssert([signal isKindOfClass:RACSignal.class]);

	@synchronized (self) {
		// The KVO notification has to be generated while synchronized, because
		// it depends on the index remaining consistent.
		NSIndexSet *indexes = [NSIndexSet indexSetWithIndex:_activeExecutionSignals.count];
		[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@keypath(self.activeExecutionSignals)];
		[_activeExecutionSignals addObject:signal];
		[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@keypath(self.activeExecutionSignals)];
	}
}

- (void)removeActiveExecutionSignal:(RACSignal *)signal {
	NSCParameterAssert([signal isKindOfClass:RACSignal.class]);

	@synchronized (self) {
		// The indexes have to be calculated and the notification generated
		// while synchronized, because they depend on the indexes remaining
		// consistent.
		NSIndexSet *indexes = [_activeExecutionSignals indexesOfObjectsPassingTest:^ BOOL (RACSignal *obj, NSUInteger index, BOOL *stop) {
			return obj == signal;
		}];

		if (indexes.count == 0) return;

		[self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indexes forKey:@keypath(self.activeExecutionSignals)];
		[_activeExecutionSignals removeObjectsAtIndexes:indexes];
		[self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indexes forKey:@keypath(self.activeExecutionSignals)];
	}
}

#pragma mark Lifecycle

- (id)init {
	NSCAssert(NO, @"Use -initWithSignalBlock: instead");
	return nil;
}

// 初始化传入一个 block
// input 是在调用 exeute: 方法时传入的对象
// RACCommand 将外部的变量 InputType 转换成了使用 RACSignal 包裹的 ValueType 对象

- (id)initWithSignalBlock:(RACSignal * (^)(id input))signalBlock {
	return [self initWithEnabled:nil signalBlock:signalBlock];
}

- (id)initWithEnabled:(RACSignal *)enabledSignal signalBlock:(RACSignal * (^)(id input))signalBlock {
	NSCParameterAssert(signalBlock != nil);

	self = [super init];
	if (self == nil) return nil;

    // 保存所有的信号
	_activeExecutionSignals = [[NSMutableArray alloc] init];
	_signalBlock = [signalBlock copy];

	// A signal of additions to `activeExecutionSignals`.
	RACSignal *newActiveExecutionSignals = [[[[[self
		rac_valuesAndChangesForKeyPath:@keypath(self.activeExecutionSignals) options:NSKeyValueObservingOptionNew observer:nil]
		reduceEach:^(id _, NSDictionary *change) {
			NSArray *signals = change[NSKeyValueChangeNewKey];
			if (signals == nil) return [RACSignal empty];

			return [signals.rac_sequence signalWithScheduler:RACScheduler.immediateScheduler];
		}]
		concat]
		publish]
		autoconnect];

    
	_executionSignals = [[[newActiveExecutionSignals
		map:^(RACSignal *signal) {
			return [signal catchTo:[RACSignal empty]];
		}]
		deliverOn:RACScheduler.mainThreadScheduler]
		setNameWithFormat:@"%@ -executionSignals", self];
	
	// `errors` needs to be multicasted so that it picks up all
	// `activeExecutionSignals` that are added.
	//
	// In other words, if someone subscribes to `errors` _after_ an execution
	// has started, it should still receive any error from that execution.
	RACMulticastConnection *errorsConnection = [[[newActiveExecutionSignals
		flattenMap:^(RACSignal *signal) {
			return [[signal
				ignoreValues]
				catch:^(NSError *error) {
					return [RACSignal return:error];
				}];
		}]
		deliverOn:RACScheduler.mainThreadScheduler]
		publish];
	
	_errors = [errorsConnection.signal setNameWithFormat:@"%@ -errors", self];
	[errorsConnection connect];

	RACSignal *immediateExecuting = [RACObserve(self, activeExecutionSignals) map:^(NSArray *activeSignals) {
		return @(activeSignals.count > 0);
	}];

	_executing = [[[[[immediateExecuting
		deliverOn:RACScheduler.mainThreadScheduler]
		// This is useful before the first value arrives on the main thread.
		startWith:@NO]
		distinctUntilChanged]
		replayLast]
		setNameWithFormat:@"%@ -executing", self];

	RACSignal *moreExecutionsAllowed = [RACSignal
		if:RACObserve(self, allowsConcurrentExecution)
		then:[RACSignal return:@YES]
		else:[immediateExecuting not]];
	
	if (enabledSignal == nil) {
		enabledSignal = [RACSignal return:@YES];
	} else {
		enabledSignal = [[[enabledSignal
			startWith:@YES]
			takeUntil:self.rac_willDeallocSignal]
			replayLast];
	}
	
	_immediateEnabled = [[RACSignal
		combineLatest:@[ enabledSignal, moreExecutionsAllowed ]]
		and];
	
	_enabled = [[[[[self.immediateEnabled
		take:1]
		concat:[[self.immediateEnabled skip:1] deliverOn:RACScheduler.mainThreadScheduler]]
		distinctUntilChanged]
		replayLast]
		setNameWithFormat:@"%@ -enabled", self];

	return self;
}

#pragma mark Execution

// 每次执行都会创建一个新的 signal
- (RACSignal *)execute:(id)input {
	// `immediateEnabled` is guaranteed to send a value upon subscription, so
	// -first is acceptable here.
    
    // 连续几次执行 -execute: 方法不能成功的原因：每次执行这个方法时，都会从另一个信号 immediateEnabled 中读取是否能执行当前命令的 BOOL 值，如果不可以执行的话，就直接返回 RACErrorSignal。
    
	BOOL enabled = [[self.immediateEnabled first] boolValue];
	if (!enabled) {
		NSError *error = [NSError errorWithDomain:RACCommandErrorDomain code:RACCommandErrorNotEnabled userInfo:@{
			NSLocalizedDescriptionKey: NSLocalizedString(@"The command is disabled and cannot be executed", nil),
			RACUnderlyingCommandErrorKey: self
		}];

		return [RACSignal error:error];
	}

    // 将 input 传入 block，返回一个 signal
	RACSignal *signal = self.signalBlock(input);
	NSCAssert(signal != nil, @"nil signal returned from signal block for value: %@", input);

	// We subscribe to the signal on the main thread so that it occurs _after_
	// -addActiveExecutionSignal: completes below.
	//
	// This means that `executing` and `enabled` will send updated values before
	// the signal actually starts performing work.
    
    // 将当前信号包装成一个 RACMulticastConnection
	RACMulticastConnection *connection = [[signal
		subscribeOn:RACScheduler.mainThreadScheduler]
		multicast:[RACReplaySubject subject]];
	
	@weakify(self);

	[self addActiveExecutionSignal:connection.signal];
	[connection.signal subscribeError:^(NSError *error) {
		@strongify(self);
		[self removeActiveExecutionSignal:connection.signal];
	} completed:^{
		@strongify(self);
		[self removeActiveExecutionSignal:connection.signal];
	}];

	[connection connect];
	return [connection.signal setNameWithFormat:@"%@ -execute: %@", self, [input rac_description]];
}

#pragma mark NSKeyValueObserving

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
	// Generate all KVO notifications manually to avoid the performance impact
	// of unnecessary swizzling.
	return NO;
}

@end
