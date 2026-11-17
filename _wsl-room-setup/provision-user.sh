#!/usr/bin/env bash
# =============================================================================
# provision-user.sh — 部屋の中で一般ユーザーとして実行する設定スクリプト
#
# 通常は Windows 側の New-SecureRoom.ps1 が自動で呼び出します。
#
#   bash provision-user.sh [--config <room.conf のパス>]
#
# 行うこと:
#   1. Claude Code のインストール（公式のインストールスクリプト）
#   2. ~/.local/bin を PATH に追加（~/.bashrc。すでにあれば追記しない）
#   -  uv（Python のパッケージ・プロジェクト管理ツール）のインストール
#      （公式のインストールスクリプト https://astral.sh/uv/install.sh。~/.local/bin に入る。~/.bashrc などは書き換えさせない）
#   -  Rust のインストール（公式の rustup https://sh.rustup.rs。stable の default プロファイルを ~/.cargo と ~/.rustup に入れ、
#      ~/.bashrc に「. "$HOME/.cargo/env"」を追記）。リンクに使う C コンパイラなどは provision-root.sh が入れる
#      （build-essential・pkg-config・libssl-dev）
#   3. ~/.claude/settings.json の配置（ステータスラインなどの好みの設定。守りの設定（サンドボックスと権限ルール）は、
#      provision-root.sh が managed settings として置く）
#   4. ステータスライン（statusline.sh）を ~/.claude/statusline.sh に配置
#   5. ~/projects の作成
#
# uv と Rust は、Claude Code と違って自動では更新されない（README 6.8）。
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

readonly UV_INSTALL_URL='https://astral.sh/uv/install.sh'
readonly UV_BIN="$HOME/.local/bin/uv"
readonly RUSTUP_URL='https://sh.rustup.rs'
readonly RUSTC_BIN="$HOME/.cargo/bin/rustc"
# ~/.bashrc に書く行。$HOME は書いた時点で展開せず、そのまま書き込む
# shellcheck disable=SC2016
readonly CARGO_ENV_LINE='. "$HOME/.cargo/env"'

usage() {
    echo '使い方: bash provision-user.sh [--config <room.conf のパス>]'
}

install_claude() {
    step "1/5 Claude Code をインストールします"
    if [[ -x $CLAUDE_BIN ]]; then
        ok "インストール済みです（$CLAUDE_BIN）。"
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
    printf '\n# Claude Code（wsl-room-setup が追加）\n%s\n' "$PATH_LINE" >> "$HOME/.bashrc"
    ok "~/.bashrc に追記しました。"
}

# uv（Python のパッケージ・プロジェクト管理ツール）を ~/.local/bin に入れる
install_uv() {
    step "uv をインストールします"
    if [[ -x $UV_BIN ]]; then
        ok "インストール済みです（$("$UV_BIN" --version)）。"
        return 0
    fi
    # ~/.local/bin は add_path_line で PATH に入るので、
    # インストーラーには ~/.bashrc などを書き換えさせない
    curl --proto '=https' --tlsv1.2 -LsSf "$UV_INSTALL_URL" | env UV_NO_MODIFY_PATH=1 sh
    [[ -x $UV_BIN ]] || die "インストール後も $UV_BIN が見つかりません。" \
        "上に表示されたインストーラーのメッセージを確認してください。"
    ok "インストールしました（$("$UV_BIN" --version)）。"
}

# Rust（rustup 経由。~/.cargo と ~/.rustup に入る）
install_rust() {
    step "Rust（rustup）をインストールします"

    # Rust はリンクに C コンパイラ（cc）を使う。無いと cargo build が失敗する
    command -v cc > /dev/null || die "C コンパイラ（cc）が見つかりません。" \
        "provision-root.sh のパッケージに build-essential を追加して、先に実行してください。"

    if [[ -x $RUSTC_BIN ]]; then
        ok "インストール済みです（$("$RUSTC_BIN" --version)）。"
    else
        curl --proto '=https' --tlsv1.2 -sSf "$RUSTUP_URL" \
            | sh -s -- -y --no-modify-path --profile default --default-toolchain stable
        [[ -x $RUSTC_BIN ]] || die "インストール後も $RUSTC_BIN が見つかりません。" \
            "上に表示されたインストーラーのメッセージを確認してください。"
        ok "インストールしました（$("$RUSTC_BIN" --version)）。"
    fi

    # ~/.cargo/bin を PATH に入れる行を ~/.bashrc に追加（すでにあれば追記しない）
    if [[ -f $HOME/.bashrc ]] && grep -Fxq -- "$CARGO_ENV_LINE" "$HOME/.bashrc"; then
        ok "~/.bashrc の設定はすでにあります（変更なし）。"
    else
        printf '\n# Rust（wsl-room-setup が追加）\n%s\n' "$CARGO_ENV_LINE" >> "$HOME/.bashrc"
        ok "~/.bashrc に追記しました。"
    fi
}

# $1 を $2 に置く（同じ内容なら何もしない。違えば元のファイルを「元の名前.bak-日時」として残す）
install_user_file() {
    local src=$1 dest=$2 bak
    [[ -r $src ]] || die "$src が見つかりません。"
    if [[ -f $dest ]] && cmp -s -- "$src" "$dest"; then
        ok "すでに同じ内容です（変更なし）。"
        return 0
    fi
    mkdir -p -- "${dest%/*}"
    if [[ -e $dest ]]; then
        bak="$dest.bak-$(date +%Y%m%d-%H%M%S)"
        cp -p -- "$dest" "$bak"
        info "元のファイルを $bak に保存しました。"
    fi
    install -m 644 -- "$src" "$dest"
    ok "配置しました。"
}

install_settings() {
    step "3/5 Claude Code の設定ファイル（$SETTINGS_FILE）を配置します"
    install_user_file "$SETTINGS_TEMPLATE" "$SETTINGS_FILE"
}

# settings.json の statusLine（bash ~/.claude/statusline.sh）から実行されるファイルを置く
install_statusline() {
    step "4/5 ステータスライン（$STATUSLINE_DEST）を配置します"
    install_user_file "$STATUSLINE_SRC" "$STATUSLINE_DEST"
}

create_projects_dir() {
    step "5/5 プロジェクト用のフォルダ ~/projects を作成します"
    mkdir -p -- "$HOME/projects"
    ok "~/projects を用意しました。Claude Code は必ず ~/projects/<プロジェクト名> の中で起動してください。"
}

main() {
    local config="$SCRIPT_DIR/room.conf"
    while (( $# )); do
        case $1 in
            --config)
                (( $# >= 2 )) || die "--config の後にファイルのパスを指定してください。"
                config=$2; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) die "知らないオプションです: $1" "$(usage)" ;;
        esac
    done

    require_not_root
    load_room_conf "$config"
    [[ $(id -un) == "$CONF_LINUX_USER" ]] || die \
        "このスクリプトは room.conf の linux_user（$CONF_LINUX_USER）として実行してください（今は $(id -un)）。"

    install_claude
    add_path_line
    install_uv
    install_rust
    install_settings
    install_statusline
    create_projects_dir
    ok "一般ユーザー用の設定が終わりました。"
}

main "$@"
