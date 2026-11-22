#!/usr/bin/env bash
# =============================================================================
# setup-base.sh — 土台（dcs-base）の設定（root で動かす）
#
# Windows 側の lib/Base.ps1 の New-Base（と、ウィザードの「更新」）が、次のように呼びます。
#   bash /opt/dcs/base/setup-base.sh --phase main <Windows のプロファイル名>
#       apt の取得先を https にして更新し、Docker Engine（Docker の公式の apt リポジトリ）、
#       ユーザー dcs（docker グループ）、Dev Containers CLI を入れ、最後に /etc/wsl.conf を置く。
#   bash /opt/dcs/base/setup-base.sh --phase mount <Windows のプロファイル名>
#       （wsl.conf を効かせるために土台を起動し直したあとで）Windows の VS Code の拡張機能フォルダだけを、
#       読み取り専用でマウントする（/etc/fstab）。最後に「設定が終わった印」（/opt/dcs/base-ready）を書く。
#   bash /opt/dcs/base/setup-base.sh --phase upgrade
#       apt の取得先が https だけであることを確かめてから更新し、Dev Containers CLI を新しくし、/etc/wsl.conf を置き直す
#       （ツールを新しくして wsl.conf が変わったとき。効かせるために、ウィザードがこのあと土台を起動し直す）。
#
# どのフェーズも、何度実行しても同じ結果になります（途中で止まっても、もう一度実行すれば続きから進む）。
# 決まっていること: DESIGN.md の 6.2（D20）、D46・D47。実機の確かめ: VERIFY.md の V1〜V4。
# =============================================================================
set -Eeuo pipefail

readonly BASE_USER=dcs
readonly BASE_HOME=/home/dcs
readonly APT_SOURCES=/etc/apt/sources.list.d/ubuntu.sources
# CVE-2026-109518 を修正した apt の版（従来の _wsl-room-setup と同じ。VERIFY.md の V3）
readonly APT_MIN_VERSION=3.2.1ubuntu0.1
readonly DOCKER_KEY=/etc/apt/keyrings/docker.asc
readonly DOCKER_SOURCES=/etc/apt/sources.list.d/docker.sources
readonly DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
# Dev Containers CLI の公式のインストールスクリプト。既定の Node.js 20 はサポートが終わっているので 24 にする（VERIFY.md の V4）
readonly CLI_INSTALL_URL=https://raw.githubusercontent.com/devcontainers/cli/main/scripts/install.sh
readonly CLI_NODE_MAJOR=24
readonly CLI_BIN=$BASE_HOME/.devcontainers/bin/devcontainer
readonly WSL_CONF_SRC=/opt/dcs/base/wsl.conf
readonly READY_MARK=/opt/dcs/base-ready
readonly RE_PROFILE='^[A-Za-z0-9._-]+$'

# 色（端末に出すときだけ。Windows 側のウィザードの色にそろえる）
if [[ -t 1 ]]; then
    readonly C_STEP=$'\e[96m' C_OK=$'\e[92m' C_NOTE=$'\e[93m' C_ERR=$'\e[91m' C_OFF=$'\e[0m'
else
    readonly C_STEP='' C_OK='' C_NOTE='' C_ERR='' C_OFF=''
fi
step() { printf '\n%s==> %s%s\n' "$C_STEP" "$*" "$C_OFF"; }
ok() { printf '  %s[完了] %s%s\n' "$C_OK" "$*" "$C_OFF"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '  %s[注意] %s%s\n' "$C_NOTE" "$*" "$C_OFF" >&2; }
die() {
    printf '  %s[エラー] %s%s\n' "$C_ERR" "$1" "$C_OFF" >&2
    shift
    local l
    for l in "$@"; do printf '          %s\n' "$l" >&2; done
    exit 1
}
trap 'die "予期しないエラーで止まりました（setup-base.sh の $LINENO 行目）。"' ERR

usage() {
    cat <<'EOF'
使い方（通常は Windows 側の lib/Base.ps1 が呼び出します）:
  bash setup-base.sh --phase main <Windows のプロファイル名>
  bash setup-base.sh --phase mount <Windows のプロファイル名>
  bash setup-base.sh --phase upgrade
EOF
}

# -----------------------------------------------------------------------------
# apt
# -----------------------------------------------------------------------------

