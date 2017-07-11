//
//  NSObject+BKBlockObservation.m
//  BlocksKit
//

#import "NSObject+BKBlockObservation.h"
@import ObjectiveC.runtime;
@import ObjectiveC.message;
#import "NSArray+BlocksKit.h"
#import "NSDictionary+BlocksKit.h"
#import "NSSet+BlocksKit.h"
#import "NSObject+BKAssociatedObjects.h"

typedef NS_ENUM(int, BKObserverContext) {
	BKObserverContextKey,                 // 只观察一个 key
	BKObserverContextKeyWithChange,
	BKObserverContextManyKeys,            // 观察一些 key
	BKObserverContextManyKeysWithChange
};

// _BKObserver 作为观察者对象
@interface _BKObserver : NSObject {
	BOOL _isObserving;
}

// 被观察者
@property (nonatomic, readonly, unsafe_unretained) id observee;
// 要观察的 keypath 数组
@property (nonatomic, readonly) NSMutableArray *keyPaths;
// 要执行的 block
@property (nonatomic, readonly) id task;
@property (nonatomic, readonly) BKObserverContext context;

- (id)initWithObservee:(id)observee keyPaths:(NSArray *)keyPaths context:(BKObserverContext)context task:(id)task;

@end

static void *BKObserverBlocksKey = &BKObserverBlocksKey;
static void *BKBlockObservationContext = &BKBlockObservationContext;

@implementation _BKObserver

- (id)initWithObservee:(id)observee keyPaths:(NSArray *)keyPaths context:(BKObserverContext)context task:(id)task
{
	if ((self = [super init])) {
		_observee = observee;
		_keyPaths = [keyPaths mutableCopy];
		_context = context;
		_task = [task copy];
	}
	return self;
}

// 系统回调
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context != BKBlockObservationContext) return;

	@synchronized(self) {
		switch (self.context) {
			case BKObserverContextKey: {
				void (^task)(id) = self.task;
				task(object);
				break;
			}
			case BKObserverContextKeyWithChange: {
				void (^task)(id, NSDictionary *) = self.task;
				task(object, change);
				break;
			}
			case BKObserverContextManyKeys: {
				void (^task)(id, NSString *) = self.task;
				task(object, keyPath);
				break;
			}
			case BKObserverContextManyKeysWithChange: {
				void (^task)(id, NSString *, NSDictionary *) = self.task;
				task(object, keyPath, change);
				break;
			}
		}
	}
}

// 开始观察
// 保证线程安全
- (void)startObservingWithOptions:(NSKeyValueObservingOptions)options
{
	@synchronized(self) {
		if (_isObserving) return;

		[self.keyPaths bk_each:^(NSString *keyPath) {
			[self.observee addObserver:self forKeyPath:keyPath options:options context:BKBlockObservationContext];
		}];

		_isObserving = YES;
	}
}

// 移除观察
- (void)stopObservingKeyPath:(NSString *)keyPath
{
	NSParameterAssert(keyPath);

	@synchronized (self) {
		if (!_isObserving) return;
		if (![self.keyPaths containsObject:keyPath]) return;

		NSObject *observee = self.observee;
		if (!observee) return;

		[self.keyPaths removeObject: keyPath];
		keyPath = [keyPath copy];

		if (!self.keyPaths.count) {
			_task = nil;
			_observee = nil;
			_keyPaths = nil;
		}

		[observee removeObserver:self forKeyPath:keyPath context:BKBlockObservationContext];
	}
}

- (void)_stopObservingLocked
{
	if (!_isObserving) return;

	_task = nil;

	NSObject *observee = self.observee;
	NSArray *keyPaths = [self.keyPaths copy];

	_observee = nil;
	_keyPaths = nil;

    // 释放每一个 keypaths
	[keyPaths bk_each:^(NSString *keyPath) {
		[observee removeObserver:self forKeyPath:keyPath context:BKBlockObservationContext];
	}];
}

- (void)stopObserving
{
	if (_observee == nil) return;

	@synchronized (self) {
		[self _stopObservingLocked];
	}
}

- (void)dealloc
{
	if (self.keyPaths) {
		[self _stopObservingLocked];
	}
}

@end

static const NSUInteger BKKeyValueObservingOptionWantsChangeDictionary = 0x1000;

