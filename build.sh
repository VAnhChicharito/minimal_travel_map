#!/bin/bash

# Cài đặt Flutter
echo "Installing Flutter..."
cd /tmp
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PATH:/tmp/flutter/bin"

# Kiểm tra Flutter
flutter --version

# Build web
echo "Building Flutter web..."
cd $OLDPWD
flutter pub get
flutter build web --release --dart-define=FLUTTER_WEB_USE_SKIA=false

echo "Build completed!"
