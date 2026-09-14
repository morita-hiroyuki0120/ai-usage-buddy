#!/bin/bash
# ユニットテストを実行する。
# この環境のCommand Line ToolsにはXCTest / Testingモジュールが無いため、
# swift.org公式ツールチェーン（swift-testing同梱）を使用する。
# ツールチェーンが無い場合は先に scripts/setup-test-toolchain.sh を実行すること。
set -euo pipefail

TOOLCHAIN_DIR="$HOME/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain"

if [[ ! -x "$TOOLCHAIN_DIR/usr/bin/swift" ]]; then
  echo "Swift 6.3.3 ツールチェーンが見つかりません。" >&2
  echo "先に scripts/setup-test-toolchain.sh を実行してください。" >&2
  exit 1
fi

exec "$TOOLCHAIN_DIR/usr/bin/swift" test "$@"
