# Nhật ký thay đổi

Định dạng phiên bản: `MAJOR.MINOR.PATCH`. Mỗi bản phát hành có tag `v<ver>-<sha7>` trên GitHub và một file `.deb` trong kho Sileo.

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
