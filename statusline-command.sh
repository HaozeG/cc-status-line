#!/bin/bash
# Claude Code status line: model/effort/advisor, git (cached), usage meters.
input=$(cat)

# ---------- palette (256-color) ----------
RST=$'\033[0m'; BOLD=$'\033[1m'
C_MODEL=$'\033[38;5;81m'    # cyan
C_ADV=$'\033[38;5;177m'     # violet
C_REPO=$'\033[38;5;75m'     # blue
C_BRANCH=$'\033[38;5;114m'  # soft green
C_LABEL=$'\033[38;5;250m'   # light gray
C_DIM=$'\033[38;5;240m'     # dark gray (empty bar, separators)
C_OK=$'\033[38;5;71m'       # green
C_WARN=$'\033[38;5;220m'    # yellow
C_HOT=$'\033[38;5;208m'     # orange
C_CRIT=$'\033[38;5;196m'    # red
C_STAGED=$C_OK; C_MOD=$C_WARN; C_UNT=$'\033[38;5;247m'; C_CONF=$C_CRIT
C_SYNC=$'\033[38;5;80m'; C_ADD=$C_OK; C_DEL=$'\033[38;5;203m'
SEP=" ${C_DIM}│${RST} "

# ---------- tunables ----------
COMMIT_WIDTH=110   # max chars of commit subject per line; longer subjects wrap on word boundaries
COMMIT_LINES=2     # max lines the subject may use (last one ends with …)
CACHE_FRESH=3      # seconds a git result is used as-is
CACHE_STALE=120    # seconds a stale git result is still shown while refreshing in the background
CACHE_DIR="$HOME/.claude/cache"

