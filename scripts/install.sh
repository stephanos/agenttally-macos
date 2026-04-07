#!/usr/bin/env bash
set -euo pipefail

app_path="$HOME/Applications/ClaudeCost.app"
app_executable="$app_path/Contents/MacOS/ClaudeCost"

pkill -f "$app_executable" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$app_path"
cp -R .build/release/ClaudeCost.app "$app_path"
open "$app_path"
