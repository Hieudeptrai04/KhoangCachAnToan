# Bảng kiểm thử trên máy thật

Dùng khi cài bản mới lên iPhone. Ghi kết quả vào cột "Kết quả" rồi dán lại cho người phát triển, hoặc gửi kèm `log.txt`.

Máy test: iPhone X (iPhone10,3), iOS 16.7.11, Dopamine 2 rootless.

## Chuẩn bị

1. Lấy IP của iPhone: Cài đặt → Wi-Fi → chạm chữ **i** cạnh tên mạng → dòng "Địa chỉ IP".
2. Trên máy tính, tại thư mục dự án:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools/install_device.ps1 -Ip <IP> -Deb .\KhoangCachAnToan_<ver>_iphoneos-arm64.deb
   ```

3. Xem nhật ký khi cần:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools/device_log.ps1 -Ip <IP> -Lines 120
   ```

Nếu app tắt ngay khi mở sau khi khởi động lại máy, chạy trên iPhone:

```sh
xargs -rn1 /var/jb/basebin/jbctl trustcache add < /var/jb/etc/khoangcachantoan/cdhashes
```

## Phase 0 — khung xương (0.1.1)

| # | Việc kiểm | Cách làm | Đạt khi | Kết quả |
|---|---|---|---|---|
| 0.1 | Cài được | `dpkg -i` chạy xong không lỗi | báo `Setting up com.khoangcachantoan.app` | |
| 0.2 | Icon hiện | nhìn màn hình chính | có icon nền xanh lá, tên "Khoảng Cách An Toàn" | |
| 0.3 | Mở thẳng vào camera | chạm icon, bấm giờ | thấy hình camera trong dưới 2 giây, không màn hình chờ | |
| 0.4 | Toàn màn hình | nhìn mép trái phải | **không có viền đen**, hình tràn hết màn hình | |
| 0.5 | Xoay ngang cả hai chiều | xoay máy hai bên | hình luôn đúng chiều, không lộn ngược | |
| 0.6 | Không xoay dọc | dựng máy đứng | giao diện giữ nguyên nằm ngang | |
| 0.7 | Màn hình không tự tắt | để yên 3 phút | vẫn sáng | |
| 0.8 | Nhật ký ghi được | chạy `device_log.ps1` | có dòng `intrinsics: buffer=1920x1080 fx=... nguon=...` | |
| 0.9 | Ống kính tele | xem dòng `camera: device=...` trong log | ghi `(tele)` | |

## Phase 1 — phát hiện xe (0.2.0)

Có thể thử ngay trong nhà: mở một video giao thông trên màn hình máy tính rồi chĩa điện thoại vào.

| # | Việc kiểm | Cách làm | Đạt khi | Kết quả |
|---|---|---|---|---|
| 1.1 | Mô hình nạp được | mở ⚙ | dòng "Model: sẵn sàng" | |
| 1.2 | Có khung bao | chĩa vào video xe chạy | xe được đóng khung | |
| 1.3 | **Khung khớp đúng vị trí xe** | nhìn kỹ khung so với xe | khung ôm sát xe, lệch dưới 5 % bề rộng màn hình | |
| 1.4 | Xe dẫn đầu | có nhiều xe trong hình | đúng một xe khung dày màu, xe khác khung xám mảnh | |
| 1.5 | Nhãn đúng | nhìn chữ trên khung | ghi `car` / `truck` / `bus` / `motorbike` hợp lý | |
| 1.6 | Tốc độ suy luận | đọc huy hiệu trên cùng | **≥ 10 fps** | |
| 1.7 | Không nhấp nháy | xem 30 giây | khung dày không nhảy qua lại giữa các xe liên tục | |
| 1.8 | Mất dấu | che camera 2 giây | hiện huy hiệu "mất dấu" rồi khung biến mất | |
| 1.9 | Vùng quan tâm | ⚙ → Hiện vùng quan tâm | thấy khung nét đứt ở giữa hình | |
| 1.9b | **Khung không nhảy khi xoay** | bật vùng quan tâm, xoay máy 180° sang chiều ngang kia | khung nét đứt **đứng yên** tại chỗ; nếu nó tụt xuống khoảng 10 % chiều cao màn hình ở một chiều thì lỗi xoay hai lần đã tái phát | |
| 1.10 | Tiết kiệm pin | ⚙ → Tiết kiệm pin (10 fps) | số fps giảm còn khoảng 10 | |
| 1.11 | Ổn định | để chạy 10 phút | không thoát app, máy không nóng bỏng tay | |

**Nếu mục 1.3 hoặc 1.9b sai** (khung lệch hẳn, dồn về một góc, hoặc lật đối xứng qua tâm màn hình khi xoay sang chiều ngang kia), chụp màn hình ở **cả hai chiều ngang** và gửi kèm. Đây là chỗ dễ sai nhất vì liên quan tới quy đổi hệ toạ độ giữa mô hình và màn hình. Trong nhật ký có dòng `detector: bbox tho kenh xa = ...` cho biết toạ độ thô, cũng gửi kèm.

## Ghi chú khi báo cáo

- Chụp màn hình lúc có xe trong khung.
- Gửi `log.txt` (lấy bằng `device_log.ps1`).
- Nếu app thoát đột ngột, lấy thêm báo cáo sự cố trong `/var/mobile/Library/Logs/CrashReporter/`.
