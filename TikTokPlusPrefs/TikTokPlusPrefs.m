// TikTokPlusPrefs — Preference Bundle (Settings).
// Đọc/ghi plist com.tiktokplus.prefs, cùng plist mà Tweak.x đọc.
// Mỗi lần đổi switch, Preferences framework tự lưu; tweak nhận thay đổi
// qua Darwin notification com.tiktokplus.prefs/ReloadPrefs (xem Root.plist:
// mỗi specifier đều có PostNotification). Không cần respring TikTok —
// chỉ cần kill rồi mở lại TikTok để tweak load lại, vì tweak chạy trong
// process TikTok (prefs mới sẽ được đọc ở lần mở app sau, hoặc ngay qua
// notification nếu app đang chạy).
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface TikTokPlusPrefsListController : PSListController
@end

@implementation TikTokPlusPrefsListController
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}
// Tiêu đề hiển thị trên cùng màn hình Settings.
- (NSString *)title {
    return @"TikTokPlus";
}
@end
