// ============================================================================
//  TikTokPlus — Tweak.x
//  Tweak cho TikTok iOS (Theos + Logos), tiêm bằng Feather.
//  ----------------------------------------------------------------------------
//  3 tính năng (bật/tắt riêng trong Settings / trong app):
//    1. Thumbnail Progress Bar — chỉ video ngắn (< 60s), long-press progress bar
//       để xem thumbnail preview theo vị trí kéo.
//    2. Country Filter trong Search — nút chọn quốc gia + chèn tham số
//       region/country vào request search của TikTok.
//    3. Auto-save vào Collection gần nhất + ẩn tip "Saved".
//
//  NGUYÊN TẮC QUAN TRỌNG — ĐỌC TRƯỚC KHI BUILD:
//  * TikTok obfuscate / đổi tên class private mỗi bản cập nhật, nên tweak này
//    KHÔNG hard-code class private của TikTok làm điểm hook chính. Thay vào đó
//    nó hook các class public ổn định (UIView, UIViewController, NSURLSession)
//    rồi nhận diện view/controller của TikTok bằng PATTERN TÊN CLASS lúc runtime
//    (vd: tên chứa "Progress", "Search", "Toast", "Collect"...).
//  * Vì vậy tweak vẫn chạy được qua nhiều bản TikTok, và khi TikTok đổi hẳn
//    kiến trúc, chỉ cần sửa các pattern ở mục "ADAPTATION POINTS" bên dưới.
//  * Bật "Debug log" trong Settings để xem log các class candidate trong
//    Console — đó là cách nhanh nhất để map lại khi TikTok update.
//  * Feather: tweak này chỉ dùng Objective-C runtime + Logos hook trên class
//    public, không link CydiaSubstrate. Runtime hook của Feather (ElleKit-
//    compatible) là đủ để load %hook. Không cần jailbreak đầy đủ.
//  * RỦI RO: TikTok có thể phát hiện tweak injection và giới hạn tài khoản.
//    Chỉ dùng trên tài khoản phụ / chấp nhận rủi ro, không dùng để spam.
// ============================================================================

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

// ============================================================================
// ADAPTATION POINTS — chỉ sửa ở đây khi TikTok update
// ============================================================================
// Pattern tên class (không phân biệt hoa/thường). Thêm/bớt chuỗi nếu bản
// TikTok mới đổi tên. Giữ pattern càng chung càng bền, càng cụ thể càng ít
// false-positive — cân bằng ở mức hiện tại là đủ cho TikTok 2024–2026.
static NSArray<NSString *> *TTKProgressPatterns(void) {
    return @[@"progress", @"slider", @"seekbar", @"seek"];
}
static NSArray<NSString *> *TTKSearchPatterns(void) {
    return @[@"search"];
}
static NSArray<NSString *> *TTKToastPatterns(void) {
    return @[@"toast", @"snackbar", @"tipview", @"toastview"];
}
static NSArray<NSString *> *TTKPickerPatterns(void) {
    // Màn chọn Collection / Favorite khi bấm Save (bookmark).
    return @[@"collect", @"collection", @"favorite", @"bookmark", @"save"];
}
// Các chuỗi toast cần ẩn sau khi save thành công (TikTok dùng nhiều locale).
static NSArray<NSString *> *TTKSavedTexts(void) {
    return @[@"saved", @"đã lưu", @"added to", @"đã thêm vào",
             @"saved to", @"added to favorites", @"đã lưu vào"];
}
// Danh sách quốc gia cho filter (mã ISO 2 chữ + tên hiển thị).
static NSArray<NSDictionary *> *TTKCountries(void) {
    return @[
        @{@"code": @"",   @"name": @"Tất cả quốc gia"},
        @{@"code": @"VN", @"name": @"Việt Nam"},
        @{@"code": @"US", @"name": @"Hoa Kỳ"},
        @{@"code": @"GB", @"name": @"Anh"},
        @{@"code": @"JP", @"name": @"Nhật Bản"},
        @{@"code": @"KR", @"name": @"Hàn Quốc"},
        @{@"code": @"TH", @"name": @"Thái Lan"},
        @{@"code": @"ID", @"name": @"Indonesia"},
        @{@"code": @"PH", @"name": @"Philippines"},
        @{@"code": @"MY", @"name": @"Malaysia"},
        @{@"code": @"SG", @"name": @"Singapore"},
        @{@"code": @"TW", @"name": @"Đài Loan"},
        @{@"code": @"FR", @"name": @"Pháp"},
        @{@"code": @"DE", @"name": @"Đức"},
        @{@"code": @"BR", @"name": @"Brazil"},
        @{@"code": @"MX", @"name": @"Mexico"},
    ];
}

