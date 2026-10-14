#!/bin/bash
# Live colored preview in your terminal: ./preview.sh [healthy|busy|critical]
here=$(cd "$(dirname "$0")" && pwd)
s=${1:-healthy}; now=$(date +%s)
sed -e "s#__CWD__#$here#" -e "s#__NOW_PLUS_11520__#$((now+11520))#" -e "s#__NOW_PLUS_385200__#$((now+385200))#" \
  "$here/fixtures/$s.json" | bash "$here/statusline-command.sh"
