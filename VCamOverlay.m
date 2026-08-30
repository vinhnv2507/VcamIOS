#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "VCamPaths.h"
#include <spawn.h>
#include <signal.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>

#if __has_include(<roothide.h>)
#include <roothide.h>
#define VCAM_OVERLAY_HAS_ROOTHIDE 1
#endif

extern char **environ;

static NSString *const VCamOverlayNotification = @"com.yourcompany.vcam.adjustments.changed";
static NSString *const VCamPreferencesNotification = @"com.yourcompany.vcam.prefs.changed";

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
@property(nonatomic, strong) UILabel *sourceStatusLabel;
@property(nonatomic, strong) NSTimer *remoteTimer;
@property(nonatomic, copy) NSString *remoteTimerMode;
@property(nonatomic, strong) NSData *lastRemoteFrame;
@property(nonatomic, assign) BOOL remoteRequestRunning;
@property(nonatomic, assign) pid_t remoteFFmpegPID;
@property(nonatomic, strong) NSDate *lastRemoteVideoModification;
- (void)refreshFromPreferences;
@end

static __weak VCamOverlayController *vcamOverlayController = nil;

static void VCamPreferencesDidChange(CFNotificationCenterRef center, void *observer,
                                     CFStringRef name, const void *object,
                                     CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [vcamOverlayController refreshFromPreferences];
    });
}

@implementation VCamOverlayController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    self.floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.floatingButton.frame = CGRectMake(CGRectGetWidth(self.view.bounds) - 58.0,
        CGRectGetHeight(self.view.bounds) * 0.42, 46.0, 46.0);
    self.floatingButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.floatingButton.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.92];
    self.floatingButton.layer.cornerRadius = 23.0;
    self.floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.floatingButton.layer.shadowOpacity = 0.35;
    self.floatingButton.layer.shadowRadius = 5.0;
    self.floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
    [self.floatingButton setTitle:@"VC" forState:UIControlStateNormal];
    [self.floatingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
    [self.floatingButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.floatingButton addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(dragButton:)]];
    [self.view addSubview:self.floatingButton];

    [self buildPanel];
    vcamOverlayController = self;
    [self refreshFromPreferences];
}