// ============================================================================
// Preferences — đọc/ghi cùng plist mà Preference Bundle ghi vào.
// Preference Bundle id: com.tiktokplus.prefs
// Notification reload:  com.tiktokplus.prefs/ReloadPrefs
// ============================================================================
static NSString * const kPrefsID = @"com.tiktokplus.prefs";
static NSString * const kReloadNote = @"com.tiktokplus.prefs/ReloadPrefs";

// Cache prefs trong memory, reload khi nhận Darwin notification.
static BOOL     gEnabled = YES;
static BOOL     gThumbnail = YES;
static BOOL     gCountryFilter = YES;
static BOOL     gAutoSave = YES;
static BOOL     gHideSavedTip = YES;
static BOOL     gDebug = NO;
static NSString *gCountryCode = nil;        // vd: @"VN", rỗng = tất cả
static NSString *gLastCollectionName = nil; // tên collection dùng gần nhất

static id TTKPrefValue(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)kPrefsID);
    if (!v) return nil;
    return CFBridgingRelease(v);
}
static BOOL TTKPrefBool(NSString *key, BOOL def) {
    id v = TTKPrefValue(key);
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    return def;
}
static NSString *TTKPrefString(NSString *key, NSString *def) {
    id v = TTKPrefValue(key);
    if ([v isKindOfClass:[NSString class]]) return v;
    return def;
}
static void TTKPrefSet(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFTypeRef)value,
                             (__bridge CFStringRef)kPrefsID);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsID);
    // Báo cho chính process này (và các process khác) reload ngay.
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kReloadNote, NULL, NULL, YES);
}
static void TTKReloadPrefs(void) {
    gEnabled       = TTKPrefBool(@"enabled", YES);
    gThumbnail     = TTKPrefBool(@"thumbnailProgress", YES);
    gCountryFilter = TTKPrefBool(@"countryFilter", YES);
    gAutoSave      = TTKPrefBool(@"autoSaveCollection", YES);
    gHideSavedTip  = TTKPrefBool(@"hideSavedTip", YES);
    gDebug         = TTKPrefBool(@"debugLog", NO);
    gCountryCode   = TTKPrefString(@"countryCode", @"");
    gLastCollectionName = TTKPrefString(@"lastCollectionName", nil);
}
static void TTKReloadCallback(CFNotificationCenterRef center, void *observer,
                              CFStringRef name, const void *object,
                              CFDictionaryRef userInfo) {
    TTKReloadPrefs();
}
#define TTKLog(fmt, ...) do { if (gDebug) NSLog(@"[TikTokPlus] " fmt, ##__VA_ARGS__); } while (0)

// ============================================================================
// Helpers — nhận diện class / view theo pattern, tìm AVPlayer
// ============================================================================
static BOOL TTKNameMatches(NSString *name, NSArray<NSString *> *patterns) {
    if (!name) return NO;
    NSString *lower = [name lowercaseString];
    for (NSString *p in patterns) {
        if ([lower containsString:[p lowercaseString]]) return YES;
    }
    return NO;
}
static NSString *TTKClassNameOf(id obj) {
    return obj ? NSStringFromClass(object_getClass(obj)) : @"";
}
// Tìm view controller đang chứa một view (đi ngược responder chain).
static UIViewController *TTKViewControllerForView(UIView *view) {
    UIResponder *r = view;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) return (UIViewController *)r;
        r = [r nextResponder];
    }
    return nil;
}
// Tìm AVPlayerLayer trong cây layer của một view (đệ quy, có giới hạn sâu).
static AVPlayer *TTKPlayerInLayer(CALayer *layer, int depth) {
    if (!layer || depth > 6) return nil;
    if ([layer isKindOfClass:[AVPlayerLayer class]]) {
        return [(AVPlayerLayer *)layer player];
    }
    for (CALayer *sub in layer.sublayers) {
        AVPlayer *p = TTKPlayerInLayer(sub, depth + 1);
        if (p) return p;
    }
    return nil;
}
// Tìm AVPlayer cho một progress bar: thử layer của chính nó và các superview,
// rồi thử KVC "player" trên view controller chứa nó (TikTok có thể giữ player
// ở controller thay vì layer trực tiếp).
static AVPlayer *TTKPlayerForView(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        AVPlayer *p = TTKPlayerInLayer(v.layer, 0);
        if (p) return p;
    }
    UIViewController *vc = TTKViewControllerForView(view);
    if (vc) {
        for (NSString *key in @[@"player", @"avPlayer", @"currentPlayer", @"videoPlayer"]) {
            @try {
                id v = [vc valueForKey:key];
                if ([v isKindOfClass:[AVPlayer class]]) return v;
            } @catch (NSException *e) { /* key không tồn tại: bỏ qua */ }
        }
    }
    return nil;
}
static double TTKPlayerDuration(AVPlayer *player) {
    if (!player || !player.currentItem) return 0;
    CMTime d = player.currentItem.duration;
    if (CMTIME_IS_INVALID(d) || CMTIME_IS_INDEFINITE(d)) return 0;
    return CMTimeGetSeconds(d);
}
// Thu thập toàn bộ UILabel trong một view (để nhận diện toast / tên collection).
static void TTKCollectLabels(UIView *view, NSMutableArray<UILabel *> *out, int depth) {
    if (!view || depth > 8) return;
    if ([view isKindOfClass:[UILabel class]]) [out addObject:(UILabel *)view];
    for (UIView *sub in view.subviews) TTKCollectLabels(sub, out, depth + 1);
}
static NSString *TTKTextOfCell(UIView *cell) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    TTKCollectLabels(cell, labels, 0);
    // Lấy label dài nhất, có nội dung — thường là tên collection.
    NSString *best = nil;
    for (UILabel *l in labels) {
        if (l.text.length && (!best || l.text.length > best.length)) best = l.text;
    }
    return best;
}

