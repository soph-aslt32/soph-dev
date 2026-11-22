#!/usr/bin/env bash
# 土台の検証（verify-base.sh）の B2 のテスト。土台の dcs として bash -s で動かす（tests\TestHelpers.ps1 の Invoke-BaseTest）。
# B2 は、/etc/wsl.conf を、Windows 側のツールの base\wsl.conf の SHA256（2 つ目の引数）と比べる。最後に PASS を表示する。
# プロファイル名は B5（警告だけ）にしか使わないので、決まった名前でよい
set -Eeuo pipefail
v=/opt/dcs/base/verify-base.sh
good=$(sha256sum /etc/wsl.conf | cut -d ' ' -f 1)
bad=0000000000000000000000000000000000000000000000000000000000000000
out=$(bash "$v" nobody "$good" || true)
grep -q '^\[OK\] B2 ' <<< "$out"                                        # 1. 同じなら OK
rc=0; out=$(bash "$v" nobody "$bad") || rc=$?
[[ $rc == 1 ]] && grep -q '^\[NG\] B2 .*「更新」' <<< "$out"           # 2. 違えば NG（直し方は「更新」）
rc=0; bash "$v" nobody > /dev/null 2>&1 || rc=$?; [[ $rc == 2 ]]        # 3. SHA256 が無ければ、引数の誤り
rc=0; bash "$v" nobody xyz > /dev/null 2>&1 || rc=$?; [[ $rc == 2 ]]    #    SHA256 の形でなくても
echo PASS
