#!/usr/bin/env bash
# =============================================================================
# init-firewall.sh — コンテナから外への通信を、許可したところだけにする（DESIGN.md の 6.6。D27・D40）
#
# イメージの中の /usr/local/bin/init-firewall.sh（root 所有）。注文書の postStartCommand から、コンテナが起動するたびに
# sudo で実行します（dev が sudo できるのは、このスクリプトだけ）。
# 引数は取りません（取ると、sudo できる Claude が、許可するところを増やせてしまうため）。読むのは次の 2 つだけです。
#   /etc/dcs/firewall-domains.txt  固定の許可リスト（イメージの中。root 所有）
#   /etc/dcs/allowed-domains.txt   開発環境ごとの許可リスト（土台の allowed-domains.txt を読み取り専用でつないだもの。無ければ飛ばす）
# 許すもの: lo、確立済みの接続、土台のゲートウェイの /24、許可リストのドメインの IPv4、GitHub（api.github.com/meta の web・api・git）。
# DNS は Docker の内部の DNS（127.0.0.11。lo を通る）だけ。SSH（22 番）の規則は入れない。
# 終了コード: 成功が 0、失敗が 1（失敗したときは、lo と確立済みの接続だけを通す、閉じた状態にする）、引数の誤りが 2
# 公式の参考例は写さず、しくみだけをもとに書いた（D40）。
# =============================================================================
set -Eeuo pipefail

readonly FIXED_LIST=/etc/dcs/firewall-domains.txt
readonly ENV_LIST=/etc/dcs/allowed-domains.txt
readonly SET=dcs-allowed
readonly NEW_SET=dcs-allowed-new
readonly GITHUB_META=https://api.github.com/meta
readonly DOMAIN_RE='^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$'
readonly IPV4_RE='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
readonly CIDR4_RE='^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'

# 色（端末に出すとき（VS Code のターミナルなど）だけ。ウィザードが受け取るときは付けない。ウィザードの色にそろえる）
if [[ -t 1 ]]; then
    readonly C_STEP=$'\e[96m' C_OK=$'\e[92m' C_NOTE=$'\e[93m' C_ERR=$'\e[91m' C_OFF=$'\e[0m'
else
    readonly C_STEP='' C_OK='' C_NOTE='' C_ERR='' C_OFF=''
fi
warn() { printf '%s[注意] %s%s\n' "$C_NOTE" "$1" "$C_OFF"; }

# lo と確立済みの接続のほかは、出入りとも通さない
close_all() {
    iptables-restore <<'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
COMMIT
EOF
}

die() {
    trap - ERR
    printf '%s[失敗] ファイアウォールを入れられませんでした: %s%s\n' "$C_ERR" "$1" "$C_OFF" >&2
    if close_all; then
        echo '  外への通信は、すべて止めた状態にしました（コンテナを起動し直すと、もう一度入れます）。' >&2
    else
        echo '  閉じた状態にもできませんでした。このコンテナは使わないでください。' >&2
    fi
    exit 1
}