// ============================================================================
// TÍNH NĂNG 1 — Thumbnail Progress Bar (chỉ video < 60s)
// ============================================================================
// Cách hoạt động:
//  * Khi một view có tên chứa Progress/Slider/Seek xuất hiện trên màn hình,
//    gắn 1 UILongPressGestureRecognizer (chỉ 1 lần, đánh dấu bằng associated
//    object). Gesture không cancel touch gốc (cancelsTouchesInView = NO) nên
//    hành vi seek gốc của TikTok không bị phá.
//  * Khi long-press bắt đầu / di chuyển: lấy AVPlayer, kiểm tra duration.
//    duration >= 60s hoặc không xác định được -> ẩn preview, return ngay
//    (video dài hoàn toàn không bị ảnh hưởng).
//  * Ngược lại: tính thời gian = progress * duration, dùng AVAssetImageGenerator
//    để render frame tại thời gian đó (cache theo giây để không render lại
//    cùng 1 frame khi kéo chậm), hiển thị bubble thumbnail bám theo ngón tay,
//    phía trên progress bar.
//  * Khi thả tay: chỉ ẩn preview. Không tự seek — seek vẫn là việc của TikTok
//    khi user tap/kéo bình thường, tránh xung đột với player gốc.
//  * Giới hạn: TikTok dùng player tùy biến (không phải AVPlayerLayer) ở một số
//    bản thì TTKPlayerForView trả về nil và preview sẽ không hiện. Khi đó bật
//    Debug log để xem player nằm ở đâu, rồi bổ sung KVC key ở hàm trên.
@interface TTKThumbnailPreview : NSObject
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) AVAssetImageGenerator *generator;
@property (nonatomic, strong) AVAsset *lastAsset;
@property (nonatomic) double lastSecond; // giây đã render gần nhất (cache)
+ (instancetype)shared;
- (void)showForBar:(UIView *)bar atX:(CGFloat)x player:(AVPlayer *)player;
- (void)hide;
@end

@implementation TTKThumbnailPreview
+ (instancetype)shared {
    static TTKThumbnailPreview *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TTKThumbnailPreview new]; s.lastSecond = -1; });
    return s;
}
- (UIView *)bubbleForSuperview:(UIView *)superview {
    if (!self.bubble) {
        UIView *b = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 144, 104)];
        b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.9];
        b.layer.cornerRadius = 10;
        b.layer.masksToBounds = YES;
        b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
        b.layer.borderWidth = 1;
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 144, 81)];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        [b addSubview:iv];
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(0, 81, 144, 23)];
        lb.textAlignment = NSTextAlignmentCenter;
        lb.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
        lb.textColor = UIColor.whiteColor;
        [b addSubview:lb];
        self.imageView = iv; self.timeLabel = lb; self.bubble = b;
    }
    if (self.bubble.superview != superview) {
        [self.bubble removeFromSuperview];
        [superview addSubview:self.bubble];
    }
    return self.bubble;
}
- (NSString *)stringForTime:(double)t {
    int s = (int)round(t);
    return [NSString stringWithFormat:@"%d:%02d", s / 60, s % 60];
}
- (void)showForBar:(UIView *)bar atX:(CGFloat)x player:(AVPlayer *)player {
    double duration = TTKPlayerDuration(player);
    // CỬA CHẶN QUAN TRỌNG: chỉ video ngắn mới có preview.
    if (duration <= 0 || duration >= 60) { [self hide]; return; }
    UIView *superview = bar.superview ?: bar;
    UIView *bubble = [self bubbleForSuperview:superview];
    CGFloat progress = MAX(0, MIN(1, x / MAX(1, bar.bounds.size.width)));
    double target = progress * duration;
    // Đặt bubble bám theo ngón tay, kẹp trong biên màn hình.
    CGFloat bw = bubble.bounds.size.width;
    CGFloat cx = [bar convertPoint:CGPointMake(x, 0) toView:superview].x;
    cx = MAX(bw / 2 + 4, MIN(superview.bounds.size.width - bw / 2 - 4, cx));
    CGFloat top = CGRectGetMinY(bar.frame) - bubble.bounds.size.height - 10;
    bubble.center = CGPointMake(cx, top + bubble.bounds.size.height / 2);
    bubble.hidden = NO;
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@",
                           [self stringForTime:target], [self stringForTime:duration]];
    // Cache theo giây: kéo chậm trong cùng 1 giây thì không render lại.
    double second = floor(target);
    AVAsset *asset = player.currentItem.asset;
    if (!asset) return;
    if (asset != self.lastAsset) {
        self.generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        self.generator.appliesPreferredTrackTransform = YES;
        self.generator.maximumSize = CGSizeMake(288, 162);
        self.lastAsset = asset; self.lastSecond = -1;
    }
    if (second == self.lastSecond) return;
    self.lastSecond = second;
    AVAssetImageGenerator *gen = self.generator;
    CMTime time = CMTimeMakeWithSeconds(target, 600);
    [gen generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:time]]
                              completionHandler:^(CMTime t, CGImageRef img,
                                                  CMTime actual, AVAssetImageGeneratorResult r,
                                                  NSError *e) {
        if (r == AVAssetImageGeneratorSucceeded && img) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // Chỉ cập nhật nếu vẫn đang hiển thị đúng giây đó.
                if (self.lastSecond == floor(CMTimeGetSeconds(t))) {
                    self.imageView.image = [UIImage imageWithCGImage:img];
                }
            });
        }
    }];
}
- (void)hide {
    self.bubble.hidden = YES;
}
@end

