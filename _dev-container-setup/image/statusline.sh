#!/usr/bin/env bash
set +o errexit +o nounset +o pipefail 2>/dev/null; _f=${BASH_SOURCE[0]}; [[ -n "$_f" && -f "$_f" && -z "$SL_CRLF_FIXED" ]] && IFS= read -r -n 200 _l < "$_f" && [[ "$_l" == *$'\r' ]] && SL_CRLF_FIXED=1 exec bash -c "$(tr -d '\r' < "$_f")" "$_f" # CRLF self-heal: re-run this file once with CR removed
# ============================================================
#  Glacier status line for Claude Code  (ice & water theme)
#  Pure bash + awk: works in Git Bash on Windows, macOS and Linux.
#  No jq, no PowerShell, no execution-policy issues.
#  This file is ASCII-only: emoji are written as UTF-8 byte escapes.
#  Keep LF line endings (CRLF breaks bash scripts).
# ============================================================

# ---------- settings ----------
# Effort gauge style: wave | bubble | ripple | crystal | segment
EFFORT_STYLE='wave'

# Show a dot after the branch name when there are uncommitted changes.
# OFF by default: checking this requires running "git status", and git
# obeys the repository's own config. A malicious repository can then
#  - make git run arbitrary programs (e.g. clean filters), and
#  - make git open files on a network share (e.g. include.path), which on
#    Windows can send your login credentials to that server.
# Turn on only if you never open repositories from untrusted sources
# (zip files, other people's folders).
SHOW_DIRTY=0

# Muted label shown before the branch name (set to '' to hide it)
BRANCH_LABEL='branch'

# ---------- glyphs (UTF-8 bytes) ----------
I_SNOWMAN=$'\xe2\x9b\x84\xef\xb8\x8f'   # snowman (model)
I_ICE=$'\xf0\x9f\xa7\x8a'               # ice cube (workspace)
I_BRANCH=$'\xf0\x9f\xa6\x80'            # crab (git branch). Coral: \xf0\x9f\xaa\xb8
I_DROP=$'\xf0\x9f\x92\xa7'              # droplet (context)
I_JELLY=$'\xf0\x9f\xaa\xbc'             # jellyfish (rate limits)
I_DOLPHIN=$'\xf0\x9f\x90\xac'           # dolphin (5h limit reset countdown)
G_SEP=$'\xe2\x94\x82'
G_CELL=$'\xe2\x96\x88'
G_DOT=$'\xe2\x80\xa2'

case "$EFFORT_STYLE" in
  bubble)  G_ON=($'\xe2\x97\x8f' $'\xe2\x97\x8f' $'\xe2\x97\x8f' $'\xe2\x97\x8f' $'\xe2\x97\x8f')
           G_OFF=($'\xe2\x97\x8b' $'\xe2\x97\x8b' $'\xe2\x97\x8b' $'\xe2\x97\x8b' $'\xe2\x97\x8b'); OFFC=dim ;;
  ripple)  G_ON=($'\xe2\x88\xbf' $'\xe2\x88\xbf' $'\xe2\x88\xbf' $'\xe2\x88\xbf' $'\xe2\x88\xbf')
           G_OFF=("${G_ON[@]}"); OFFC=navy ;;
  crystal) G_ON=($'\xe2\x97\x86' $'\xe2\x97\x86' $'\xe2\x97\x86' $'\xe2\x97\x86' $'\xe2\x97\x86')
           G_OFF=($'\xe2\x97\x87' $'\xe2\x97\x87' $'\xe2\x97\x87' $'\xe2\x97\x87' $'\xe2\x97\x87'); OFFC=dim ;;
  segment) G_ON=($'\xe2\x96\xb0' $'\xe2\x96\xb0' $'\xe2\x96\xb0' $'\xe2\x96\xb0' $'\xe2\x96\xb0')
           G_OFF=($'\xe2\x96\xb1' $'\xe2\x96\xb1' $'\xe2\x96\xb1' $'\xe2\x96\xb1' $'\xe2\x96\xb1'); OFFC=dim ;;
  *)       G_ON=($'\xe2\x96\x81' $'\xe2\x96\x82' $'\xe2\x96\x83' $'\xe2\x96\x85' $'\xe2\x96\x87')
           G_OFF=("${G_ON[@]}"); OFFC=navy ;;
esac

# ---------- colours ----------
E=$'\033'
# fg VAR R G B : store a 24-bit colour escape in VAR (no subshell = fast in Git Bash)
fg() { printf -v "$1" '%s[38;2;%d;%d;%dm' "$E" "$2" "$3" "$4"; }
RST="$E[0m"; BOLD="$E[1m"
fg DIM 90 110 135; fg FROST 224 242 254; fg ICE 165 243 252
fg AQUA 103 232 249; fg SKY 56 189 248; fg OCEAN 14 165 233
fg WARN 251 191 36; fg DANGER 248 113 113; fg NAVY 30 41 82
[ "$OFFC" = navy ] && OFFC_C=$NAVY || OFFC_C=$DIM
SEP=" $DIM$G_SEP$RST "

