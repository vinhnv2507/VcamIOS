#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import "../VCamPaths.h"
#include <math.h>
#include <spawn.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

extern char **environ;

#define VCamPreferencesPath VCamPreferencesFile()
#define VCamStatusPath VCamStatusFile()
static NSString *const VCamNotificationName = @"com.yourcompany.vcam.prefs.changed";
static NSString *const VCamImageMediaType = @"public.image";
static NSString *const VCamMovieMediaType = @"public.movie";
static NSString *const VCamImportDiagnosticPath = @"/private/var/tmp/com.yourcompany.vcam.import.plist";

static void VCamWriteImportStage(NSString *stage) {
    if (!stage) return;
    [@{ @"stage": stage, @"timestamp": [NSDate date] }
        writeToFile:VCamImportDiagnosticPath atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{
        NSFilePosixPermissions: @0666, NSFileProtectionKey: NSFileProtectionNone
    } ofItemAtPath:VCamImportDiagnosticPath error:nil];
}

static NSString *VCamDescribeError(NSError *error) {
    if (!error) return @"Lỗi không xác định.";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSError *current = error;
    for (NSInteger depth = 0; current && depth < 4; depth++) {
        NSString *part = [NSString stringWithFormat:@"%@ (%@/%ld)",
            current.localizedDescription ?: @"Lỗi", current.domain, (long)current.code];
        NSString *reason = current.localizedFailureReason;
        if (reason.length > 0) part = [part stringByAppendingFormat:@": %@", reason];
        [parts addObject:part];
        NSError *underlying = current.userInfo[NSUnderlyingErrorKey];
        current = [underlying isKindOfClass:[NSError class]] ? underlying : nil;
    }
    return [parts componentsJoinedByString:@"\n↳ "];
}

typedef void (^VCamVideoSelectionHandler)(PHAsset *asset);

@interface VCamVideoPickerController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) PHFetchResult<PHAsset *> *assets;
@property(nonatomic, strong) PHCachingImageManager *imageManager;
@property(nonatomic, copy) VCamVideoSelectionHandler selectionHandler;
@end

@implementation VCamVideoPickerController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Chọn video";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];

    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    self.assets = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeVideo options:options];
    self.imageManager = [[PHCachingImageManager alloc] init];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 82.0;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.tableView];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.assets.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"VCamVideoCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
        cell.imageView.clipsToBounds = YES;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    PHAsset *asset = self.assets[(NSUInteger)indexPath.row];
    cell.tag = indexPath.row;
    NSInteger totalSeconds = MAX(0, (NSInteger)llround(asset.duration));
    cell.textLabel.text = [NSString stringWithFormat:@"Video %ld", (long)indexPath.row + 1];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld:%02ld  •  %ld×%ld",
        (long)(totalSeconds / 60), (long)(totalSeconds % 60),
        (long)asset.pixelWidth, (long)asset.pixelHeight];
    cell.imageView.image = nil;

    CGFloat scale = [UIScreen mainScreen].scale;
    PHImageRequestOptions *requestOptions = [[PHImageRequestOptions alloc] init];
    requestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;
    requestOptions.resizeMode = PHImageRequestOptionsResizeModeFast;
    [self.imageManager requestImageForAsset:asset
        targetSize:CGSizeMake(112.0 * scale, 72.0 * scale)
        contentMode:PHImageContentModeAspectFill
        options:requestOptions
        resultHandler:^(UIImage *result, NSDictionary *info) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UITableViewCell *visibleCell = [tableView cellForRowAtIndexPath:indexPath];
                if (visibleCell && visibleCell.tag == indexPath.row) visibleCell.imageView.image = result;
            });
        }];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PHAsset *asset = self.assets[(NSUInteger)indexPath.row];
    VCamVideoSelectionHandler handler = self.selectionHandler;
    tableView.userInteractionEnabled = NO;
    [self dismissViewControllerAnimated:YES completion:^{
        if (handler) handler(asset);
    }];
}

