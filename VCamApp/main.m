#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import "../VCamPaths.h"
#include <math.h>

#define VCamPreferencesPath VCamPreferencesFile()
#define VCamStatusPath VCamStatusFile()
static NSString *const VCamNotificationName = @"com.yourcompany.vcam.prefs.changed";
static NSString *const VCamImageMediaType = @"public.image";
static NSString *const VCamMovieMediaType = @"public.movie";

@interface VCamViewController : UIViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate>
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UILabel *daemonStatusLabel;
@property(nonatomic, strong) UIImageView *previewView;
@property(nonatomic, strong) AVAssetReader *videoReader;
- (BOOL)prepareSharedStorage:(NSError **)error;
- (void)applySelectedMediaAtPath:(NSString *)path;
- (void)prepareVideoFramesAtPath:(NSString *)path;
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
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc]
        initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
    configuration.filter = [PHPickerFilter videosFilter];
    configuration.selectionLimit = 1;
    // Ask Photos for an iOS-compatible representation (typically H.264) so
    // the older A10 decoder does not have to open an unsupported source codec.
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCompatible;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
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
    picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;

    NSItemProvider *provider = result.itemProvider;
    if (![provider hasItemConformingToTypeIdentifier:VCamMovieMediaType]) {
        [self showMessage:@"Video đã chọn không có định dạng mà VCam có thể đọc."];
        return;
    }

    self.statusLabel.text = @"Đang nhập video…";
    NSString *assetIdentifier = result.assetIdentifier;
    [provider loadFileRepresentationForTypeIdentifier:VCamMovieMediaType
        completionHandler:^(NSURL *url, NSError *fileError) {
            NSError *copyError = nil;
            NSString *destination = nil;
            BOOL copied = url && [self copyPickedVideoAtURL:url destination:&destination error:&copyError];
            if (copied) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self applySelectedMediaAtPath:destination];
                });
                return;
            }

            // Never request the whole movie as NSData: a large MOV can exceed
            // the iPhone 7 memory limit and iOS kills VCam immediately. Prefer
            // Photos' streaming resource API when the picker exposes an asset.
            if (assetIdentifier.length > 0) {
                PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithLocalIdentifiers:
                    @[assetIdentifier] options:nil];
                PHAsset *asset = assets.firstObject;
                if (asset) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self importVideoResourceForAsset:asset];
                    });
                    return;
                }
            }

            // Last low-memory fallback: request an in-place URL and stream it
            // to /private/var/tmp instead of materialising the movie in RAM.
            [provider loadInPlaceFileRepresentationForTypeIdentifier:VCamMovieMediaType
                completionHandler:^(NSURL *inPlaceURL, BOOL isInPlace, NSError *inPlaceError) {
                    NSError *streamError = nil;
                    NSString *streamedPath = nil;
                    BOOL streamed = inPlaceURL && [self copyPickedVideoAtURL:inPlaceURL
                        destination:&streamedPath error:&streamError];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (streamed) {
                            [self applySelectedMediaAtPath:streamedPath];
                        } else {
                            NSError *finalError = streamError ?: inPlaceError ?: copyError ?: fileError;
                            NSString *detail = finalError ? [NSString stringWithFormat:@"%@ (%@/%ld)",
                                finalError.localizedDescription, finalError.domain, (long)finalError.code]
                                : @"Photos không cấp quyền đọc video.";
                            [self showMessage:detail];
                            [self reloadState];
                        }
                    });
                }];
        }];
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
    NSString *destination = VCamMediaFile(extension);
    NSOutputStream *output = [NSOutputStream outputStreamToFileAtPath:destination append:NO];
    [output open];
    __block NSError *writeError = nil;

    PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    [[PHAssetResourceManager defaultManager] requestDataForAssetResource:selectedResource
        options:options
        dataReceivedHandler:^(NSData *data) {
            if (writeError || data.length == 0) return;
            const uint8_t *bytes = data.bytes;
            NSInteger remaining = (NSInteger)data.length;
            while (remaining > 0) {
                NSInteger written = [output write:bytes maxLength:(NSUInteger)remaining];
                if (written <= 0) {
                    writeError = output.streamError ?: [NSError errorWithDomain:@"VCamVideoImport"
                        code:2 userInfo:@{NSLocalizedDescriptionKey: @"Không thể ghi dữ liệu video vào bộ nhớ dùng chung."}];
                    return;
                }
                bytes += written;
                remaining -= written;
            }
        }
        completionHandler:^(NSError *error) {
            [output close];
            NSError *finalError = error ?: writeError;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!finalError) {
                    [self applySelectedMediaAtPath:destination];
                } else {
                    [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
                    [self showMessage:finalError.localizedDescription ?: @"Không thể lấy dữ liệu video từ Photos."];
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

    NSString *temporary = VCamMediaFile([NSString stringWithFormat:@"exporting.%@", extension]);
    NSString *destination = VCamMediaFile(extension);
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
    NSString *extension = destination.pathExtension.lowercaseString;
    if ([@[@"mov", @"mp4", @"m4v"] containsObject:extension]) {
        [self prepareVideoFramesAtPath:destination];
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
    [[NSFileManager defaultManager] removeItemAtPath:VCamStatusPath error:nil];
    [self savePreferences:preferences];
    self.enabledSwitch.on = YES;
    [self reloadState];
    [self showMessage:@"Đã áp dụng. Hãy mở ứng dụng Camera để kiểm tra."];
}

- (void)prepareVideoFramesAtPath:(NSString *)path {
    [self.videoReader cancelReading];
    self.statusLabel.text = @"Đang chuẩn bị video an toàn cho Camera…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:path]];
        double duration = CMTimeGetSeconds(asset.duration);
        NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (!isfinite(duration) || duration <= 0.0 || tracks.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showMessage:@"Video không có track hình ảnh hợp lệ."];
                [self reloadState];
            });
            return;
        }

        // Decode sequentially instead of issuing many random AVAssetImageGenerator
        // seeks. The latter can remain pending forever for some HEVC/MOV assets on
        // iOS 15. Keep the first 20 seconds at 6 fps for bounded RAM and disk use.
        double preparedDuration = MIN(duration, 20.0);
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
        AVAssetTrack *track = tracks.firstObject;
        CGSize naturalSize = track.naturalSize;
        CGAffineTransform preferredTransform = track.preferredTransform;
        CGRect sourceRect = CGRectMake(0, 0, naturalSize.width, naturalSize.height);
        CGRect orientedRect = CGRectApplyAffineTransform(sourceRect, preferredTransform);
        CGFloat orientedWidth = fabs(CGRectGetWidth(orientedRect));
        CGFloat orientedHeight = fabs(CGRectGetHeight(orientedRect));
        CGFloat largestSide = MAX(orientedWidth, orientedHeight);
        CGFloat outputScale = largestSide > 960.0 ? 960.0 / largestSide : 1.0;

        CGAffineTransform normalizedTransform = CGAffineTransformConcat(preferredTransform,
            CGAffineTransformMakeTranslation(-CGRectGetMinX(orientedRect), -CGRectGetMinY(orientedRect)));
        normalizedTransform = CGAffineTransformConcat(normalizedTransform,
            CGAffineTransformMakeScale(outputScale, outputScale));

        AVMutableVideoComposition *composition = [AVMutableVideoComposition videoComposition];
        composition.frameDuration = CMTimeMake(1, 6);
        composition.renderSize = CGSizeMake(MAX(2.0, floor(orientedWidth * outputScale)),
                                             MAX(2.0, floor(orientedHeight * outputScale)));
        AVMutableVideoCompositionInstruction *instruction =
            [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
        AVMutableVideoCompositionLayerInstruction *layerInstruction =
            [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
        [layerInstruction setTransform:normalizedTransform atTime:kCMTimeZero];
        instruction.layerInstructions = @[layerInstruction];
        composition.instructions = @[instruction];

        NSError *readerError = nil;
        AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&readerError];
        NSDictionary *outputSettings = @{
            (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
        };
        AVAssetReaderVideoCompositionOutput *output = [[AVAssetReaderVideoCompositionOutput alloc]
            initWithVideoTracks:@[track] videoSettings:outputSettings];
        output.videoComposition = composition;
        output.alwaysCopiesSampleData = NO;
        if (!reader || ![reader canAddOutput:output]) {
            [[NSFileManager defaultManager] removeItemAtPath:frameDirectory error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *detail = readerError ? [NSString stringWithFormat:@"%@ (%@/%ld)",
                    readerError.localizedDescription, readerError.domain, (long)readerError.code]
                    : @"Không thể tạo bộ giải mã video.";
                [self showMessage:detail];
                [self reloadState];
            });
            return;
        }
        [reader addOutput:output];
        reader.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(preparedDuration, 600));
        self.videoReader = reader;
        if (![reader startReading]) {
            NSError *startError = reader.error;
            [[NSFileManager defaultManager] removeItemAtPath:frameDirectory error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.videoReader = nil;
                NSString *detail = startError ? [NSString stringWithFormat:@"%@ (%@/%ld)",
                    startError.localizedDescription, startError.domain, (long)startError.code]
                    : @"Không thể bắt đầu giải mã video.";
                [self showMessage:detail];
                [self reloadState];
            });
            return;
        }

        NSInteger saved = 0;
        NSError *lastError = nil;
        CIContext *imageContext = [CIContext contextWithOptions:nil];
        while (saved < frameCount) {
            @autoreleasepool {
                CMSampleBufferRef sample = [output copyNextSampleBuffer];
                if (!sample) break;
                CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sample);
                CGImageRef image = NULL;
                if (pixelBuffer) {
                    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
                    image = [imageContext createCGImage:ciImage fromRect:ciImage.extent];
                }
                if (image) {
                    NSString *frameName = [NSString stringWithFormat:@"frame-%05ld.jpg", (long)saved];
                    NSString *framePath = [frameDirectory stringByAppendingPathComponent:frameName];
                    NSData *jpeg = UIImageJPEGRepresentation([UIImage imageWithCGImage:image], 0.82);
                    NSError *frameWriteError = nil;
                    if ([jpeg writeToFile:framePath options:0 error:&frameWriteError]) {
                        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644,
                            NSFileProtectionKey: NSFileProtectionNone} ofItemAtPath:framePath error:nil];
                        saved++;
                    } else if (frameWriteError) {
                        lastError = frameWriteError;
                    }
                    CGImageRelease(image);
                }
                CFRelease(sample);

                if ((saved % 6) == 0 || saved == frameCount) {
                    NSInteger progress = (NSInteger)llround(((double)saved / (double)frameCount) * 100.0);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.statusLabel.text = [NSString stringWithFormat:@"Đang chuẩn bị video… %ld%%", (long)progress];
                    });
                }
            }
        }
        if (reader.status == AVAssetReaderStatusFailed) lastError = reader.error;

        dispatch_async(dispatch_get_main_queue(), ^{
            self.videoReader = nil;
            if (saved > 0) {
                [self applySelectedMediaAtPath:frameDirectory];
            } else {
                [[NSFileManager defaultManager] removeItemAtPath:frameDirectory error:nil];
                NSString *detail = lastError ? [NSString stringWithFormat:@"%@ (%@/%ld)",
                    lastError.localizedDescription, lastError.domain, (long)lastError.code]
                    : @"Không trích xuất được frame từ video.";
                [self showMessage:detail];
                [self reloadState];
            }
        });
        } @catch (NSException *exception) {
            [self.videoReader cancelReading];
            [[NSFileManager defaultManager] removeItemAtPath:frameDirectory error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.videoReader = nil;
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
