#!/bin/bash
# Render docs/*.svg (and docs/*.txt) by running the real status line against throwaway repos.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; mkdir -p "$HOME/.claude"
echo '{"advisorModel":"opus"}' > "$HOME/.claude/settings.json"
export GIT_AUTHOR_NAME=demo GIT_AUTHOR_EMAIL=demo@example.com GIT_COMMITTER_NAME=demo GIT_COMMITTER_EMAIL=demo@example.com
export GIT_AUTHOR_DATE="$(date -d "2 hours ago" -R)" GIT_COMMITTER_DATE="$(date -d "2 hours ago" -R)"
g() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

setup_repo() {  # NAME -> path of a repo with an upstream
  local r="$tmp/$1" o="$tmp/$1-origin.git"
  git init -q --bare "$o"; git init -q -b main "$r"
  echo one > "$r/app.py"; g "$r" add .; g "$r" commit -m "Initial commit"
  g "$r" remote add origin "$o"; g "$r" push -u origin main
  echo "$r"
}

healthy=$(setup_repo my-project)
busy=$(setup_repo web-app)
echo two >> "$busy/app.py"; g "$busy" commit -am "Add request retry with exponential backoff for flaky upstream calls"
echo three > "$busy/staged.py"; g "$busy" add staged.py
echo four >> "$busy/app.py"; echo x > "$busy/notes.txt"
echo wip > "$busy/wip"; g "$busy" add wip; g "$busy" stash
echo five >> "$busy/app.py"; echo y > "$busy/staged.py"; g "$busy" add staged.py
critical=$(setup_repo data-pipeline)
g "$critical" checkout -q -b feature; echo a > "$critical/f"; g "$critical" add f; g "$critical" commit -m "Feature work"
g "$critical" checkout -q main; echo b > "$critical/f"; g "$critical" add f; g "$critical" commit -m "Main work"
g "$critical" merge feature || true

now=$(date +%s)
for s in healthy busy critical; do
  cwd=${!s}
  sed -e "s#__CWD__#$cwd#" -e "s#__NOW_PLUS_11520__#$((now+11520))#" -e "s#__NOW_PLUS_385200__#$((now+385200))#" \
    "$here/fixtures/$s.json" | bash "$here/statusline-command.sh" > "$tmp/$s.ansi"
  python3 -I "$here/tools/ansi2svg.py" < "$tmp/$s.ansi" > "$here/docs/$s.svg"
  sed 's/\x1b\[[0-9;]*m//g' "$tmp/$s.ansi" > "$here/docs/$s.txt"
done
echo "rendered: $(ls "$here"/docs)"