@end

@interface VCamViewController : UIViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UILabel *daemonStatusLabel;
@property(nonatomic, strong) UIImageView *previewView;
@property(nonatomic, strong) AVAssetImageGenerator *videoGenerator;
- (BOOL)prepareSharedStorage:(NSError **)error;
- (void)applySelectedMediaAtPath:(NSString *)path;
- (void)prepareVideoFramesAtPath:(NSString *)path;
- (void)prepareVideoFramesWithFFmpegAtPath:(NSString *)path;
- (void)prepareVideoFramesForAsset:(AVAsset *)asset;
- (void)requestVideoAsset:(PHAsset *)photoAsset;
- (void)presentPhotoKitVideoPicker;
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

    [self prepareSharedStorage:nil];
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

- (BOOL)prepareSharedStorage:(NSError **)error {
    NSString *probe = VCamMediaFile(@"probe");
    BOOL writable = [[NSData dataWithBytes:"V" length:1] writeToFile:probe options:0 error:error];
    if (writable) [[NSFileManager defaultManager] removeItemAtPath:probe error:nil];
    return writable;
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

    NSDictionary *diagnostic = [NSDictionary dictionaryWithContentsOfFile:VCamImportDiagnosticPath];
    NSDate *diagnosticDate = diagnostic[@"timestamp"];
    NSString *diagnosticStage = diagnostic[@"stage"];
    if ([diagnosticDate isKindOfClass:[NSDate class]] &&
        [diagnosticStage isKindOfClass:[NSString class]] &&
        -diagnosticDate.timeIntervalSinceNow < 600.0) {
        self.statusLabel.text = [NSString stringWithFormat:@"Lần nhập video dừng ở: %@", diagnosticStage];
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
    NSError *storageError = nil;
    if (![self prepareSharedStorage:&storageError]) {
        [self showMessage:storageError.localizedDescription ?: @"Không thể mở bộ nhớ dùng chung của VCam."];
        return;
    }

    void (^continueWithAccess)(PHAuthorizationStatus) = ^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
                [self presentPhotoKitVideoPicker];
            } else {
                [self showMessage:@"VCam cần quyền đọc Ảnh. Hãy vào Cài đặt > VCam > Ảnh và chọn Tất cả ảnh."];
            }
        });
    };

    if (@available(iOS 14, *)) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:continueWithAccess];
        } else {
            continueWithAccess(status);
        }
    } else {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorization:continueWithAccess];
        } else {
            continueWithAccess(status);
        }
    }
}

- (void)presentPhotoKitVideoPicker {
    VCamVideoPickerController *picker = [[VCamVideoPickerController alloc] init];
    __weak typeof(self) weakSelf = self;
    picker.selectionHandler = ^(PHAsset *asset) {
        [weakSelf requestVideoAsset:asset];
    };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:picker];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)requestVideoAsset:(PHAsset *)photoAsset {
    if (!photoAsset) return;
    VCamWriteImportStage(@"Bắt đầu sao chép resource Photos");
    self.statusLabel.text = @"Đang sao chép video an toàn từ Photos…";
    [self importVideoResourceForAsset:photoAsset];
}

- (void)presentPickerForMediaType:(NSString *)mediaType {
    NSError *storageError = nil;
    if (![self prepareSharedStorage:&storageError]) {
        [self showMessage:storageError.localizedDescription ?: @"Không thể mở bộ nhớ dùng chung của VCam."];
        return;
    }
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [self showMessage:@"Không mở được thư viện ảnh."];
        return;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[mediaType];
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
        NSString *destination = VCamMediaFile(@"jpg");
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
        if (fallbackURL) {
            // Keep the picker alive while its temporary URL is being read.
            // A background stream avoids FileManager's destination-directory
            // permission check and does not freeze the UI for large videos.
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSError *copyError = nil;
                NSString *copiedVideoPath = nil;
                BOOL copied = [self copyPickedVideoAtURL:fallbackURL
                    destination:&copiedVideoPath error:&copyError];
                dispatch_async(dispatch_get_main_queue(), ^{
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
                });
            });
        } else {
            [picker dismissViewControllerAnimated:YES completion:^{
                self.statusLabel.text = @"Đang nhập video…";
                if (photoAsset) {
                    [self importVideoResourceForAsset:photoAsset];
                } else {
                    [self showMessage:@"Không tìm thấy dữ liệu video đã chọn."];
                    [self reloadState];
                }
            }];
        }
        return;
    }

    [picker dismissViewControllerAnimated:YES completion:^{
        [self showMessage:@"Định dạng media không được hỗ trợ."];
    }];
}

