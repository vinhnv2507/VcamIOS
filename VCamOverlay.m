#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "VCamPaths.h"

static NSString *const VCamOverlayNotification = @"com.yourcompany.vcam.adjustments.changed";

@interface VCamPassThroughWindow : UIWindow
@end

@implementation VCamPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self.rootViewController.view ? nil : hit;
}
@end

@interface VCamOverlayController : UIViewController
@property(nonatomic, strong) UIButton *floatingButton;
@property(nonatomic, strong) UIView *panel;
@end

@implementation VCamOverlayController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    self.floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.floatingButton.frame = CGRectMake(CGRectGetWidth(self.view.bounds) - 68.0,
        CGRectGetHeight(self.view.bounds) * 0.42, 54.0, 54.0);
    self.floatingButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.floatingButton.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.92];
    self.floatingButton.layer.cornerRadius = 27.0;
    self.floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.floatingButton.layer.shadowOpacity = 0.35;
    self.floatingButton.layer.shadowRadius = 5.0;
    self.floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
    [self.floatingButton setTitle:@"VC" forState:UIControlStateNormal];
    [self.floatingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
    [self.floatingButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.floatingButton addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(dragButton:)]];
    [self.view addSubview:self.floatingButton];

    [self buildPanel];
}

- (void)buildPanel {
    CGFloat width = MIN(310.0, CGRectGetWidth(self.view.bounds) - 28.0);
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 452.0)];
    self.panel.center = self.view.center;
    self.panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleBottomMargin;
    self.panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.86];
    self.panel.layer.cornerRadius = 18.0;
    self.panel.layer.borderWidth = 1.0;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    self.panel.hidden = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(18, 12, width - 72, 32)];
    title.text = @"Điều khiển VCam";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:19.0];
    [self.panel addSubview:title];

    UIButton *close = [self smallButton:@"×" action:@selector(togglePanel)];
    close.frame = CGRectMake(width - 50, 8, 40, 40);
    [self.panel addSubview:close];

    CGFloat centerX = width / 2.0;
    UIButton *up = [self smallButton:@"↑" action:@selector(moveUp)];
    up.frame = CGRectMake(centerX - 27, 52, 54, 48);
    UIButton *left = [self smallButton:@"←" action:@selector(moveLeft)];
    left.frame = CGRectMake(centerX - 88, 106, 54, 48);
    UIButton *reset = [self smallButton:@"●" action:@selector(resetAdjustments)];
    reset.frame = CGRectMake(centerX - 27, 106, 54, 48);
    UIButton *right = [self smallButton:@"→" action:@selector(moveRight)];
    right.frame = CGRectMake(centerX + 34, 106, 54, 48);
    UIButton *down = [self smallButton:@"↓" action:@selector(moveDown)];
    down.frame = CGRectMake(centerX - 27, 160, 54, 48);
    for (UIButton *button in @[up, left, reset, right, down]) [self.panel addSubview:button];

    UILabel *zoomLabel = [self panelLabel:@"Zoom"];
    zoomLabel.frame = CGRectMake(16, 218, 72, 42);
    [self.panel addSubview:zoomLabel];
    UIButton *zoomOut = [self wideButton:@"−" action:@selector(zoomOut)];
    zoomOut.frame = CGRectMake(91, 218, 91, 42);
    UIButton *zoomIn = [self wideButton:@"＋" action:@selector(zoomIn)];
    zoomIn.frame = CGRectMake(188, 218, width - 204, 42);
    [self.panel addSubview:zoomOut];
    [self.panel addSubview:zoomIn];

    UILabel *brightnessLabel = [self panelLabel:@"Độ sáng"];
    brightnessLabel.frame = CGRectMake(16, 270, 72, 42);
    [self.panel addSubview:brightnessLabel];
    UIButton *darken = [self wideButton:@"−" action:@selector(darken)];
    darken.frame = CGRectMake(91, 270, 91, 42);
    UIButton *brighten = [self wideButton:@"＋" action:@selector(brighten)];
    brighten.frame = CGRectMake(188, 270, width - 204, 42);
    [self.panel addSubview:darken];
    [self.panel addSubview:brighten];

    UILabel *rotationLabel = [self panelLabel:@"Xoay 360°"];
    rotationLabel.frame = CGRectMake(16, 322, 72, 42);
    [self.panel addSubview:rotationLabel];
    UIButton *rotateLeft = [self wideButton:@"↺ 15°" action:@selector(rotateLeft)];
    rotateLeft.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    rotateLeft.frame = CGRectMake(91, 322, 91, 42);
    UIButton *rotateRight = [self wideButton:@"↻ 15°" action:@selector(rotateRight)];
    rotateRight.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    rotateRight.frame = CGRectMake(188, 322, width - 204, 42);
    [self.panel addSubview:rotateLeft];
    [self.panel addSubview:rotateRight];

    UILabel *flipLabel = [self panelLabel:@"Lật"];
    flipLabel.frame = CGRectMake(16, 374, 72, 42);
    [self.panel addSubview:flipLabel];
    UIButton *flipHorizontal = [self wideButton:@"↔ Ngang" action:@selector(flipHorizontal)];
    flipHorizontal.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
    flipHorizontal.frame = CGRectMake(91, 374, 91, 42);
    UIButton *flipVertical = [self wideButton:@"↕ Dọc" action:@selector(flipVertical)];
    flipVertical.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
    flipVertical.frame = CGRectMake(188, 374, width - 204, 42);
    [self.panel addSubview:flipHorizontal];
    [self.panel addSubview:flipVertical];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(12, 424, width - 24, 20)];
    hint.text = @"● đặt lại  •  kéo nút VC để di chuyển";
    hint.textAlignment = NSTextAlignmentCenter;
    hint.textColor = [UIColor colorWithWhite:1 alpha:0.65];
    hint.font = [UIFont systemFontOfSize:12.0];
    [self.panel addSubview:hint];
    [self.view addSubview:self.panel];
}