// Handler cho long-press trên progress bar (singleton, làm target của gesture).
@interface TTKProgressHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)attachToBar:(UIView *)bar;
- (void)onLongPress:(UILongPressGestureRecognizer *)g;
@end

@implementation TTKProgressHandler
+ (instancetype)shared {
    static TTKProgressHandler *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TTKProgressHandler new]; });
    return s;
}
- (void)attachToBar:(UIView *)bar {
    static const char kAttachedKey;
    if (objc_getAssociatedObject(bar, &kAttachedKey)) return; // đã gắn rồi
    UILongPressGestureRecognizer *g =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(onLongPress:)];
    g.minimumPressDuration = 0.3;
    g.cancelsTouchesInView = NO; // không cướp touch seek gốc của TikTok
    g.delegate = self;
    [bar addGestureRecognizer:g];
    objc_setAssociatedObject(bar, &kAttachedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    TTKLog(@"Attached long-press to progress bar: %@", TTKClassNameOf(bar));
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o {
    return YES; // cho phép TikTok xử lý gesture của nó song song
}
- (void)onLongPress:(UILongPressGestureRecognizer *)g {
    if (!gEnabled || !gThumbnail) return;
    UIView *bar = g.view;
    if (!bar) return;
    if (g.state == UIGestureRecognizerStateEnded ||
        g.state == UIGestureRecognizerStateCancelled ||
        g.state == UIGestureRecognizerStateFailed) {
        [[TTKThumbnailPreview shared] hide];
        return;
    }
    if (g.state != UIGestureRecognizerStateBegan &&
        g.state != UIGestureRecognizerStateChanged) return;
    AVPlayer *player = TTKPlayerForView(bar);
    if (!player) { // không tìm thấy player: không làm gì, không crash
        TTKLog(@"No AVPlayer found for progress bar %@", TTKClassNameOf(bar));
        return;
    }
    CGPoint p = [g locationInView:bar];
    [[TTKThumbnailPreview shared] showForBar:bar atX:p.x player:player];
}
@end

// ============================================================================
// TÍNH NĂNG 2 — Country Filter trong Search
// ============================================================================
// 2a. UI: khi một Search view controller xuất hiện, thêm nút "Quốc gia: XX"
//     ở góc trên phải (tag riêng để không thêm trùng). Bấm nút -> action sheet
//     chọn quốc gia -> lưu countryCode vào prefs -> nút đổi nhãn ngay.
//     Action sheet có thêm mục "Cài đặt TikTokPlus..." mở màn hình cài đặt
//     trong app (quan trọng với Feather: không cần vào Settings.app của máy
//     đã jailbreak mới đổi được setting).
// 2b. API: hook NSURLSession -dataTaskWithRequest:completionHandler:. Nếu URL
//     thuộc TikTok và path chứa "search", chèn region/country vào request:
//       - GET: thêm query param region + country_code.
//       - POST JSON: decode body, thêm key region/country_code, encode lại.
//     LƯU Ý TRUNG THỰC: TikTok có thể bỏ qua tham số này ở phía server
//     (search region thường bị khóa theo tài khoản/IP). Khi đó filter vẫn
//     hiển thị đúng lựa chọn của user, nhưng kết quả có thể không đổi —
//     đó là giới hạn phía server, không phải lỗi hook. Không có cách client
//     nào ép server TikTok lọc nếu nó không hỗ trợ tham số đó cho endpoint
//     đang dùng; bật Debug log để xem URL thực tế của bản TikTok đang dùng
//     rồi điều chỉnh tên tham số nếu cần (vd: "region" thay vì "country").
@interface TTKInAppSettingsViewController : UITableViewController
@end
@implementation TTKInAppSettingsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"TikTokPlus";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"c"];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 6; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"c" forIndexPath:ip];
    NSArray *titles = @[@"Bật TikTokPlus", @"Thumbnail Progress Bar",
                        @"Country Filter", @"Auto-save Collection",
                        @"Ẩn tip \"Saved\"", @"Debug log"];
    NSArray *keys = @[@"enabled", @"thumbnailProgress", @"countryFilter",
                      @"autoSaveCollection", @"hideSavedTip", @"debugLog"];
    cell.textLabel.text = titles[ip.row];
    UISwitch *sw = [UISwitch new];
    sw.on = TTKPrefBool(keys[ip.row], YES);
    sw.tag = ip.row;
    [sw addTarget:self action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)swChanged:(UISwitch *)sw {
    NSArray *keys = @[@"enabled", @"thumbnailProgress", @"countryFilter",
                      @"autoSaveCollection", @"hideSavedTip", @"debugLog"];
    TTKPrefSet(keys[sw.tag], @(sw.on));
    TTKReloadPrefs();
}
@end

