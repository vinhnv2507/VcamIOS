#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

static NSString *const VCamPreferencesPath = @"/tmp/com.yourcompany.vcam.plist";
static NSString *const VCamStatusPath = @"/tmp/com.yourcompany.vcam.status.plist";
static NSString *const VCamMediaDirectory = @"/tmp/VCam";
static NSString *const VCamNotificationName = @"com.yourcompany.vcam.prefs.changed";
static NSString *const VCamImageMediaType = @"public.image";
static NSString *const VCamMovieMediaType = @"public.movie";

@interface VCamViewController : UIViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UILabel *daemonStatusLabel;
@property(nonatomic, strong) UIImageView *previewView;
- (void)applySelectedMediaAtPath:(NSString *)path;
- (void)exportVideoAsset:(AVAsset *)asset;
- (void)importVideoResourceForAsset:(PHAsset *)asset;
- (BOOL)copyPickedVideoAtURL:(NSURL *)sourceURL destination:(NSString **)destination error:(NSError **)error;
@end

@implementation VCamViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"VCam";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"Camera ảo";
    titleLabel.font = [UIFont boldSystemFontOfSize:30.0];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = @"Chọn ảnh hoặc video để thay thế hình ảnh camera.";
    subtitleLabel.font = [UIFont systemFontOfSize:16.0];
    subtitleLabel.textColor = [UIColor secondaryLabelColor];
    subtitleLabel.numberOfLines = 0;

    UILabel *enabledLabel = [[UILabel alloc] init];
    enabledLabel.translatesAutoresizingMaskIntoConstraints = NO;
    enabledLabel.text = @"Bật VCam";
    enabledLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];

    self.enabledSwitch = [[UISwitch alloc] init];
    self.enabledSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];

    UIView *switchRow = [[UIView alloc] init];
    switchRow.translatesAutoresizingMaskIntoConstraints = NO;
    switchRow.backgroundColor = [UIColor secondarySystemBackgroundColor];
    switchRow.layer.cornerRadius = 14.0;
    [switchRow addSubview:enabledLabel];
    [switchRow addSubview:self.enabledSwitch];

    self.previewView = [[UIImageView alloc] init];
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.previewView.contentMode = UIViewContentModeScaleAspectFit;
    self.previewView.layer.cornerRadius = 14.0;
    self.previewView.clipsToBounds = YES;

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:14.0];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;

    self.daemonStatusLabel = [[UILabel alloc] init];
    self.daemonStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.daemonStatusLabel.font = [UIFont boldSystemFontOfSize:14.0];
    self.daemonStatusLabel.textAlignment = NSTextAlignmentCenter;
    self.daemonStatusLabel.numberOfLines = 2;

    UIButton *imageButton = [self actionButtonWithTitle:@"Chọn ảnh" selector:@selector(selectImage)];
    UIButton *videoButton = [self actionButtonWithTitle:@"Chọn video" selector:@selector(selectVideo)];

    UIStackView *buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[imageButton, videoButton]];
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.spacing = 12.0;
    buttonStack.distribution = UIStackViewDistributionFillEqually;

    [self.view addSubview:titleLabel];
    [self.view addSubview:subtitleLabel];
    [self.view addSubview:switchRow];
    [self.view addSubview:self.previewView];
    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.daemonStatusLabel];
    [self.view addSubview:buttonStack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:20.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20.0],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [switchRow.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:20.0],
        [switchRow.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [switchRow.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [switchRow.heightAnchor constraintEqualToConstant:58.0],
        [enabledLabel.centerYAnchor constraintEqualToAnchor:switchRow.centerYAnchor],
        [enabledLabel.leadingAnchor constraintEqualToAnchor:switchRow.leadingAnchor constant:16.0],
        [self.enabledSwitch.centerYAnchor constraintEqualToAnchor:switchRow.centerYAnchor],
        [self.enabledSwitch.trailingAnchor constraintEqualToAnchor:switchRow.trailingAnchor constant:-16.0],

        [self.previewView.topAnchor constraintEqualToAnchor:switchRow.bottomAnchor constant:18.0],
        [self.previewView.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.previewView.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.previewView.heightAnchor constraintEqualToConstant:230.0],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.previewView.bottomAnchor constant:10.0],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [self.daemonStatusLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8.0],
        [self.daemonStatusLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.daemonStatusLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [buttonStack.topAnchor constraintEqualToAnchor:self.daemonStatusLabel.bottomAnchor constant:14.0],
        [buttonStack.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [buttonStack.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [buttonStack.heightAnchor constraintEqualToConstant:50.0]
    ]];

    [self ensureMediaDirectory];
    [self reloadState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadState];
}

- (UIButton *)actionButtonWithTitle:(NSString *)title selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    button.backgroundColor = [UIColor systemBlueColor];
    button.layer.cornerRadius = 12.0;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)ensureMediaDirectory {
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtPath:VCamMediaDirectory
       withIntermediateDirectories:YES
                        attributes:@{NSFilePosixPermissions: @0777}
                             error:nil];
    [manager setAttributes:@{NSFilePosixPermissions: @0777}
              ofItemAtPath:VCamMediaDirectory error:nil];
}

