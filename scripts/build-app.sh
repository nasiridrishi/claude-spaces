#!/usr/bin/env bash
# Builds "Claude Spaces.app" into ./build. Pass --install to also copy it to ~/Applications.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
bin_path="$(swift build -c release --show-bin-path)"

app="build/Claude Spaces.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/ClaudeSpaces" "$app/Contents/MacOS/ClaudeSpaces"
cp Resources/Info.plist "$app/Contents/Info.plist"

# Ad-hoc signature: enough for SMAppService and TCC on this machine; not for distribution.
codesign --force --sign - "$app"

echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
    dest="$HOME/Applications/Claude Spaces.app"
    mkdir -p "$HOME/Applications"
    if pgrep -xq ClaudeSpaces; then
        pkill -x ClaudeSpaces || true
        sleep 1
    fi
    rm -rf "$dest"
    cp -R "$app" "$dest"
    echo "Installed $dest"
fi