# ---------- parse input + settings in ONE jq call each ----------
IFS=$'\t' read -r model effort cwd ctx_pct five_pct five_reset week_pct week_reset < <(
  jq -r '[(.model.display_name // "Claude"), (.effort.level // "-"),
          (.workspace.current_dir // .cwd // "-"), (.context_window.used_percentage // "-"),
          (.rate_limits.five_hour.used_percentage // "-"), (.rate_limits.five_hour.resets_at // "-"),
          (.rate_limits.seven_day.used_percentage // "-"), (.rate_limits.seven_day.resets_at // "-")] | @tsv' <<<"$input")
[ "$cwd" = "-" ] && cwd=""

# Advisor model is not in the status JSON; first of project-local > project > user settings
files=()
for f in "$cwd/.claude/settings.local.json" "$cwd/.claude/settings.json" "$HOME/.claude/settings.json"; do
  [ -f "$f" ] && files+=("$f")
done
advisor=""
[ "${#files[@]}" -gt 0 ] && advisor=$(jq -rs '[.[].advisorModel // empty][0] // empty' "${files[@]}" 2>/dev/null)

# ---------- helpers ----------
sev_color() {  # green <50, yellow <75, orange <90, red >=90
  local p=${1%.*}; [ -z "$p" ] && p=0
  if   [ "$p" -ge 90 ]; then printf '%s' "$C_CRIT"
  elif [ "$p" -ge 75 ]; then printf '%s' "$C_HOT"
  elif [ "$p" -ge 50 ]; then printf '%s' "$C_WARN"
  else printf '%s' "$C_OK"; fi
}

bar() {  # filled blocks in severity color + dim empty blocks
  local pct=${1%.*} width=${2:-10}
  [ -z "$pct" ] && pct=0; [ "$pct" -lt 0 ] && pct=0; [ "$pct" -gt 100 ] && pct=100
  local filled=$(( (pct * width + 50) / 100 ))
  [ "$pct" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
  [ "$pct" -lt 100 ] && [ "$filled" -eq "$width" ] && filled=$(( width - 1 ))
  local f="" e="" i
  for ((i=0; i<filled; i++)); do f+="█"; done
  for ((i=filled; i<width; i++)); do e+="░"; done
  printf '%s%s%s%s%s' "$(sev_color "$pct")" "$f" "$C_DIM" "$e" "$RST"
}

meter() {  # ICON LABEL PCT [COUNTDOWN]
  local out="$1 ${C_LABEL}$2${RST} $(bar "$3" 10) $(sev_color "$3")${BOLD}$(printf '%3d' "$3")%${RST}"
  [ -n "$4" ] && out+=" ${C_DIM}resets${RST} ${C_LABEL}$4${RST}"
  printf '%s' "$out"
}

wrap_subject() {  # wrap_subject TEXT -> up to COMMIT_LINES lines of <= COMMIT_WIDTH chars, word-aware
  local text=$1 lines=() line="" w
  for w in $text; do
    if [ -z "$line" ]; then line=$w
    elif [ $(( ${#line} + 1 + ${#w} )) -le "$COMMIT_WIDTH" ]; then line+=" $w"
    else lines+=("$line"); line=$w; fi
  done
  [ -n "$line" ] && lines+=("$line")
  if [ "${#lines[@]}" -gt "$COMMIT_LINES" ]; then
    lines=("${lines[@]:0:$COMMIT_LINES}")
    lines[$((COMMIT_LINES-1))]="${lines[$((COMMIT_LINES-1))]}…"
  fi
  local i
  for ((i=0; i<${#lines[@]}; i++)); do
    [ "$i" -gt 0 ] && printf '\n      '
    printf '%s' "${lines[$i]}"
  done
}

# ---------- git block (status line + commit line) ----------
git_block() {
  local G="git -C $cwd --no-optional-locks" top gd
  { read -r top; read -r gd; } < <($G rev-parse --show-toplevel --absolute-git-dir 2>/dev/null)
  [ -z "$top" ] && return 0

  local branch="" has_up=0 ahead=0 behind=0 staged=0 modified=0 untracked=0 conflicts=0 line xy
  while IFS= read -r line; do
    case "$line" in
      "# branch.head "*)     branch=${line#\# branch.head } ;;
      "# branch.upstream "*) has_up=1 ;;
      "# branch.ab "*)       read -r _ _ ahead behind <<<"$line"; ahead=${ahead#+}; behind=${behind#-} ;;
      "1 "*|"2 "*)           xy=${line:2:2}
                             [ "${xy:0:1}" != "." ] && staged=$((staged+1))
                             [ "${xy:1:1}" != "." ] && modified=$((modified+1)) ;;
      "u "*)                 conflicts=$((conflicts+1)) ;;
      "? "*)                 untracked=$((untracked+1)) ;;
    esac
  done < <($G status --porcelain=v2 --branch --ignore-submodules=dirty 2>/dev/null)
  [ "$branch" = "(detached)" ] && branch="detached@$($G rev-parse --short HEAD 2>/dev/null)"

  local g="📁 ${C_REPO}${top##*/}${RST} ${C_DIM}⎇${RST} ${BOLD}${C_BRANCH}${branch}${RST}"
  if [ "$has_up" -gt 0 ]; then
    if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then g+=" ${C_SYNC}synced${RST}"
    else
      [ "$ahead" -gt 0 ]  && g+=" ${C_SYNC}${ahead} ahead${RST}"
      [ "$behind" -gt 0 ] && g+=" ${C_HOT}${behind} behind${RST}"
    fi
  else g+=" ${C_DIM}no upstream${RST}"; fi

  local op=""
  [ -e "$gd/MERGE_HEAD" ] && op=MERGING
  [ -e "$gd/CHERRY_PICK_HEAD" ] && op=CHERRY-PICKING
  { [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; } && op=REBASING
  [ -n "$op" ] && g+=" ${BOLD}${C_CRIT}⚠ ${op}${RST}"

  if [ $((staged+modified+untracked+conflicts)) -eq 0 ]; then
    g+="${SEP}${C_OK}✔ clean${RST}"
  else
    local w=() x first=1 ds ins="" del=""
    [ "$conflicts" -gt 0 ] && w+=("${BOLD}${C_CONF}${conflicts} conflicted${RST}")
    [ "$staged" -gt 0 ]    && w+=("${C_STAGED}${staged} staged${RST}")
    [ "$modified" -gt 0 ]  && w+=("${C_MOD}${modified} modified${RST}")
    [ "$untracked" -gt 0 ] && w+=("${C_UNT}${untracked} untracked${RST}")
    g+="$SEP"
    for x in "${w[@]}"; do [ $first -eq 0 ] && g+=" ${C_DIM}·${RST} "; g+="$x"; first=0; done
    ds=$($G diff --shortstat HEAD --ignore-submodules=dirty 2>/dev/null)
    if [[ $ds =~ ([0-9]+)\ insertion ]]; then ins=${BASH_REMATCH[1]}; fi
    if [[ $ds =~ ([0-9]+)\ deletion ]]; then del=${BASH_REMATCH[1]}; fi
    [ -n "$ins$del" ] && g+="${SEP}${C_ADD}+${ins:-0}${RST} ${C_DEL}−${del:-0}${RST} ${C_LABEL}lines${RST}"
  fi

  if [ -f "$gd/logs/refs/stash" ]; then
    local stash; stash=$(wc -l < "$gd/logs/refs/stash")
    [ "$stash" -gt 0 ] && g+="${SEP}📦 ${C_LABEL}${stash} stash${RST}"
  fi
  printf '%s\n' "$g"

  # commit line: hash, then the first line of the subject (wrapped), then age
  local h when sub
  IFS=$'\t' read -r h when sub < <($G log -1 --format='%h%x09%cr%x09%s' 2>/dev/null)
  if [ -n "$h" ]; then
    printf '%s\n' "↳ ${C_DIM}${h}${RST} ${C_LABEL}$(wrap_subject "$sub")${RST} ${C_DIM}· ${when}${RST}"
  fi
}

git_cached() {
  [ -z "$cwd" ] && return 0
  mkdir -p "$CACHE_DIR" 2>/dev/null
  local key; key=$(cksum <<<"$cwd"); key=${key%% *}
  local cache="$CACHE_DIR/git-$key" lock="$CACHE_DIR/git-$key.lock" now mtime age lm
  printf -v now '%(%s)T' -1
  if [ -f "$cache" ]; then
    mtime=$(stat -c %Y "$cache" 2>/dev/null || echo 0); age=$(( now - mtime ))
    if [ "$age" -le "$CACHE_FRESH" ]; then cat "$cache"; return 0; fi
    if [ "$age" -le "$CACHE_STALE" ]; then
      cat "$cache"   # serve stale instantly, refresh in the background (at most one at a time)
      lm=$(stat -c %Y "$lock" 2>/dev/null || echo 0)
      if [ $(( now - lm )) -gt 10 ]; then
        : > "$lock"
        ( git_block > "$cache.$$" 2>/dev/null; mv -f "$cache.$$" "$cache"; rm -f "$lock" ) >/dev/null 2>&1 &
        disown 2>/dev/null
      fi
      return 0
    fi
  fi
  git_block > "$cache.$$" 2>/dev/null; mv -f "$cache.$$" "$cache"; cat "$cache"
}

# ---------- muted palette for low-frequency info ----------
M_TXT=$'\033[38;5;245m'; M_DIM=$'\033[38;5;240m'; M_NAME=$'\033[38;5;109m'
SEPM=" ${M_DIM}·${RST} "

# muted_color PCT: stays gray until it matters (>=75 orange, >=90 red)
muted_color() {
  local p=${1%.*}; [ -z "$p" ] && p=0
  if   [ "$p" -ge 90 ]; then printf '%s' "$C_CRIT"
  elif [ "$p" -ge 75 ]; then printf '%s' "$C_HOT"
  else printf '%s' "$M_TXT"; fi
}

mbar() {  # compact 8-wide bar, gray unless near the limit
  local pct=${1%.*} width=8 f="" e="" i
  [ -z "$pct" ] && pct=0; [ "$pct" -lt 0 ] && pct=0; [ "$pct" -gt 100 ] && pct=100
  local filled=$(( (pct * width + 50) / 100 ))
  [ "$pct" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
  [ "$pct" -lt 100 ] && [ "$filled" -eq "$width" ] && filled=$(( width - 1 ))
  for ((i=0; i<filled; i++)); do f+="█"; done
  for ((i=filled; i<width; i++)); do e+="░"; done
  printf '%s%s%s%s%s' "$(muted_color "$pct")" "$f" "$M_DIM" "$e" "$RST"
}

mmeter() {  # LABEL PCT [RESET_IN]
  local out="${M_TXT}$1${RST} $(mbar "$2") $(muted_color "$2")$(printf '%d' "$2")%${RST}"
  [ -n "$3" ] && out+=" ${M_DIM}resets $3${RST}"
  printf '%s' "$out"
}

# ---------- git lines first: high-frequency, vivid ----------
git_cached

# ---------- one muted line: config + plan limits + context ----------
cfg="${M_NAME}${model}${RST}"
[ "$effort" != "-" ] && cfg+="${SEPM}${M_TXT}${effort}${RST}"
[ -n "$advisor" ] && cfg+="${SEPM}${M_TXT}advisor ${advisor}${RST}"

printf -v now '%(%s)T' -1
parts=("$cfg")
if [ "$five_pct" != "-" ] && [ "$five_reset" != "-" ]; then
  rem=$(( five_reset - now )); [ "$rem" -lt 0 ] && rem=0
  parts+=("$(mmeter '5h' "$(printf '%.0f' "$five_pct")" "$(printf '%dh%02dm' $((rem/3600)) $(((rem%3600)/60)))")")
fi
if [ "$week_pct" != "-" ] && [ "$week_reset" != "-" ]; then
  rem=$(( week_reset - now )); [ "$rem" -lt 0 ] && rem=0
  parts+=("$(mmeter '7d' "$(printf '%.0f' "$week_pct")" "$(printf '%dd%02dh' $((rem/86400)) $(((rem%86400)/3600)))")")
fi
[ "$ctx_pct" != "-" ] && parts+=("$(mmeter 'ctx' "$(printf '%.0f' "$ctx_pct")")")

line=""
for p in "${parts[@]}"; do [ -n "$line" ] && line+=" ${M_DIM}│${RST} "; line+="$p"; done
printf '%s\n' "$line"