- (void)buildPanel {
    CGFloat width = MIN(276.0, CGRectGetWidth(self.view.bounds) - 24.0);
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 410.0)];
    self.panel.center = self.view.center;
    self.panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleBottomMargin;
    self.panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.58];
    self.panel.layer.cornerRadius = 15.0;
    self.panel.layer.borderWidth = 1.0;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    self.panel.hidden = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 6, width - 60, 30)];
    title.text = @"Điều khiển VCam";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:17.0];
    [self.panel addSubview:title];

    UIButton *close = [self smallButton:@"×" action:@selector(togglePanel)];
    close.frame = CGRectMake(width - 42, 4, 36, 34);
    [self.panel addSubview:close];

    CGFloat centerX = width / 2.0;
    UIButton *up = [self smallButton:@"↑" action:@selector(moveUp)];
    up.frame = CGRectMake(centerX - 22, 38, 44, 36);
    UIButton *left = [self smallButton:@"←" action:@selector(moveLeft)];
    left.frame = CGRectMake(centerX - 72, 78, 44, 36);
    UIButton *reset = [self smallButton:@"●" action:@selector(resetAdjustments)];
    reset.frame = CGRectMake(centerX - 22, 78, 44, 36);
    UIButton *right = [self smallButton:@"→" action:@selector(moveRight)];
    right.frame = CGRectMake(centerX + 28, 78, 44, 36);
    UIButton *down = [self smallButton:@"↓" action:@selector(moveDown)];
    down.frame = CGRectMake(centerX - 22, 118, 44, 36);
    for (UIButton *button in @[up, left, reset, right, down]) [self.panel addSubview:button];

    UILabel *zoomLabel = [self panelLabel:@"Zoom"];
    zoomLabel.frame = CGRectMake(12, 160, 56, 32);
    [self.panel addSubview:zoomLabel];
    UIButton *zoomOut = [self wideButton:@"−" action:@selector(zoomOut)];
    zoomOut.frame = CGRectMake(70, 160, 88, 32);
    UIButton *zoomIn = [self wideButton:@"＋" action:@selector(zoomIn)];
    zoomIn.frame = CGRectMake(164, 160, width - 176, 32);
    [self.panel addSubview:zoomOut];
    [self.panel addSubview:zoomIn];

    UILabel *brightnessLabel = [self panelLabel:@"Độ sáng"];
    brightnessLabel.frame = CGRectMake(12, 200, 56, 32);
    [self.panel addSubview:brightnessLabel];
    UIButton *darken = [self wideButton:@"−" action:@selector(darken)];
    darken.frame = CGRectMake(70, 200, 88, 32);
    UIButton *brighten = [self wideButton:@"＋" action:@selector(brighten)];
    brighten.frame = CGRectMake(164, 200, width - 176, 32);
    [self.panel addSubview:darken];
    [self.panel addSubview:brighten];

    UILabel *rotationLabel = [self panelLabel:@"Xoay 360°"];
    rotationLabel.frame = CGRectMake(12, 240, 56, 32);
    [self.panel addSubview:rotationLabel];
    UIButton *rotateLeft = [self wideButton:@"↺ 15°" action:@selector(rotateLeft)];
    rotateLeft.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
    rotateLeft.frame = CGRectMake(70, 240, 88, 32);
    UIButton *rotateRight = [self wideButton:@"↻ 15°" action:@selector(rotateRight)];
    rotateRight.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
    rotateRight.frame = CGRectMake(164, 240, width - 176, 32);
    [self.panel addSubview:rotateLeft];
    [self.panel addSubview:rotateRight];

    UILabel *flipLabel = [self panelLabel:@"Lật"];
    flipLabel.frame = CGRectMake(12, 280, 56, 32);
    [self.panel addSubview:flipLabel];
    UIButton *flipHorizontal = [self wideButton:@"↔ Ngang" action:@selector(flipHorizontal)];
    flipHorizontal.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    flipHorizontal.frame = CGRectMake(70, 280, 88, 32);
    UIButton *flipVertical = [self wideButton:@"↕ Dọc" action:@selector(flipVertical)];
    flipVertical.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    flipVertical.frame = CGRectMake(164, 280, width - 176, 32);
    [self.panel addSubview:flipHorizontal];
    [self.panel addSubview:flipVertical];

    UIButton *pickImage = [self wideButton:@"Ảnh" action:@selector(openImagePicker)];
    pickImage.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    pickImage.frame = CGRectMake(12, 320, 76, 34);
    UIButton *pickVideo = [self wideButton:@"Video" action:@selector(openVideoPicker)];
    pickVideo.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    pickVideo.frame = CGRectMake(94, 320, 76, 34);
    UIButton *remoteSource = [self wideButton:@"Link live" action:@selector(enterRemoteSource)];
    remoteSource.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    remoteSource.frame = CGRectMake(176, 320, width - 188, 34);
    [self.panel addSubview:pickImage];
    [self.panel addSubview:pickVideo];
    [self.panel addSubview:remoteSource];

    self.sourceStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 360, width - 24, 18)];
    self.sourceStatusLabel.textAlignment = NSTextAlignmentCenter;
    self.sourceStatusLabel.textColor = [UIColor colorWithWhite:1 alpha:0.82];
    self.sourceStatusLabel.font = [UIFont systemFontOfSize:10.5];
    self.sourceStatusLabel.adjustsFontSizeToFitWidth = YES;
    [self.panel addSubview:self.sourceStatusLabel];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(12, 385, width - 24, 18)];
    hint.text = @"● đặt lại  •  kéo nút VC để di chuyển";
    hint.textAlignment = NSTextAlignmentCenter;
    hint.textColor = [UIColor colorWithWhite:1 alpha:0.65];
    hint.font = [UIFont systemFontOfSize:10.5];
    [self.panel addSubview:hint];
    [self.view addSubview:self.panel];
}

- (NSDictionary *)mainPreferences {
    return [NSDictionary dictionaryWithContentsOfFile:VCamPreferencesFile()] ?: @{};
}

- (void)writeMainPreferences:(NSDictionary *)preferences {
    [preferences writeToFile:VCamPreferencesFile() atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{
        NSFilePosixPermissions: @0666, NSFileProtectionKey: NSFileProtectionNone
    } ofItemAtPath:VCamPreferencesFile() error:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)VCamPreferencesNotification, NULL, NULL, YES);
}

