# shellcheck shell=bash
# =============================================================================
# lib.sh — provision-root.sh / provision-user.sh / verify-room.sh の共通部品
#
# 単体では実行しません。各スクリプトの先頭で source して使います。
# =============================================================================

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------

# ~/.bashrc に追記する PATH の行（3.5）
# shellcheck disable=SC2016  # $HOME と $PATH は .bashrc の中で展開させるため、ここでは展開しない
readonly PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

# 入力チェック用の正規表現
readonly RE_LINUX_USER='^[a-z_][a-z0-9_-]{0,31}$'
# Windows ユーザー名はスペース・非 ASCII を含むと fstab の書き方が未検証のため、安全な文字だけ許可する（3.3）
readonly RE_WIN_USER='^[A-Za-z0-9._-]+$'
# ドメイン名。先頭の「*.」（サブドメインすべて）だけはワイルドカードとして許可する
readonly RE_DOMAIN='^(\*\.)?[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$'
# 空行とコメント行（# で始まる行）
readonly RE_SKIP_LINE='^[[:space:]]*(#|$)'

# ---------------------------------------------------------------------------
# 表示
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
    C_CYAN=$'\e[36m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_RED=$'\e[31m' C_RESET=$'\e[0m'
else
    C_CYAN='' C_GREEN='' C_YELLOW='' C_RED='' C_RESET=''
fi

step() { printf '\n%s==> %s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
# ドライランのときは実際には何もしていないので、[完了] ではなく [予定] と表示する
ok() {
    if (( ${DRY_RUN:-0} )); then
        printf '  [予定] %s\n' "$*"
    else
        printf '%s  [完了] %s%s\n' "$C_GREEN" "$*" "$C_RESET"
    fi
}
info() { printf '  %s\n' "$*"; }
warn() { printf '%s  [注意] %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }

# die "何が起きたか" ["次に何をすればよいか" ...]
die() {
    printf '%s[エラー] %s%s\n' "$C_RED" "$1" "$C_RESET" >&2
    shift
    local line
    for line in "$@"; do printf '        %s\n' "$line" >&2; done
    exit 1
}

# set -e で予期せず止まったときに、どこで止まったかを表示する（trap で登録して使う）
on_error() {
    local rc=$? line=$1
    printf '%s[エラー] %s の %s 行目で予期しないエラーが起きたため停止しました（終了コード %s）。%s\n' \
        "$C_RED" "${0##*/}" "$line" "$rc" "$C_RESET" >&2
    printf '        直前に表示されたメッセージを確認してください。\n' >&2
}

# ---------------------------------------------------------------------------
# ドライラン
# ---------------------------------------------------------------------------

DRY_RUN=0

# コマンドを実行する。--dry-run のときは実行せずに表示だけする。
run() {
    if (( DRY_RUN )); then
        printf '  [dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

# ---------------------------------------------------------------------------
# 権限
# ---------------------------------------------------------------------------

require_root() {
    [[ $(id -u) == 0 ]] || die "このスクリプトは root として実行する必要があります。" \
        "Windows 側の New-SecureRoom.ps1 から実行してください。"
}

require_not_root() {
    [[ $(id -u) != 0 ]] || die "このスクリプトは root ではなく、部屋の一般ユーザーとして実行してください。"
}

# ---------------------------------------------------------------------------
# 文字列
# ---------------------------------------------------------------------------

trim() {
    local s=$1
    s=${s#"${s%%[![:space:]]*}"}
    s=${s%"${s##*[![:space:]]}"}
    printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# VS Code 拡張フォルダの公開（3.3）
# ---------------------------------------------------------------------------

# 部屋の中の取り付け先。Windows 側の実パスを WSL の標準規則で変換したものと完全一致させる。
win_ext_mountpoint() {
    printf '/mnt/c/Users/%s/.vscode/extensions' "$1"
}

# /etc/fstab に書く 1 行（仕様 3.3 の文字どおり。バックスラッシュは 2 つずつ）
fstab_expected_line() {
    printf '%s %s drvfs defaults,ro 0 0' \
        'C:\\Users\\'"$1"'\\.vscode\\extensions' "$(win_ext_mountpoint "$1")"
}

# ---------------------------------------------------------------------------
# 設定ファイル（room.conf）
# ---------------------------------------------------------------------------
# 書式は「名前 = 値」。# で始まる行はコメント。
# Windows で編集されることを想定し、CRLF の改行と UTF-8 の BOM は取り除いて読む。
# New-SecureRoom.ps1 の Read-RoomConf も同じ規則で事前チェックしている（変えるときは両方）。
#
# 部屋の中では、New-SecureRoom.ps1 が root 所有でコピーした
# /usr/local/lib/wsl-room-setup/room.conf を読む。部屋の一般ユーザーやサンドボックス内の
# Claude は書き換えられないので、検証（verify-room.sh）の期待値としても使える。

# 読み込んで次の変数を設定する:
#   CONF_LINUX_USER      部屋の Linux ユーザー名
#   CONF_WINDOWS_USER    Windows のユーザーフォルダ名（C:\Users\<ここ>）
#   CONF_ALLOWED_DOMAINS サンドボックスから通信してよいドメイン（配列）
load_room_conf() {
    local file=$1 lineno=0 line key value
    local -A seen=()
    CONF_LINUX_USER='' CONF_WINDOWS_USER='' CONF_ALLOWED_DOMAINS=()

    [[ -r $file ]] || die "設定ファイル $file が読めません。"
    while IFS= read -r line || [[ -n $line ]]; do
        lineno=$((lineno + 1))
        line=${line%$'\r'}
        (( lineno == 1 )) && line=${line#$'\xEF\xBB\xBF'}
        [[ $line =~ $RE_SKIP_LINE ]] && continue
        [[ $line =~ ^[[:space:]]*([a-z_]+)[[:space:]]*=(.*)$ ]] || die \
            "設定ファイル $file の $lineno 行目の書き方が正しくありません: $line" \
            "「名前 = 値」の形で書いてください。"
        key=${BASH_REMATCH[1]}
        value=$(trim "${BASH_REMATCH[2]}")
        # 値を "..." で囲んで書いた場合は外す
        if [[ ${#value} -ge 2 && $value == \"*\" ]]; then value=${value:1:-1}; fi
        [[ -z ${seen[$key]:-} ]] || die "設定ファイル $file の $lineno 行目: $key が 2 回書かれています。"
        seen[$key]=1
        case $key in
            linux_user)
                [[ -n $value ]] || die "設定ファイル $file の $lineno 行目: linux_user が空です。" \
                    "部屋の中で使う Linux のユーザー名を書いてください（例: taro）。"
                [[ $value =~ $RE_LINUX_USER ]] || die \
                    "設定ファイル $file の $lineno 行目: linux_user が正しくありません: '$value'" \
                    "半角英小文字で始まり、英小文字・数字・_・- だけを使った 32 文字以内の名前にしてください。"
                CONF_LINUX_USER=$value ;;
            windows_user)
                [[ -n $value ]] || die "設定ファイル $file の $lineno 行目: windows_user が空です。" \
                    "Windows のユーザーフォルダの名前（C:\\Users\\<ここ>）を書いてください。"
                [[ $value =~ $RE_WIN_USER ]] || die \
                    "設定ファイル $file の $lineno 行目: windows_user が正しくありません: '$value'" \
                    "半角英数字と . _ - だけに対応しています（スペースや日本語を含む名前は、動作が未確認のため未対応）。"
                CONF_WINDOWS_USER=$value ;;
            allowed_domains) parse_allowed_domains "$value" "$file" "$lineno" ;;
            *) die "設定ファイル $file の $lineno 行目: 知らない項目名です: $key" \
                   "使える項目は linux_user、windows_user、allowed_domains です。" ;;
        esac
    done < "$file"
    [[ -n ${seen[linux_user]:-} ]] || die "設定ファイル $file に linux_user がありません。"
    [[ -n ${seen[windows_user]:-} ]] || die "設定ファイル $file に windows_user がありません。"
    [[ -n ${seen[allowed_domains]:-} ]] || die "設定ファイル $file に allowed_domains がありません。" \
        "通信を許可するドメインが無い場合も「allowed_domains =」と空で書いてください。"
}

parse_allowed_domains() {
    local value=$1 file=$2 lineno=$3 part d existing
    local -a parts=()
    IFS=',' read -ra parts <<< "$value"
    for part in "${parts[@]}"; do
        d=$(trim "$part")
        [[ -n $d ]] || continue
        [[ $d != '*' ]] || die "設定ファイル $file の $lineno 行目: allowed_domains に「*」は使えません。" \
            "「*」はすべてのドメインへの通信を許可してしまい、サンドボックスの意味がなくなるためです。"
        [[ $d =~ $RE_DOMAIN ]] || die "設定ファイル $file の $lineno 行目: ドメイン名として正しくありません: $d" \
            "例: registry.npmjs.org や *.example.com のように書いてください（https:// やパスは不要です）。"
        for existing in "${CONF_ALLOWED_DOMAINS[@]}"; do
            [[ $existing == "$d" ]] && continue 2
        done
        CONF_ALLOWED_DOMAINS+=("$d")
    done
}
