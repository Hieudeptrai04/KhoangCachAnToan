#!/bin/bash
# Dung Packages / Packages.gz / Release tu MOI .deb dang co trong <site>/pool/main (kho tich luy nhieu ban).
set -euo pipefail
SITE="$1"
BASE_URL="https://hieudeptrai04.github.io/KhoangCachAnToan"
cd "$SITE"
ls pool/main/*.deb >/dev/null 2>&1 || { echo "no deb in pool"; exit 1; }
: > Packages.new
SEP=0
VERLIST=""
for DEB in pool/main/*.deb; do
  BN=$(basename "$DEB")
  CTRL=$(dpkg-deb -f "$DEB")
  VER=$(printf '%s\n' "$CTRL" | sed -n 's/^Version: *//p' | head -1)
  if [ "$SEP" -eq 1 ]; then printf '\n' >> Packages.new; fi
  SEP=1
  printf '%s\n' "$CTRL" | grep -vE '^(Filename|Size|MD5sum|SHA1|SHA256|Icon|SileoDepiction|Depiction|Tag):' >> Packages.new
  printf 'Icon: %s/icon.png\n' "$BASE_URL" >> Packages.new
  printf 'SileoDepiction: %s/depiction.json\n' "$BASE_URL" >> Packages.new
  printf 'Depiction: %s/depiction.html\n' "$BASE_URL" >> Packages.new
  printf 'Tag: purpose::uikit, compatible::dopamine\n' >> Packages.new
  printf 'Filename: pool/main/%s\n' "$BN" >> Packages.new
  printf 'Size: %s\n' "$(stat -f%z "$DEB")" >> Packages.new
  printf 'MD5sum: %s\n' "$(md5 -q "$DEB")" >> Packages.new
  printf 'SHA1: %s\n' "$(shasum -a 1 "$DEB" | cut -d' ' -f1)" >> Packages.new
  printf 'SHA256: %s\n' "$(shasum -a 256 "$DEB" | cut -d' ' -f1)" >> Packages.new
  VERLIST="$VERLIST $VER"
  echo "indexed $BN ($VER)"
done
grep -q '^Package: ' Packages.new
mv Packages.new Packages
gzip -9 -n -kf Packages          # -n: khong ghi ten/mtime vao header -> cung input cho cung bytes, tranh commit rac
NEWEST=$(printf '%s\n' $VERLIST | python3 -c '
import sys
vs=[l.strip() for l in sys.stdin if l.strip()]
key=lambda v:[(0,int(p)) if p.isdigit() else (1,p) for p in v.replace("-",".").split(".")]
print(sorted(vs,key=key)[-1])')
cat > Release <<EOF
Origin: Khoang Cach An Toan
Label: Khoang Cach An Toan
Suite: stable
Version: ${NEWEST}
Codename: ios
Architectures: iphoneos-arm64
Components: main
Description: Do khoang cach xe phia truoc bang camera, doi chieu Thong tu 38/2024
EOF
echo "Release Version -> ${NEWEST}"
