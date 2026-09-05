from PIL import Image, ImageDraw
import os, shutil
os.makedirs("app/Resources", exist_ok=True); os.makedirs("repo", exist_ok=True)
sizes = {"AppIcon60x60@2x": 120, "AppIcon60x60@3x": 180, "AppIcon-Small-40@2x": 80,
         "AppIcon-Small-40@3x": 120, "AppIcon-Small@2x": 58, "AppIcon-Small@3x": 87}
for name, s in sizes.items():
    img = Image.new("RGB", (s, s), (48, 209, 88))           # nen xanh la, khong alpha (iOS tu bo goc)
    d = ImageDraw.Draw(img)
    d.rectangle((int(s*.16), int(s*.40), int(s*.34), int(s*.60)), fill="white")   # xe truoc
    d.rectangle((int(s*.66), int(s*.40), int(s*.84), int(s*.60)), fill="white")   # xe minh
    d.line((int(s*.36), int(s*.50), int(s*.64), int(s*.50)), fill="white", width=max(2, s // 28))
    img.save(f"app/Resources/{name}.png")
shutil.copyfile("app/Resources/AppIcon60x60@3x.png", "repo/icon.png")
print("ok")