static void TTKPresentCountryPicker(UIViewController *host) {
    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:@"Lọc theo quốc gia"
                                            message:@"Chọn quốc gia để lọc kết quả tìm kiếm."
                                     preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *c in TTKCountries()) {
        NSString *code = c[@"code"];
        UIAlertAction *a = [UIAlertAction actionWithTitle:c[@"name"]
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction *_) {
            TTKPrefSet(@"countryCode", code ?: @"");
            TTKReloadPrefs();
            // Cập nhật nhãn nút ngay (tìm lại theo tag).
            for (UIView *v in host.view.subviews) {
                if ([v isKindOfClass:[UIButton class]] && v.tag == 987001) {
                    NSString *label = code.length ? [NSString stringWithFormat:@"Quốc gia: %@", code]
                                                  : @"Quốc gia: Tất cả";
                    [(UIButton *)v setTitle:label forState:UIControlStateNormal];
                }
            }
        }];
        [sheet addAction:a];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cài đặt TikTokPlus..."
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_) {
        TTKInAppSettingsViewController *vc = [TTKInAppSettingsViewController new];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        [host presentViewController:nav animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Hủy"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    // iPad: action sheet cần source view.
    sheet.popoverPresentationController.sourceView = host.view;
    sheet.popoverPresentationController.sourceRect =
        CGRectMake(host.view.bounds.size.width - 60, 60, 1, 1);
    [host presentViewController:sheet animated:YES completion:nil];
}
static void TTKMaybeAddCountryButton(UIViewController *vc) {
    if (!gEnabled || !gCountryFilter) return;
    if (!TTKNameMatches(TTKClassNameOf(vc), TTKSearchPatterns())) return;
    for (UIView *v in vc.view.subviews) {
        if ([v isKindOfClass:[UIButton class]] && v.tag == 987001) return; // đã có
    }
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = 987001;
    NSString *label = gCountryCode.length ? [NSString stringWithFormat:@"Quốc gia: %@", gCountryCode]
                                          : @"Quốc gia: Tất cả";
    [btn setTitle:label forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    btn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.layer.cornerRadius = 14;
    btn.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 12);
    [btn sizeToFit];
    CGRect f = btn.frame;
    CGFloat top = vc.view.safeAreaInsets.top + 8;
    btn.frame = CGRectMake(vc.view.bounds.size.width - f.size.width - 12, top,
                           f.size.width, f.size.height);
    btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    // Target là singleton TTKProgressHandler; method countryButtonTapped:
    // được định nghĩa trong category bên dưới, tìm host qua responder chain.
    [btn addTarget:[TTKProgressHandler shared]
            action:@selector(countryButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:btn];
    TTKLog(@"Added country button to %@", TTKClassNameOf(vc));
}

// Category bổ sung method nút quốc gia (đặt sau để tránh forward declaration).
@interface TTKProgressHandler (CountryButton)
- (void)countryButtonTapped:(UIButton *)sender;
@end
@implementation TTKProgressHandler (CountryButton)
- (void)countryButtonTapped:(UIButton *)sender {
    UIViewController *host = TTKViewControllerForView(sender);
    if (host) TTKPresentCountryPicker(host);
}
@end

static NSURLRequest *TTKRequestWithCountry(NSURLRequest *request) {
    if (!gEnabled || !gCountryFilter || !gCountryCode.length) return request;
    NSURL *url = request.URL;
    if (!url) return request;
    NSString *host = url.host.lowercaseString ?: @"";
    BOOL isTikTok = [host containsString:@"tiktok"] || [host containsString:@"musical"];
    BOOL isSearch = [url.path.lowercaseString containsString:@"search"];
    if (!isTikTok || !isSearch) return request;
    TTKLog(@"Search request intercepted: %@", url.absoluteString);
    NSMutableURLRequest *m = [request mutableCopy];
    if ([request.HTTPMethod isEqualToString:@"GET"] || !request.HTTPBody) {
        NSURLComponents *comp = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSMutableArray *items = [comp.queryItems mutableCopy] ?: [NSMutableArray array];
        // Xóa param cũ rồi thêm mới (tránh trùng).
        NSPredicate *keep = [NSPredicate predicateWithBlock:^BOOL(NSURLQueryItem *it, NSDictionary *b) {
            return ![it.name isEqualToString:@"region"] && ![it.name isEqualToString:@"country_code"];
        }];
        items = [[items filteredArrayUsingPredicate:keep] mutableCopy];
        [items addObject:[NSURLQueryItem queryItemWithName:@"region" value:gCountryCode]];
        [items addObject:[NSURLQueryItem queryItemWithName:@"country_code" value:gCountryCode]];
        comp.queryItems = items;
        m.URL = comp.URL;
    } else {
        // POST JSON: decode -> chèn region/country_code -> encode lại.
        NSError *err = nil;
        id json = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:NSJSONReadingMutableContainers error:&err];
        if (!err && [json isKindOfClass:[NSMutableDictionary class]]) {
            json[@"region"] = gCountryCode;
            json[@"country_code"] = gCountryCode;
            NSData *body = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
            if (body) m.HTTPBody = body;
        }
    }
    return [m copy];
}

// ============================================================================
// TÍNH NĂNG 3 — Auto-save vào Collection gần nhất + ẩn tip "Saved"
// ============================================================================
// 3a. Ghi nhớ collection gần nhất BẰNG UI, không cần private API:
//     Khi màn chọn Collection xuất hiện, gắn 1 tap gesture (không cướp touch)
//     lên UITableView/UICollectionView của nó. User chạm vào cell nào, tên
//     cell đó được lưu vào prefs làm "lastCollectionName" — lần save sau
//     tweak sẽ tự chạm hộ đúng cell đó (xem 3b). Lần đầu chưa có gì lưu thì
//     picker hiện bình thường cho user chọn tay — đó cũng là lần "dạy" tweak.
// 3b. Auto-save: khi picker xuất hiện mà đã có lastCollectionName, đợi 0.35s
//     cho list load xong, tìm cell có tên trùng, rồi gọi delegate
//     didSelectRow/Item hộ user. Picker tự đóng như khi user chạm tay.
//     Nếu không tìm thấy cell (collection bị xóa/đổi tên) -> để yên cho user
//     chọn tay, không crash, không chọn bừa collection khác.
// 3c. Ẩn tip "Saved": trong UIView didMoveToWindow, nếu view mới xuất hiện là
//     toast (tên class chứa toast/snackbar/tip) và có label chứa "Saved" /
//     "Đã lưu" / ... thì ẩn nó ngay (hidden = YES) thay vì để nó hiện rồi
//     biến mất. Chỉ ẩn đúng các chuỗi trong TTKSavedTexts, không ẩn toast
//     khác (vd: lỗi mạng, "Link copied") để không che thông báo quan trọng.
@interface TTKPickerTapHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)installOnScrollView:(UIScrollView *)sv;
- (void)onPickerTap:(UITapGestureRecognizer *)g;
@end
@implementation TTKPickerTapHandler
+ (instancetype)shared {
    static TTKPickerTapHandler *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TTKPickerTapHandler new]; });
    return s;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o {
    return YES;
}
- (void)installOnScrollView:(UIScrollView *)sv {
    static const char kPickerTapKey;
    if (objc_getAssociatedObject(sv, &kPickerTapKey)) return;
    UITapGestureRecognizer *g = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(onPickerTap:)];
    g.cancelsTouchesInView = NO;
    g.delegate = self;
    [sv addGestureRecognizer:g];
    objc_setAssociatedObject(sv, &kPickerTapKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)onPickerTap:(UITapGestureRecognizer *)g {
    if (!gEnabled || !gAutoSave) return;
    UIScrollView *sv = (UIScrollView *)g.view;
    CGPoint p = [g locationInView:sv];
    UIView *cell = nil;
    if ([sv isKindOfClass:[UITableView class]]) {
        NSIndexPath *ip = [(UITableView *)sv indexPathForRowAtPoint:p];
        cell = ip ? [(UITableView *)sv cellForRowAtIndexPath:ip] : nil;
    } else if ([sv isKindOfClass:[UICollectionView class]]) {
        NSIndexPath *ip = [(UICollectionView *)sv indexPathForItemAtPoint:p];
        cell = ip ? [(UICollectionView *)sv cellForItemAtIndexPath:ip] : nil;
    }
    NSString *name = TTKTextOfCell(cell);
    if (name.length) {
        TTKPrefSet(@"lastCollectionName", name);
        TTKReloadPrefs();
        TTKLog(@"Learned last collection: %@", name);
    }
}
@end

