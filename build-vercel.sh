#!/bin/bash
set -e

# Cài Flutter nếu chưa có
if [ ! -d "/tmp/flutter" ]; then
    echo "Installing Flutter..."
    cd /tmp
    git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

export PATH="/tmp/flutter/bin:$PATH"

# Cài dependencies
cd $VERCEL_BUILD_ENV || true
flutter pub get

# Build web
flutter build web --release

echo "Build completed!"
