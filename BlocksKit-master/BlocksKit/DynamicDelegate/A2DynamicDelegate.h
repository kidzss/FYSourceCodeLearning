//
//  A2DynamicDelegate.h
//  BlocksKit
//

#import "BKDefines.h"
#import <Foundation/Foundation.h>
#import <BlocksKit/NSObject+A2BlockDelegate.h>
#import <BlocksKit/NSObject+A2DynamicDelegate.h>


// 用来实现类的代理和数据源，它是 NSProxy 的子类
// 进行消息转发的主体，实现了block与委托方法的映射
// 实现了类的Delegate和DataSource等协议，是实现动态委托的核心类之一
// A2DynamicDelegate继承自NSProxy类，对于一些预留未实现的类，使用forwardInvocation:方法来转发






NS_ASSUME_NONNULL_BEGIN

/** A2DynamicDelegate implements a class's delegate, data source, or other
 delegated protocol by associating protocol methods with a block implementation.

	- (IBAction) annoyUser
	{
		// Create an alert view
		UIAlertView *alertView = [[UIAlertView alloc]
								  initWithTitle:@"Hello World!"
								  message:@"This alert's delegate is implemented using blocks. That's so cool!"
								  delegate:nil
								  cancelButtonTitle:@"Meh."
								  otherButtonTitles:@"Woo!", nil];

		// Get the dynamic delegate
		A2DynamicDelegate *dd = alertView.bk_dynamicDelegate;

		// Implement -alertViewShouldEnableFirstOtherButton:
		[dd implementMethod:@selector(alertViewShouldEnableFirstOtherButton:) withBlock:^(UIAlertView *alertView) {
			NSLog(@"Message: %@", alertView.message);
			return YES;
		}];

		// Implement -alertView:willDismissWithButtonIndex:
		[dd implementMethod:@selector(alertView:willDismissWithButtonIndex:) withBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
			NSLog(@"You pushed button #%d (%@)", buttonIndex, [alertView buttonTitleAtIndex:buttonIndex]);
		}];

		// Set the delegate
		alertView.delegate = dd;

		[alertView show];
	}

 A2DynamicDelegate is designed to be 'plug and play'.
 */
@interface A2DynamicDelegate : NSProxy

// 一个动态代理对象对应一个协议
/**
 * The designated initializer for the A2DynamicDelegate proxy.
 *
 * An instance of A2DynamicDelegate should generally not be created by the user,
 * but instead by calling a method in NSObject(A2DynamicDelegate). Since
 * delegates are usually weak references on the part of the delegating object, a
 * dynamic delegate would be deallocated immediately after its declaring scope
 * ends. NSObject(A2DynamicDelegate) creates a strong reference.
 *
 * @param protocol A protocol to which the dynamic delegate should conform.
 * @return An initialized delegate proxy.
 */
- (instancetype)initWithProtocol:(Protocol *)protocol;

/** The protocol delegating the dynamic delegate. */
@property (nonatomic, readonly) Protocol *protocol;

/** A dictionary of custom handlers to be used by custom responders
 in a A2Dynamic(Protocol Name) subclass of A2DynamicDelegate, like
 `A2DynamicUIAlertViewDelegate`. */

// handlers则建立了block属性名到具体block实现的映射关系
@property (nonatomic, strong, readonly) NSMutableDictionary *handlers;

/** When replacing the delegate using the A2BlockDelegate extensions, the object
 responding to classical delegate method implementations. */


// realDelegate是对象真正的代理
@property (nonatomic, weak, readonly, nullable) id realDelegate;

/** @name Block Instance Method Implementations */

/** The block that is to be fired when the specified
 selector is called on the reciever.

 @param selector An encoded selector. Must not be NULL.
 @return A code block, or nil if no block is assigned.
 */
- (nullable id)blockImplementationForMethod:(SEL)selector;

/** Assigns the given block to be fired when the specified
 selector is called on the reciever.

	[tableView.dynamicDataSource implementMethod:@selector(numberOfSectionsInTableView:)
									  withBlock:NSInteger^(UITableView *tableView) {
		return 2;
	}];

 @warning Starting with A2DynamicDelegate 2.0, a block will
 not be checked for a matching signature. A block can have
 less parameters than the original selector and will be
 ignored, but cannot have more.

 @param selector An encoded selector. Must not be NULL.
 @param block A code block with the same signature as selector.
 */
- (void)implementMethod:(SEL)selector withBlock:(nullable id)block;

/** Disassociates any block so that nothing will be fired
 when the specified selector is called on the reciever.

 @param selector An encoded selector. Must not be NULL.
 */
- (void)removeBlockImplementationForMethod:(SEL)selector;

/** @name Block Class Method Implementations */

/** The block that is to be fired when the specified
 selector is called on the delegating object's class.

 @param selector An encoded selector. Must not be NULL.
 @return A code block, or nil if no block is assigned.
 */
- (id)blockImplementationForClassMethod:(SEL)selector;

/** Assigns the given block to be fired when the specified
 selector is called on the reciever.

 @warning Starting with A2DynamicDelegate 2.0, a block will
 not be checked for a matching signature. A block can have
 less parameters than the original selector and will be
 ignored, but cannot have more.

 @param selector An encoded selector. Must not be NULL.
 @param block A code block with the same signature as selector.
 */
- (void)implementClassMethod:(SEL)selector withBlock:(nullable id)block;

/** Disassociates any blocks so that nothing will be fired
 when the specified selector is called on the delegating
 object's class.

 @param selector An encoded selector. Must not be NULL.
 */
- (void)removeBlockImplementationForClassMethod:(SEL)selector;

@end

NS_ASSUME_NONNULL_END
