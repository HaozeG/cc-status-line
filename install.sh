#!/bin/bash
# Install the status line: copies the script and adds the statusLine key to ~/.claude/settings.json.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dest="$HOME/.claude"; settings="$dest/settings.json"
for c in jq git bash; do command -v "$c" >/dev/null || { echo "missing dependency: $c" >&2; exit 1; }; done
mkdir -p "$dest"
install -m 755 "$here/statusline-command.sh" "$dest/statusline-command.sh"
[ -f "$settings" ] || echo '{}' > "$settings"
cp "$settings" "$settings.bak"
jq --slurpfile s "$here/settings.statusLine.json" '. + $s[0]' "$settings.bak" > "$settings"
echo "Installed to $dest/statusline-command.sh (settings backup: $settings.bak)"
echo "Restart Claude Code to see it."
