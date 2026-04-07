#!/usr/bin/env bash
set -euo pipefail

preferred_app_path="/Applications/ClaudeCost.app"
fallback_app_path="$HOME/Applications/ClaudeCost.app"

if [[ -d "/Applications" && -w "/Applications" ]]; then
  app_path="${preferred_app_path}"
elif [[ -e "${preferred_app_path}" && -w "${preferred_app_path}" ]]; then
  app_path="${preferred_app_path}"
else
  app_path="${fallback_app_path}"
fi

app_executable="${app_path}/Contents/MacOS/ClaudeCost"

pkill -f "$app_executable" 2>/dev/null || true
mkdir -p "$(dirname "${app_path}")"
rm -rf "$app_path"
cp -R .build/release/ClaudeCost.app "$app_path"
open "$app_path"
