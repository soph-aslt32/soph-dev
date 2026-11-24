#!/usr/bin/env bash
# ファイアウォール（init-firewall.sh）のテスト。土台の dcs で bash -s で動かす（tests\TestHelpers.ps1 の Invoke-BaseTest）。
# dcs-image からコンテナを作って、その中で確かめる。最後に PASS を表示する。
# 作ったもの（ネットワーク dcs-fwtest、コンテナ 3 つ、一時ファイル）は、終わるときに片付ける。
set -Eeuo pipefail
net=dcs-fwtest
tmp=$(mktemp -d)
cleanup() {
    docker rm -f dcs-fwtest-open dcs-fwtest-closed dcs-fwtest-fixed > /dev/null 2>&1 || true
    docker network rm "$net" > /dev/null 2>&1 || true
    rm -rf -- "$tmp"
}
trap cleanup EXIT

# 1. ネットワークと、開発環境ごとの許可リスト（引けないドメインと、ドメインの形でない行を混ぜる）
docker network create --label dcs=1 --label dcs.env=fwtest "$net" > /dev/null
printf 'pypi.org\nnonexistent.invalid\nbad line!\n' > "$tmp/allowed-domains.txt"
chmod 644 -- "$tmp/allowed-domains.txt"
run=(docker run --rm -i --pull never --network "$net" --cap-add NET_ADMIN --cap-add NET_RAW
     -v "$tmp/allowed-domains.txt:/etc/dcs/allowed-domains.txt:ro")

# 中の確かめは、最後の行（CASE n OK）まで動いたことも確かめる（標準入力で渡すので、途中で読まれずに終わると気づけないため）
# 2. ふつうに入れられる。合わない行と引けないドメインは、警告して飛ばす（Review Focus 4）
case_out=$("${run[@]}" --name dcs-fwtest-open dcs-image bash -s <<'EOF'
set -Eeuo pipefail
out=$(sudo /usr/local/bin/init-firewall.sh 2>&1) || { printf '%s\n' "$out"; echo 'init-firewall.sh が失敗しました'; exit 1; }
printf '%s\n' "$out"
grep -qF 'nonexistent.invalid' <<< "$out" || { echo 'nonexistent.invalid の警告がありません'; exit 1; }
grep -qF 'bad line!' <<< "$out" || { echo 'bad line! の警告がありません'; exit 1; }
dcs-verify --only firewall
curl -sS -o /dev/null --max-time 10 https://pypi.org
# 色: 端末でないとき（ウィザードが受け取るとき）は付けない。端末（VS Code のターミナルなど）では付ける。入れ直しても同じ結果になる
[[ $out != *$'\e['* ]] || { echo '端末でないのに色が付いています'; exit 1; }
command -v script > /dev/null || { echo 'script がありません'; exit 1; }
# script の標準入力は /dev/null にする（このテストは標準入力で渡しているので、続きの行を script に読まれないように）
tty_out=$(script -qec 'sudo /usr/local/bin/init-firewall.sh' /dev/null < /dev/null) || { printf '%s\n' "$tty_out"; echo '端末で init-firewall.sh が失敗しました'; exit 1; }
[[ $tty_out == *$'\e[96m==>'* && $tty_out == *$'\e[92m[完了]'* ]] || { printf '%s\n' "$tty_out"; echo '端末なのに色が付いていません'; exit 1; }
dcs-verify --only firewall
echo 'CASE 2 OK'
EOF
) || { printf '%s\n' "$case_out"; exit 1; }
printf '%s\n' "$case_out"
[[ $case_out == *'CASE 2 OK'* ]] || { echo 'CASE 2 が最後まで動いていません'; exit 1; }

