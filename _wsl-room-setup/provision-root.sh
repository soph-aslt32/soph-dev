#!/usr/bin/env bash
# =============================================================================
# provision-root.sh — 部屋の中で root として実行する設定スクリプト
#
# 通常は Windows 側の New-SecureRoom.ps1 が、次の 2 段階に分けて自動で呼び出します。
#
#   bash provision-root.sh --phase base [--config <room.conf のパス>]
#       パッケージの導入、/etc/wsl.conf の書き換え、AppArmor の確認。
#       wsl.conf の変更（C ドライブを隠す）は、このあと部屋を再起動するまで反映されない。
#
#   bash provision-root.sh --phase mount [--config <room.conf のパス>]
#       VS Code 拡張フォルダを読み取り専用でマウントする設定（/etc/fstab）。
#       再起動前に実行すると、本物の C ドライブの上にフォルダを作ってしまうので、
#       C ドライブが見えなくなったことを確認してから進む。
#
# Linux ユーザー名と Windows ユーザー名は room.conf（省略時はこのスクリプトと同じフォルダのもの）から読みます。
# どちらにも --dry-run を付けると、何も変更せずに実行内容だけを表示します。
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
trap 'on_error $LINENO' ERR

readonly PACKAGES=(bubblewrap socat git curl jq)
readonly APT_OPTS=(-y -o DPkg::Lock::Timeout=300)
readonly APPARMOR_PROFILE=/etc/apparmor.d/bwrap

usage() {
    cat <<'EOF'
使い方:
  bash provision-root.sh --phase base  [--config <room.conf のパス>] [--dry-run]
  bash provision-root.sh --phase mount [--config <room.conf のパス>] [--dry-run]
EOF
}

# 標準入力の内容を、root 所有・指定のモードでファイルに書く（途中で止まっても壊れたファイルを残さない）
write_file_atomic() {
    local dest=$1 mode=$2 tmp
    if (( DRY_RUN )); then
        info "[dry-run] $dest に次の内容を書き込みます（モード $mode）:"
        sed 's/^/      | /'
        return 0
    fi
    tmp=$(mktemp "$dest.tmp.XXXXXX")
    cat > "$tmp"
    chown root:root "$tmp"
    chmod "$mode" "$tmp"
    mv -f "$tmp" "$dest"
}

# 書き換える前のファイルを「元の名前.bak-日時」として残す
backup_file() {
    local f=$1 bak
    [[ -e $f ]] || return 0
    bak="$f.bak-$(date +%Y%m%d-%H%M%S)"
    run cp -p -- "$f" "$bak"
    (( DRY_RUN )) || info "元のファイルを $bak に保存しました。"
}

systemd_running() {
    [[ -d /run/systemd/system ]]
}

# systemd が起動を終えるまで待つ（WSL では "degraded" で終わることが多いが、それでもよい）
wait_for_systemd() {
    systemd_running || return 1
    timeout 60 systemctl is-system-running --wait > /dev/null 2>&1 || true
}

# -----------------------------------------------------------------------------
# --phase base
# -----------------------------------------------------------------------------

phase_base() {
    local uid
    uid=$(id -u -- "$CONF_LINUX_USER" 2> /dev/null) || die \
        "room.conf の linux_user（$CONF_LINUX_USER）というユーザーが、部屋の中にありません。" \
        "部屋を作るときに入力したユーザー名と、room.conf の linux_user が同じか確認してください。"
    [[ $uid != 0 ]] || die "$CONF_LINUX_USER は root（UID 0）です。一般ユーザーを指定してください。"

    step "1/3 パッケージを更新し、必要なもの（${PACKAGES[*]}）をインストールします（数分かかります）"
    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
    run apt-get "${APT_OPTS[@]}" update
    run apt-get "${APT_OPTS[@]}" -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade
    run apt-get "${APT_OPTS[@]}" install "${PACKAGES[@]}"
    ok "パッケージの準備ができました。"

    step "2/3 /etc/wsl.conf を仕様どおりの内容に置き換えます"
    install_wsl_conf "$CONF_LINUX_USER"

    step "3/3 AppArmor の追加設定が必要か確認します"
    setup_apparmor_if_needed

    ok "base 段階が終わりました。部屋を再起動してから --phase mount を実行します。"
}

install_wsl_conf() {
    local user=$1 tmpl="$SCRIPT_DIR/templates/wsl.conf.tmpl" content
    [[ -r $tmpl ]] || die "テンプレート $tmpl が見つかりません。"
    content=$(< "$tmpl")
    content=${content//__LINUX_USER__/$user}

    if [[ -f /etc/wsl.conf && "$(< /etc/wsl.conf)" == "$content" ]]; then
        ok "すでに仕様どおりです（変更なし）。"
        return 0
    fi
    backup_file /etc/wsl.conf
    printf '%s\n' "$content" | write_file_atomic /etc/wsl.conf 644
    ok "/etc/wsl.conf を書き換えました（部屋の再起動後に反映されます）。"
}

setup_apparmor_if_needed() {
    local val
    if ! val=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2> /dev/null); then
        ok "kernel.apparmor_restrict_unprivileged_userns が存在しないため不要です（WSL では通常この結果です）。"
        return 0
    fi
    case $val in
        0)
            ok "制限は無効（0）なので不要です。"
            ;;
        1)
            info "制限が有効（1）なので、bubblewrap 用の AppArmor プロファイルを追加します。"
            # 内容は Claude Code 公式ドキュメント「Sandboxing」の Linux / WSL2 の手順のとおり
            write_file_atomic "$APPARMOR_PROFILE" 644 <<'EOF'
abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
  include if exists <local/bwrap>
}
EOF
            if systemd_running; then
                run systemctl reload apparmor
                ok "AppArmor プロファイルを追加して読み込みました。"
            else
                ok "AppArmor プロファイルを追加しました（次回の起動時に読み込まれます）。"
            fi
            ;;
        *)
            die "kernel.apparmor_restrict_unprivileged_userns の値が想定外です: $val"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# --phase mount
# -----------------------------------------------------------------------------

phase_mount() {
    local mp line
    mp=$(win_ext_mountpoint "$CONF_WINDOWS_USER")
    line=$(fstab_expected_line "$CONF_WINDOWS_USER")

    step "1/4 C ドライブが部屋から見えなくなっていることを確認します"
    if [[ -e /mnt/c/Windows ]] || mountpoint -q /mnt/c; then
        die "C ドライブがまだ部屋から見えています（/mnt/c）。" \
            "/etc/wsl.conf の変更が反映されていません。部屋を再起動してから、もう一度実行してください。" \
            "（Windows 側で: wsl --terminate <部屋の名前>）"
    fi
    ok "C ドライブは見えていません。"

    step "2/4 取り付け先のフォルダ $mp を用意します（部屋の中のフォルダです）"
    if mountpoint -q "$mp"; then
        ok "すでにマウントされています。"
    else
        run mkdir -p -- "$mp"
        ok "用意しました。"
    fi

    step "3/4 /etc/fstab に読み取り専用マウントの設定を追加します"
    update_fstab "$mp" "$line"

    step "4/4 マウントします"
    if wait_for_systemd; then
        # systemd は fstab の内容を覚えているので、読み直させてからマウントする（9 章）
        run systemctl daemon-reload
    else
        warn "systemd が動いていないため daemon-reload は行いません。"
    fi
    if mountpoint -q "$mp"; then
        info "すでにマウントされています。"
    else
        run mount "$mp"
    fi
    if (( ! DRY_RUN )); then
        local opts
        opts=$(awk -v mp="$mp" '$2 == mp { print $4 }' /proc/self/mounts | tail -n 1)
        [[ ,$opts, == *,ro,* ]] || die "$mp が読み取り専用でマウントされていません（オプション: ${opts:-なし}）。" \
            "安全のため、ここで停止します。/etc/fstab の内容を確認してください。"
    fi
    ok "$mp を読み取り専用でマウントしました。"
}

update_fstab() {
    local mp=$1 line=$2 l found=0
    local -a fields
    if [[ -f /etc/fstab ]]; then
        while IFS= read -r l || [[ -n $l ]]; do
            l=${l%$'\r'}
            [[ $l =~ $RE_SKIP_LINE ]] && continue
            read -ra fields <<< "$l"
            [[ ${fields[1]:-} == "$mp" ]] || continue
            if [[ "${fields[*]}" == "$line" ]]; then
                found=1
            else
                die "/etc/fstab に、同じ取り付け先で仕様と違う行があります:" "  $l" \
                    "安全のため自動では書き換えません。この行を削除してから、もう一度実行してください。"
            fi
        done < /etc/fstab
    fi
    if (( found )); then
        ok "すでに設定済みです（変更なし）。"
        return 0
    fi

    backup_file /etc/fstab
    {
        if [[ -s /etc/fstab ]]; then
            cat /etc/fstab
            # 最後の行に改行が無ければ補う
            [[ -z $(tail -c 1 /etc/fstab) ]] || printf '\n'
        fi
        printf '%s\n' "$line"
    } | write_file_atomic /etc/fstab 644
    ok "次の 1 行を追加しました:"
    info "$line"
}

# -----------------------------------------------------------------------------

main() {
    local phase='' config="$SCRIPT_DIR/room.conf"
    while (( $# )); do
        case $1 in
            --phase|--config)
                (( $# >= 2 )) || die "$1 の後に値を指定してください。" "$(usage)"
                if [[ $1 == --phase ]]; then phase=$2; else config=$2; fi
                shift 2
                ;;
            --dry-run) DRY_RUN=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "知らないオプションです: $1" "$(usage)" ;;
        esac
    done

    require_root
    (( DRY_RUN )) && warn "ドライランです。何も変更しません。"
    load_room_conf "$config"
    case $phase in
        base) phase_base ;;
        mount) phase_mount ;;
        *) die "--phase base または --phase mount を指定してください。" "$(usage)" ;;
    esac
}

main "$@"