- (NSMutableDictionary *)preferences {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:VCamPreferencesPath];
    return stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)savePreferences:(NSMutableDictionary *)preferences {
    [preferences writeToFile:VCamPreferencesPath atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{
        NSFilePosixPermissions: @0666,
        NSFileProtectionKey: NSFileProtectionNone
    } ofItemAtPath:VCamPreferencesPath error:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)VCamNotificationName, NULL, NULL, YES);
}

- (void)reloadState {
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:VCamPreferencesPath] ?: @{};
    NSNumber *enabled = preferences[@"enabled"];
    self.enabledSwitch.on = enabled == nil ? YES : enabled.boolValue;

    NSString *path = preferences[@"mediaPath"];
    if (![path isKindOfClass:[NSString class]] || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        self.statusLabel.text = @"Chưa chọn ảnh hoặc video";
        self.previewView.image = [UIImage systemImageNamed:@"camera.fill"];
        self.previewView.tintColor = [UIColor tertiaryLabelColor];
    } else {
        NSString *ext = path.pathExtension.lowercaseString;
        if ([@[@"jpg", @"jpeg", @"png"] containsObject:ext]) {
            self.previewView.image = [UIImage imageWithContentsOfFile:path];
            self.previewView.tintColor = nil;
            self.statusLabel.text = [NSString stringWithFormat:@"Đang dùng ảnh: %@", path.lastPathComponent];
        } else {
            self.previewView.image = [UIImage systemImageNamed:@"video.fill"];
            self.previewView.tintColor = [UIColor systemBlueColor];
            self.statusLabel.text = [NSString stringWithFormat:@"Đang dùng video: %@", path.lastPathComponent];
        }
    }

    NSDictionary *daemonStatus = [NSDictionary dictionaryWithContentsOfFile:VCamStatusPath];
    if (daemonStatus) {
        BOOL loaded = [daemonStatus[@"loaded"] boolValue];
        NSString *message = daemonStatus[@"message"] ?: @"Unknown";
        self.daemonStatusLabel.text = [NSString stringWithFormat:@"mediaserverd: %@", message];
        self.daemonStatusLabel.textColor = loaded ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
    } else {
        self.daemonStatusLabel.text = @"mediaserverd: mở Camera rồi quay lại đây để kiểm tra";
        self.daemonStatusLabel.textColor = [UIColor secondaryLabelColor];
    }
}

- (void)enabledChanged:(UISwitch *)sender {
    NSMutableDictionary *preferences = [self preferences];
    preferences[@"enabled"] = @(sender.isOn);
    [self savePreferences:preferences];
    self.statusLabel.text = sender.isOn ? @"VCam đã bật" : @"VCam đã tắt";
}

- (void)selectImage {
    [self presentPickerForMediaType:VCamImageMediaType];
}

- (void)selectVideo {
    [self presentPickerForMediaType:VCamMovieMediaType];
}

