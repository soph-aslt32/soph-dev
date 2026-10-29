#!/usr/bin/env bash
# =============================================================================
# provision-user.sh — 部屋の中で一般ユーザーとして実行する設定スクリプト
#
# 通常は Windows 側の New-SecureRoom.ps1 が自動で呼び出します。
#
#   bash provision-user.sh [--config <room.conf のパス>] [--dry-run]
#
# 行うこと:
#   1. Claude Code のインストール（公式のインストールスクリプト）
#   2. ~/.local/bin を PATH に追加（~/.bashrc。すでにあれば追記しない）
#   3. ~/.claude/settings.json の配置（サンドボックス等の設定。room.conf の allowed_domains を反映）
#   4. ステータスライン（statusline.sh）を ~/.claude/statusline.sh に配置
#   5. ~/projects の作成
#
# Claude Code へのログインは対話が必要なので、ここでは行いません（README 参照）。
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
trap 'on_error $LINENO' ERR

readonly INSTALL_URL='https://claude.ai/install.sh'
readonly CLAUDE_BIN="$HOME/.local/bin/claude"
readonly SETTINGS_FILE="$HOME/.claude/settings.json"
readonly SETTINGS_TEMPLATE="$SCRIPT_DIR/templates/claude-settings.json.tmpl"
readonly STATUSLINE_SRC="$SCRIPT_DIR/statusline.sh"
readonly STATUSLINE_DEST="$HOME/.claude/statusline.sh"

usage() {
    echo '使い方: bash provision-user.sh [--config <room.conf のパス>] [--dry-run]'
}

install_claude() {
    step "1/5 Claude Code をインストールします"
    if [[ -x $CLAUDE_BIN ]]; then
        ok "インストール済みです（$CLAUDE_BIN）。"
        return 0
    fi
    if (( DRY_RUN )); then
        info "[dry-run] curl -fsSL $INSTALL_URL | bash"
        return 0
    fi
    curl -fsSL "$INSTALL_URL" | bash
    [[ -x $CLAUDE_BIN ]] || die "インストール後も $CLAUDE_BIN が見つかりません。" \
        "上に表示されたインストーラーのメッセージを確認してください。"
    ok "インストールしました（$CLAUDE_BIN）。"
}

add_path_line() {
    step "2/5 ~/.local/bin を PATH に追加します（~/.bashrc）"
    if [[ -f $HOME/.bashrc ]] && grep -Fxq -- "$PATH_LINE" "$HOME/.bashrc"; then
        ok "すでに追加されています（変更なし）。"
        return 0
    fi
    if (( DRY_RUN )); then
        info "[dry-run] ~/.bashrc に次の行を追記: $PATH_LINE"
        return 0
    fi
    printf '\n# Claude Code（wsl-room-setup が追加）\n%s\n' "$PATH_LINE" >> "$HOME/.bashrc"
    ok "~/.bashrc に追記しました。"
}

install_settings() {
    step "3/5 Claude Code の設定ファイル（$SETTINGS_FILE）を配置します"
    command -v jq > /dev/null || die "jq が見つかりません。" \
        "provision-root.sh（root 用の設定）が先に完了している必要があります。"
    [[ -r $SETTINGS_TEMPLATE ]] || die "テンプレート $SETTINGS_TEMPLATE が見つかりません。"

    # テンプレートの allowedDomains を room.conf の内容で置き換える。
    # jq を通すので、JSON として正しいことも同時に保証される。
    local domains_json new
    domains_json=$(jq -nc '$ARGS.positional' --args "${CONF_ALLOWED_DOMAINS[@]}")
    new=$(jq --indent 2 --argjson domains "$domains_json" \
        '.sandbox.network.allowedDomains = $domains' "$SETTINGS_TEMPLATE")
    info "通信を許可するドメイン: ${CONF_ALLOWED_DOMAINS[*]:-（なし）}"

    if [[ -f $SETTINGS_FILE && "$(< "$SETTINGS_FILE")" == "$new" ]]; then
        ok "すでに同じ内容です（変更なし）。"
        return 0
    fi
    if (( DRY_RUN )); then
        info "[dry-run] $SETTINGS_FILE に次の内容を書き込みます:"
        printf '%s\n' "$new" | sed 's/^/      | /'
        return 0
    fi
    mkdir -p -- "${SETTINGS_FILE%/*}"
    if [[ -e $SETTINGS_FILE ]]; then
        local bak
        bak="$SETTINGS_FILE.bak-$(date +%Y%m%d-%H%M%S)"
        cp -p -- "$SETTINGS_FILE" "$bak"
        info "元のファイルを $bak に保存しました。"
    fi
    printf '%s\n' "$new" > "$SETTINGS_FILE.tmp"
    mv -f -- "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    ok "配置しました。"
}

# settings.json の statusLine（bash ~/.claude/statusline.sh）から実行されるファイルを置く
install_statusline() {
    step "4/5 ステータスライン（$STATUSLINE_DEST）を配置します"
    [[ -r $STATUSLINE_SRC ]] || die "$STATUSLINE_SRC が見つかりません。"
    if [[ -f $STATUSLINE_DEST ]] && cmp -s -- "$STATUSLINE_SRC" "$STATUSLINE_DEST"; then
        ok "すでに同じ内容です（変更なし）。"
        return 0
    fi
    if (( DRY_RUN )); then
        info "[dry-run] $STATUSLINE_SRC を $STATUSLINE_DEST にコピー"
        return 0
    fi
    mkdir -p -- "${STATUSLINE_DEST%/*}"
    if [[ -e $STATUSLINE_DEST ]]; then
        local bak
        bak="$STATUSLINE_DEST.bak-$(date +%Y%m%d-%H%M%S)"
        cp -p -- "$STATUSLINE_DEST" "$bak"
        info "元のファイルを $bak に保存しました。"
    fi
    install -m 644 -- "$STATUSLINE_SRC" "$STATUSLINE_DEST"
    ok "配置しました。"
}

create_projects_dir() {
    step "5/5 プロジェクト用のフォルダ ~/projects を作成します"
    run mkdir -p -- "$HOME/projects"
    ok "~/projects を用意しました。Claude Code は必ず ~/projects/<プロジェクト名> の中で起動してください。"
}

main() {
    local config="$SCRIPT_DIR/room.conf"
    while (( $# )); do
        case $1 in
            --config)
                (( $# >= 2 )) || die "--config の後にファイルのパスを指定してください。"
                config=$2; shift 2 ;;
            --dry-run) DRY_RUN=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "知らないオプションです: $1" "$(usage)" ;;
        esac
    done

    require_not_root
    (( DRY_RUN )) && warn "ドライランです。何も変更しません。"
    load_room_conf "$config"
    [[ $(id -un) == "$CONF_LINUX_USER" ]] || die \
        "このスクリプトは room.conf の linux_user（$CONF_LINUX_USER）として実行してください（今は $(id -un)）。"

    install_claude
    add_path_line
    install_settings
    install_statusline
    create_projects_dir
    ok "一般ユーザー用の設定が終わりました。"
}

main "$@"
