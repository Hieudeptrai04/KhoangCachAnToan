# Khoảng Cách An Toàn

Ứng dụng iOS (jailbreak rootless, Dopamine 2) đo **khoảng cách tới xe phía trước bằng camera sau** của iPhone gắn trên kính lái, đối chiếu với **khoảng cách an toàn tối thiểu** theo quy định hiện hành của Việt Nam và cảnh báo khi bám quá gần.

> **Miễn trừ trách nhiệm.** Ứng dụng chỉ **hỗ trợ** và **ước lượng** bằng camera điện thoại. Đây không phải thiết bị đo được kiểm định và không phải bằng chứng pháp lý. Người lái chịu hoàn toàn trách nhiệm quan sát và giữ khoảng cách an toàn.

| | |
|---|---|
| Bundle id / gói | `com.khoangcachantoan.app` |
| Kho Sileo | `https://zalosuper.net/KhoangCachAnToan/` (địa chỉ `https://hieudeptrai04.github.io/KhoangCachAnToan/` tự chuyển hướng sang đây) |
| Bản build | GitHub Releases của repo này, tag `v<ver>-<sha7>` |
| Máy đã thử | iPhone X (iPhone10,3), iOS 16.7.11, Dopamine 2 rootless |

## Trạng thái phát triển

| Phase | Phiên bản | Nội dung | Trạng thái |
|---|---|---|---|
| 0 | 0.1.1 | Khung xương: CI, kho Sileo, camera preview ngang, ma trận nội tại, HUD số giả | CI xanh, chờ thử máy |
| 1 | 0.2.0 | Phát hiện xe (YOLOv3-Tiny, 2 kênh suy luận), chọn xe dẫn đầu, bám theo | CI xanh, chờ thử máy |
| 2 | 0.3.0 | Ước lượng khoảng cách, hiệu chỉnh h / d_front / k / cân ngang | chưa |
| 3 | 0.4.0 | GPS, ngưỡng luật, cảnh báo 3 màu, bíp/rung/giọng, thời tiết xấu, màn Luật | chưa |
| 4 | 1.0.0 | Onboarding, cài đặt đầy đủ, tiết kiệm pin, CSV, kiểm thử đường | chưa |

Bản 0.2.0 **chưa đo khoảng cách thật**: app đã phát hiện và bám xe phía trước (khung bao trên màn hình), nhưng con số khoảng cách và tốc độ trên HUD vẫn là số giả có nhãn `DEMO`. Đo thật bắt đầu từ Phase 2.

## Yêu cầu

- iPhone jailbreak rootless (Dopamine 2, prefix `/var/jb`), iOS 15 – 16. Không cần ellekit / substrate.
- Giá đỡ điện thoại trên kính lái. GPS bật (từ Phase 3).
- Máy có camera tele (iPhone X, 8 Plus, XS, 11 Pro…) cho tầm xa tốt hơn; máy chỉ có góc rộng vẫn chạy nhưng tầm phát hiện ngắn hơn.

## Cài đặt

### Qua Sileo (khuyến nghị, tự cập nhật)

1. Sileo → **Sources** → **+** → dán `https://zalosuper.net/KhoangCachAnToan/` → Add.
2. Refresh → tìm **Khoang Cach An Toan** → Install.
3. App xuất hiện trên SpringBoard với tên **Khoảng Cách An Toàn**. Nếu chưa thấy icon, mở lại SpringBoard hoặc chạy `uicache -a`.

### Qua file .deb

Tải `KhoangCachAnToan_<ver>_iphoneos-arm64.deb` ở trang Releases, chép vào máy rồi:

```sh
sudo dpkg -i KhoangCachAnToan_<ver>_iphoneos-arm64.deb
```

Script postinst tự thêm cdhash vào trustcache và chạy `uicache`. Nếu app tắt ngay khi mở sau khi reboot máy (Dopamine 2 mất trustcache động):

```sh
xargs -rn1 /var/jb/basebin/jbctl trustcache add < /var/jb/etc/khoangcachantoan/cdhashes
```

## Gắn máy

- Đặt điện thoại **nằm ngang**, ở **giữa kính lái** theo chiều ngang, **cao ngang gương chiếu hậu trong**, ống kính không bị cần gạt mưa hay vết bẩn che.
- Xoay máy sao cho mép trên của điện thoại hướng lên; app chỉ chạy màn ngang (LandscapeLeft / LandscapeRight).
- Dùng **vạch chân trời** (đường nét đứt ngang) trên HUD: đứng trên đường bằng, chỉnh giá đỡ để chân trời thật trùng vạch; sau đó bấm **Cân ngang** trong cài đặt (Phase 2) để lưu góc chúc.
- **Hình thang làn** (nét đứt) phải ôm lấy làn mình đang chạy ở phần dưới khung hình.