# rnd NUM DEN -> RN = NUM/DEN rounded half-to-even (same as PowerShell)
rnd() {
  local q=$(( $1 / $2 )) rem=$(( $1 % $2 ))
  if   [ $(( rem * 2 )) -gt $2 ]; then q=$(( q + 1 ))
  elif [ $(( rem * 2 )) -eq $2 ] && [ $(( q % 2 )) -eq 1 ]; then q=$(( q + 1 )); fi
  RN=$q
}
# san VAR : replace with "?" every character that can control the terminal or
# make text display as something else (shown, not hidden, so tampering stays
# visible): C0/C1 controls (ESC, CSI, ...), bidi controls
# (U+200E/F, U+202A-202E, U+2066-2069), invisible characters (U+200B,
# U+2060, U+FEFF, Unicode tag chars) and line/paragraph separators
# (U+2028/2029). Byte-wise in the C locale, whatever the shell locale.
san() {
  local LC_ALL=C
  local v=${!1}
  v=${v//[$'\x01'-$'\x1f'$'\x7f']/?}
  v=${v//$'\xc2'[$'\x80'-$'\x9f']/?}
  v=${v//$'\xe2\x80'[$'\x8b\x8e\x8f\xa8'-$'\xae']/?}
  v=${v//$'\xe2\x81'[$'\xa0\xa6'-$'\xa9']/?}
  v=${v//$'\xef\xbb\xbf'/?}
  v=${v//$'\xf3\xa0'[$'\x80\x81'][$'\x80'-$'\xbf']/?}
  printf -v "$1" '%s' "$v"
}
# Gradient ice -> deep sea. Usage: grad K N  (position K of 0..N) -> sets $GC
GR=(165 56 37 30); GG=(243 189 99 58); GB=(252 248 235 138)
grad() {
  local n=$2; [ "$n" -le 0 ] && n=1
  local M=1000000
  local pos=$(( $1 * 3 * M / n )); local s=$(( pos / M )); [ $s -gt 2 ] && s=2
  local f=$(( pos - s * M ))
  rnd $(( GR[s] * M + (GR[s+1]-GR[s]) * f )) $M; local r=$RN
  rnd $(( GG[s] * M + (GG[s+1]-GG[s]) * f )) $M; local g=$RN
  rnd $(( GB[s] * M + (GB[s+1]-GB[s]) * f )) $M
  fg GC $r $g $RN
}

# ---------- read JSON from stdin ----------
# A small JSON reader in awk. Prints one line per requested key, in order.
# Keys starting with '#' are numbers (printed rounded to an integer).
# '!dir' is the workspace path and '!leaf' its last folder name.
# Strings are sanitised (control, bidi and invisible characters -> "?"),
# \uXXXX escapes not decoded; names are capped at 40 characters.
KEYS='model.display_name effort.level !dir !leaf #context_window.used_percentage #rate_limits.five_hour.used_percentage #rate_limits.five_hour.resets_at #rate_limits.seven_day.used_percentage'
PARSED=$(LC_ALL=C awk -v keys="$KEYS" '
function emit(v,   p, k) { p = ""; for (k = 1; k <= depth; k++) p = p (k > 1 ? "." : "") key[k]; val[p] = v }
function nchars(v,   i, n) { n = 0; for (i = 1; i <= length(v); i++) if (substr(v, i, 1) !~ /[\200-\277]/) n++; return n }
function clean(v, max,   out, i, b, n) {
  gsub(/[\001-\037\177]/, "?", v); gsub(/\302[\200-\237]/, "?", v)
  gsub(/\342\200[\213\216\217\250-\256]/, "?", v); gsub(/\342\201[\240\246-\251]/, "?", v)  # bidi, zero-width, line sep.
  gsub(/\357\273\277/, "?", v); gsub(/\363\240[\200\201][\200-\277]/, "?", v)           # BOM, Unicode tag chars
  if (max == 0 || nchars(v) <= max) return v
  out = ""; n = 0
  for (i = 1; i <= length(v); i++) {
    b = substr(v, i, 1)
    if (b !~ /[\200-\277]/) { n++; if (n > max - 1) break }
    out = out b
  }
  return out "\342\200\246"
}
{ buf = buf $0 "\n" }
END {
  n = length(buf); i = 1; depth = 0
  while (i <= n) {
    c = substr(buf, i, 1)
    if (c ~ /[ \t\r\n:]/) { i++; continue }
    if (c == "{") { depth++; typ[depth] = "o"; key[depth] = ""; ek = 1; i++; continue }
    if (c == "[") { depth++; typ[depth] = "a"; idx[depth] = 0; key[depth] = "0"; i++; continue }
    if (c == "}" || c == "]") { depth--; i++; continue }
    if (c == ",") { if (typ[depth] == "o") ek = 1; else { idx[depth]++; key[depth] = idx[depth] }; i++; continue }
    if (c == "\"") {
      j = i + 1; s = ""
      while (j <= n) {
        d = substr(buf, j, 1)
        if (d == "\\") {
          e = substr(buf, j + 1, 1)
          if (e == "u") { s = s "?"; j += 6; continue }
          if (e ~ /[nrtbf]/) e = " "
          s = s e; j += 2; continue
        }
        if (d == "\"") break
        s = s d; j++
      }
      i = j + 1
      if (typ[depth] == "o" && ek) { key[depth] = s; ek = 0; continue }
      emit(s); continue
    }
    j = i; while (j <= n && substr(buf, j, 1) !~ /[],} \t\r\n]/) j++
    v = substr(buf, i, j - i); if (v == "null") v = ""
    emit(v); i = j
  }
  m = split(keys, K, " ")
  for (k = 1; k <= m; k++) {
    if (substr(K[k], 1, 1) == "#") {
      v = val[substr(K[k], 2)]
      if (v ~ /^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$/) {
        v = v + 0; neg = (v < 0); if (neg) v = -v
        if (v > 1e15) { print ""; continue }            # absurd value: treat as missing
        q = int(v); d = v - q
        if (d > 0.5 || (d == 0.5 && q % 2 == 1)) q++    # half-to-even, like PowerShell
        printf "%d\n", (neg ? -q : q)
      }
      else print ""
    } else if (K[k] == "!dir" || K[k] == "!leaf") {
      p = val["workspace.current_dir"]; if (p == "") p = val["cwd"]
      p = clean(p, 0)
      if (K[k] == "!dir") { print p; continue }
      t = p; gsub(/\\/, "/", t); sub(/\/+$/, "", t); sub(/.*\//, "", t)
      if (t == "") t = p
      print clean(t, 40)
    } else print clean(val[K[k]], 40)
  }
}')
{ IFS= read -r MODEL; IFS= read -r EFFORT; IFS= read -r DIR; IFS= read -r LEAF
  IFS= read -r CTX; IFS= read -r P5; IFS= read -r R5; IFS= read -r P7; } <<< "$PARSED"

COLS=${COLUMNS:-120}; case "$COLS" in ''|*[!0-9]*) COLS=120 ;; esac

# ---------- line 1: model, effort, directory, branch ----------
[ -n "$MODEL" ] || MODEL='Claude'
LINE1="$I_SNOWMAN $BOLD$FROST$MODEL$RST"

if [ -n "$EFFORT" ]; then
  case "$EFFORT" in low) N=1;; medium) N=2;; high) N=3;; xhigh) N=4;; max) N=5;; *) N=3;; esac
  GAUGE=''
  for k in 0 1 2 3 4; do
    if [ $k -lt $N ]; then grad $k 4; GAUGE+="$GC${G_ON[k]}"; else GAUGE+="$OFFC_C${G_OFF[k]}"; fi
  done
  LINE1+="$SEP$GAUGE$RST $AQUA$EFFORT$RST"