# 前後の空白を除く
trim() {
    local s=$1
    s=${s#"${s%%[![:space:]]*}"}
    s=${s%"${s##*[![:space:]]}"}
    printf '%s' "$s"
}

# $1 のドメインの IPv4 のアドレスを、1 行に 1 つ表示する（引けなければ何も表示しない）
resolve_v4() {
    local out line
    out=$(dig +short +time=3 +tries=2 A "$1" 2> /dev/null) || return 0
    while IFS= read -r line; do
        if [[ $line =~ $IPV4_RE ]]; then printf '%s\n' "$line"; fi
    done <<< "$out"
    return 0
}

main() {
    if (( $# != 0 )); then
        echo '使い方: sudo /usr/local/bin/init-firewall.sh（引数は取りません）' >&2
        exit 2
    fi
    if [[ $EUID != 0 ]]; then
        echo 'root で（sudo で）実行してください。' >&2
        exit 1
    fi
    trap 'die "予期しないエラーです（$LINENO 行目）"' ERR

    local -a addrs=() a=()
    local line d meta gw hostnet out fixed=0 env=0 github=0

    printf '%s==> ファイアウォールを入れます%s\n' "$C_STEP" "$C_OFF"

    # 1. 許す IPv4 の一覧を作る（この間は、今の規則を変えない）
    [[ -r $FIXED_LIST ]] || die "固定の許可リスト（$FIXED_LIST）がありません"
    while IFS= read -r line || [[ -n $line ]]; do
        d=$(trim "${line%$'\r'}")
        if [[ -z $d || $d == \#* ]]; then continue; fi
        [[ $d =~ $DOMAIN_RE ]] || die "固定の許可リストに、ドメインの形でない行があります（${d//[[:cntrl:]]/?}）"
        mapfile -t a < <(resolve_v4 "$d")
        (( ${#a[@]} > 0 )) || die "固定の許可リストの $d の IPv4 のアドレスを引けませんでした（DNS に届いているかを確かめてください）"
        addrs+=("${a[@]}")
        fixed=$((fixed + 1))
    done < "$FIXED_LIST"

    meta=$(curl -fsS --max-time 20 "$GITHUB_META" 2>&1) || die "GitHub の IP の範囲（$GITHUB_META）を取れませんでした（${meta//$'\n'/ }）"
    mapfile -t a < <(jq -r '(.web + .api + .git)[]' <<< "$meta" 2> /dev/null | grep -E "$CIDR4_RE" | aggregate -q 2> /dev/null)
    (( ${#a[@]} > 0 )) || die "GitHub の IP の範囲（$GITHUB_META）を読めませんでした"
    addrs+=("${a[@]}")
    github=${#a[@]}

    if [[ -f $ENV_LIST ]]; then
        while IFS= read -r line || [[ -n $line ]]; do
            d=$(trim "${line%$'\r'}")
            if [[ -z $d || $d == \#* ]]; then continue; fi
            if [[ ! $d =~ $DOMAIN_RE ]]; then
                warn "開発環境ごとの許可リストの「${d//[[:cntrl:]]/?}」は、ドメインの形ではないので飛ばします。"
                continue
            fi
            mapfile -t a < <(resolve_v4 "$d")
            if (( ${#a[@]} == 0 )); then
                warn "開発環境ごとの許可リストの $d は、IPv4 のアドレスを引けなかったので飛ばします。"
                continue
            fi
            addrs+=("${a[@]}")
            env=$((env + 1))
        done < "$ENV_LIST"
    fi

    gw=$(ip -4 route show default | awk '{ for (i = 1; i < NF; i++) if ($i == "via") { print $(i + 1); exit } }')
    [[ $gw =~ $IPV4_RE ]] || die 'ゲートウェイ（土台）のアドレスが分かりません'
    hostnet=${gw%.*}.0/24

    # 2. ipset に詰めてから、今のものと入れ替える
    ipset destroy "$NEW_SET" > /dev/null 2>&1 || true
    ipset create "$NEW_SET" hash:net family inet
    printf "add $NEW_SET %s\n" "${addrs[@]}" | ipset restore -exist
    ipset list -n "$SET" > /dev/null 2>&1 || ipset create "$SET" hash:net family inet
    ipset swap "$NEW_SET" "$SET"
    ipset destroy "$NEW_SET"

    # 3. filter 表の規則を一度に入れる（nat 表にある Docker の内部の DNS の規則には触らない）
    iptables-restore <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -s $hostnet -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -d $hostnet -j ACCEPT
-A OUTPUT -m set --match-set $SET dst -j ACCEPT
-A OUTPUT -j REJECT --reject-with icmp-admin-prohibited
COMMIT
EOF

    # 4. 自分で確かめる（dcs-verify の I3a・I3b と同じ）
    if curl -sS -o /dev/null --max-time 5 https://1.1.1.1 > /dev/null 2>&1; then
        die '許可していないところ（1.1.1.1）に届きます'
    fi
    out=$(curl -sS -o /dev/null --max-time 10 https://api.anthropic.com 2>&1) || die "Claude Code の通信先（api.anthropic.com）に届きません（${out//$'\n'/ }）"

    printf '  %s[完了] ファイアウォールを入れました（固定の許可リスト %s 個、開発環境ごとの許可リスト %s 個、GitHub の範囲 %s 個、ゲートウェイの %s）。%s\n' \
        "$C_OK" "$fixed" "$env" "$github" "$hostnet" "$C_OFF"
}

main "$@"