- (void)presentPickerForMediaType:(NSString *)mediaType {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [self showMessage:@"Không mở được thư viện ảnh."];
        return;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[mediaType];
    picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    NSString *mediaType = info[UIImagePickerControllerMediaType];

    if ([mediaType isEqualToString:VCamImageMediaType]) {
        NSError *error = nil;
        UIImage *image = info[UIImagePickerControllerOriginalImage];
        NSData *data = UIImageJPEGRepresentation(image, 0.92);
        NSString *destination = [VCamMediaDirectory stringByAppendingPathComponent:@"replacement.jpg"];
        if (!data || ![data writeToFile:destination options:NSDataWritingAtomic error:&error]) {
            destination = nil;
        }
        [picker dismissViewControllerAnimated:YES completion:^{
            if (destination) {
                [self applySelectedMediaAtPath:destination];
            } else {
                [self showMessage:error.localizedDescription ?: @"Không thể nhập ảnh đã chọn."];
            }
        }];
        return;
    }

    if ([mediaType isEqualToString:VCamMovieMediaType]) {
        PHAsset *photoAsset = info[UIImagePickerControllerPHAsset];
        NSURL *fallbackURL = info[UIImagePickerControllerMediaURL];
        NSError *copyError = nil;
        NSString *copiedVideoPath = nil;

        // UIImagePickerController owns mediaURL only while the picker is alive.
        // Copy it before dismissing; exporting it afterwards is what caused the
        // generic "operation could not be completed" error on iOS 15.
        BOOL copied = fallbackURL && [self copyPickedVideoAtURL:fallbackURL
            destination:&copiedVideoPath error:&copyError];
        [picker dismissViewControllerAnimated:YES completion:^{
            self.statusLabel.text = @"Đang nhập video…";
            if (copied) {
                [self applySelectedMediaAtPath:copiedVideoPath];
            } else if (photoAsset) {
                [self importVideoResourceForAsset:photoAsset];
            } else {
                [self showMessage:copyError.localizedDescription ?: @"Không tìm thấy dữ liệu video đã chọn."];
                [self reloadState];
            }
        }];
        return;
    }

    [picker dismissViewControllerAnimated:YES completion:^{
        [self showMessage:@"Định dạng media không được hỗ trợ."];
    }];
}

- (BOOL)copyPickedVideoAtURL:(NSURL *)sourceURL destination:(NSString **)destination error:(NSError **)error {
    [self ensureMediaDirectory];
    NSString *extension = sourceURL.pathExtension.lowercaseString;
    if (![@[@"mp4", @"mov", @"m4v"] containsObject:extension]) extension = @"mov";

    NSString *temporary = [VCamMediaDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"importing.%@", extension]];
    NSString *finalPath = [VCamMediaDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"replacement.%@", extension]];
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtPath:temporary error:nil];

    BOOL scoped = [sourceURL startAccessingSecurityScopedResource];
    BOOL copied = [manager copyItemAtURL:sourceURL
        toURL:[NSURL fileURLWithPath:temporary] error:error];
    if (scoped) [sourceURL stopAccessingSecurityScopedResource];
    if (!copied) return NO;

    [manager removeItemAtPath:finalPath error:nil];
    if (![manager moveItemAtPath:temporary toPath:finalPath error:error]) {
        [manager removeItemAtPath:temporary error:nil];
        return NO;
    }
    if (destination) *destination = finalPath;
    return YES;
}

- (void)importVideoResourceForAsset:(PHAsset *)asset {
    PHAssetResource *selectedResource = nil;
    for (PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]) {
        if (resource.type == PHAssetResourceTypeFullSizeVideo) {
            selectedResource = resource;
            break;
        }
        if (!selectedResource && resource.type == PHAssetResourceTypeVideo) {
            selectedResource = resource;
        }
    }
    if (!selectedResource) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showMessage:@"Không tìm thấy resource video trong Photos."];
            [self reloadState];
        });
        return;
    }

    NSString *extension = selectedResource.originalFilename.pathExtension.lowercaseString;
    if (![@[@"mp4", @"mov", @"m4v"] containsObject:extension]) extension = @"mov";
    NSString *temporary = [VCamMediaDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"importing.%@", extension]];
    NSString *destination = [VCamMediaDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"replacement.%@", extension]];
    [[NSFileManager defaultManager] removeItemAtPath:temporary error:nil];

    PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    [[PHAssetResourceManager defaultManager] writeDataForAssetResource:selectedResource
        toFile:[NSURL fileURLWithPath:temporary]
        options:options
        completionHandler:^(NSError *error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showMessage:error.localizedDescription ?: @"Không thể lấy video gốc từ Photos."];
                    [self reloadState];
                });
                return;
            }
            NSError *moveError = nil;
            NSFileManager *manager = [NSFileManager defaultManager];
            [manager removeItemAtPath:destination error:nil];
            BOOL moved = [manager moveItemAtPath:temporary toPath:destination error:&moveError];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (moved) {
                    [self applySelectedMediaAtPath:destination];
                } else {
                    [self showMessage:moveError.localizedDescription ?: @"Không thể lưu video gốc."];
                    [self reloadState];
                }
            });
        }];
}