- (void)refreshFromPreferences {
    NSDictionary *preferences = [self mainPreferences];
    id enabledValue = preferences[@"enabled"];
    BOOL enabled = enabledValue == nil ? YES : [enabledValue boolValue];
    self.view.hidden = !enabled;
    if (!enabled) {
        self.panel.hidden = YES;
        [self.remoteTimer invalidate];
        self.remoteTimer = nil;
        self.remoteRequestRunning = NO;
        [self stopRemoteFFmpeg];
        return;
    }

    NSString *remoteURL = preferences[@"remoteURL"];
    if ([remoteURL isKindOfClass:[NSString class]] && remoteURL.length > 0) {
        NSString *mode = [preferences[@"remoteMode"] isEqualToString:@"video"] ? @"video" : @"image";
        NSTimeInterval interval = [mode isEqualToString:@"video"] ? 0.18 : 1.0;
        self.sourceStatusLabel.text = [mode isEqualToString:@"video"]
            ? @"Video live độ trễ thấp" : @"Nguồn ảnh live cập nhật mỗi giây";
        if (!self.remoteTimer || ![self.remoteTimerMode isEqualToString:mode]) {
            [self.remoteTimer invalidate];
            self.remoteTimerMode = mode;
            self.remoteTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self
                selector:@selector(fetchRemoteFrame) userInfo:nil repeats:YES];
            [self fetchRemoteFrame];
        }
    } else {
        [self.remoteTimer invalidate];
        self.remoteTimer = nil;
        self.remoteTimerMode = nil;
        self.sourceStatusLabel.text = @"Chọn ảnh, video hoặc nhập link live";
        [self stopRemoteFFmpeg];
    }
}

- (void)openVCamPath:(NSString *)path {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"vcam://pick/%@", path]];
    if (!url) return;
    self.panel.hidden = YES;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)openImagePicker { [self openVCamPath:@"image"]; }
- (void)openVideoPicker { [self openVCamPath:@"video"]; }

- (void)enterRemoteSource {
    NSDictionary *preferences = [self mainPreferences];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Nguồn ảnh/video live"
        message:@"Nhập URL HTTPS trả về ảnh JPEG/PNG hiện tại. VCam sẽ tải frame mới mỗi giây."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"https://server/camera.jpg";
        field.keyboardType = UIKeyboardTypeURL;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        NSString *saved = preferences[@"remoteURL"];
        if ([saved isKindOfClass:[NSString class]]) field.text = saved;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    if ([preferences[@"remoteURL"] length] > 0) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Xóa link" style:UIAlertActionStyleDestructive
            handler:^(UIAlertAction *action) {
                NSMutableDictionary *updated = [[self mainPreferences] mutableCopy];
                [updated removeObjectForKey:@"remoteURL"];
                [updated removeObjectForKey:@"remoteMode"];
                [self writeMainPreferences:updated];
            }]];
    }
    void (^saveRemote)(NSString *) = ^(NSString *mode) {
        NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSURL *url = [NSURL URLWithString:value];
        NSArray *schemes = [mode isEqualToString:@"video"]
            ? @[@"http", @"https", @"rtsp"] : @[@"http", @"https"];
        if (!url || ![schemes containsObject:url.scheme.lowercaseString]) {
            self.sourceStatusLabel.text = @"Link không hợp lệ";
            return;
        }
        [self stopRemoteFFmpeg];
        self.lastRemoteFrame = nil;
        self.lastRemoteVideoModification = nil;
        NSMutableDictionary *updated = [[self mainPreferences] mutableCopy];
        updated[@"enabled"] = @YES;
        updated[@"remoteURL"] = value;
        updated[@"remoteMode"] = mode;
        [self writeMainPreferences:updated];
        [self refreshFromPreferences];
    };
    [alert addAction:[UIAlertAction actionWithTitle:@"Ảnh live" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            saveRemote(@"image");
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Video live" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) { saveRemote(@"video"); }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)fetchRemoteFrame {
    if (self.remoteRequestRunning) return;
    NSDictionary *preferences = [self mainPreferences];
    NSString *urlString = preferences[@"remoteURL"];
    if ([preferences[@"remoteMode"] isEqualToString:@"video"]) {
        [self monitorRemoteVideoAtURL:urlString];
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    self.remoteRequestRunning = YES;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:8.0];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.remoteRequestRunning = NO;
                NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]]
                    ? (NSHTTPURLResponse *)response : nil;
                UIImage *image = data.length <= 20 * 1024 * 1024 ? [UIImage imageWithData:data] : nil;
                if (error || (http && http.statusCode >= 400) || !image) {
                    self.sourceStatusLabel.text = @"Link chưa trả về JPEG/PNG hợp lệ";
                    return;
                }
                if ([data isEqualToData:self.lastRemoteFrame]) return;
                self.lastRemoteFrame = data;

                CGFloat longest = MAX(image.size.width, image.size.height);
                CGFloat scale = longest > 1280.0 ? 1280.0 / longest : 1.0;
                CGSize size = CGSizeMake(MAX(1.0, image.size.width * scale),
                    MAX(1.0, image.size.height * scale));
                UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
                [image drawInRect:(CGRect){CGPointZero, size}];
                UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                NSData *jpeg = UIImageJPEGRepresentation(resized, 0.86);
                NSString *destination = [VCamSharedDirectory() stringByAppendingPathComponent:@"media-live.jpg"];
                if (![jpeg writeToFile:destination options:NSDataWritingAtomic error:nil]) {
                    self.sourceStatusLabel.text = @"Không ghi được frame live";
                    return;
                }
                [[NSFileManager defaultManager] setAttributes:@{
                    NSFilePosixPermissions: @0666, NSFileProtectionKey: NSFileProtectionNone
                } ofItemAtPath:destination error:nil];
                NSMutableDictionary *updated = [[self mainPreferences] mutableCopy];
                updated[@"enabled"] = @YES;
                updated[@"mediaPath"] = destination;
                [self writeMainPreferences:updated];
                self.sourceStatusLabel.text = @"Live: đã nhận frame mới";
            });
        }] resume];
}