static void TTKFindScrollViews(UIView *view, NSMutableArray<UIScrollView *> *out, int depth) {
    if (!view || depth > 8) return;
    if ([view isKindOfClass:[UIScrollView class]]) [out addObject:(UIScrollView *)view];
    for (UIView *sub in view.subviews) TTKFindScrollViews(sub, out, depth + 1);
}
// Tự chạm vào cell có tên = lastCollectionName. Trả về YES nếu đã chạm.
static BOOL TTKAutoTapCollection(UIViewController *picker) {
    if (!gLastCollectionName.length) return NO;
    NSMutableArray<UIScrollView *> *svs = [NSMutableArray array];
    TTKFindScrollViews(picker.view, svs, 0);
    NSString *want = [gLastCollectionName stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    for (UIScrollView *sv in svs) {
        if ([sv isKindOfClass:[UITableView class]]) {
            UITableView *tv = (UITableView *)sv;
            for (NSInteger s = 0; s < tv.numberOfSections; s++) {
                for (NSInteger r = 0; r < [tv numberOfRowsInSection:s]; r++) {
                    NSIndexPath *ip = [NSIndexPath indexPathForRow:r inSection:s];
                    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
                    NSString *name = TTKTextOfCell(cell);
                    if (name && [name.lowercaseString containsString:want]) {
                        TTKLog(@"Auto-tapping collection: %@", name);
                        if ([tv.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
                            [tv.delegate tableView:tv didSelectRowAtIndexPath:ip];
                            return YES;
                        }
                    }
                }
            }
        } else if ([sv isKindOfClass:[UICollectionView class]]) {
            UICollectionView *cv = (UICollectionView *)sv;
            for (NSInteger s = 0; s < cv.numberOfSections; s++) {
                for (NSInteger it = 0; it < [cv numberOfItemsInSection:s]; it++) {
                    NSIndexPath *ip = [NSIndexPath indexPathForItem:it inSection:s];
                    UICollectionViewCell *cell = [cv cellForItemAtIndexPath:ip];
                    NSString *name = TTKTextOfCell(cell);
                    if (name && [name.lowercaseString containsString:want]) {
                        TTKLog(@"Auto-tapping collection: %@", name);
                        if ([cv.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
                            [cv.delegate collectionView:cv didSelectItemAtIndexPath:ip];
                            return YES;
                        }
                    }
                }
            }
        }
    }
    TTKLog(@"Last collection not found in picker: %@", gLastCollectionName);
    return NO;
}
static void TTKMaybeHandlePicker(UIViewController *vc) {
    if (!gEnabled) return;
    if (!TTKNameMatches(TTKClassNameOf(vc), TTKPickerPatterns())) return;
    // Chỉ xử lý khi picker này thực sự là màn chọn collection sau khi Save:
    // nó phải chứa 1 table/collection view. Nếu không có, bỏ qua.
    NSMutableArray<UIScrollView *> *svs = [NSMutableArray array];
    TTKFindScrollViews(vc.view, svs, 0);
    if (!svs.count) return;
    TTKLog(@"Collection picker appeared: %@", TTKClassNameOf(vc));
    if (gAutoSave) {
        for (UIScrollView *sv in svs) [[TTKPickerTapHandler shared] installOnScrollView:sv];
        if (gLastCollectionName.length) {
            // Đợi list load xong rồi mới auto-tap.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                // Chỉ auto-tap nếu picker vẫn đang hiển thị.
                if (vc.view.window) TTKAutoTapCollection(vc);
            });
        }
    }
}
static BOOL TTKIsSavedToast(UIView *view) {
    if (!gEnabled || !gHideSavedTip) return NO;
    // Điều kiện 1: tên class gợi ý đây là toast/tip.
    BOOL nameLooksToast = TTKNameMatches(TTKClassNameOf(view), TTKToastPatterns());
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    TTKCollectLabels(view, labels, 0);
    BOOL textMatches = NO;
    for (UILabel *l in labels) {
        NSString *t = l.text.lowercaseString ?: @"";
        for (NSString *saved in TTKSavedTexts()) {
            if ([t containsString:saved]) { textMatches = YES; break; }
        }
        if (textMatches) break;
    }
    // Ẩn khi: (là toast VÀ text khớp) — tránh ẩn nhầm label "Saved" nằm trong
    // nội dung video. Toast thật thường là view nhỏ, thêm trực tiếp vào window.
    if (nameLooksToast && textMatches) return YES;
    // Trường hợp TikTok dùng toast generic không có tên gợi ý: chỉ ẩn khi view
    // là con trực tiếp của UIWindow, chiều cao < 120, và text khớp chính xác
    // một trong các chuỗi Saved (không phải "chứa" để tránh false-positive).
    if (textMatches && [view.superview isKindOfClass:[UIWindow class]] &&
        view.bounds.size.height < 120) {
        for (UILabel *l in labels) {
            NSString *t = [l.text stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
            for (NSString *saved in TTKSavedTexts()) {
                if ([t isEqualToString:saved]) return YES;
            }
        }
    }
    return NO;
}

// ============================================================================
// Hooks (Logos) — chỉ hook class public, ổn định qua các bản TikTok.
// ============================================================================
%hook UIView
- (void)didMoveToWindow {
    %orig;
    if (!gEnabled || !self.window) return;
    // 1. Progress bar -> gắn long-press thumbnail.
    if (gThumbnail && TTKNameMatches(TTKClassNameOf(self), TTKProgressPatterns())) {
        // Chỉ gắn cho view có kích thước giống thanh progress (ngang, thấp),
        // tránh gắn nhầm vào progress indicator tròn / loading spinner.
        if (self.bounds.size.width > 100 && self.bounds.size.height <= 40) {
            [[TTKProgressHandler shared] attachToBar:self];
        }
    }
    // 3c. Toast "Saved" -> ẩn ngay khi vừa xuất hiện.
    if (gHideSavedTip && TTKIsSavedToast(self)) {
        TTKLog(@"Hiding Saved toast: %@", TTKClassNameOf(self));
        self.hidden = YES;
        // Một số toast tự set hidden = NO lại sau đó: gỡ khỏi hierarchy luôn
        // thì chắc chắn không hiện, nhưng vẫn để completion gốc chạy xong.
        dispatch_async(dispatch_get_main_queue(), ^{ [self removeFromSuperview]; });
    }
}
%end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!gEnabled) return;
    // 2a. Search -> thêm nút Country Filter.
    TTKMaybeAddCountryButton(self);
    // 3a/3b. Collection picker -> học collection + auto-tap nếu có.
    TTKMaybeHandlePicker(self);
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                           completionHandler:(void (^)(NSData *data,
                                                       NSURLResponse *response,
                                                       NSError *error))completionHandler {
    NSURLRequest *modified = TTKRequestWithCountry(request);
    return %orig(modified, completionHandler);
}
%end

// ============================================================================
// TEMPLATE (chưa kích hoạt) — Hook private của TikTok sau khi class-dump
// ----------------------------------------------------------------------------
// Nếu muốn auto-save "chuẩn" hơn (gọi thẳng API add-to-collection thay vì
// auto-tap UI ở trên), làm như sau cho đúng bản TikTok đang dùng:
//   1. Bật debugLog, mở TikTok, bấm Save, xem Console để lấy tên class của
//      màn Collection picker và của controller xử lý save.
//   2. Class-dump / dùng Frida objection để lấy tên method chọn collection
//      (thường chứa "didSelect", "addToCollection", "collectWithId"...).
//   3. Bỏ comment %group dưới đây, điền đúng tên class + selector, build lại.
// Template này KHÔNG được kích hoạt mặc định để tránh hook nhầm class không
// tồn tại ở bản TikTok khác.
//   %group TikTokPrivateSaveFlow
//   %hook AWECollectionPickerViewController // <-- THAY BẰNG TÊN THẬT
//   - (void)didSelectCollection:(id)collection { // <-- THAY SELECTOR THẬT
//       TTKPrefSet(@"lastCollectionName", [collection valueForKey:@"name"]);
//       %orig;
//   }
//   %end
//   %end
//   // Trong %ctor, thêm: %init(TikTokPrivateSaveFlow);
// ============================================================================

%ctor {
    TTKReloadPrefs();
    // Reload prefs ngay khi Preference Bundle / in-app settings đổi.
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        TTKReloadCallback, (__bridge CFStringRef)kReloadNote, NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
    %init;
    TTKLog(@"Loaded. thumbnail=%d country=%d autosave=%d hideTip=%d countryCode=%@ lastCollection=%@",
           gThumbnail, gCountryFilter, gAutoSave, gHideSavedTip,
           gCountryCode, gLastCollectionName);
}