@implementation NSObject (BlockObservation)

- (NSString *)bk_addObserverForKeyPath:(NSString *)keyPath task:(void (^)(id target))task
{
    // 产生一个唯一的标示符，每次调用都会不一样，所以可以用当作一些临时缓存文件的名字
	NSString *token = [[NSProcessInfo processInfo] globallyUniqueString];
	[self bk_addObserverForKeyPaths:@[ keyPath ] identifier:token options:0 context:BKObserverContextKey task:task];
	return token;
}

- (NSString *)bk_addObserverForKeyPaths:(NSArray *)keyPaths task:(void (^)(id obj, NSString *keyPath))task
{
	NSString *token = [[NSProcessInfo processInfo] globallyUniqueString];
	[self bk_addObserverForKeyPaths:keyPaths identifier:token options:0 context:BKObserverContextManyKeys task:task];
	return token;
}

- (NSString *)bk_addObserverForKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options task:(void (^)(id obj, NSDictionary *change))task
{
	NSString *token = [[NSProcessInfo processInfo] globallyUniqueString];
	options = options | BKKeyValueObservingOptionWantsChangeDictionary;
	[self bk_addObserverForKeyPath:keyPath identifier:token options:options task:task];
	return token;
}

- (NSString *)bk_addObserverForKeyPaths:(NSArray *)keyPaths options:(NSKeyValueObservingOptions)options task:(void (^)(id obj, NSString *keyPath, NSDictionary *change))task
{
	NSString *token = [[NSProcessInfo processInfo] globallyUniqueString];
	options = options | BKKeyValueObservingOptionWantsChangeDictionary;
	[self bk_addObserverForKeyPaths:keyPaths identifier:token options:options task:task];
	return token;
}

- (void)bk_addObserverForKeyPath:(NSString *)keyPath identifier:(NSString *)identifier options:(NSKeyValueObservingOptions)options task:(void (^)(id obj, NSDictionary *change))task
{
	BKObserverContext context = (options == 0) ? BKObserverContextKey : BKObserverContextKeyWithChange;
	options = options & (~BKKeyValueObservingOptionWantsChangeDictionary);
	[self bk_addObserverForKeyPaths:@[keyPath] identifier:identifier options:options context:context task:task];
}

- (void)bk_addObserverForKeyPaths:(NSArray *)keyPaths identifier:(NSString *)identifier options:(NSKeyValueObservingOptions)options task:(void (^)(id obj, NSString *keyPath, NSDictionary *change))task
{
	BKObserverContext context = (options == 0) ? BKObserverContextManyKeys : BKObserverContextManyKeysWithChange;
	options = options & (~BKKeyValueObservingOptionWantsChangeDictionary);
	[self bk_addObserverForKeyPaths:keyPaths identifier:identifier options:options context:context task:task];
}

// 移除观察
- (void)bk_removeObserverForKeyPath:(NSString *)keyPath identifier:(NSString *)token
{
	NSParameterAssert(keyPath.length);
	NSParameterAssert(token.length);

	NSMutableDictionary *dict;

	@synchronized (self) {
		dict = [self bk_observerBlocks];
		if (!dict) return;
	}

	_BKObserver *observer = dict[token];
	[observer stopObservingKeyPath:keyPath];

	if (observer.keyPaths.count == 0) {
		[dict removeObjectForKey:token];
	}

	if (dict.count == 0) [self bk_setObserverBlocks:nil];
}

// 通过 token 移除观察
- (void)bk_removeObserversWithIdentifier:(NSString *)token
{
	NSParameterAssert(token);

	NSMutableDictionary *dict;

	@synchronized (self) {
		dict = [self bk_observerBlocks];
		if (!dict) return;
	}

	_BKObserver *observer = dict[token];
	[observer stopObserving];

	[dict removeObjectForKey:token];

	if (dict.count == 0) [self bk_setObserverBlocks:nil];
}

// 移除所有的观察
- (void)bk_removeAllBlockObservers
{
	NSDictionary *dict;

	@synchronized (self) {
		dict = [[self bk_observerBlocks] copy];
		[self bk_setObserverBlocks:nil];
	}

    // 获取当前对象的所有观察者，并一一停止观察
	[dict.allValues bk_each:^(_BKObserver *trampoline) {
		[trampoline stopObserving];
	}];
}