# 3. DNS に届かないと、閉じたまま失敗する（Review Focus 3）
#    DNS から答えが無いときは、ドメインのせいではないので、固定の許可リストのドメインを飛ばし続けずに止まる（D54）
case_out=$("${run[@]}" --name dcs-fwtest-closed --dns 192.0.2.1 dcs-image bash -s <<'EOF'
set -Eeuo pipefail
rc=0
out=$(sudo /usr/local/bin/init-firewall.sh 2>&1) || rc=$?
printf '%s\n' "$out"
[[ $rc == 1 ]] || { echo "init-firewall.sh の終了コードが $rc です（1 のはず）"; exit 1; }
grep -qF 'DNS から答えがありません' <<< "$out" || { echo 'DNS から答えが無いことを理由にして止まっていません'; exit 1; }
if grep -qF '[WARN]' <<< "$out"; then echo 'DNS から答えが無いのに、固定の許可リストのドメインを飛ばしています'; exit 1; fi
if curl -sS -o /dev/null --max-time 5 https://1.1.1.1; then echo '1.1.1.1 に届きました'; exit 1; fi
if curl -sS -o /dev/null --max-time 5 https://140.82.112.3; then echo '140.82.112.3（GitHub）に届きました'; exit 1; fi
echo 'CASE 3 OK'
EOF
) || { printf '%s\n' "$case_out"; exit 1; }
printf '%s\n' "$case_out"
[[ $case_out == *'CASE 3 OK'* ]] || { echo 'CASE 3 が最後まで動いていません'; exit 1; }

# 4. 固定の許可リストのドメインを引けないときは、目立つ警告と理由を出して飛ばし、ほかは入れる
#    （固定の許可リストを、先頭に引けないドメインを足したものに差し替える）
docker run --rm --pull never dcs-image cat /etc/dcs/firewall-domains.txt > "$tmp/fixed.txt"
{ printf '# 試しの用途（わざと引けないドメイン）\nnonexistent-fixed.invalid\n\n'; cat -- "$tmp/fixed.txt"; } > "$tmp/firewall-domains.txt"
chmod 644 -- "$tmp/firewall-domains.txt"
case_out=$("${run[@]}" --name dcs-fwtest-fixed -v "$tmp/firewall-domains.txt:/etc/dcs/firewall-domains.txt:ro" dcs-image bash -s <<'EOF'
set -Eeuo pipefail
out=$(sudo /usr/local/bin/init-firewall.sh 2>&1) || { printf '%s\n' "$out"; echo 'init-firewall.sh が失敗しました'; exit 1; }
printf '%s\n' "$out"
grep -qE '^\[WARN\] .*固定の許可リスト.*nonexistent-fixed\.invalid' <<< "$out" || { echo '固定の許可リストの nonexistent-fixed.invalid の [WARN] がありません'; exit 1; }
# 色の付かないところでも目立つよう、[WARN] の行の上を = の線で区切る
before=$(grep -B1 -E '^\[WARN\] .*固定の許可リスト.*nonexistent-fixed\.invalid' <<< "$out")
grep -qE '^={20,}$' <<< "$before" || { echo '[WARN] の行の上に = の線がありません'; exit 1; }
grep -qF '試しの用途（わざと引けないドメイン）' <<< "$out" || { echo '飛ばしたドメインの用途がありません'; exit 1; }
grep -qF 'NXDOMAIN' <<< "$out" || { echo '引けなかった理由（NXDOMAIN）がありません'; exit 1; }
# 警告が流れて見落とされないように、最後（[完了] の後）にも、飛ばしたドメインを出す
tail_out=$(sed -n '/\[完了\]/,$p' <<< "$out")
grep -qE '^\[WARN\] .*nonexistent-fixed\.invalid' <<< "$tail_out" || { echo '[完了] の後に、飛ばしたドメインの [WARN] がありません'; exit 1; }
dcs-verify --only firewall
echo 'CASE 4 OK'
EOF
) || { printf '%s\n' "$case_out"; exit 1; }
printf '%s\n' "$case_out"
[[ $case_out == *'CASE 4 OK'* ]] || { echo 'CASE 4 が最後まで動いていません'; exit 1; }

echo PASS
