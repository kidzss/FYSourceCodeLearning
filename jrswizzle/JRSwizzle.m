// JRSwizzle.m semver:1.1.0
//   Copyright (c) 2007-2016 Jonathan 'Wolf' Rentzsch: http://rentzsch.com
//   Some rights reserved: http://opensource.org/licenses/mit
//   https://github.com/rentzsch/jrswizzle

#import "JRSwizzle.h"

#if TARGET_OS_IPHONE
	#import <objc/runtime.h>
	#import <objc/message.h>
#else
	#import <objc/objc-class.h>
#endif

#define SetNSErrorFor(FUNC, ERROR_VAR, FORMAT,...)	\
	if (ERROR_VAR) {	\
		NSString *errStr = [NSString stringWithFormat:@"%s: " FORMAT,FUNC,##__VA_ARGS__]; \
		*ERROR_VAR = [NSError errorWithDomain:@"NSCocoaErrorDomain" \
										 code:-1	\
									 userInfo:[NSDictionary dictionaryWithObject:errStr forKey:NSLocalizedDescriptionKey]]; \
	}
#define SetNSError(ERROR_VAR, FORMAT,...) SetNSErrorFor(__func__, ERROR_VAR, FORMAT, ##__VA_ARGS__)

// 获取对象的 Class
#if OBJC_API_VERSION >= 2
#define GetClass(obj)	object_getClass(obj)
#else
#define GetClass(obj)	(obj ? obj->isa : Nil)
#endif

@implementation NSObject (JRSwizzle)

// 交换两个 SEL 的 IMP，返回是否成功，并传入错误对象的地址
+ (BOOL)jr_swizzleMethod:(SEL)origSel_ withMethod:(SEL)altSel_ error:(NSError**)error_ {
    // 判断OC的版本
    // OC 版本大于 2
#if OBJC_API_VERSION >= 2
    // 获取原始方法对象Method（子类没有，会去父类寻找）
	Method origMethod = class_getInstanceMethod(self, origSel_);
	if (!origMethod) {
        // 未找到原始方法的实现，直接返回 NO
#if TARGET_OS_IPHONE
		SetNSError(error_, @"original method %@ not found for class %@", NSStringFromSelector(origSel_), [self class]);
#else
		SetNSError(error_, @"original method %@ not found for class %@", NSStringFromSelector(origSel_), [self className]);
#endif
		return NO;
	}

    // 获取 swizzle 方法，没有也直接返回 NO
	Method altMethod = class_getInstanceMethod(self, altSel_);
	if (!altMethod) {
        // 判断 IPHONE 还是 SIMULATOR 的宏
#if TARGET_OS_IPHONE
		SetNSError(error_, @"alternate method %@ not found for class %@", NSStringFromSelector(altSel_), [self class]);
#else
		SetNSError(error_, @"alternate method %@ not found for class %@", NSStringFromSelector(altSel_), [self className]);
#endif
		return NO;
	}

    // 如果已经存在 class_addMethod 返回 NO
	class_addMethod(self,
					origSel_,
					class_getMethodImplementation(self, origSel_),
					method_getTypeEncoding(origMethod));
	class_addMethod(self,
					altSel_,
					class_getMethodImplementation(self, altSel_),
					method_getTypeEncoding(altMethod));

	method_exchangeImplementations(class_getInstanceMethod(self, origSel_), class_getInstanceMethod(self, altSel_));
	return YES;
#else
    // OC 版本小于 2
	//	Scan for non-inherited methods.
	Method directOriginalMethod = NULL, directAlternateMethod = NULL;

	void *iterator = NULL;
	struct objc_method_list *mlist = class_nextMethodList(self, &iterator);
	while (mlist) {
		int method_index = 0;
		for (; method_index < mlist->method_count; method_index++) {
			if (mlist->method_list[method_index].method_name == origSel_) {
				assert(!directOriginalMethod);
				directOriginalMethod = &mlist->method_list[method_index];
			}
			if (mlist->method_list[method_index].method_name == altSel_) {
				assert(!directAlternateMethod);
				directAlternateMethod = &mlist->method_list[method_index];
			}
		}
		mlist = class_nextMethodList(self, &iterator);
	}

	//	If either method is inherited, copy it up to the target class to make it non-inherited.
	if (!directOriginalMethod || !directAlternateMethod) {
		Method inheritedOriginalMethod = NULL, inheritedAlternateMethod = NULL;
		if (!directOriginalMethod) {
			inheritedOriginalMethod = class_getInstanceMethod(self, origSel_);
			if (!inheritedOriginalMethod) {
#if TARGET_OS_IPHONE
                SetNSError(error_, @"original method %@ not found for class %@", NSStringFromSelector(origSel_), [self class]);
#else
                SetNSError(error_, @"original method %@ not found for class %@", NSStringFromSelector(origSel_), [self className]);
#endif
				return NO;
			}
		}
		if (!directAlternateMethod) {
			inheritedAlternateMethod = class_getInstanceMethod(self, altSel_);
			if (!inheritedAlternateMethod) {
#if TARGET_OS_IPHONE
                SetNSError(error_, @"alternate method %@ not found for class %@", NSStringFromSelector(altSel_), [self class]);
#else
                SetNSError(error_, @"alternate method %@ not found for class %@", NSStringFromSelector(altSel_), [self className]);
#endif
				return NO;
			}
		}

		int hoisted_method_count = !directOriginalMethod && !directAlternateMethod ? 2 : 1;
		struct objc_method_list *hoisted_method_list = malloc(sizeof(struct objc_method_list) + (sizeof(struct objc_method)*(hoisted_method_count-1)));
        hoisted_method_list->obsolete = NULL;	// soothe valgrind - apparently ObjC runtime accesses this value and it shows as uninitialized in valgrind
		hoisted_method_list->method_count = hoisted_method_count;
		Method hoisted_method = hoisted_method_list->method_list;

		if (!directOriginalMethod) {
			bcopy(inheritedOriginalMethod, hoisted_method, sizeof(struct objc_method));
			directOriginalMethod = hoisted_method++;
		}
		if (!directAlternateMethod) {
			bcopy(inheritedAlternateMethod, hoisted_method, sizeof(struct objc_method));
			directAlternateMethod = hoisted_method;
		}
		class_addMethods(self, hoisted_method_list);
	}

	//	Swizzle.
	IMP temp = directOriginalMethod->method_imp;
	directOriginalMethod->method_imp = directAlternateMethod->method_imp;
	directAlternateMethod->method_imp = temp;

	return YES;
#endif
}

// 替换类方法
// 类本身也是对象，直接获取当前对象所属的类，调用 jr_swizzleMethod 即可
+ (BOOL)jr_swizzleClassMethod:(SEL)origSel_ withClassMethod:(SEL)altSel_ error:(NSError**)error_ {
	return [GetClass((id)self) jr_swizzleMethod:origSel_ withMethod:altSel_ error:error_];
}

// 使用 block 替换原始方法，返回替换后的 NSInvocation 对象
+ (NSInvocation*)jr_swizzleMethod:(SEL)origSel withBlock:(id)block error:(NSError**)error {
    // 获取 block 的 IMP
    IMP blockIMP = imp_implementationWithBlock(block);
    // 拼接一个 block 的 selector
    NSString *blockSelectorString = [NSString stringWithFormat:@"_jr_block_%@_%p", NSStringFromSelector(origSel), block];
    // 通过 selector 的字符串获取 SEL
    SEL blockSel = sel_registerName([blockSelectorString cStringUsingEncoding:NSUTF8StringEncoding]);
    // 获取原始方法 Method
    Method origSelMethod = class_getInstanceMethod(self, origSel);
    // 获取原始方法的描述方法参数和返回值类型的字符串
    const char* origSelMethodArgs = method_getTypeEncoding(origSelMethod);
    // 添加一个传入 block 代表的方法
    class_addMethod(self, blockSel, blockIMP, origSelMethodArgs);

    // 创建 blockSel
    NSMethodSignature *origSig = [NSMethodSignature signatureWithObjCTypes:origSelMethodArgs];
    NSInvocation *origInvocation = [NSInvocation invocationWithMethodSignature:origSig];
    origInvocation.selector = blockSel;

    [self jr_swizzleMethod:origSel withMethod:blockSel error:nil];

    return origInvocation;
}

+ (NSInvocation*)jr_swizzleClassMethod:(SEL)origSel withBlock:(id)block error:(NSError**)error {
    NSInvocation *invocation = [GetClass((id)self) jr_swizzleMethod:origSel withBlock:block error:error];
    invocation.target = self;

    return invocation;
}

@end
