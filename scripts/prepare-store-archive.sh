#!/bin/bash
# Offline archive packaging only. No downloads, archive, export, or identity discovery.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
export PYTHONDONTWRITEBYTECODE=1
exec /usr/bin/env python3 "$repo_root/Tools/StorePackaging/prepare.py" "$@"
