#!/bin/bash
# テスト実行用に swift.org 公式ツールチェーンをユーザー領域へ展開する。
# - Command Line Tools だけの環境（Xcode未導入）では XCTest も swift-testing も無いため
#   swift test を実行できない。公式ツールチェーンには swift-testing が同梱されている。
# - sudo不要。~/Library/Developer/Toolchains 以下に約4.6GB展開する。
# - 削除: rm -rf ~/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain
set -euo pipefail

VERSION="6.3.3"
TAG="swift-${VERSION}-RELEASE"
URL="https://download.swift.org/swift-${VERSION}-release/xcode/${TAG}/${TAG}-osx.pkg"
PKG="/tmp/${TAG}-osx.pkg"
DEST="$HOME/Library/Developer/Toolchains/${TAG}.xctoolchain"

if [[ -x "$DEST/usr/bin/swift" ]]; then
  echo "既にインストール済み: $DEST"
  exit 0
fi

echo "==> ダウンロード: $URL （約1.4GB）"
curl -fL -o "$PKG" "$URL"

echo "==> 展開中..."
WORK=$(mktemp -d /tmp/swifttc.XXXXXX)
xar -xf "$PKG" -C "$WORK"
mkdir -p "$HOME/Library/Developer/Toolchains"
rm -rf "$DEST"
mkdir -p "$DEST"
(cd "$DEST" && cat "$WORK/${TAG}-osx-package.pkg/Payload" | gzip -d | cpio -id --quiet)

rm -rf "$WORK" "$PKG"

echo "==> 検証"
"$DEST/usr/bin/swift" --version | head -2
echo "完了: $DEST"
echo "テスト実行: ./scripts/run-tests.sh"
