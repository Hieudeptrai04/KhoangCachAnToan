#!/bin/bash
# Cho GitHub Actions build xong ma KHONG dung gh (muc 8.5). Chay trong Git Bash tai thu muc goc repo.
#   tools/wait_ci.sh            -> theo doi HEAD hien tai
#   tools/wait_ci.sh <sha7>     -> theo doi commit khac
set -u
# Mac dinh theo doi commit GAN NHAT co dong vao app/, repo/ hoac workflow:
# commit chi sua tai lieu khong kich hoat build (bo loc paths:), doi no se timeout oan.
SHA7="${1:-$(git log -1 --format=%h --abbrev=7 -- app repo .github/workflows/build.yml)}"
VERSION=$(grep '^Version:' app/control | awk '{print $2}')
echo "waiting for build of $SHA7 (version $VERSION) ..."
for i in $(seq 1 40); do
  out=$(git ls-remote --tags origin 2>/dev/null)
  if echo "$out" | grep -q "refs/tags/v${VERSION}-${SHA7}"; then
    echo "BUILD_OK  tag v${VERSION}-${SHA7}"
    echo "deb: https://github.com/Hieudeptrai04/KhoangCachAnToan/releases/download/v${VERSION}-${SHA7}/KhoangCachAnToan_${VERSION}_iphoneos-arm64.deb"
    exit 0
  fi
  fail=$(echo "$out" | grep -o "refs/tags/debug-fail-${SHA7}-[0-9]*" | head -1)
  if [ -n "$fail" ]; then
    TAG=${fail#refs/tags/}
    echo "BUILD_FAILED  tag $TAG"
    echo "log: https://github.com/Hieudeptrai04/KhoangCachAnToan/releases/download/${TAG}/build.log"
    exit 1
  fi
  sleep 30
done
echo "TIMEOUT (20 min)"
exit 2
