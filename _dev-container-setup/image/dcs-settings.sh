#!/usr/bin/env bash
# =============================================================================
# dcs-settings — ~/.claude/settings.json に、守りの設定（managed settings）を置き直す（DESIGN.md の 6.5b）
#
# イメージの中の /usr/local/bin/dcs-settings（root 所有）。Windows 側のツールが、コンテナのユーザー（dev）で、
# 開発環境を作るとき・「設定をやり直す」・「更新」のときに呼びます。引数はありません。
#   - 今のファイルが JSON のオブジェクトなら「今のファイル * 守り」、無いか壊れていれば「好み * 守り」にする（jq の *）。
#     ほかの設定は残る。permissions.deny は、managed settings の deny のあとに、利用者が足した deny を続ける
#     （jq の * は配列を置き換えるので、そのままでは利用者が足した deny が消える。I3）。
#   - 中身が変わるときだけ書き、元のファイルを settings.json.bak-YYYYmmdd-HHMMSS として残す。
#   - 一時ファイルに書いてから名前を変える（途中で止まっても、壊れたファイルを残さない）。
# =============================================================================
set -Eeuo pipefail

readonly PREFS=/usr/local/share/dcs/claude-settings.json
readonly MANAGED=/etc/claude-code/managed-settings.json
readonly SETTINGS=$HOME/.claude/settings.json

tmp=''
trap '[[ -z $tmp ]] || rm -f -- "$tmp"' EXIT

mkdir -p -- "${SETTINGS%/*}"
tmp=$(mktemp -- "$SETTINGS.tmp-XXXXXX")

# 今のファイルが、JSON のオブジェクト 1 つだけのときに使う
if [[ -f $SETTINGS ]] && jq -e -s 'length == 1 and (.[0] | type) == "object"' "$SETTINGS" > /dev/null 2>&1; then
    base=$SETTINGS
else
    base=$PREFS
fi
# 利用者の deny（配列でなければ無いものとする）のうち、守りの deny に無いものを、守りの deny のあとに続ける
jq --indent 2 -n --slurpfile b "$base" --slurpfile m "$MANAGED" '
    ($b[0] | (try .permissions.deny catch null) | if type == "array" then . else [] end) as $mine
    | $m[0].permissions.deny as $guard
    | ($b[0] * $m[0]) | .permissions.deny = $guard + ($mine - $guard)' > "$tmp"
chmod 644 -- "$tmp"

if [[ -f $SETTINGS ]] && cmp -s -- "$tmp" "$SETTINGS"; then
    echo "$SETTINGS は、すでに同じ内容です（変更なし）。"
    exit 0
fi
if [[ -e $SETTINGS ]]; then
    # 同じ秒に 2 回置き直しても、前の写しを上書きしない
    stamp=$(date +%Y%m%d-%H%M%S)
    bak=$SETTINGS.bak-$stamp
    n=1
    while [[ -e $bak ]]; do n=$((n + 1)); bak=$SETTINGS.bak-$stamp-$n; done
    cp -p -- "$SETTINGS" "$bak"
    echo "元のファイルを $bak に残しました。"
fi
mv -f -- "$tmp" "$SETTINGS"
tmp=''
echo "$SETTINGS を置きました。"
