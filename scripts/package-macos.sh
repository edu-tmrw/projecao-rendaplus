#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
root="$(pwd -P)"
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
executable="$app/Contents/MacOS/ProjecaoRenda"
install -m 755 "$bin" "$executable"
strip -S "$executable"
if LC_ALL=C grep -aEq '/Users/[^/]+/' "$executable"; then
    echo 'O executável ainda contém um caminho local de usuário.' >&2
    exit 1
fi
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict --verbose=2 "$app"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$app" "$stage/Projecao-Vitalicia-macOS.zip"
mv -f "$stage/Projecao-Vitalicia-macOS.zip" "$root/dist/"
