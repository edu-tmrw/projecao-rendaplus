#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
root="$PWD"
args=(--configuration release --arch arm64 --arch x86_64)

swift build "${args[@]}"
bin="$(swift build "${args[@]}" --show-bin-path)/ProjecaoRenda"
archs="$(lipo -archs "$bin")"
[[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]]

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
app="$stage/Projeção Vitalícia.app"
mkdir -p "$app/Contents/MacOS" "$root/dist"
cp Resources/Info.plist "$app/Contents/Info.plist"
install -m 755 "$bin" "$app/Contents/MacOS/ProjecaoRenda"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict --verbose=2 "$app"
ditto -c -k --keepParent "$app" "$stage/Projecao-Vitalicia-macOS.zip"
mv -f "$stage/Projecao-Vitalicia-macOS.zip" "$root/dist/"
