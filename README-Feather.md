# TikTokPlus — Tiêm bằng Feather (ngắn gọn)

## 1. Build (làm 1 lần, từ điện thoại cũng được)
- Cách A — GitHub Actions (không cần máy tính): push repo này lên GitHub,
  vào tab Actions → chạy workflow `Build TikTokPlus` → tải artifact
  `TikTokPlus-deb` về, giải nén `.deb` (dùng app Files / iSH / web unzip)
  để lấy file `.dylib` trong
  `Library/MobileSubstrate/DynamicLibraries/TikTokPlus.dylib`.
- Cách B — máy có Theos: `make package FINALPACKAGE=1`, lấy `.dylib` tương tự.

## 2. Tiêm bằng Feather
1. Mở Feather → Sources → tải IPA TikTok (phiên bản khớp với tweak, tránh bản
   quá mới nếu tweak chưa được test).
2. Import IPA vào Feather → chọn app TikTok → Add Tweak → chọn file
   `TikTokPlus.dylib` vừa lấy ở bước 1.
3. Sign bằng chứng chỉ của bạn → Install → mở TikTok.
4. TikTok sẽ hỏi trust chứng chỉ nếu là lần đầu: Settings → General →
   VPN & Device Management → tin cậy chứng chỉ đó.

## 3. Bật/tắt tính năng (không cần jailbreak)
- Preference Bundle trong Settings.app chỉ hiện trên máy đã jailbreak.
  Trên máy sideload bằng Feather, dùng cài đặt trong app:
  vào tab Search → bấm nút `Quốc gia: ...` → `Cài đặt TikTokPlus...`
  → bật/tắt từng switch.
- Trên máy jailbreak: Settings → TikTokPlus, đổi switch rồi mở lại TikTok.

## 4. Dùng từng tính năng
- **Thumbnail Progress Bar:** mở video < 60s, nhấn GIỮ vào thanh progress,
  kéo ngang để xem thumbnail + thời gian. Thả tay là ẩn. Video ≥ 60s
  không có gì thay đổi.
- **Country Filter:** tab Search → nút `Quốc gia` góc trên phải → chọn nước.
  Lần đầu có thể cần mở lại tab Search để kết quả áp dụng.
- **Auto-save:** bấm Save (bookmark) → lần đầu chọn tay 1 collection.
  Các lần sau, khi màn chọn collection hiện lên, tweak tự chọn lại
  collection đó và không hiện tip "Saved" nữa. Muốn đổi collection mặc định:
  chọn tay collection khác 1 lần, hoặc sửa ô "Tên Collection gần nhất"
  trong Settings.

## 5. Khi TikTok update mà tính năng ngừng chạy
1. Bật `Debug log` trong cài đặt TikTokPlus, mở lại TikTok, làm lại thao tác
   bị lỗi, xem log `[TikTokPlus]` trong Console.
2. Nếu tên class/progress/search/toast đổi, sửa pattern ở đầu `Tweak.x`
   (mục ADAPTATION POINTS), build lại, tiêm lại.
3. Nếu server TikTok bỏ qua tham số `region` ở endpoint search mới, xem URL
   thực tế trong log và đổi tên tham số trong `TTKRequestWithCountry`.