## Sử dụng

Mở app là camera bật và đo ngay; không có nút Start. Trên HUD:

- **Góc trái trên**: khoảng cách hiện tại (m) và ngưỡng, ví dụ `≥ 55 m (luật)` hoặc `≥ 42 m (khuyến nghị)`.
- **Góc phải trên**: tốc độ GPS (km/h) và khoảng thời gian tới xe trước (s).
- **Dải đáy**: xanh = an toàn (≥ 110 % ngưỡng), vàng = sát ngưỡng, đỏ nhấp nháy = dưới ngưỡng (kèm rung + bíp + giọng đọc tuỳ chọn, tối đa 1 lần / 3 s).
- **☔**: bật chế độ thời tiết xấu (ngưỡng nhân hệ số, mặc định ×1,5, nhãn "khuyến nghị").
- **⚙**: cài đặt, hiệu chỉnh, màn Luật.

Khi đang chạy không cần chạm màn hình: cấu hình trước khi khởi hành.

## Hiệu chỉnh (Phase 2)

| Tham số | Ý nghĩa | Cách đo |
|---|---|---|
| `h` | chiều cao ống kính so với mặt đường (m) | thước dây từ mặt đường lên tâm ống kính khi máy đã gắn |
| `d_front` | khoảng cách từ điện thoại tới đầu xe mình (m), mặc định 1,5 | thước dây từ kính lái tới mép trước cản |
| `k` | hệ số chỉnh tay | đỗ sau một xe ở 10 – 20 m, đo thật bằng thước, đặt `k = thật / app` |
| Cân ngang | offset góc chúc | đứng trên đường bằng, chân trời trùng vạch, bấm Cân ngang |

Quy trình kiểm thử tĩnh: đỗ sau một ô tô ở 5 / 10 / 15 / 20 / 30 m, ghi cặp (thật, app), tính sai số, chỉnh `k`, đo lại. Mục tiêu sai số ≤ 10 % ở 10 – 30 m.

## Giới hạn

- **Đơn mắt, không LiDAR**: khoảng cách suy từ bề rộng xe trong ảnh và vị trí cạnh đáy so với mặt đường. Sai số mục tiêu ≤ 10 % ở 10 – 40 m, ≤ 15 % ở 40 – 70 m; từ 100 m trở lên chỉ là ước lượng (hiện `~`).
- **Tầm xa** phụ thuộc camera: góc rộng iPhone X ở 1080p thấy xe rộng 1,8 m ở 100 m chỉ ≈ 27 px, mô hình không nhận được; app dùng camera tele + vùng quan tâm giữa khung để kéo tầm phát hiện tới ≈ 60 – 100 m ban ngày.
- **Đêm / mưa / sương mù**: phát hiện giảm mạnh; app hiện "tầm nhìn kém – tham khảo" và không cảnh báo giả.
- **Nhiệt**: chip A11 chạy suy luận liên tục sẽ nóng; mặc định 1080p + 15 fps suy luận, có chế độ tiết kiệm 10 fps.
- Chỉ nhận **xe cùng làn** (ô tô, xe tải, xe buýt, xe máy); xe lệch làn được vẽ khung xám và không tính.

## Căn cứ pháp lý (số liệu ngày 05/9/2026)

### Khoảng cách an toàn tối thiểu — Điều 11 Thông tư 38/2024/TT-BGTVT

Hiệu lực 01/01/2025. Từ 01/7/2026 thẩm quyền chuyển sang Bộ Xây dựng (Luật 118/2025/QH15), nội dung không đổi. Áp dụng khi mặt đường khô ráo, không sương mù, không trơn trượt, đường thẳng, tầm nhìn tốt.

| Tốc độ V (km/h) | Khoảng cách tối thiểu (m) |
|---|---|
| V = 60 | 35 |
| 60 < V ≤ 80 | 55 |
| 80 < V ≤ 100 | 70 |
| 100 < V ≤ 120 | 100 |
| V < 60 | không có số cứng, tài xế chủ động giữ khoảng cách phù hợp (app gợi ý theo 2 giây) |

Nơi có biển P.121 "Cự ly tối thiểu giữa hai xe": giữ không nhỏ hơn trị số trên biển. Mưa, sương mù, đường trơn, đèo dốc, tầm nhìn hạn chế: phải tăng khoảng cách (app dùng hệ số cấu hình, mặc định ×1,5, nhãn "khuyến nghị").

### Mức phạt — Nghị định 168/2024/NĐ-CP (ô tô)

| Hành vi | Phạt tiền | Trừ điểm GPLX |
|---|---|---|
| Không giữ khoảng cách an toàn để xảy ra va chạm / không giữ theo biển "Cự ly tối thiểu" | 800.000 – 1.000.000 đ | — |
| Không tuân thủ khoảng cách an toàn với xe liền trước trên đường cao tốc | 4.000.000 – 6.000.000 đ | 2 điểm |
| Không giữ khoảng cách an toàn gây tai nạn giao thông | 20.000.000 – 22.000.000 đ | 10 điểm |

