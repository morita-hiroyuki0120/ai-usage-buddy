#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
render_tmp="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/AIUsageBuddy-AppIcon.XXXXXX")"
trap '/bin/rm -f -- "$render_tmp/render-app-icon"; /bin/rmdir -- "$render_tmp"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcrun swiftc \
    -swift-version 5 -parse-as-library \
    "$ROOT/Sources/AIUsageBuddy/Models/CharacterState.swift" \
    "$ROOT/Sources/AIUsageBuddy/Views/CatDrawing.swift" \
    "$ROOT/Tools/AppIcon/RenderAppIcon.swift" \
    -o "$render_tmp/render-app-icon"
"$render_tmp/render-app-icon" "$ROOT/Store/Assets.xcassets/AppIcon.appiconset"
