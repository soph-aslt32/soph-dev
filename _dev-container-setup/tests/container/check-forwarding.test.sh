#!/usr/bin/env bash
# dcs-check-forwarding（VS Code の受け渡しが残っていないかの確かめ）のテスト。dcs-image のコンテナの中で、dev として
# bash -s で動かす（tests\TestHelpers.ps1 の Invoke-ImageTest）。最後に PASS を表示する。
set -Eeuo pipefail
unset DISPLAY WAYLAND_DISPLAY SSH_AUTH_SOCK GIT_ASKPASS
rm -f ~/.gitconfig ~/.docker/config.json
dcs-check-forwarding                                                       # 何も無ければ 0
touch ~/.gitconfig
if out=$(dcs-check-forwarding 2>&1); then exit 1; fi; [[ $out == *.gitconfig* ]]; rm ~/.gitconfig
mkdir -p ~/.docker; echo '{"credsStore":"x"}' > ~/.docker/config.json
if dcs-check-forwarding --files-only; then exit 1; fi; rm ~/.docker/config.json
if DISPLAY=:0 dcs-check-forwarding; then exit 1; fi                        # 環境変数は、ふつうのときに見る
DISPLAY=:0 dcs-check-forwarding --files-only                               # --files-only では見ない
git config --file /tmp/sys credential.helper /tmp/vscode-helper
if GIT_CONFIG_SYSTEM=/tmp/sys dcs-check-forwarding --files-only; then exit 1; fi   # ほかの helper があれば警告
if REMOTE_CONTAINERS_SOCKETS='["/tmp/.X11-unix/X0"]' dcs-check-forwarding; then exit 1; fi   # 受け渡されたソケットの一覧（V15）
REMOTE_CONTAINERS_SOCKETS='[]' dcs-check-forwarding                                         # 空の一覧は警告しない
dcs-verify --only forwarding                                               # I9: 何も無ければ 0
touch ~/.gitconfig; if dcs-verify --only forwarding; then exit 1; fi; rm ~/.gitconfig       # I9: 残っていれば NG
# 色: 端末に出すとき（VS Code のターミナルなど）だけ付ける。端末でないとき（dcs-verify の中、ウィザードが受け取るとき）は付けない。
# script の標準入力は /dev/null にする（このテストは標準入力で渡しているので、続きの行を script に読まれないように）
command -v script > /dev/null || { echo 'script がありません'; exit 1; }
touch ~/.gitconfig
if out=$(dcs-check-forwarding --files-only 2>&1); then exit 1; fi
[[ $out != *$'\e['* ]] || { echo '端末でないのに [警告] に色が付いています'; exit 1; }
out=$(script -qec 'dcs-check-forwarding --files-only' /dev/null < /dev/null || true)
[[ $out == *$'\e[93m[警告]'* ]] || { echo '端末なのに [警告] に色が付いていません'; exit 1; }
rm ~/.gitconfig
out=$(dcs-verify --only forwarding)
[[ $out != *$'\e['* ]] || { echo '端末でないのに [OK] に色が付いています'; exit 1; }
out=$(script -qec 'dcs-verify --only forwarding' /dev/null < /dev/null)
[[ $out == *$'\e[92m[OK]'* ]] || { echo '端末なのに [OK] に色が付いていません'; exit 1; }
echo PASS