fi

if [ -n "$DIR" ]; then
  # Windows paths (C:\...) -> Git Bash paths (/c/...) for file checks
  UDIR=$DIR
  if [[ "$DIR" == *\\* || "$DIR" == ?:* ]] && command -v cygpath >/dev/null 2>&1; then
    UDIR=$(cygpath -u -- "$DIR" 2>/dev/null) || UDIR=${DIR//\\//}
  fi
  LINE1+="$SEP$I_ICE $SKY$LEAF$RST"

  # Branch name read from .git/HEAD; git itself is never run here.
  # Safety rules for files a repository controls:
  #  - never touch network paths (on Windows, opening \\server\share can
  #    send your login credentials to that server)
  #  - never follow symlinked .git / HEAD (could point anywhere)
  #  - read at most 256 bytes of a line (a huge file cannot stall us)
  BRANCH=''; GITDIR=''; d=$UDIR
  is_net() { [[ "$1" == //* || "$1" == \\\\* || "$1" == /net/* ]]; }
  is_net "$DIR" || is_net "$UDIR" && d=''
  for (( up = 0; up < 40; up++ )); do
    [ -n "$d" ] || break
    if [ -L "$d/.git" ]; then break; fi
    if [ -d "$d/.git" ]; then GITDIR="$d/.git"; break; fi
    if [ -f "$d/.git" ]; then
      IFS= read -r -n 256 L < "$d/.git"
      if [[ "$L" == gitdir:* ]]; then
        p=${L#gitdir:}; p=${p# }; p=${p%$'\r'}
        if ! is_net "$p"; then
          if [[ "$p" == ?:* ]] && command -v cygpath >/dev/null 2>&1; then p=$(cygpath -u -- "$p"); fi
          [[ "$p" == /* ]] || p="$d/$p"
          is_net "$p" || GITDIR=$p
        fi
      fi
      break
    fi
    parent=${d%/*}; [ "$parent" = "$d" ] && break; d=$parent
  done
  if [ -n "$GITDIR" ] && [ ! -L "$GITDIR/HEAD" ] && [ -f "$GITDIR/HEAD" ]; then
    IFS= read -r -n 256 H < "$GITDIR/HEAD"
    H=${H%$'\r'}; san H
    if [[ "$H" == "ref: refs/heads/"* ]]; then BRANCH=${H#ref: refs/heads/}
    elif [[ "$H" =~ ^[0-9a-f]{7} ]]; then BRANCH="detached@${H:0:7}"; fi
    [ ${#BRANCH} -gt 40 ] && BRANCH="${BRANCH:0:39}"$'\xe2\x80\xa6'
  fi

  if [ -n "$BRANCH" ]; then
    DIRTY=''
    if [ "$SHOW_DIRTY" = 1 ] && command -v git >/dev/null 2>&1; then
      if [ -n "$(git -C "$UDIR" -c core.fsmonitor=false -c core.untrackedCache=false --no-optional-locks \
                 status --porcelain --ignore-submodules=all 2>/dev/null | head -c 1)" ]; then
        DIRTY=" $WARN$G_DOT$RST"
      fi
    fi
    LABEL=''; [ -n "$BRANCH_LABEL" ] && LABEL="$DIM$BRANCH_LABEL$RST "
    LINE1+="$SEP$I_BRANCH $LABEL$OCEAN$BRANCH$RST$DIRTY"
  fi
fi

# ---------- line 2: context tank, rate limits, reset countdown ----------
PCT=${CTX:-0}; [ "$PCT" -lt 0 ] 2>/dev/null && PCT=0
WIDTH=12; [ "$COLS" -lt 70 ] && WIDTH=8
FILLED=$(( PCT * WIDTH / 100 )); [ $(( PCT * WIDTH % 100 )) -ge 50 ] && FILLED=$(( FILLED + 1 ))
BAR=''
for (( k = 0; k < WIDTH; k++ )); do
  if [ $k -lt $FILLED ]; then
    if   [ "$PCT" -ge 90 ]; then BAR+="$DANGER$G_CELL"
    elif [ "$PCT" -ge 75 ]; then BAR+="$WARN$G_CELL"
    else grad $k $(( WIDTH - 1 )); BAR+="$GC$G_CELL"; fi
  else BAR+="$NAVY$G_CELL"; fi
done
PC=$ICE; [ "$PCT" -ge 75 ] && PC=$WARN; [ "$PCT" -ge 90 ] && PC=$DANGER
LINE2="$I_DROP $BAR$RST $PC$BOLD$PCT%$RST ${DIM}ctx$RST"

limit() {  # limit VAR LABEL PERCENT
  printf -v "$1" '%s' ''; [ -n "$3" ] || return 0
  local c=$AQUA; [ "$3" -ge 70 ] && c=$WARN; [ "$3" -ge 90 ] && c=$DANGER
  printf -v "$1" '%s' "$DIM$2$RST $c$3%$RST"
}
limit L5 5h "$P5"; limit L7 7d "$P7"
if [ -n "$L5$L7" ]; then
  LIMITS=$L5; [ -n "$L5" ] && [ -n "$L7" ] && LIMITS+="  "; LIMITS+=$L7
  LINE2+="$SEP$I_JELLY $LIMITS"
fi

if [ -n "$R5" ] && [ "$COLS" -ge 70 ]; then
  printf -v NOW '%(%s)T' -1 2>/dev/null; case "$NOW" in ''|*[!0-9]*) NOW=$(date +%s) ;; esac
  LEFT=$(( R5 - NOW ))
  if [ $LEFT -gt 0 ]; then
    if [ $LEFT -ge 3600 ]; then printf -v T '%dh%02dm' $(( LEFT / 3600 )) $(( LEFT % 3600 / 60 ))
    else T="$(( (LEFT + 59) / 60 ))m"; fi
    LINE2+="$SEP$I_DOLPHIN ${DIM}reset$RST $AQUA$T$RST"
  fi
fi

printf '%s\n%s' "$LINE1" "$LINE2"
exit 0