- (NSString *)ffmpegPath {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
#if VCAM_OVERLAY_HAS_ROOTHIDE
    NSString *rootHidePath = jbroot(@"/usr/bin/ffmpeg");
    if (rootHidePath.length) [paths addObject:rootHidePath];
#endif
    [paths addObjectsFromArray:@[@"/var/jb/usr/bin/ffmpeg", @"/usr/bin/ffmpeg", @"/usr/local/bin/ffmpeg"]];
    for (NSString *path in paths) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

- (void)stopRemoteFFmpeg {
    if (self.remoteFFmpegPID > 0) {
        kill(self.remoteFFmpegPID, SIGTERM);
        waitpid(self.remoteFFmpegPID, NULL, WNOHANG);
        self.remoteFFmpegPID = 0;
    }
}

- (void)startRemoteFFmpegAtURL:(NSString *)urlString {
    NSString *ffmpeg = [self ffmpegPath];
    if (!ffmpeg) {
        self.sourceStatusLabel.text = @"Thiếu FFmpeg, hãy cài lại VCam";
        return;
    }
    NSString *destination = [VCamSharedDirectory() stringByAppendingPathComponent:@"media-live.jpg"];
    unlink(destination.fileSystemRepresentation);
    const char *executable = ffmpeg.fileSystemRepresentation;
    const char *input = urlString.UTF8String;
    const char *output = destination.fileSystemRepresentation;
    char *const arguments[] = {
        (char *)executable, "-nostdin", "-hide_banner", "-loglevel", "error",
        "-threads", "1", "-stream_loop", "-1", "-re", "-i", (char *)input,
        "-map", "0:v:0", "-an", "-sn",
        "-vf", "fps=6,scale=960:960:force_original_aspect_ratio=decrease",
        "-q:v", "5", "-f", "image2", "-update", "1", "-y", (char *)output, NULL
    };
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    pid_t pid = 0;
    int result = posix_spawn(&pid, executable, &actions, NULL, arguments, environ);
    posix_spawn_file_actions_destroy(&actions);
    if (result == 0) {
        self.remoteFFmpegPID = pid;
        self.sourceStatusLabel.text = @"Đang kết nối video live…";
    } else {
        self.sourceStatusLabel.text = @"Không chạy được video live";
    }
}

- (void)monitorRemoteVideoAtURL:(NSString *)urlString {
    if (urlString.length == 0) return;
    if (self.remoteFFmpegPID > 0) {
        int status = 0;
        if (waitpid(self.remoteFFmpegPID, &status, WNOHANG) == self.remoteFFmpegPID) {
            self.remoteFFmpegPID = 0;
        }
    }
    if (self.remoteFFmpegPID <= 0) [self startRemoteFFmpegAtURL:urlString];

    NSString *destination = [VCamSharedDirectory() stringByAppendingPathComponent:@"media-live.jpg"];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:destination error:nil];
    NSDate *modified = attributes[NSFileModificationDate];
    if (!modified || [modified isEqualToDate:self.lastRemoteVideoModification]) return;
    // Decoding verifies FFmpeg has completed this JPEG before the camera daemon reloads it.
    if (![UIImage imageWithContentsOfFile:destination]) return;
    self.lastRemoteVideoModification = modified;
    [[NSFileManager defaultManager] setAttributes:@{
        NSFilePosixPermissions: @0666, NSFileProtectionKey: NSFileProtectionNone
    } ofItemAtPath:destination error:nil];
    NSMutableDictionary *updated = [[self mainPreferences] mutableCopy];
    updated[@"enabled"] = @YES;
    updated[@"mediaPath"] = destination;
    [self writeMainPreferences:updated];
    self.sourceStatusLabel.text = @"Video live: đang nhận hình";
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
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            VCamPreferencesDidChange, (__bridge CFStringRef)VCamPreferencesNotification,
            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        VCamShowOverlay();
    }
}
