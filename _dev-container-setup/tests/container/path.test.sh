#!/usr/bin/env bash
# イメージの PATH のテスト（C1）。dcs-image のコンテナの中で、dev として bash -s で動かす（tests\TestHelpers.ps1 の Invoke-ImageTest）。
# Claude が書ける場所（~/.local/bin・~/.cargo/bin）に同じ名前のコマンドを置いても、システムのものが先に見つかること。最後に PASS を表示する。
set -Eeuo pipefail
names=(sudo bash sh env git base64 dcs-verify dcs-settings dcs-github dcs-check-forwarding)
mkdir -p ~/.local/bin ~/.cargo/bin
for c in "${names[@]}"; do
    printf '#!/bin/sh\nexit 0\n' > ~/.local/bin/"$c"
    chmod +x ~/.local/bin/"$c"
    cp -- ~/.local/bin/"$c" ~/.cargo/bin/"$c"
done
for c in "${names[@]}"; do
    p=$(type -P "$c")
    [[ $p != /home/* ]] || { echo "$c が $p を指しています（システムのものが先のはず）" >&2; exit 1; }
done
# 道具は、今までどおり見つかる
[[ $(type -P claude) == /home/dev/.local/bin/claude ]]
[[ $(type -P uv) == /home/dev/.local/bin/uv ]]
[[ $(type -P cargo) == /home/dev/.cargo/bin/cargo ]]
echo PASS