- (UIButton *)smallButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:25.0];
    button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    button.layer.cornerRadius = 10.0;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIButton *)wideButton:(NSString *)title action:(SEL)action {
    UIButton *button = [self smallButton:title action:action];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:22.0];
    return button;
}

- (UILabel *)panelLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    return label;
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    [self.view bringSubviewToFront:self.floatingButton];
}

- (void)dragButton:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.view];
    CGPoint center = self.floatingButton.center;
    center.x += translation.x;
    center.y += translation.y;
    CGFloat radius = CGRectGetWidth(self.floatingButton.bounds) / 2.0;
    center.x = MAX(radius + 6.0, MIN(CGRectGetWidth(self.view.bounds) - radius - 6.0, center.x));
    center.y = MAX(radius + 30.0, MIN(CGRectGetHeight(self.view.bounds) - radius - 24.0, center.y));
    self.floatingButton.center = center;
    [gesture setTranslation:CGPointZero inView:self.view];
}

- (NSMutableDictionary *)preferences {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:VCamAdjustmentsFile()];
    return stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)save:(NSMutableDictionary *)preferences {
    [preferences writeToFile:VCamAdjustmentsFile() atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0666}
        ofItemAtPath:VCamAdjustmentsFile() error:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)VCamOverlayNotification, NULL, NULL, YES);
}

- (void)adjust:(NSString *)key delta:(CGFloat)delta minimum:(CGFloat)minimum maximum:(CGFloat)maximum {
    NSMutableDictionary *preferences = [self preferences];
    CGFloat value = [preferences[key] doubleValue];
    if (![preferences[key] isKindOfClass:[NSNumber class]] && [key isEqualToString:@"zoom"]) value = 1.0;
    preferences[key] = @(MAX(minimum, MIN(maximum, value + delta)));
    [self save:preferences];
}

- (void)moveLeft { [self adjust:@"offsetX" delta:-0.04 minimum:-1.0 maximum:1.0]; }
- (void)moveRight { [self adjust:@"offsetX" delta:0.04 minimum:-1.0 maximum:1.0]; }
- (void)moveUp { [self adjust:@"offsetY" delta:0.04 minimum:-1.0 maximum:1.0]; }
- (void)moveDown { [self adjust:@"offsetY" delta:-0.04 minimum:-1.0 maximum:1.0]; }
- (void)zoomIn { [self adjust:@"zoom" delta:0.1 minimum:0.5 maximum:3.0]; }
- (void)zoomOut { [self adjust:@"zoom" delta:-0.1 minimum:0.5 maximum:3.0]; }
- (void)brighten { [self adjust:@"brightness" delta:0.08 minimum:-1.0 maximum:1.0]; }
- (void)darken { [self adjust:@"brightness" delta:-0.08 minimum:-1.0 maximum:1.0]; }
- (void)rotateBy:(CGFloat)degrees {
    NSMutableDictionary *preferences = [self preferences];
    CGFloat rotation = [preferences[@"rotation"] doubleValue] + degrees;
    while (rotation >= 360.0) rotation -= 360.0;
    while (rotation < 0.0) rotation += 360.0;
    preferences[@"rotation"] = @(rotation);
    [self save:preferences];
}
- (void)rotateLeft { [self rotateBy:-15.0]; }
- (void)rotateRight { [self rotateBy:15.0]; }
- (void)toggleBoolean:(NSString *)key {
    NSMutableDictionary *preferences = [self preferences];
    preferences[key] = @(![preferences[key] boolValue]);
    [self save:preferences];
}
- (void)flipHorizontal { [self toggleBoolean:@"flipHorizontal"]; }
- (void)flipVertical { [self toggleBoolean:@"flipVertical"]; }
- (void)resetAdjustments {
    NSMutableDictionary *preferences = [self preferences];
    preferences[@"offsetX"] = @0.0;
    preferences[@"offsetY"] = @0.0;
    preferences[@"zoom"] = @1.0;
    preferences[@"brightness"] = @0.0;
    preferences[@"rotation"] = @0.0;
    preferences[@"flipHorizontal"] = @NO;
    preferences[@"flipVertical"] = @NO;
    [self save:preferences];
}

@end

static VCamPassThroughWindow *vcamOverlayWindow = nil;

static void VCamShowOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!vcamOverlayWindow) {
            UIWindowScene *windowScene = nil;
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    windowScene = (UIWindowScene *)scene;
                    if (scene.activationState == UISceneActivationStateForegroundActive) break;
                }
            }
            if (windowScene) {
                vcamOverlayWindow = [[VCamPassThroughWindow alloc] initWithWindowScene:windowScene];
                vcamOverlayWindow.frame = windowScene.coordinateSpace.bounds;
            } else {
                vcamOverlayWindow = [[VCamPassThroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            }
            vcamOverlayWindow.rootViewController = [[VCamOverlayController alloc] init];
            vcamOverlayWindow.windowLevel = UIWindowLevelAlert + 100.0;
            vcamOverlayWindow.backgroundColor = [UIColor clearColor];
        }
        vcamOverlayWindow.hidden = NO;
    });
}

__attribute__((constructor))
static void VCamOverlayInitialize(void) {
    @autoreleasepool {
        VCamShowOverlay();
    }
}
