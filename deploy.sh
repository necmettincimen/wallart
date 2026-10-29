#!/usr/bin/env bash
# Web build alır, dosya adlarına sürüm ekler ve gh-pages dalına yayınlar.
# GitHub Pages dosyaları ~10 dk önbellekte tuttuğu için ?v=<sürüm> eklenmezse
# istemciler güncellemeden sonra eski main.dart.js'i kullanmaya devam eder.
set -euo pipefail
cd "$(dirname "$0")"

FLUTTER="${FLUTTER:-/d/flutter/bin/flutter.bat}"
REPO="https://github.com/necmettincimen/wallart.git"
V="$(date +%Y%m%d%H%M%S)"

# Git Bash, /wallart/ yolunu Windows yoluna çevirmesin.
MSYS_NO_PATHCONV=1 "$FLUTTER" build web --release --base-href /wallart/

cd build/web
sed -i "s|\"mainJsPath\":\"main.dart.js\"|\"mainJsPath\":\"main.dart.js?v=$V\"|" flutter_bootstrap.js
sed -i "s|src=\"flutter_bootstrap.js\"|src=\"flutter_bootstrap.js?v=$V\"|; s|href=\"main.dart.js\"|href=\"main.dart.js?v=$V\"|" index.html
grep -q "main.dart.js?v=$V" flutter_bootstrap.js || { echo "mainJsPath sürümlenemedi" >&2; exit 1; }
touch .nojekyll

rm -rf .git
git init -q -b gh-pages
git config core.autocrlf false
git add -A
git commit -q -m "Web yayını $V"
[ "${1:-}" = "--no-push" ] && { echo "Build hazır: sürüm $V"; exit 0; }
git push -q -f "$REPO" gh-pages
echo "Yayınlandı: sürüm $V"