# apt の取得先のうち https でないものを「ファイル: URI」の形で 1 行ずつ表示する（すべて https なら何も表示しない）
apt_non_https_uris() {
    local f line uri
    local -a uris
    for f in /etc/apt/sources.list.d/*.sources; do
        [[ -f $f ]] || continue
        while IFS= read -r line || [[ -n $line ]]; do
            # deb822 形式: 「URIs: <URI> [<URI> ...]」
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
            # 1 行形式: 「deb [オプション] <URI> ...」
            [[ $line =~ ^[[:space:]]*deb(-src)?[[:space:]] ]] || continue
            [[ $line == *https://* ]] || printf '%s: %s\n' "$f" "$line"
        done < "$f"
    done
}

assert_apt_all_https() {
    local bad
    bad=$(apt_non_https_uris)
    [[ -z $bad ]] || die "apt の取得先に、https でないものがあります:"$'\n'"$bad" \
        "http のままだと、CVE-2026-109518 により、通信の途中で検証されていないパッケージを入れさせられるおそれがあります。" \
        "表示されたファイルの URI を https に直してから、もう一度実行してください。"
    ok "apt の取得先はすべて https です。"
}

assert_apt_version() {
    local v
    v=$(dpkg-query -W -f='${Version}' apt)
    dpkg --compare-versions "$v" ge "$APT_MIN_VERSION" || die "apt の版（$v）が、修正版（$APT_MIN_VERSION）より古いままです。" \
        "apt-get update と apt-get upgrade が失敗していないか、上の表示を確かめてください。"
    ok "apt の版は $v です（修正版 $APT_MIN_VERSION 以上）。"
}

apt_quiet() {
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -q -y \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

# -----------------------------------------------------------------------------
# Dev Containers CLI（dcs として入れる）
# -----------------------------------------------------------------------------

# $@ は install.sh に渡す引数（--update など）
install_cli() {
    runuser -u "$BASE_USER" -- env HOME="$BASE_HOME" bash -c '
        set -euo pipefail
        cd "$HOME"
        t=$(mktemp)
        trap "rm -f -- \"$t\"" EXIT
        curl --proto "=https" --tlsv1.2 -fsSL "$1" -o "$t"
        shift
        sh "$t" "$@"
    ' _ "$CLI_INSTALL_URL" --node-version "$CLI_NODE_MAJOR" "$@" > /tmp/dcs-cli-install.log 2>&1 || {
        tail -n 20 /tmp/dcs-cli-install.log >&2
        die "Dev Containers CLI を入れられませんでした。" "上に表示されたメッセージを確かめてください。"
    }
    local v
    v=$(runuser -u "$BASE_USER" -- "$CLI_BIN" --version) || die "Dev Containers CLI（$CLI_BIN）が動きません。"
    ok "Dev Containers CLI $v を入れました（$CLI_BIN）。"
}

# -----------------------------------------------------------------------------
# --phase main
# -----------------------------------------------------------------------------

phase_main() {
    step "1/6 apt の取得先を https に書き換えます（CVE-2026-109518 への対策）"
    [[ -f $APT_SOURCES ]] || die "apt の取得先の設定ファイル（$APT_SOURCES）がありません。" \
        "このスクリプトは、Ubuntu 26.04 の設定ファイルの形（deb822 形式）を前提にしています。"
    if grep -qE 'http://(([a-z]+\.)?archive|security)\.ubuntu\.com' "$APT_SOURCES"; then
        sed -Ei 's!http://((([a-z]+\.)?archive|security)\.ubuntu\.com)!https://\1!g' "$APT_SOURCES"
    fi
    assert_apt_all_https

    step "2/6 パッケージを更新します（apt を修正版にするため）"
    apt_quiet update
    apt_quiet upgrade
    assert_apt_version

    step "3/6 Docker Engine を入れます（Docker の公式の apt リポジトリから）"
    apt_quiet install ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -s $DOCKER_KEY ]]; then
        curl --proto '=https' --tlsv1.2 -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$DOCKER_KEY.tmp"
        mv -f -- "$DOCKER_KEY.tmp" "$DOCKER_KEY"
    fi
    chmod a+r "$DOCKER_KEY"
    # shellcheck source=/dev/null
    . /etc/os-release
    printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nSigned-By: %s\n' \
        "$VERSION_CODENAME" "$DOCKER_KEY" > "$DOCKER_SOURCES"
    assert_apt_all_https
    apt_quiet update
    apt_quiet install "${DOCKER_PACKAGES[@]}"
    ok "$(docker --version)"

    step "4/6 土台のユーザー（$BASE_USER）を用意します（パスワード無し・sudo 無し・docker グループ）"
    if id -u "$BASE_USER" > /dev/null 2>&1; then
        info "$BASE_USER はすでにあります。"
    else
        useradd -m -s /bin/bash "$BASE_USER"
    fi
    usermod -aG docker "$BASE_USER"
    if id -nG "$BASE_USER" | tr ' ' '\n' | grep -qxE 'sudo|admin'; then
        die "$BASE_USER が sudo のグループに入っています。" "土台のユーザーには sudo を許しません。"
    fi
    ok "$(id "$BASE_USER")"

    step "5/6 Dev Containers CLI を入れます（$BASE_USER として）"
    if [[ -x $CLI_BIN ]] && runuser -u "$BASE_USER" -- "$CLI_BIN" --version > /dev/null 2>&1; then
        ok "すでに入っています（$(runuser -u "$BASE_USER" -- "$CLI_BIN" --version)）。"
    else
        install_cli
    fi

    step "6/6 /etc/wsl.conf を置きます（C ドライブを見せない・Windows のプログラムを動かさない・既定のユーザーを $BASE_USER に）"
    place_wsl_conf
}

# /opt/dcs/base/wsl.conf（ツールのもの）を /etc/wsl.conf に置く（同じなら何もしない）
place_wsl_conf() {
    [[ -f $WSL_CONF_SRC ]] || die "$WSL_CONF_SRC がありません。"
    if [[ -f /etc/wsl.conf ]] && cmp -s -- "$WSL_CONF_SRC" /etc/wsl.conf; then
        ok "すでに同じ内容です。"
    else
        install -m 644 -o root -g root -- "$WSL_CONF_SRC" /etc/wsl.conf
        ok "置きました。土台を起動し直すと効きます。"
    fi
}

# -----------------------------------------------------------------------------
# --phase mount
# -----------------------------------------------------------------------------

phase_mount() {
    local profile=$1 mp line l fields
    mp="/mnt/c/Users/$profile/.vscode/extensions"
    # v1 と同じ行に nofail を足したもの（マウントに失敗しても、土台の起動を止めない。VERIFY.md の V14 の続き）
    line='C:\\Users\\'"$profile"'\\.vscode\\extensions '"$mp"' drvfs defaults,ro,nofail 0 0'

    step "1/3 C ドライブが土台から見えなくなっていることを確かめます"
    # 起動し直す前に実行すると、本物の C ドライブの上にフォルダを作ってしまうので止める
    [[ ! -e /mnt/c/Windows ]] || die "C ドライブが見えています（/mnt/c/Windows があります）。" \
        "/etc/wsl.conf（automount の無効）を効かせるために、土台を起動し直してから、もう一度実行してください。"
    ok "見えていません。"

    step "2/3 /etc/fstab に、VS Code の拡張機能フォルダを読み取り専用でマウントする 1 行を足します"
    if [[ -f /etc/fstab ]]; then
        while IFS= read -r l || [[ -n $l ]]; do
            l=${l%$'\r'}
            [[ $l == "$line" ]] && { ok "すでに同じ行があります。"; break; }
            read -ra fields <<< "$l"
            if [[ ${fields[1]:-} == "$mp" ]]; then
                die "/etc/fstab に、同じ取り付け先で違う行があります:" "  $l" \
                    "安全のため自動では書き換えません。この行を削除してから、もう一度実行してください。"
            fi
        done < /etc/fstab
    fi
    if ! grep -qxF -- "$line" /etc/fstab 2> /dev/null; then
        if [[ -s /etc/fstab && -n $(tail -c 1 /etc/fstab) ]]; then printf '\n' >> /etc/fstab; fi
        printf '%s\n' "$line" >> /etc/fstab
        ok "次の 1 行を足しました:"
        info "$line"
    fi

    step "3/3 マウントします"
    mkdir -p -- "$mp"
    if mountpoint -q -- "$mp"; then
        ok "すでにマウントされています。"
    else
        systemctl daemon-reload 2> /dev/null || true
        if mount -- "$mp" 2> /tmp/dcs-mount.err; then
            ok "$mp を読み取り専用でマウントしました。"
        else
            # D47: 止めずに知らせる（VS Code から土台につなげないので、直し方を示す）
            warn "VS Code の拡張機能フォルダをマウントできませんでした（$(tr '\n' ' ' < /tmp/dcs-mount.err)）。"
            warn "このままでは、VS Code から土台につなげません。Windows の %USERPROFILE%\\.wslconfig に"
            warn "hostFileSystemAccess=false の行があれば消し、PowerShell で wsl --shutdown を実行してください（README）。"
        fi
    fi

    date '+%Y-%m-%d %H:%M:%S' > "$READY_MARK"
    ok "土台の設定が終わりました（$READY_MARK）。"
}

# -----------------------------------------------------------------------------
# --phase upgrade
# -----------------------------------------------------------------------------

phase_upgrade() {
    step "1/4 apt の取得先がすべて https であることを確かめます"
    assert_apt_all_https
    step "2/4 Ubuntu と Docker Engine を更新します"
    apt_quiet update
    apt_quiet upgrade
    assert_apt_version
    step "3/4 Dev Containers CLI を新しくします"
    install_cli --update
    # ツールを新しくして wsl.conf が変わったとき、土台の検証の B2 が NG になる。ここで置き直す（ウィザードが、このあと土台を起動し直す）
    step "4/4 /etc/wsl.conf を、ツールのものに置き直します"
    place_wsl_conf
}

# -----------------------------------------------------------------------------

main() {
    local phase='' profile=''
    while (( $# )); do
        case $1 in
            --phase)
                (( $# >= 2 )) || { usage >&2; exit 2; }
                phase=$2; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            -*) usage >&2; exit 2 ;;
            *)
                [[ -z $profile ]] || { usage >&2; exit 2; }
                profile=$1; shift ;;
        esac
    done
    [[ $(id -u) == 0 ]] || die "root で実行してください。"
    cd /
    case $phase in
        main|mount)
            [[ $profile =~ $RE_PROFILE ]] || die "Windows のプロファイル名が正しくありません: $profile"
            "phase_$phase" "$profile" ;;
        upgrade)
            [[ -z $profile ]] || { usage >&2; exit 2; }
            phase_upgrade ;;
        *) usage >&2; exit 2 ;;
    esac
}

main "$@"
