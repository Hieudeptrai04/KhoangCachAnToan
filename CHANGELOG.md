# Nhật ký thay đổi

Định dạng phiên bản: `MAJOR.MINOR.PATCH`. Mỗi bản phát hành có tag `v<ver>-<sha7>` trên GitHub và một file `.deb` trong kho Sileo.

## 0.3.0 — 2026-09-06 (Phase 2: đo khoảng cách)

- **Đo khoảng cách thật**, thay số giả trên HUD. Hai phép đo độc lập chạy song song rồi hợp nhất theo nghịch phương sai: một theo bề rộng xe trong ảnh, một theo vị trí cạnh đáy xe trên mặt đường. Sai số của từng phép được ước lượng từ sai số vị trí cạnh khung bao, quy đổi theo hệ số thu nhỏ của đúng kênh đã phát hiện ra xe đó.
- Phép đo theo bề rộng chỉ dùng khi tỉ lệ khung bao còn hợp lý cho lớp xe đó, vì xe lệch góc làm khung rộng ra. Phép đo theo mặt đường chỉ dùng khi góc nhìn xuống đủ lớn.
- Lọc theo thời gian: trung vị 5 mẫu để loại giá trị lạc, rồi bộ lọc Kalman một chiều mô hình vận tốc không đổi. Bộ lọc cũng cho ra tốc độ tiến sát, dùng cho cảnh báo va chạm ở bản sau.
- Góc chúc camera lấy từ trọng lực, lọc thông thấp. Cách tính không phụ thuộc máy đang nằm ngang chiều nào. Vạch chân trời trên HUD vẽ đúng theo góc này nên dùng để cân máy.
- Màn cài đặt đầy đủ: chiều cao ống kính, khoảng cách tới đầu xe, hệ số chỉnh tay, nút cân ngang, bề rộng bốn lớp xe, số khung suy luận, hệ số thời tiết xấu, bật tắt vạch hướng dẫn. Có nút đặt hệ số chỉnh tay từ một lần đo bằng thước.
- Cài đặt lưu thẳng vào plist riêng của app, không dựa vào NSUserDefaults vì app chạy ngoài sandbox.
- Huy hiệu "cần hiệu chỉnh" khi hai phép đo lệch quá 30 % kéo dài trên 1 giây. Khoảng cách từ 100 m trở lên hiện dấu ngã phía trước để nhắc đây chỉ là ước lượng.
- Tốc độ và ngưỡng theo luật vẫn chưa có, chờ Phase 3.

## 0.2.1 — 2026-09-06

- **Sửa lỗi vẽ khung bao bị xoay hai lần.** Buffer giao cho mô hình đã được xoay sẵn theo chiều màn hình, nhưng hàm quy đổi của lớp preview lại nhận toạ độ theo khung chưa xoay và tự xoay thêm một lần nữa. Hậu quả: ở một trong hai chiều ngang, mọi khung bao bị lật đối xứng qua tâm màn hình trong khi hình vẫn hiện đúng, nên rất dễ bỏ sót khi thử. Nay quy đổi bằng phép co giãn thuần, đúng ở cả hai chiều.
- Cắt khung bao về trong khung hình và cắt lớp phủ theo mép view, tránh khung tràn ra ngoài.
- Ghi ra log toạ độ thô của kênh xa ở lần phát hiện đầu tiên, để kiểm chứng hệ toạ độ ngay trên máy.
- Ghi chú trong mã về hai ràng buộc dễ phá vỡ: việc xoay buffer ở data output gắn liền với hướng khai báo cho Vision, và cách khớp chiều ngang giữa giao diện với camera.

## 0.2.0 — 2026-09-06 (Phase 1: phát hiện xe)

- Nạp mô hình YOLOv3-Tiny Int8 từ bundle bằng Core ML, ghi ra log toàn bộ tên đầu vào, đầu ra và danh sách nhãn trước khi dùng, không giả định trước tên nào.
- Hai kênh suy luận: kênh xa đặt vùng quan tâm ở giữa khung nên xe ở xa được phóng to trước khi đưa vào mô hình; kênh gần quét cả khung, chạy một lần trên mỗi ba lần suy luận. Hai kênh gộp bằng loại bỏ trùng lặp theo tỉ lệ giao trên hợp.
- Lọc theo lớp xe: ô tô, xe tải, xe buýt, xe máy. Nhãn xe máy khớp theo tiền tố nên chạy được với cả `motorbike` lẫn `motorcycle`.
- Chọn xe dẫn đầu: hình thang hành lang làn, xe cùng làn có cạnh đáy thấp nhất. Đổi mục tiêu chỉ khi ứng viên mới thắng 5 khung liên tiếp. Mất dấu thì giữ khung cũ tối đa 1 giây rồi bỏ.
- Lớp phủ vẽ khung bao: xe dẫn đầu khung dày đổi màu theo trạng thái, xe khác khung xám mảnh, kèm nhãn và độ tin cậy. Toạ độ quy đổi qua chính phép biến đổi của lớp preview nên khớp với ảnh đang hiển thị.
- Số khung suy luận mỗi giây hiện trên HUD, chuyển được giữa 15 và 10 khung mỗi giây trong cài đặt. Hiện được vùng quan tâm của kênh xa để kiểm tra khi hiệu chỉnh.
- Khoảng cách và tốc độ trên HUD vẫn là số giả có nhãn DEMO; đo thật ở Phase 2.

## 0.1.1 — 2026-09-06

- **Sửa lỗi hiển thị**: bổ sung khoá `UILaunchScreen` vào `Info.plist`. Thiếu khoá này iOS coi app là ứng dụng đời cũ, chạy ở chế độ tương thích: preview camera và HUD bị thu nhỏ, có viền đen hai bên và `safeAreaInsets` bằng 0 trên iPhone X.
- Đóng gói lại `.deb` với `--root-owner-group`: mọi file thuộc `root/root` thay vì UID của máy chạy CI.
- CI kiểm tra hai điều kiện trước khi phát hành: `Info.plist` có `UILaunchScreen`, và mọi file trong `.deb` thuộc `root/root`.
- Ghi rõ địa chỉ kho Sileo sau chuyển hướng: `https://zalosuper.net/KhoangCachAnToan/`.

## 0.1.0 — 2026-09-05 (Phase 0: khung xương)

- Khung dự án Theos rootless (`iphone:clang:16.5:15.0`), CI GitHub Actions build → Release → kho Sileo trên `gh-pages`.
- App mở lên vào thẳng camera: AVCaptureSession 1080p, ưu tiên camera tele, khóa lấy nét vô cực, bật nhận ma trận nội tại (fx, fy, cx, cy) và ghi ra log.
- HUD màn ngang: khoảng cách 96 pt, ngưỡng, tốc độ, khoảng thời gian, dải màu đáy (đỏ nhấp nháy 2 Hz), nút ☔ / ⚙, vạch chân trời + hình thang làn.
- Số trên HUD ở bản này là **số giả (DEMO)** để kiểm tra bố cục; chưa có phát hiện xe hay đo thật.
- Nhật ký kỹ thuật `/var/mobile/Documents/KhoangCachAnToan/log.txt` (xoay vòng 1 MB).
- `legal.json` (Thông tư 38/2024, Nghị định 168/2024) đóng gói trong bundle; chưa dùng để tính toán.