- (BOOL)copyPickedVideoAtURL:(NSURL *)sourceURL destination:(NSString **)destination error:(NSError **)error {
    NSString *extension = sourceURL.pathExtension.lowercaseString;
    if (![@[@"mp4", @"mov", @"m4v"] containsObject:extension]) extension = @"mov";

    NSString *finalPath = VCamMediaFile(extension);
    NSFileManager *manager = [NSFileManager defaultManager];

    BOOL scoped = [sourceURL startAccessingSecurityScopedResource];
    NSInputStream *input = [NSInputStream inputStreamWithURL:sourceURL];
    NSOutputStream *output = [NSOutputStream outputStreamToFileAtPath:finalPath append:NO];
    [input open];
    [output open];

    uint8_t buffer[64 * 1024];
    BOOL copied = YES;
    unsigned long long totalBytes = 0;
    while (copied) {
        NSInteger bytesRead = [input read:buffer maxLength:sizeof(buffer)];
        if (bytesRead == 0) break;
        if (bytesRead < 0) {
            copied = NO;
            break;
        }
        NSInteger offset = 0;
        while (offset < bytesRead) {
            NSInteger bytesWritten = [output write:buffer + offset maxLength:(NSUInteger)(bytesRead - offset)];
            if (bytesWritten <= 0) {
                copied = NO;
                break;
            }
            offset += bytesWritten;
            totalBytes += (unsigned long long)bytesWritten;
        }
    }
    NSError *streamError = input.streamError ?: output.streamError;
    [input close];
    [output close];
    if (scoped) [sourceURL stopAccessingSecurityScopedResource];
    if (!copied || totalBytes == 0) {
        [manager removeItemAtPath:finalPath error:nil];
        if (error) *error = streamError ?: [NSError errorWithDomain:@"VCamVideoImport"
            code:1 userInfo:@{NSLocalizedDescriptionKey: totalBytes == 0
                ? @"Photos trả về file video rỗng hoặc không cho phép đọc."
                : @"Không thể đọc hoặc ghi dữ liệu video đã chọn."}];
        return NO;
    }

    if (destination) *destination = finalPath;
    return YES;
}

- (void)importVideoResourceForAsset:(PHAsset *)asset {
    PHAssetResource *selectedResource = nil;
    for (PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]) {
        // Prefer the original video resource. FullSizeVideo can represent an
        // adjusted derivative whose private codec/composition fails with
        // OSStatus -12437 on iOS 15.
        if (resource.type == PHAssetResourceTypeVideo) {
            selectedResource = resource;
            break;
        }
        if (!selectedResource && resource.type == PHAssetResourceTypeFullSizeVideo) {
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
    if (![@[@"mp4", @"mov", @"m4v", @"3gp", @"3gpp"] containsObject:extension]) extension = @"mov";
    NSString *destination = VCamMediaFile(extension);

    PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.progressHandler = ^(double progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = [NSString stringWithFormat:@"Đang sao chép video… %ld%%",
                (long)llround(progress * 100.0)];
        });
    };
    VCamWriteImportStage(@"Photos đang ghi file cục bộ");
    [[PHAssetResourceManager defaultManager] writeDataForAssetResource:selectedResource
        toFile:[NSURL fileURLWithPath:destination]
        options:options
        completionHandler:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSNumber *fileSize = [[[NSFileManager defaultManager]
                    attributesOfItemAtPath:destination error:nil] objectForKey:NSFileSize];
                if (!error && fileSize.unsignedLongLongValue > 0) {
                    [[NSFileManager defaultManager] setAttributes:@{
                        NSFilePosixPermissions: @0666,
                        NSFileProtectionKey: NSFileProtectionNone
                    } ofItemAtPath:destination error:nil];
                    VCamWriteImportStage(@"Đã sao chép video thành file cục bộ");
                    [self prepareVideoFramesWithFFmpegAtPath:destination];
                } else {
                    [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
                    NSString *detail = error ? VCamDescribeError(error) : @"Photos đã tạo file video rỗng.";
                    [self showMessage:detail];
                    [self reloadState];
                }
            });
        }];
}