- (void)exportVideoAsset:(AVAsset *)asset {
    NSArray<NSString *> *presets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    NSString *preset = [presets containsObject:AVAssetExportPresetPassthrough]
        ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality;
    AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    if (!exporter) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showMessage:@"Không thể tạo phiên nhập video."];
            [self reloadState];
        });
        return;
    }

    NSString *fileType = nil;
    NSString *extension = nil;
    if ([exporter.supportedFileTypes containsObject:AVFileTypeMPEG4]) {
        fileType = AVFileTypeMPEG4;
        extension = @"mp4";
    } else if ([exporter.supportedFileTypes containsObject:AVFileTypeQuickTimeMovie]) {
        fileType = AVFileTypeQuickTimeMovie;
        extension = @"mov";
    }
    if (!fileType) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showMessage:@"Video này không có định dạng xuất tương thích."];
            [self reloadState];
        });
        return;
    }

    NSString *temporary = [VCamMediaDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"exporting.%@", extension]];
    NSString *destination = [VCamMediaDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"replacement.%@", extension]];
    [[NSFileManager defaultManager] removeItemAtPath:temporary error:nil];
    exporter.outputURL = [NSURL fileURLWithPath:temporary];
    exporter.outputFileType = fileType;
    exporter.shouldOptimizeForNetworkUse = YES;

    [exporter exportAsynchronouslyWithCompletionHandler:^{
        if (exporter.status == AVAssetExportSessionStatusCompleted) {
            NSError *moveError = nil;
            NSFileManager *manager = [NSFileManager defaultManager];
            [manager removeItemAtPath:destination error:nil];
            BOOL moved = [manager moveItemAtPath:temporary toPath:destination error:&moveError];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (moved) {
                    [self applySelectedMediaAtPath:destination];
                } else {
                    [self showMessage:moveError.localizedDescription ?: @"Không thể lưu video đã nhập."];
                    [self reloadState];
                }
            });
        } else {
            NSError *exportError = exporter.error;
            [[NSFileManager defaultManager] removeItemAtPath:temporary error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showMessage:exportError.localizedDescription ?: @"Không thể xuất video đã chọn."];
                [self reloadState];
            });
        }
    }];
}

- (void)applySelectedMediaAtPath:(NSString *)destination {
    [[NSFileManager defaultManager] setAttributes:@{
        NSFilePosixPermissions: @0666,
        NSFileProtectionKey: NSFileProtectionNone
    } ofItemAtPath:destination error:nil];
    [self removeOldMediaExcept:destination];
    NSMutableDictionary *preferences = [self preferences];
    preferences[@"enabled"] = @YES;
    preferences[@"mediaPath"] = destination;
    [[NSFileManager defaultManager] removeItemAtPath:VCamStatusPath error:nil];
    [self savePreferences:preferences];
    self.enabledSwitch.on = YES;
    [self reloadState];
    [self showMessage:@"Đã áp dụng. Hãy mở ứng dụng Camera để kiểm tra."];
}

- (void)removeOldMediaExcept:(NSString *)keptPath {
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:VCamMediaDirectory error:nil];
    for (NSString *file in files) {
        NSString *path = [VCamMediaDirectory stringByAppendingPathComponent:file];
        if (![path isEqualToString:keptPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        }
    }
}

- (void)showMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"VCam"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@interface VCamAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation VCamAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    VCamViewController *controller = [[VCamViewController alloc] init];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:controller];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([VCamAppDelegate class]));
    }
}
