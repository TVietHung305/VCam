#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "MediaManager.h"

// ============================================================================
// MARK: - 全局状态
// ============================================================================

static BOOL g_vcamEnabled = NO;
static UIWindow *g_overlayWindow = nil;
static UIButton *g_floatButton = nil;

// ============================================================================
// MARK: - 工具函数
// ============================================================================

static UIViewController *findTopViewController(void) {
    UIViewController *topVC = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) {
                topVC = w.rootViewController;
                break;
            }
        }
        if (topVC) break;
    }
    while (topVC && topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

static UIColor *vcamButtonColor(void) {
    return g_vcamEnabled
        ? [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9]
        : [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:0.9];
}

// ============================================================================
// MARK: - 相册选择代理
// ============================================================================

@interface VCamImagePickerControllerDelegate : NSObject <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@end

@implementation VCamImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker
        didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];

    NSURL *url = info[UIImagePickerControllerMediaURL];
    if (!url) return;

    NSURL *tempURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
        stringByAppendingPathComponent:@"vcam_input.mp4"]];
    [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    [[NSFileManager defaultManager] copyItemAtURL:url toURL:tempURL error:nil];

    [[MediaManager sharedManager] loadMediaFromURL:tempURL];
    g_vcamEnabled = YES;
    [[MediaManager sharedManager] start];
    if (g_floatButton) {
        g_floatButton.backgroundColor = vcamButtonColor();
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end

static VCamImagePickerControllerDelegate *g_pickerDelegate = nil;

// ============================================================================
// MARK: - 悬浮按钮 UI
// ============================================================================

@interface VCamFloatButton : UIButton
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
- (void)handleTap:(UITapGestureRecognizer *)gesture;
@end

@implementation VCamFloatButton

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *btn = gesture.view;
    CGPoint translation = [gesture translationInView:btn.superview];
    btn.center = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:btn.superview];

    if (gesture.state == UIGestureRecognizerStateEnded) {
        CGRect screen = [UIScreen mainScreen].bounds;
        CGFloat x = btn.center.x < screen.size.width / 2 ? 35 : screen.size.width - 35;
        [UIView animateWithDuration:0.2 animations:^{
            btn.center = CGPointMake(x, btn.center.y);
        }];
    }
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    UIViewController *topVC = findTopViewController();
    if (!topVC) return;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"VCam"
        message:g_vcamEnabled ? @"虚拟相机已启用" : @"虚拟相机已关闭"
        preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"选择视频"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {

        if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum]) {
            return;
        }
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypeSavedPhotosAlbum;
        picker.mediaTypes = @[@"public.movie"];
        picker.delegate = g_pickerDelegate;
        [topVC presentViewController:picker animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:g_vcamEnabled ? @"关闭虚拟相机" : @"开启虚拟相机"
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        g_vcamEnabled = !g_vcamEnabled;
        if (g_floatButton) {
            g_floatButton.backgroundColor = vcamButtonColor();
        }
        if (g_vcamEnabled) {
            [[MediaManager sharedManager] start];
        } else {
            [[MediaManager sharedManager] stop];
        }
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = gesture.view;
        alert.popoverPresentationController.sourceRect = gesture.view.bounds;
    }

    [topVC presentViewController:alert animated:YES completion:nil];
}

@end

static void setupFloatButton(void) {
    if (g_floatButton) return;

    CGFloat btnSize = 50;
    CGRect screen = [UIScreen mainScreen].bounds;

    VCamFloatButton *button = [VCamFloatButton buttonWithType:UIButtonTypeSystem];
    g_floatButton = button;
    button.frame = CGRectMake(screen.size.width - btnSize - 15, 100, btnSize, btnSize);
    button.layer.cornerRadius = btnSize / 2.0;
    button.layer.shadowColor = [UIColor blackColor].CGColor;
    button.layer.shadowOffset = CGSizeMake(0, 2);
    button.layer.shadowOpacity = 0.3;
    button.layer.shadowRadius = 4;
    button.backgroundColor = vcamButtonColor();

    [button setTitle:@"📷" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:24];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:button action:@selector(handlePan:)];
    [button addGestureRecognizer:pan];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:button action:@selector(handleTap:)];
    [button addGestureRecognizer:tap];

    g_overlayWindow = [[UIWindow alloc] initWithFrame:screen];
    g_overlayWindow.windowLevel = UIWindowLevelAlert + 100;
    g_overlayWindow.hidden = NO;
    g_overlayWindow.backgroundColor = [UIColor clearColor];

    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    [rootVC.view addSubview:button];
    g_overlayWindow.rootViewController = rootVC;
}

// ============================================================================
// MARK: - Hook AVCaptureSession / Video Output
// ============================================================================

%group VCamHooks

%hook AVCaptureSession

- (void)startRunning {
    %orig;
}

- (void)stopRunning {
    %orig;
}

%end

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                          queue:(dispatch_queue_t)queue {
    %orig;
}

%end

// Intercept frame delegate callback -> substitute with fake frames
%hook NSObject

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {

    if (g_vcamEnabled && [[MediaManager sharedManager] isRunning]) {
        CMSampleBufferRef fakeFrame = [[MediaManager sharedManager] nextVideoFrame];
        if (fakeFrame) {
            %orig(output, fakeFrame, connection);
            CFRelease(fakeFrame);
            return;
        }
    }
    %orig;
}

%end

%hook AVCapturePhotoOutput

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings
                        delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    %orig;
}

%end

%hook AVCaptureVideoPreviewLayer

- (void)setSession:(AVCaptureSession *)session {
    %orig;
}

%end

%end // VCamHooks group

// ============================================================================
// MARK: - Constructor
// ============================================================================

%ctor {
    @autoreleasepool {
        g_pickerDelegate = [[VCamImagePickerControllerDelegate alloc] init];

        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:@"com.apple.springboard"]) {
            %init(VCamHooks);
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                @autoreleasepool {
                    setupFloatButton();
                }
            });
    }
}
