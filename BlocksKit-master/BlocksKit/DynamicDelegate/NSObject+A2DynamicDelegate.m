//
//  NSObject+A2DynamicDelegate.m
//  BlocksKit
//

#import "NSObject+A2DynamicDelegate.h"
@import ObjectiveC.runtime;
#import "A2DynamicDelegate.h"

extern Protocol *a2_dataSourceProtocol(Class cls);
extern Protocol *a2_delegateProtocol(Class cls);

// 返回动态代理对象的类，添加前缀 A2Dynamic
static Class a2_dynamicDelegateClass(Class cls, NSString *suffix)
{
	while (cls) {
		NSString *className = [NSString stringWithFormat:@"A2Dynamic%@%@", NSStringFromClass(cls), suffix];
		Class ddClass = NSClassFromString(className);
		if (ddClass) return ddClass;

		cls = class_getSuperclass(cls);
	}

	return [A2DynamicDelegate class];
}

// 后台线程
static dispatch_queue_t a2_backgroundQueue(void)
{
	static dispatch_once_t onceToken;
	static dispatch_queue_t backgroundQueue = nil;
	dispatch_once(&onceToken, ^{
		backgroundQueue = dispatch_queue_create("BlocksKit.DynamicDelegate.Queue", DISPATCH_QUEUE_SERIAL);
	});
	return backgroundQueue;
}

@implementation NSObject (A2DynamicDelegate)

// 获取 DataSource 的动态代理对象
- (id)bk_dynamicDataSource
{
    // 获取 xxxDataSource 协议，xxx为类名
	Protocol *protocol = a2_dataSourceProtocol([self class]);
    // 获取动态代理类，A2DynamicXxx  Xxx为类名
	Class class = a2_dynamicDelegateClass([self class], @"DataSource");
	return [self bk_dynamicDelegateWithClass:class forProtocol:protocol];
}

// 获取 Delegate 的动态代理对象
- (id)bk_dynamicDelegate
{
	Protocol *protocol = a2_delegateProtocol([self class]);
	Class class = a2_dynamicDelegateClass([self class], @"Delegate");
	return [self bk_dynamicDelegateWithClass:class forProtocol:protocol];
}

// 获取指定协议的动态代理对象
- (id)bk_dynamicDelegateForProtocol:(Protocol *)protocol
{
	Class class = [A2DynamicDelegate class];
	NSString *protocolName = NSStringFromProtocol(protocol);
	if ([protocolName hasSuffix:@"Delegate"]) {
		class = a2_dynamicDelegateClass([self class], @"Delegate");
	} else if ([protocolName hasSuffix:@"DataSource"]) {
		class = a2_dynamicDelegateClass([self class], @"DataSource");
	}

	return [self bk_dynamicDelegateWithClass:class forProtocol:protocol];
}

// 返回动态代理对象
// 动态代理对设置在关联对象上
- (id)bk_dynamicDelegateWithClass:(Class)cls forProtocol:(Protocol *)protocol
{
	/**
	 * Storing the dynamic delegate as an associated object of the delegating
	 * object not only allows us to later retrieve the delegate, but it also
	 * creates a strong relationship to the delegate. Since delegates are weak
	 * references on the part of the delegating object, a dynamic delegate
	 * would be deallocated immediately after its declaring scope ends.
	 * Therefore, this strong relationship is required to ensure that the
	 * delegate's lifetime is at least as long as that of the delegating object.
	 **/

	__block A2DynamicDelegate *dynamicDelegate;

	dispatch_sync(a2_backgroundQueue(), ^{
		dynamicDelegate = objc_getAssociatedObject(self, (__bridge const void *)protocol);

		if (!dynamicDelegate)
		{
			dynamicDelegate = [[cls alloc] initWithProtocol:protocol];
			objc_setAssociatedObject(self, (__bridge const void *)protocol, dynamicDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
	});

	return dynamicDelegate;
}

@end
