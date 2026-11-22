#!/usr/bin/env bash
# =============================================================================
# dcs-verify — 開発環境のコンテナの中の自動検証（DESIGN.md の 6.5d の「コンテナの中で」）
#
# イメージの中の /usr/local/bin/dcs-verify（root 所有）。Windows 側のツールが、コンテナのユーザー（dev）で呼びます。
#   dcs-verify [--only image|firewall|forwarding] [--managed-sha256 <64 桁>]
#   --only を付けないと、すべての項目を確かめる（このときは --managed-sha256 が要る）。
# 出力: 1 項目 1 行。「[OK] <ID> <説明>」か「[NG] <ID> <説明>: <理由>」
# 終了コード: すべて OK なら 0、NG があれば 1、引数の誤りは 2
# =============================================================================
set -Eeuo pipefail

readonly MANAGED=/etc/claude-code/managed-settings.json
readonly FIREWALL_SCRIPT=/usr/local/bin/init-firewall.sh

ng=0
# 色（端末に出すときだけ。Windows 側の Test-EnvInside が受け取るときは付けない。ウィザードの色にそろえる）
if [[ -t 1 ]]; then
    readonly C_OK=$'\e[92m' C_ERR=$'\e[91m' C_OFF=$'\e[0m'
else
    readonly C_OK='' C_ERR='' C_OFF=''
fi
pass() { printf '%s[OK] %s %s%s\n' "$C_OK" "$1" "$2" "$C_OFF"; }
fail() { printf '%s[NG] %s %s: %s%s\n' "$C_ERR" "$1" "$2" "$3" "$C_OFF"; ng=1; }

usage() {
    echo '使い方: dcs-verify [--only image|firewall|forwarding] [--managed-sha256 <64 桁>]' >&2
    exit 2
}