- (void)exportVideoAsset:(AVAsset *)asset {
    NSArray<NSString *> *presets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    NSString *preset = nil;
    if ([presets containsObject:AVAssetExportPreset640x480]) {
        preset = AVAssetExportPreset640x480;
    } else if ([presets containsObject:AVAssetExportPresetMediumQuality]) {
        preset = AVAssetExportPresetMediumQuality;
    } else if ([presets containsObject:AVAssetExportPresetLowQuality]) {
        preset = AVAssetExportPresetLowQuality;
    }
    if (!preset) {
        [self showMessage:@"Video không hỗ trợ preset chuyển mã tương thích trên iOS 15."];
        [self reloadState];
        return;
    }
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

    NSString *temporary = VCamMediaFile([NSString stringWithFormat:@"exporting.%@", extension]);
    NSString *destination = VCamMediaFile(extension);
    [[NSFileManager defaultManager] removeItemAtPath:temporary error:nil];
    exporter.outputURL = [NSURL fileURLWithPath:temporary];
    exporter.outputFileType = fileType;
    exporter.shouldOptimizeForNetworkUse = YES;
    double exportDuration = CMTimeGetSeconds(asset.duration);
    if (isfinite(exportDuration) && exportDuration > 15.0) {
        exporter.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(15.0, 600));
    }
    VCamWriteImportStage(@"Đang chuyển mã video tương thích");
    self.statusLabel.text = @"Đang chuyển video sang định dạng tương thích…";

    [exporter exportAsynchronouslyWithCompletionHandler:^{
        if (exporter.status == AVAssetExportSessionStatusCompleted) {
            NSError *moveError = nil;
            NSFileManager *manager = [NSFileManager defaultManager];
            [manager removeItemAtPath:destination error:nil];
            BOOL moved = [manager moveItemAtPath:temporary toPath:destination error:&moveError];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (moved) {
                    [[NSFileManager defaultManager] setAttributes:@{
                        NSFilePosixPermissions: @0666,
                        NSFileProtectionKey: NSFileProtectionNone
                    } ofItemAtPath:destination error:nil];
                    if ([asset isKindOfClass:[AVURLAsset class]]) {
                        NSString *sourcePath = ((AVURLAsset *)asset).URL.path;
                        if ([sourcePath hasPrefix:VCamSharedDirectory()] &&
                            ![sourcePath isEqualToString:destination]) {
                            [manager removeItemAtPath:sourcePath error:nil];
                        }
                    }
                    VCamWriteImportStage(@"Đã chuyển mã video tương thích");
                    [self applySelectedMediaAtPath:destination];
                } else {
                    [self showMessage:moveError ? VCamDescribeError(moveError) : @"Không thể lưu video đã nhập."];
                    [self reloadState];
                }
            });
        } else {
            NSError *exportError = exporter.error;
            [[NSFileManager defaultManager] removeItemAtPath:temporary error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                VCamWriteImportStage(exportError ? [NSString stringWithFormat:@"Chuyển mã lỗi %@/%ld",
                    exportError.domain, (long)exportError.code] : @"Chuyển mã video thất bại");
                [self showMessage:exportError ? VCamDescribeError(exportError) : @"Không thể chuyển mã video đã chọn."];
                [self reloadState];
            });
        }
    }];
}

