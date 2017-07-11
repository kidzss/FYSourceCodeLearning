//
//  UIImagePickerController+BlocksKit.m
//  BlocksKit
//

#import "UIImagePickerController+BlocksKit.h"
#import "A2DynamicDelegate.h"
#import "NSObject+A2DynamicDelegate.h"
#import "NSObject+A2BlockDelegate.h"

#pragma mark Custom delegate

@interface A2DynamicUIImagePickerControllerDelegate : A2DynamicDelegate <UIImagePickerControllerDelegate>

@end

@implementation A2DynamicUIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    // 获取真实的代理
	id realDelegate = self.realDelegate;
    
    // 先调用真实代理的方法
	if (realDelegate && [realDelegate respondsToSelector:@selector(imagePickerController:didFinishPickingMediaWithInfo:)])
		[realDelegate imagePickerController:picker didFinishPickingMediaWithInfo:info];

    // 返回对应 A2DynamicDelegate 子类中存储的 block
	void (^block)(UIImagePickerController *, NSDictionary *) = [self blockImplementationForMethod:_cmd];
	if (block) block(picker, info);
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	id realDelegate = self.realDelegate;
	if (realDelegate && [realDelegate respondsToSelector:@selector(imagePickerControllerDidCancel:)])
		[realDelegate imagePickerControllerDidCancel:picker];

	void (^block)(UIImagePickerController *) = [self blockImplementationForMethod:_cmd];
	if (block) block(picker);
}

@end

#pragma mark Category

@implementation UIImagePickerController (BlocksKit)

// 动态生成 setter 和 getter，不让编译器自动生成，因为会添加一些操作
@dynamic bk_didFinishPickingMediaBlock;
@dynamic bk_didCancelBlock;

+ (void)load
{
	@autoreleasepool {
        // 添加动态代理对象
		[self bk_registerDynamicDelegate];
        // 将 block 对应到原来代理的方法上，做一个对应关系
		[self bk_linkDelegateMethods:@{ @"bk_didFinishPickingMediaBlock": @"imagePickerController:didFinishPickingMediaWithInfo:",
                                        @"bk_didCancelBlock": @"imagePickerControllerDidCancel:" }];
	}
}

@end
