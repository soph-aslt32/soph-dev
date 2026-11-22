#!/usr/bin/env bash
# =============================================================================
# dcs-check-forwarding — VS Code の受け渡しが、コンテナに残っていないかを確かめる（DESIGN.md の 6.4a。D34）
#
# イメージの中の /usr/local/bin/dcs-check-forwarding（root 所有）。
#   dcs-check-forwarding               注文書の postAttachCommand から、VS Code がつながるたびに動く（下の 1〜4）
#   dcs-check-forwarding --files-only  ファイルに残るもの（1〜3）だけを見る（dcs-verify の I9 から）
# これは守りではなく、VS Code の設定のし忘れに気づくための知らせです。何も止めません。
# 残っていれば [警告] を表示し、最後に README の案内を 1 行表示して、終了コード 1（VS Code のターミナルのパネルに目立って出る。V15）。
# 残っていなければ何も表示せず、終了コード 0。
# =============================================================================
set -Eeuo pipefail

# /etc/gitconfig にツールが書いた credential helper（これだけは、あってよい）
readonly OWN_HELPER='credential.https://github.com.helper store --file=/home/dev/.dcs-git/credentials'

found=0
# 色（端末に出すとき（VS Code のターミナル）だけ。dcs-verify が受け取るときは付けない。ウィザードの [注意] と同じ黄色）
if [[ -t 1 ]]; then readonly C_NOTE=$'\e[93m' C_OFF=$'\e[0m'; else readonly C_NOTE='' C_OFF=''; fi
warn() { printf '%s[警告] %s%s\n' "$C_NOTE" "${1//[[:cntrl:]]/?}" "$C_OFF"; found=1; }

files_only=0
case $# in
    0) ;;
    1) [[ $1 == --files-only ]] || { echo '使い方: dcs-check-forwarding [--files-only]' >&2; exit 2; }; files_only=1 ;;
    *) echo '使い方: dcs-check-forwarding [--files-only]' >&2; exit 2 ;;
esac

# 1. Windows の .gitconfig のコピー（このツールはコンテナの ~/.gitconfig を作らない）
if [[ -e $HOME/.gitconfig || -L $HOME/.gitconfig ]]; then
    warn '~/.gitconfig があります（Windows の .gitconfig が、VS Code からコピーされた見込みです）。'
fi

# 2. git の credential helper（system と global）に、ツールのもののほかのもの（VS Code の受け渡しなど）
helpers=$(git config --system --get-regexp '^credential\..*helper$' 2> /dev/null || true
          git config --global --get-regexp '^credential\..*helper$' 2> /dev/null || true)
while IFS= read -r line; do
    if [[ -z $line || $line == "$OWN_HELPER" ]]; then continue; fi
    warn "git の credential helper に、ツールのもののほかのものがあります（$line）。"
done <<< "$helpers"

# 3. Docker の認証情報の受け渡し
if [[ -f $HOME/.docker/config.json ]] \
    && jq -e 'type == "object" and (has("credsStore") or has("credHelpers"))' "$HOME/.docker/config.json" > /dev/null 2>&1; then
    warn '~/.docker/config.json に credsStore か credHelpers があります（Docker の認証情報が受け渡された見込みです）。'
fi

# 4. 環境変数とソケット（VS Code がつながっている間にしか現れない）
if (( ! files_only )); then
    for v in DISPLAY WAYLAND_DISPLAY SSH_AUTH_SOCK GIT_ASKPASS; do
        if [[ -n ${!v:-} ]]; then warn "環境変数 $v があります（${!v}）。"; fi
    done
    s=${REMOTE_CONTAINERS_SOCKETS:-}
    if [[ -n $s && $s != '[]' ]]; then warn "VS Code が受け渡したソケットがあります（REMOTE_CONTAINERS_SOCKETS=$s）。"; fi
    shopt -s nullglob
    socks=(/tmp/.X11-unix/*)
    if [[ -n ${XDG_RUNTIME_DIR:-} ]]; then socks+=("$XDG_RUNTIME_DIR"/wayland-*); fi
    shopt -u nullglob
    for f in "${socks[@]}"; do
        warn "画面のソケットがあります（$f）。"
    done
fi

if (( found )); then
    echo "README の『VS Code の設定』を確かめてください。"
    exit 1
fi
exit 0