- (void)applySelectedMediaAtPath:(NSString *)destination {
    NSString *extension = destination.pathExtension.lowercaseString;
    if ([@[@"mov", @"mp4", @"m4v", @"3gp", @"3gpp"] containsObject:extension]) {
        [self prepareVideoFramesWithFFmpegAtPath:destination];
        return;
    }

    BOOL isDirectory = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:destination isDirectory:&isDirectory];
    [[NSFileManager defaultManager] setAttributes:@{
        NSFilePosixPermissions: isDirectory ? @0755 : @0666,
        NSFileProtectionKey: NSFileProtectionNone
    } ofItemAtPath:destination error:nil];
    [self removeOldMediaExcept:destination];
    NSMutableDictionary *preferences = [self preferences];
    preferences[@"enabled"] = @YES;
    preferences[@"mediaPath"] = destination;
    if ([extension isEqualToString:@"vcamframes"]) {
        [[NSFileManager defaultManager] removeItemAtPath:VCamImportDiagnosticPath error:nil];
    }
    [[NSFileManager defaultManager] removeItemAtPath:VCamStatusPath error:nil];
    [self savePreferences:preferences];
    self.enabledSwitch.on = YES;
    [self reloadState];
    [self showMessage:@"Đã áp dụng. Hãy mở ứng dụng Camera để kiểm tra."];
}

- (void)prepareVideoFramesAtPath:(NSString *)path {
    AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:path]];
    [self prepareVideoFramesForAsset:asset];
}

