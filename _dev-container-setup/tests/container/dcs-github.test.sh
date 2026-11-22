#!/usr/bin/env bash
# dcs-github（PAT の保存と clone）のテスト。dcs-image の使い捨てのコンテナの中で、dev として bash -s で動かす
# （tests\Integration.Tests.ps1 の Describe 'GitHub' が Invoke-ImageTest で渡す。作業フォルダは tmpfs で、
# DCS_WORKSPACE で場所を知らせる。D49）。最後に PASS を表示する。
# 本物の PAT は使わない（形だけの値。clone は、無いリポジトリなので失敗する）。
# 最後に、このテストが保存した形だけの PAT を消す（本物の PAT が保存されていても、それは消さない）。
set -Eeuo pipefail
ws=${DCS_WORKSPACE:?}
pat="ghp_$(printf 'a%.0s' {1..36})"
url="https://github.com/dcs-test-owner/no-such-repo-$RANDOM.git"
payload=$(printf 'user_name=T\nuser_email=t@example.com\npat=%s\nrepo_url=%s\n' "$pat" "$url" | base64 -w0)
[[ -z $(ls -A "$ws") ]]                                                  # 前提: 作業フォルダが空
if out=$(printf '%s' "$payload" | dcs-github 2>&1); then exit 1; fi     # clone は失敗する（無いリポジトリ）
[[ $out != *"$pat"* ]]                                                   # PAT を表示しない
[[ $out == *"$ws"* ]]                                                    # 作業フォルダに clone しようとした
[[ -z $(ls -A "$ws") ]]                                                  # 失敗した clone の残りが無い
[[ $(stat -c %a ~/.dcs-git/credentials) == 600 ]]
# 保存はできた（dcs-github は、git が取り出せることとモードを確かめてから、この表示を出す）。
# 保存した PAT は、ファイルには残らない（git は、認証に失敗した PAT を自分で消す。GitHub は形だけの PAT に 401 を返す）
[[ $out == *'[完了] 保存しました'* ]]
mv ~/.dcs-git/credentials /tmp/c; ln -s /tmp/x ~/.dcs-git/credentials
if printf '%s' "$payload" | dcs-github; then exit 1; fi; [[ ! -e /tmp/x ]]  # シンボリックリンクなら書かない
rm ~/.dcs-git/credentials; mv /tmp/c ~/.dcs-git/credentials
if printf 'pat=x\n' | base64 -w0 | dcs-github; then exit 1; fi           # 項目の足りない入力は断る
if printf '%s' "$payload" | DCS_WORKSPACE=/etc dcs-github; then exit 1; fi  # 作業フォルダが /workspaces/<名前> でなければ断る
# 色: 端末でないときは付けない。DCS_COLOR=1（Windows 側が、画面にそのまま出すときに付ける）なら付ける
if out=$(printf 'pat=x\n' | base64 -w0 | dcs-github 2>&1); then exit 1; fi
[[ $out != *$'\e['* ]] || { echo '端末でないのに色が付いています'; exit 1; }
if out=$(printf 'pat=x\n' | base64 -w0 | DCS_COLOR=1 dcs-github 2>&1); then exit 1; fi
[[ $out == *$'\e[91m[失敗]'* ]] || { echo 'DCS_COLOR=1 なのに [失敗] に色が付いていません'; exit 1; }
printf 'url=%s\n\n' "$url" | git credential reject                       # 片付け: 形だけの PAT を消す
if grep -q "$pat" ~/.dcs-git/credentials; then exit 1; fi
echo PASS
