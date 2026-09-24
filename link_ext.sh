#!/bin/sh
# Hard-links the extension into the MoneyMoney extensions folder so that
# edits in this repository take effect immediately in MoneyMoney.
# Requires the signature check to be disabled in MoneyMoney:
# Einstellungen → Erweiterungen → "Digitale Signatur von Extensions überprüfen".
set -e
cd "$(dirname "$0")"

EXT_DIR="$HOME/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions"
NAME="GEG-Gastro.lua"

rm -f "$EXT_DIR/$NAME"
ln "$NAME" "$EXT_DIR/$NAME"
ls -li "$EXT_DIR/$NAME" "$NAME"