### Bối cảnh

- 27/8/2026: CSGT bắt đầu xử phạt lỗi khoảng cách trên cao tốc Pháp Vân – Cầu Giẽ – Cao Bồ – Mai Sơn – Nghi Sơn bằng camera và vạch mốc 0 – 50 – 100 – 150 – 200 m.
- 01/9/2026: Chính phủ yêu cầu rà soát quy định khoảng cách và mức phạt, báo cáo trong tháng 9/2026. **Số liệu có thể đổi.**

Vì vậy app **không hard-code ngưỡng**: toàn bộ bảng, mức phạt, trích dẫn nằm trong [app/Resources/legal.json](app/Resources/legal.json) (đóng gói theo bản) và app tự tải bản mới từ `https://zalosuper.net/KhoangCachAnToan/legal.json` tối đa 1 lần / 7 ngày (so `version`, xác thực JSON, lỗi thì giữ bản cũ). CI tự chép `legal.json` lên `gh-pages` mỗi lần build.

## Độ chính xác đã đo

Chưa có số liệu. Bảng này được điền sau kiểm thử tĩnh Phase 2 (5 / 10 / 15 / 20 / 30 m) và kiểm thử đường Phase 4.

| Khoảng cách thật (m) | App (m) | Sai số |
|---|---|---|
| 5 | | |
| 10 | | |
| 15 | | |
| 20 | | |
| 30 | | |

## Kiến trúc và build

```
app/                Theos application (Objective-C, UIKit thuần, không storyboard)
  KCAppDelegate      cửa sổ, xoay ngang, giữ màn hình sáng
  KCMainViewController  màn đo: preview + HUD (+ detector, estimator từ Phase 1–2)
  KCCameraController AVCaptureSession 1080p, tele → wide, khóa nét vô cực, ma trận nội tại
  KCDetector         Core ML + Vision, hai kênh suy luận (xa: vùng quan tâm giữa khung; gần: cả khung)
  KCDetection        một xe được phát hiện; toạ độ chuẩn hoá gốc trên-trái dùng chung toàn app
  KCTracker          hành lang làn, chọn xe dẫn đầu, bám theo bằng IoU, chống nhấp nháy
  KCOverlayView      vẽ khung bao lên preview
  KCHUDView          HUD màn ngang
  KCLog              log.txt xoay vòng 1 MB
  Resources/         Info.plist, legal.json, icon; YOLOv3TinyInt8LUT.mlmodelc do CI sinh (không commit)
repo/               tài nguyên kho Sileo (make-index.sh, postinst, depiction, icon)
.github/workflows/  build.yml: Theos rootless + SDK 16.5 → .deb → Release → gh-pages
```

- Build chạy trên GitHub Actions `macos-latest`; không cần secret ngoài `GITHUB_TOKEN`.
- Model Core ML YOLOv3-Tiny Int8 (8,9 MB) của Apple được CI tải và biên dịch bằng `xcrun coremlcompiler`; không commit vào git.
- Phase 5 (nếu cần): xuất YOLOv8n bằng gói `ultralytics` (giấy phép AGPL-3.0, chỉ dùng để xuất model trong CI).
- Tạo icon: `python tools/make_icons.py` (Pillow) hoặc `powershell -File tools/make_icons.ps1` trên Windows.

Tăng phiên bản: sửa đồng bộ `app/control`, `app/Makefile` (`PACKAGE_VERSION`), `app/Resources/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`) và `kAppVersion` trong `app/KCCommon.h`. Bản mới phải lớn hơn mọi bản trong `pool/main` của kho thì Sileo mới báo cập nhật.

## Nhật ký và dữ liệu trên máy

| Đường dẫn | Nội dung |
|---|---|
| `/var/mobile/Documents/KhoangCachAnToan/log.txt` | nhật ký kỹ thuật (camera, intrinsics, lỗi), xoay vòng 1 MB |
| `/var/mobile/Documents/KhoangCachAnToan/trip_YYYYMMDD_HHMM.csv` | nhật ký chuyến đi khi bật ghi CSV (Phase 4) |
| `/var/mobile/Documents/KhoangCachAnToan/legal.json` | bản legal.json tải về (ưu tiên hơn bản trong bundle nếu mới hơn) |
| `/var/mobile/Library/Preferences/com.khoangcachantoan.app.plist` | cài đặt |
| `/var/jb/etc/khoangcachantoan/cdhashes` | cdhash để thêm trustcache |

App không đăng nhập, không gửi dữ liệu đi đâu; kết nối mạng duy nhất là tải `legal.json` từ GitHub Pages.