- (void)prepareVideoFramesWithFFmpegAtPath:(NSString *)path {
    if (path.length == 0) return;
    self.statusLabel.text = @"Đang giải mã video bằng FFmpeg…";
    VCamWriteImportStage(@"Bắt đầu FFmpeg");

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSString *> *candidatePaths = @[
            @"/var/jb/usr/bin/ffmpeg",
            @"/usr/bin/ffmpeg",
            @"/usr/local/bin/ffmpeg"
        ];
        NSString *ffmpegPath = nil;
        for (NSString *candidate in candidatePaths) {
            if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
                ffmpegPath = candidate;
                break;
            }
        }

        if (!ffmpegPath) {
            dispatch_async(dispatch_get_main_queue(), ^{
                VCamWriteImportStage(@"Không tìm thấy FFmpeg");
                [self showMessage:@"Không tìm thấy FFmpeg. Hãy Refresh nguồn và cài lại VCam để Sileo cài dependency ffmpeg."];
                [self reloadState];
            });
            return;
        }

        NSString *frameDirectory = VCamMediaFile(@"vcamframes");
        NSError *directoryError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:frameDirectory
            withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @0755}
            error:&directoryError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showMessage:VCamDescribeError(directoryError)];
                [self reloadState];
            });
            return;
        }

        NSString *outputPattern = [frameDirectory stringByAppendingPathComponent:@"frame-%05d.jpg"];
        NSString *logPath = VCamMediaFile(@"ffmpeg.log");
        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, logPath.fileSystemRepresentation,
            O_WRONLY | O_CREAT | O_TRUNC, 0644);
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, logPath.fileSystemRepresentation,
            O_WRONLY | O_CREAT | O_TRUNC, 0644);

        const char *executable = ffmpegPath.fileSystemRepresentation;
        const char *input = path.fileSystemRepresentation;
        const char *output = outputPattern.fileSystemRepresentation;
        char *const arguments[] = {
            (char *)executable,
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-threads", "1", "-i", (char *)input,
            "-t", "15", "-map", "0:v:0", "-an", "-sn",
            "-vf", "fps=6,scale=960:960:force_original_aspect_ratio=decrease",
            "-frames:v", "90", "-q:v", "4", (char *)output,
            NULL
        };

        pid_t processID = 0;
        int spawnResult = posix_spawn(&processID, executable, &actions, NULL, arguments, environ);
        posix_spawn_file_actions_destroy(&actions);
        int processStatus = 0;
        if (spawnResult == 0) {
            VCamWriteImportStage(@"FFmpeg đang chạy");
            while (waitpid(processID, &processStatus, 0) == -1 && errno == EINTR) {}
        }

        NSArray<NSString *> *files = [[NSFileManager defaultManager]
            contentsOfDirectoryAtPath:frameDirectory error:nil];
        NSPredicate *jpegPredicate = [NSPredicate predicateWithBlock:^BOOL(NSString *file, NSDictionary *bindings) {
            return [file.pathExtension.lowercaseString isEqualToString:@"jpg"];
        }];
        NSArray<NSString *> *frames = [files filteredArrayUsingPredicate:jpegPredicate];
        BOOL exitedSuccessfully = spawnResult == 0 && WIFEXITED(processStatus) && WEXITSTATUS(processStatus) == 0;

        if (exitedSuccessfully && frames.count > 0) {
            for (NSString *file in frames) {
                NSString *framePath = [frameDirectory stringByAppendingPathComponent:file];
                [[NSFileManager defaultManager] setAttributes:@{
                    NSFilePosixPermissions: @0644,
                    NSFileProtectionKey: NSFileProtectionNone
                } ofItemAtPath:framePath error:nil];
            }
            VCamWriteImportStage([NSString stringWithFormat:@"FFmpeg đã tạo %lu frame",
                (unsigned long)frames.count]);
            [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self applySelectedMediaAtPath:frameDirectory];
            });
            return;
        }

        NSString *log = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
        if (log.length > 1200) log = [log substringFromIndex:log.length - 1200];
        NSString *detail = nil;
        if (spawnResult != 0) {
            detail = [NSString stringWithFormat:@"Không chạy được FFmpeg (posix_spawn=%d).", spawnResult];
        } else {
            detail = [NSString stringWithFormat:@"FFmpeg dừng với mã %d. %@",
                WIFEXITED(processStatus) ? WEXITSTATUS(processStatus) : -1,
                log.length ? log : @"Không có log lỗi."];
        }
        [[NSFileManager defaultManager] removeItemAtPath:frameDirectory error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
        VCamWriteImportStage(@"FFmpeg xử lý thất bại");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showMessage:detail];
            [self reloadState];
        });
    });
}

