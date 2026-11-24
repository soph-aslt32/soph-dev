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
# 引けないドメインは飛ばす（そのドメインには通信できなくなるだけで、守りは弱まらない）。開発環境ごとの許可リストのものは [注意]、
# 固定の許可リストのものは、目立つ [WARN] に用途と理由を付けて出し、最後（[完了] のあと）にももう一度出す。
# ただし、DNS から答えが無いとき（ドメインのせいではない）は、失敗にする。
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
readonly DIG_STATUS_RE='status: ([A-Z]+)'
readonly DIG_SERVER_RE='^;; SERVER: ([^#[:space:]]+)'
readonly ALERT_RULE='========================================================================'

# 色（端末に出すとき（VS Code のターミナルなど）だけ。ウィザードが受け取るときは付けない。ウィザードの色にそろえる）
if [[ -t 1 ]]; then
    readonly C_STEP=$'\e[96m' C_OK=$'\e[92m' C_NOTE=$'\e[93m' C_ALERT=$'\e[1;93m' C_ERR=$'\e[91m' C_OFF=$'\e[0m'
else
    readonly C_STEP='' C_OK='' C_NOTE='' C_ALERT='' C_ERR='' C_OFF=''
fi
warn() { printf '%s[注意] %s%s\n' "$C_NOTE" "$1" "$C_OFF"; }

# 目立たせる警告（固定の許可リストのドメインを飛ばすとき）。引数の 1 つが 1 行。
# 色の付かないところ（ウィザードの画面など）でも見落とさないよう、= の線で囲む。端末では太字の黄色
alert() {
    local line
    printf '%s%s%s\n' "$C_ALERT" "$ALERT_RULE" "$C_OFF"
    for line in "$@"; do printf '%s%s%s\n' "$C_ALERT" "$line" "$C_OFF"; done
    printf '%s%s%s\n' "$C_ALERT" "$ALERT_RULE" "$C_OFF"
}

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

# $1 のドメインの A レコードを引く（固定の許可リスト用。引けなかった理由も知りたいので、+short ではなく答えの全体を読む）。
# 結果: v4（IPv4 のアドレスの配列）、why（引けなかった理由。引けたときは空）、no_reply（DNS から答えが無かったら 1）
lookup_v4() {
    local out rc=0 line cls rtype data status='' server='' last at=''
    v4=() why='' no_reply=0
    out=$(dig +time=3 +tries=2 A "$1" 2>&1) || rc=$?
    while IFS= read -r line; do
        if [[ $line =~ $DIG_STATUS_RE ]]; then
            status=${BASH_REMATCH[1]}
        elif [[ $line =~ $DIG_SERVER_RE ]]; then
            server=${BASH_REMATCH[1]}
        elif [[ -n $line && ${line:0:1} != ';' ]]; then
            # 答えの行は「名前 TTL クラス 種類 値」（CNAME と、引けないときの SOA の行は飛ばす）
            read -r _ _ cls rtype data <<< "$line"
            if [[ $cls == IN && $rtype == A && $data =~ $IPV4_RE ]]; then v4+=("$data"); fi
        fi
    done <<< "$out"
    if (( ${#v4[@]} > 0 )); then return 0; fi

    last=${out##*$'\n'}
    last=${last//[[:cntrl:]]/?}
    if [[ -n $server ]]; then at="。問い合わせ先 ${server//[[:cntrl:]]/?}"; fi
    if (( rc == 9 )); then
        no_reply=1
        why="DNS から答えがありません（${last:-dig の終了コード 9}）"
    elif (( rc != 0 )); then
        why="dig が終了コード $rc で失敗しました（${last:-理由の表示なし}）"
    else
        case $status in
            NXDOMAIN) why="そのドメインはありません（DNS の答えが NXDOMAIN$at）" ;;
            SERVFAIL) why="DNS サーバーが答えを出せませんでした（DNS の答えが SERVFAIL$at）" ;;
            REFUSED) why="DNS サーバーに断られました（DNS の答えが REFUSED$at）" ;;
            NOERROR) why="IPv4 のアドレス（A レコード）がありません（DNS の答えは NOERROR$at）" ;;
            '') why="DNS の答えを読めませんでした（${last:-理由の表示なし}）" ;;
            *) why="引けませんでした（DNS の答えが $status$at）" ;;
        esac
    fi
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

    local -a addrs=() a=() v4=() skipped=()
    local line d meta gw hostnet out why no_reply purpose='' fixed=0 env=0 github=0

    printf '%s==> ファイアウォールを入れます%s\n' "$C_STEP" "$C_OFF"

    # 1. 許す IPv4 の一覧を作る（この間は、今の規則を変えない）
    [[ -r $FIXED_LIST ]] || die "固定の許可リスト（$FIXED_LIST）がありません"
    while IFS= read -r line || [[ -n $line ]]; do
        d=$(trim "${line%$'\r'}")
        # 用途は、ドメインのすぐ上の # の行（空の行で区切る）。飛ばすときの警告に出す
        if [[ -z $d ]]; then purpose=''; continue; fi
        if [[ $d == \#* ]]; then purpose=$(trim "${d#\#}"); purpose=${purpose//[[:cntrl:]]/?}; continue; fi
        [[ $d =~ $DOMAIN_RE ]] || die "固定の許可リストに、ドメインの形でない行があります（${d//[[:cntrl:]]/?}）"
        lookup_v4 "$d"
        (( ! no_reply )) || die "固定の許可リストの $d を引こうとしましたが、$why（DNS に届いているかを確かめてください）"
        if (( ${#v4[@]} == 0 )); then
            alert "[WARN] 固定の許可リストの $d は、IPv4 のアドレスを引けなかったので飛ばします。" \
                "       このドメインには、コンテナの中から通信できません（ほかのドメインは、そのまま許します）。" \
                "       用途: ${purpose:-（書かれていません）}" \
                "       理由: $why" \
                "       DNS の一時的な不調なら、コンテナを起動し直すと、もう一度引きます（README の「困ったとき」）。"
            skipped+=("$d")
            continue
        fi
        addrs+=("${v4[@]}")
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
    # 飛ばしたものを、最後にもう一度出す（上の [WARN] が流れて見落とされないように）
    if (( ${#skipped[@]} > 0 )); then
        alert "[WARN] 固定の許可リストのうち ${#skipped[@]} 個を、引けなかったので飛ばしました: ${skipped[*]}" \
            "       これらのドメインには、コンテナの中から通信できません。理由は、上の [WARN] を見てください。"
    fi
}

main "$@"
