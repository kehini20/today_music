#!/usr/bin/env bash
set -e

echo "Installing Flutter SDK..."

if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi

export PATH="$PATH:$HOME/flutter/bin"

flutter --version
flutter config --enable-web
flutter pub get
flutter build web --release