- (void)prepareVideoFramesForAsset:(AVAsset *)asset {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self prepareVideoFramesForAsset:asset];
        });
        return;
    }
    if (!asset) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showMessage:@"Không nhận được dữ liệu video từ Photos."];
            [self reloadState];
        });
        return;
    }
    VCamWriteImportStage(@"Bắt đầu chuẩn bị frame");
    [self.videoGenerator cancelAllCGImageGeneration];
    self.statusLabel.text = @"Đang chuẩn bị video an toàn cho Camera…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        double duration = CMTimeGetSeconds(asset.duration);
        NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (!isfinite(duration) || duration <= 0.0 || tracks.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showMessage:@"Video không có track hình ảnh hợp lệ."];
                [self reloadState];
            });
            return;
        }

        // Keep processing bounded for the A10 memory/thermal budget. PhotoKit
        // already provided a valid AVAsset, so AVAssetImageGenerator can ask
        // AVFoundation for a <= 960 px CGImage without exposing a 4K YUV/BGRA
        // decoder buffer to this process.
        double preparedDuration = MIN(duration, 15.0);
        NSInteger frameCount = MAX(1, (NSInteger)ceil(preparedDuration * 6.0));

        NSString *frameDirectory = VCamMediaFile(@"vcamframes");
        NSError *directoryError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:frameDirectory
            withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @0755}
            error:&directoryError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showMessage:directoryError.localizedDescription ?: @"Không tạo được thư mục frame video."];
            });
            return;
        }

        @try {
        AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        generator.appliesPreferredTrackTransform = YES;
        generator.maximumSize = CGSizeMake(960.0, 960.0);
        generator.requestedTimeToleranceBefore = CMTimeMake(1, 12);
        generator.requestedTimeToleranceAfter = CMTimeMake(1, 12);
        self.videoGenerator = generator;
        VCamWriteImportStage(@"Bộ tạo ảnh đã bắt đầu");

        NSInteger saved = 0;
        NSError *lastError = nil;
        NSInteger consecutiveErrors = 0;
        for (NSInteger index = 0; index < frameCount; index++) {
            @autoreleasepool {
                if (index == 0) VCamWriteImportStage(@"Đang trích frame đầu tiên");
                NSError *frameError = nil;
                CMTime requestedTime = CMTimeMakeWithSeconds((double)index / 6.0, 600);
                CGImageRef image = [generator copyCGImageAtTime:requestedTime
                    actualTime:NULL error:&frameError];
                if (image) {
                    NSString *frameName = [NSString stringWithFormat:@"frame-%05ld.jpg", (long)saved];
                    NSString *framePath = [frameDirectory stringByAppendingPathComponent:frameName];
                    NSData *jpeg = UIImageJPEGRepresentation([UIImage imageWithCGImage:image], 0.82);
                    NSError *frameWriteError = nil;
                    if ([jpeg writeToFile:framePath options:0 error:&frameWriteError]) {
                        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644,
                            NSFileProtectionKey: NSFileProtectionNone} ofItemAtPath:framePath error:nil];
                        saved++;
                        if (saved == 1 || (saved % 30) == 0) {
                            VCamWriteImportStage([NSString stringWithFormat:@"Đã lưu %ld frame", (long)saved]);
                        }
                        consecutiveErrors = 0;
                    } else if (frameWriteError) {
                        lastError = frameWriteError;
                        consecutiveErrors++;
                    }
                    CGImageRelease(image);
                } else {
                    if (frameError) lastError = frameError;
                    consecutiveErrors++;
                }

                if ((index % 6) == 0 || index == frameCount - 1) {
                    NSInteger progress = (NSInteger)llround(((double)(index + 1) / (double)frameCount) * 100.0);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.statusLabel.text = [NSString stringWithFormat:@"Đang chuẩn bị video… %ld%%", (long)progress];
                    });
                }
                if (consecutiveErrors >= 6) break;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.videoGenerator = nil;
            if (saved > 0) {
                [self applySelectedMediaAtPath:frameDirectory];
            } else {
                [[NSFileManager defaultManager] removeItemAtPath:frameDirectory error:nil];
                NSString *detail = lastError ? VCamDescribeError(lastError)
                    : @"Không trích xuất được frame từ video.";
                VCamWriteImportStage(lastError ? [NSString stringWithFormat:@"Frame lỗi %@/%ld",
                    lastError.domain, (long)lastError.code] : @"Không tạo được frame");
                [self showMessage:detail];
                [self reloadState];
            }
        });
        } @catch (NSException *exception) {
            [self.videoGenerator cancelAllCGImageGeneration];
            [[NSFileManager defaultManager] removeItemAtPath:frameDirectory error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.videoGenerator = nil;
                NSString *detail = [NSString stringWithFormat:@"%@ (%@)",
                    exception.reason ?: @"Không thể giải mã video.", exception.name];
                [self showMessage:detail];
                [self reloadState];
            });
        }
    });
}

- (void)removeOldMediaExcept:(NSString *)keptPath {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [manager contentsOfDirectoryAtPath:VCamSharedDirectory() error:nil];
    for (NSString *file in files) {
        NSString *path = [VCamSharedDirectory() stringByAppendingPathComponent:file];
        BOOL isMedia = [file hasPrefix:@"media-"] || [file hasPrefix:@"com.yourcompany.vcam.media"];
        if (isMedia && ![path isEqualToString:keptPath]) {
            [manager removeItemAtPath:path error:nil];
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
