//
//  RACReturnSignal.h
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2013-10-10.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACSignal.h"

// 私有的 signal
// 类似包装一下 NSObject 对象（用其属性 value 来保存值）
// A private `RACSignal` subclasses that synchronously sends a value to any
// subscribers, then completes.
@interface RACReturnSignal : RACSignal

+ (RACSignal *)return:(id)value;

@end