# apt の取得先のうち https でないものを「ファイル: URI」の形で 1 行ずつ表示する（土台の setup-base.sh と同じ見方）
apt_non_https_uris() {
    local f line uri
    local -a uris
    for f in /etc/apt/sources.list.d/*.sources; do
        [[ -f $f ]] || continue
        while IFS= read -r line || [[ -n $line ]]; do
            [[ $line =~ ^URIs:[[:space:]]*(.*)$ ]] || continue
            read -ra uris <<< "${BASH_REMATCH[1]}"
            for uri in "${uris[@]}"; do
                [[ $uri == https://* ]] || printf '%s: %s\n' "$f" "$uri"
            done
        done < "$f"
    done
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        [[ -f $f ]] || continue
        while IFS= read -r line || [[ -n $line ]]; do
            [[ $line =~ ^[[:space:]]*deb(-src)?[[:space:]] ]] || continue
            [[ $line == *https://* ]] || printf '%s: %s\n' "$f" "$line"
        done < "$f"
    done
}

check_image() {
    local sha=$1 out rules owner settings=$HOME/.claude/settings.json bad

    # I1: コンテナのユーザーが非 root の dev
    if [[ $(id -u) != 0 && $(id -un) == dev ]]; then
        pass I1 'コンテナのユーザーが非 root の dev'
    else
        fail I1 'コンテナのユーザーが非 root の dev' "今は $(id -un)（UID $(id -u)）です"
    fi

    # I2: sudo で許されているのは、ファイアウォールのスクリプトだけ
    # sudo・dcs-check-forwarding は絶対パスで呼ぶ（Claude が ~/.local/bin に同じ名前のものを置いても使われないように。C1）
    if out=$(LC_ALL=C /usr/bin/sudo -n -l 2>&1); then
        # 「User dev may run the following commands on <名前>:」の次の行から後ろが、許されているコマンドの一覧
        rules=$(printf '%s\n' "$out" | awk 'f && NF { sub(/^[[:space:]]+/, ""); print } / may run the following commands /{ f = 1 }')
        if [[ $rules == "(root) NOPASSWD: $FIREWALL_SCRIPT" ]]; then
            pass I2 "sudo で許されているのは $FIREWALL_SCRIPT だけ"
        else
            fail I2 "sudo で許されているのは $FIREWALL_SCRIPT だけ" "許されているもの: ${rules//$'\n'/ ／ }"
        fi
    else
        fail I2 "sudo で許されているのは $FIREWALL_SCRIPT だけ" "sudo -n -l が失敗しました（${out//$'\n'/ }）"
    fi

    # I4: managed settings が root 所有でモード 644、中身がツールのひな形と同じ（Claude Code は dev として読むので、読めることも確かめる）
    if [[ ! -f $MANAGED || ! -r $MANAGED ]]; then
        fail I4 'managed settings が root 所有で、ひな形と同じ' "$MANAGED が無いか、dev から読めません"
    else
        owner=$(stat -c '%U:%G %a' -- "$MANAGED")
        if [[ $owner != 'root:root 644' ]]; then
            fail I4 'managed settings が root 所有で、ひな形と同じ' "持ち主とモードが $owner です（root:root 644 のはず）"
        elif [[ $(sha256sum -- "$MANAGED" | cut -d ' ' -f 1) != "$sha" ]]; then
            # ツールを新しくしたあとは、イメージが古いまま（「作る」「やり直す」は今のイメージを使う）。作り直すのは「更新」（M5）
            fail I4 'managed settings が root 所有で、ひな形と同じ' '中身がツールのひな形と違います（ツールを新しくしたあとは、ウィザードの「更新」でイメージを作り直してください）'
        else
            pass I4 'managed settings が root 所有で、ひな形と同じ'
        fi
    fi

    # I5: ~/.claude/settings.json に、managed settings の deny がすべてある
    if [[ ! -f $settings ]]; then
        fail I5 '~/.claude/settings.json に managed settings の deny がすべてある' "$settings がありません"
    elif jq -e --slurpfile m "$MANAGED" '($m[0].permissions.deny - .permissions.deny) == []' "$settings" > /dev/null 2>&1; then
        pass I5 '~/.claude/settings.json に managed settings の deny がすべてある'
    else
        fail I5 '~/.claude/settings.json に managed settings の deny がすべてある' '足りないか、ファイルが壊れています（ウィザードの「設定をやり直す」で置き直せます）'
    fi

    # I6: Claude Code が入っている
    if out=$(claude --version 2>&1); then
        pass I6 "Claude Code が入っている（${out%%$'\n'*}）"
    else
        fail I6 'Claude Code が入っている' 'claude --version が失敗しました'
    fi

    # I7: Claude Code の設定の置き場所が ~/.claude（ボリューム）
    if [[ ${CLAUDE_CONFIG_DIR:-} == "$HOME/.claude" ]]; then
        pass I7 'CLAUDE_CONFIG_DIR が ~/.claude'
    else
        fail I7 'CLAUDE_CONFIG_DIR が ~/.claude' "今は「${CLAUDE_CONFIG_DIR:-（空）}」です"
    fi

    # I8: apt の取得先がすべて https
    bad=$(apt_non_https_uris)
    if [[ -z $bad ]]; then
        pass I8 'apt の取得先がすべて https'
    else
        fail I8 'apt の取得先がすべて https' "${bad//$'\n'/ ／ }"
    fi
}

# ファイアウォール（init-firewall.sh）が効いている（DESIGN.md の 6.6）
check_firewall() {
    local out rc

    # I3a: 許可していないところ（1.1.1.1）に届かない
    if curl -sS -o /dev/null --max-time 5 https://1.1.1.1 > /dev/null 2>&1; then
        fail I3a '許可していないところ（1.1.1.1）に届かない' '届きました'
    else
        pass I3a '許可していないところ（1.1.1.1）に届かない'
    fi

    # I3b: Claude Code の通信先（api.anthropic.com）に届く（HTTP の状態は問わない）
    if out=$(curl -sS -o /dev/null --max-time 10 https://api.anthropic.com 2>&1); then
        pass I3b 'Claude Code の通信先（api.anthropic.com）に届く'
    else
        fail I3b 'Claude Code の通信先（api.anthropic.com）に届く' "届きません（${out//$'\n'/ }）"
    fi

    # I3c: 外への SSH（22 番）に届かない。宛先は、SSH で待ち受けていて許可リストに無いサーバー
    # （1.1.1.1 は 22 番で待ち受けていないので、ファイアウォールが無くても届かず、確かめにならない）
    if timeout 5 bash -c '</dev/tcp/bitbucket.org/22' > /dev/null 2>&1; then
        fail I3c '外への SSH（bitbucket.org の 22 番）に届かない' '届きました'
    else
        pass I3c '外への SSH（bitbucket.org の 22 番）に届かない'
    fi

    # I3d: Docker の内部の DNS のほかには問い合わせられない（内部の DNS では引ける）
    if dig @1.1.1.1 example.com +time=2 +tries=1 > /dev/null 2>&1; then
        fail I3d 'Docker の内部の DNS のほかには問い合わせられない' '1.1.1.1 に問い合わせられました'
    elif [[ -z $(dig +short +time=3 +tries=2 example.com 2> /dev/null) ]]; then
        fail I3d 'Docker の内部の DNS のほかには問い合わせられない' '内部の DNS でも example.com を引けません'
    else
        pass I3d 'Docker の内部の DNS のほかには問い合わせられない'
    fi

    # I3e: ファイアウォールのスクリプトは引数を受け付けない（許可するところを、sudo できる Claude が増やせないように）
    rc=0
    /usr/bin/sudo -n "$FIREWALL_SCRIPT" x > /dev/null 2>&1 || rc=$?
    if [[ $rc == 2 ]]; then
        pass I3e 'ファイアウォールのスクリプトは引数を受け付けない'
    else
        fail I3e 'ファイアウォールのスクリプトは引数を受け付けない' "引数を付けたときの終了コードが $rc です（2 のはず）"
    fi
}

# VS Code の受け渡しのうち、ファイルに残るものが無い（DESIGN.md の 6.4a。環境変数とソケットは、つながっている間しか見えない）
check_forwarding() {
    local out
    if out=$(/usr/local/bin/dcs-check-forwarding --files-only 2>&1); then
        pass I9 'VS Code の受け渡しがファイルに残っていない'
    else
        fail I9 'VS Code の受け渡しがファイルに残っていない' "${out//$'\n'/ }"
    fi
}

main() {
    local only='' sha=''
    while (( $# )); do
        case $1 in
            --only) (( $# >= 2 )) || usage; only=$2; shift 2 ;;
            --managed-sha256) (( $# >= 2 )) || usage; sha=$2; shift 2 ;;
            *) usage ;;
        esac
    done
    case $only in
        '' | image) [[ $sha =~ ^[0-9a-f]{64}$ ]] || usage ;;
        firewall | forwarding) ;;
        *) usage ;;
    esac
    [[ -n $only && $only != image ]] || check_image "$sha"
    [[ -n $only && $only != firewall ]] || check_firewall
    [[ -n $only && $only != forwarding ]] || check_forwarding
    exit "$ng"
}

main "$@"
