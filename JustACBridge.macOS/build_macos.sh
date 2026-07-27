#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
app_dir="$project_dir/dist/JustACBridge.app"
build_dir="$project_dir/.build"

swift build \
  --package-path "$project_dir" \
  --configuration release \
  --jobs 2

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/release/JustACBridgeMac" "$app_dir/Contents/MacOS/JustACBridgeMac"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
chmod +x "$app_dir/Contents/MacOS/JustACBridgeMac"
codesign --force --deep --sign - "$app_dir"

echo "构建完成：$app_dir"
