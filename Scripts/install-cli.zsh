#!/bin/zsh

set -euo pipefail

ROOT=${0:A:h:h}
INSTALL_DIR=${FACTORYLOG_INSTALL_DIR:-"$HOME/.local/bin"}

swift build \
  --package-path "$ROOT" \
  --configuration release \
  --product factorylog

BIN_PATH=$(swift build \
  --package-path "$ROOT" \
  --configuration release \
  --show-bin-path)

mkdir -p "$INSTALL_DIR"
cp "$BIN_PATH/factorylog" "$INSTALL_DIR/factorylog"
chmod +x "$INSTALL_DIR/factorylog"

print "$INSTALL_DIR/factorylog"