#pragma mark - "Private"s

+ (NSMutableSet *)bk_observedClassesHash
{
	static dispatch_once_t onceToken;
	static NSMutableSet *swizzledClasses = nil;
	dispatch_once(&onceToken, ^{
		swizzledClasses = [[NSMutableSet alloc] init];
	});

	return swizzledClasses;
}

// 核心方法
- (void)bk_addObserverForKeyPaths:(NSArray *)keyPaths identifier:(NSString *)identifier options:(NSKeyValueObservingOptions)options context:(BKObserverContext)context task:(id)task
{
	NSParameterAssert(keyPaths.count);
	NSParameterAssert(identifier.length);
	NSParameterAssert(task);

    // method swizzle dealloc 方法
    Class classToSwizzle = self.class;
    
    // 所有修改过 dealloc 方法的类
    NSMutableSet *classes = self.class.bk_observedClassesHash;
    @synchronized (classes) {
        // 当前类的类名
        NSString *className = NSStringFromClass(classToSwizzle);
        
        // bk_observedClassesHash 中不包含当前类，就添加这个类
        // 获取当前类名，并判断是否修改过 dealloc 方法以减少这部分代码的调用次数
        if (![classes containsObject:className]) {
            // 获取 dealloc 这个 SEL
            // 这里的 sel_registerName 方法会返回 dealloc 的 selector，因为 dealloc 已经注册过
            SEL deallocSelector = sel_registerName("dealloc");
            
			__block void (*originalDealloc)(__unsafe_unretained id, SEL) = NULL;
            
            // 新的 dealloc 实现
			id newDealloc = ^(__unsafe_unretained id objSelf) {
                // 移除所有的观察者
                [objSelf bk_removeAllBlockObservers];
                
                if (originalDealloc == NULL) {
                    // 如果原有的 dealloc 方法没有被找到就会查找父类的 dealloc 方法，调用父类的 dealloc 方法
                    struct objc_super superInfo = {
                        .receiver = objSelf,
                        .super_class = class_getSuperclass(classToSwizzle)
                    };
                    
                    void (*msgSend)(struct objc_super *, SEL) = (__typeof__(msgSend))objc_msgSendSuper;
                    msgSend(&superInfo, deallocSelector);
                } else {
                    // 如果 dealloc 方法被找到就会直接调用该方法，并传入参数
                    originalDealloc(objSelf, deallocSelector);
                }
            };
            
            // 通过 block 获取 IMP
            IMP newDeallocIMP = imp_implementationWithBlock(newDealloc);
            
            if (!class_addMethod(classToSwizzle, deallocSelector, newDeallocIMP, "v@:")) {
                // The class already contains a method implementation.
                Method deallocMethod = class_getInstanceMethod(classToSwizzle, deallocSelector);
                
                // We need to store original implementation before setting new implementation
                // in case method is called at the time of setting.
                originalDealloc = (void(*)(__unsafe_unretained id, SEL))method_getImplementation(deallocMethod);
                
                // We need to store original implementation again, in case it just changed.
                originalDealloc = (void(*)(__unsafe_unretained id, SEL))method_setImplementation(deallocMethod, newDeallocIMP);
            }
            
            [classes addObject:className];
        }
    }

	NSMutableDictionary *dict;
    // _BKObserver 对象是内部使用的观察者类
	_BKObserver *observer = [[_BKObserver alloc] initWithObservee:self keyPaths:keyPaths context:context task:task];
	[observer startObservingWithOptions:options];

	@synchronized (self) {
		dict = [self bk_observerBlocks];

		if (dict == nil) {
			dict = [NSMutableDictionary dictionary];
			[self bk_setObserverBlocks:dict];
		}
	}

    // dict 是关联对象 {identifier，obeserver}，保存当前对象的所有观察者
	dict[identifier] = observer;
}

- (void)bk_setObserverBlocks:(NSMutableDictionary *)dict
{
	[self bk_associateValue:dict withKey:BKObserverBlocksKey];
}

- (NSMutableDictionary *)bk_observerBlocks
{
	return [self bk_associatedValueForKey:BKObserverBlocksKey];
}

@end
