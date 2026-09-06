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
sudo xargs -n1 /var/jb/basebin/jbctl trustcache add < /var/jb/etc/khoangcachantoan/cdhashes
```

Phải chạy bằng quyền root, `jbctl trustcache` từ chối khi không phải root.

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

## Phase 2 — đo khoảng cách (0.3.0)

### Bước 1: hiệu chỉnh (làm một lần, xe đứng yên)

1. Gắn điện thoại lên kính lái, nằm ngang, giữa kính, cao ngang gương chiếu hậu trong.
2. Đo bằng thước và nhập vào ⚙:
   - **Chiều cao ống kính so mặt đường**: từ mặt đường lên tâm ống kính.
   - **Điện thoại tới đầu xe**: từ vị trí điện thoại tới mép trước cản xe.
3. Đỗ xe trên mặt phẳng, nhìn thẳng. Bấm **Cân ngang**. Kiểm tra vạch nét đứt trên màn hình trùng với đường chân trời thật.

### Bước 2: đo tĩnh ở bãi xe

Đỗ sau một ô tô, dùng thước dây đo từ **đầu xe mình** tới **đuôi xe trước**.

| Thật (m) | App đọc (m) | Sai số | Ghi chú |
|---|---|---|---|
| 5 | | | |
| 10 | | | |
| 15 | | | |
| 20 | | | |
| 30 | | | |

Sau lượt đầu: ở khoảng 10–20 m, mở ⚙ → **Đặt k từ khoảng cách thật** → nhập số đo bằng thước. Rồi đo lại toàn bộ 5 mốc.

| # | Việc kiểm | Đạt khi | Kết quả |
|---|---|---|---|
| 2.1 | Số hiện ra | có số mét thay cho dấu gạch khi có xe trước | |
| 2.2 | Số không nhảy loạn | thay đổi mượt, không nhảy vọt vài chục mét | |
| 2.3 | Sai số sau hiệu chỉnh | **≤ 10 %** ở 10–30 m | |
| 2.4 | Vạch chân trời | trùng chân trời thật khi xe đứng trên mặt phẳng | |
| 2.5 | Cân ngang lưu được | thoát app rồi mở lại, offset vẫn giữ | |
| 2.6 | Huy hiệu cần hiệu chỉnh | chỉ xuất hiện khi hai phép đo lệch nhiều, không hiện liên tục lúc bình thường | |
| 2.7 | Dấu ngã | khi xe rất xa (trên 100 m) số có dấu `~` phía trước | |
| 2.8 | Mất xe thì xoá số | che camera, sau khoảng 1 giây số về dấu gạch | |

Trong nhật ký có dòng `range: ... D_w=... D_g=... hop=... -> ... m` mỗi khoảng 10 giây. Gửi kèm khi báo cáo: nếu `D_w` và `D_g` lệch nhau nhiều thì vấn đề nằm ở chiều cao ống kính hoặc góc cân ngang, không phải ở hệ số k.

## Phase 3 — luật và cảnh báo (0.4.0)

### Trong nhà, không cần lái

| # | Việc kiểm | Cách làm | Đạt khi | Kết quả |
|---|---|---|---|---|
| 3.1 | Tự kiểm tra bảng ngưỡng | ⚙ → Tự kiểm tra bảng ngưỡng | báo "tất cả phép thử đều đạt"; trong log mọi dòng `selftest:` là PASS | |
| 3.2 | Màn Luật | ⚙ → Bảng khoảng cách và mức phạt | thấy đủ 35 / 55 / 70 / 100 m, ba mức phạt, phiên bản số liệu, miễn trừ trách nhiệm | |
| 3.3 | Nghe thử cảnh báo | ⚙ → Nghe thử | có rung, có tiếng bíp, có giọng đọc "Khoảng cách quá gần" | |
| 3.4 | Không cắt nhạc | mở nhạc rồi bấm Nghe thử | nhạc chỉ nhỏ đi trong lúc bíp rồi to lại, **không dừng** | |
| 3.5 | Tắt được giọng đọc | tắt "Giọng đọc" rồi Nghe thử | chỉ còn rung và bíp | |
| 3.6 | Chưa có GPS | để trong nhà | dòng dưới số ghi "đang chờ GPS", dải đáy không màu | |

### Ngoài đường (người khác cầm máy, không phải người lái)

| # | Việc kiểm | Đạt khi | Kết quả |
|---|---|---|---|
| 3.7 | Có tốc độ | góc phải trên hiện số km/h hợp lý so với đồng hồ xe | |
| 3.8 | Đứng yên | dừng đèn đỏ thì ghi "đang đứng yên", không cảnh báo | |
| 3.9 | Ngưỡng đúng | chạy 65–75 km/h thì ghi `≥ 55 m (luật)`; trên 85 km/h thì `≥ 70 m` | |
| 3.10 | Không nhấp nháy ngưỡng | chạy quanh 80 km/h, số ngưỡng không nhảy qua lại liên tục | |
| 3.11 | Ba màu | bám gần thì dải đáy chuyển vàng rồi đỏ nhấp nháy | |
| 3.12 | Cảnh báo không dồn dập | khi đỏ liên tục, cảnh báo kêu tối đa 1 lần mỗi 3 giây | |
| 3.13 | Thời tiết xấu | bấm ☔ thì ngưỡng tăng 1,5 lần, nhãn đổi thành "khuyến nghị (mưa/sương mù)" | |
| 3.14 | Không báo giả | đường trống, không có xe trước thì không kêu | |

### Kiểm tra cập nhật số liệu từ xa

Sửa `version` trong `app/Resources/legal.json` thành ngày mới hơn rồi đẩy lên; CI tự chép sang kho. Trên máy, xoá mốc thời gian kiểm tra rồi mở lại app hai lần:

```sh
sudo rm -f /var/mobile/Documents/KhoangCachAnToan/legal.json
```

Lần mở thứ nhất app tải bản mới về, lần mở thứ hai mới áp dụng. Vào màn Luật xem dòng "Nguồn tệp" đổi thành "tải về" và phiên bản là ngày mới.

## Ghi chú khi báo cáo

- Chụp màn hình lúc có xe trong khung.
- Gửi `log.txt` (lấy bằng `device_log.ps1`).
- Nếu app thoát đột ngột, lấy thêm báo cáo sự cố trong `/var/mobile/Library/Logs/CrashReporter/`.
