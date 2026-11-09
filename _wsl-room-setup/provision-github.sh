#!/usr/bin/env bash
# =============================================================================
# provision-github.sh — GitHub を使うための git の設定と、リポジトリのクローン（一般ユーザー）
#
# 通常は Windows 側の New-SecureRoom.ps1 が、room-github.conf に記入があるときだけ、
# 次の 2 段階に分けて自動で呼び出します。
#
#   bash provision-github.sh --phase credentials   （設定は標準入力で受け取る）
#       git の設定（user.name、user.email、credential.helper store、credential.useHttpPath）と、
#       PAT の保存（~/.git-credentials、モード 600）。
#
#   bash provision-github.sh --phase clone <リポジトリの URL>
#       ~/projects/<リポジトリ名> へのクローンと、PAT で push できるかの確認。
#       認証には、credentials の段階で保存した PAT を使う。
#
# room-github.conf の中身（特に PAT）を部屋の中の Claude Code から見えないようにするため、
#   - room-github.conf は部屋の中に持ち込まない。New-SecureRoom.ps1 が内容を確認したうえで、
#     次の形の文字列を base64 にして標準入力で渡す（ディスクに一時ファイルを作らない）
#         user_name=...
#         user_email=...
#         pat=...
#         repo_url=https://github.com/OWNER/REPOSITORY.git
#   - PAT はコマンドライン引数・環境変数に置かない（ほかのプロセスから見えるため）。
#     git へも標準入力（パイプ）で渡す
#   - PAT を画面に表示しない（エラーの表示にも含めない）
#   - PAT の保存先は ~/.git-credentials だけ。Claude からは、~/.claude/settings.json の
#     sandbox.credentials（Claude が実行するコマンド）と permissions.deny（Claude の読み取り機能）で
#     読めないようにしてある
#
# 値のチェックは New-SecureRoom.ps1 の Read-GitHubConf と同じ規則（変えるときは両方）。
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
trap 'on_error $LINENO' ERR

readonly CRED_FILE="$HOME/.git-credentials"
readonly PROJECTS_DIR="$HOME/projects"
# 認証用のユーザー名（git が PAT と組にして GitHub に送るもの）。
# GitHub は PAT だけでアカウントを見分けるので、空でなければ何でもよい。コミットの作者名（user.name）とは無関係。
readonly CRED_USERNAME='pat'

readonly RE_REPO_URL='^https://github\.com/[A-Za-z0-9-]+/[A-Za-z0-9._-]+\.git$'
readonly RE_PAT='^[A-Za-z0-9_]{20,255}$'
readonly RE_EMAIL='^[^[:space:]<>@]+@[^[:space:]<>@]+$'

usage() {
    cat <<'EOF'
使い方（通常は New-SecureRoom.ps1 が呼び出します）:
  bash provision-github.sh --phase credentials        設定を標準入力（base64）で受け取る
  bash provision-github.sh --phase clone <URL>
EOF
}

# パスワードの入力を求めて止まらないようにして git を実行する（PAT が違うときは、聞き返さずに失敗させる）
git_noprompt() {
    env -u GIT_ASKPASS -u SSH_ASKPASS GIT_TERMINAL_PROMPT=0 git -c core.askPass= "$@"
}

# リポジトリの URL（New-SecureRoom.ps1 が https://github.com/OWNER/REPOSITORY.git の形にそろえたもの）を確かめ、
# リポジトリ名を REPO_NAME に入れる
parse_repo_url() {
    local url=$1
    [[ $url =~ $RE_REPO_URL ]] || die "リポジトリの URL が正しくありません: $url" \
        "https://github.com/OWNER/REPOSITORY.git の形で指定してください。"
    REPO_NAME=${url##*/}
    REPO_NAME=${REPO_NAME%.git}
    [[ -n $REPO_NAME && $REPO_NAME != . && $REPO_NAME != .. ]] || die "リポジトリの名前が正しくありません: $url"
}

# -----------------------------------------------------------------------------
# --phase credentials
# -----------------------------------------------------------------------------

phase_credentials() {
    local payload line key value got mode
    local name='' email='' pat='' url=''
    local -A seen=()

    [[ ! -t 0 ]] || die "設定を標準入力で渡してください。" "このスクリプトは New-SecureRoom.ps1 から実行します。"
    command -v git > /dev/null || die "git が見つかりません。" \
        "provision-root.sh（root 用の設定）が先に完了している必要があります。"

    payload=$(base64 -d -i) || die "標準入力で受け取った設定を読めませんでした（base64 として正しくありません）。"
    # 一時ファイルを作らないよう、ヒアストリングではなくプロセス置換（パイプ）で 1 行ずつ読む
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        # 行の中身は PAT を含むことがあるので、エラーの表示に含めない
        [[ $line == *=* ]] || die "標準入力で受け取った設定の形式が正しくありません。"
        key=${line%%=*}
        value=${line#*=}
        [[ -z ${seen[$key]:-} ]] || die "標準入力で受け取った設定に、同じ項目が 2 回あります: $key"
        seen[$key]=1
        case $key in
            user_name) name=$value ;;
            user_email) email=$value ;;
            pat) pat=$value ;;
            repo_url) url=$value ;;
            *) die "標準入力で受け取った設定に、知らない項目があります: $key" ;;
        esac
    done < <(printf '%s\n' "$payload")
    payload=''

    [[ -n $name ]] || die "user_name が空です。"
    if [[ $name =~ [[:cntrl:]] || $name == *[\<\>]* ]]; then
        die "user_name に使えない文字が含まれています（制御文字と < > は使えません）。"
    fi
    if [[ ! $email =~ $RE_EMAIL || $email =~ [[:cntrl:]] ]]; then
        die "user_email がメールアドレスの形になっていません: $email"
    fi
    [[ $pat =~ $RE_PAT ]] || die "pat が PAT の形になっていません（内容は表示しません）。"
    parse_repo_url "$url"

    step "1/2 git の設定をします（コミットの作者と、認証情報の保存方法）"
    git config --global user.name "$name"
    git config --global user.email "$email"
    git config --global --replace-all credential.helper store
    git config --global credential.useHttpPath true
    info "user.name             : $name"
    info "user.email            : $email"
    info "credential.helper     : store（~/.git-credentials に保存）"
    info "credential.useHttpPath: true（リポジトリごとに認証情報を分ける）"
    ok "git の設定をしました（~/.gitconfig）。"

    step "2/2 PAT を ~/.git-credentials に保存します（あなただけが読めるモード 600）"
    umask 077
    [[ ! -L $CRED_FILE ]] || die "$CRED_FILE がシンボリックリンクになっています。" \
        "PAT を思わぬ場所に書き込まないよう、ここで停止します。中身を確認して削除してから、もう一度実行してください。"
    [[ ! -e $CRED_FILE || -f $CRED_FILE ]] || die "$CRED_FILE が通常のファイルではありません。"
    touch -- "$CRED_FILE"
    chmod 600 -- "$CRED_FILE"
    # このリポジトリ用の古い認証情報を消してから保存する
    # （古いものがファイルの前のほうに残っていると、そちらが先に見つかって使われてしまうため）
    printf 'url=%s\n\n' "$url" | git credential reject
    printf 'url=%s\nusername=%s\npassword=%s\n\n' "$url" "$CRED_USERNAME" "$pat" | git credential approve

    # 保存した PAT を git が取り出せることを確かめる（通信はしない。PAT は変数の中で比べるだけで表示しない）
    got=$(printf 'url=%s\n\n' "$url" | git_noprompt credential fill 2> /dev/null) || got=''
    [[ $'\n'$got$'\n' == *$'\n'"password=$pat"$'\n'* ]] || die "保存した PAT を git が取り出せませんでした。" \
        "~/.gitconfig の credential.helper と、~/.git-credentials の中身を確認してください。"
    got=''
    pat=''
    mode=$(stat -c %a -- "$CRED_FILE")
    [[ $mode == 600 ]] || die "$CRED_FILE のモードが $mode になっています（600 のはずです）。" \
        "chmod 600 ~/.git-credentials を実行してから、もう一度実行してください。"
    ok "保存しました（リポジトリ $url 用）。"
}

# -----------------------------------------------------------------------------
# --phase clone
# -----------------------------------------------------------------------------

phase_clone() {
    local url=$1 dest origin
    command -v git > /dev/null || die "git が見つかりません。"
    parse_repo_url "$url"
    dest="$PROJECTS_DIR/$REPO_NAME"
    [[ -d $PROJECTS_DIR ]] || die "$PROJECTS_DIR がありません。" \
        "provision-user.sh（一般ユーザー用の設定）が先に完了している必要があります。"

    step "1/3 $url を ~/projects/$REPO_NAME にクローンします"
    if [[ -e $dest || -L $dest ]]; then
        # すでにあるリポジトリの中で git を動かさず、設定ファイルを直接読んで origin を確かめる
        origin=''
        if [[ -f $dest/.git/config ]]; then
            origin=$(git config --file "$dest/.git/config" --get remote.origin.url 2> /dev/null) || origin=''
        fi
        [[ $origin == "$url" ]] || die "~/projects/$REPO_NAME がすでにあり、$url のクローンではありません。" \
            "安全のため自動では消しません。中身を確認して、別の場所へ移すか削除してから、もう一度実行してください。"
        ok "すでにクローン済みです（変更なし）。"
    else
        git_noprompt clone -- "$url" "$dest" || die "リポジトリをクローンできませんでした。" \
            "次の点を確認してください:" \
            "  - room-github.conf の repo_url が正しいか" \
            "  - PAT が有効か（有効期限が切れていないか）" \
            "  - PAT がこのリポジトリにアクセスできるか（fine-grained PAT なら Repository access と Contents の権限）" \
            "直したら、room-github.conf を直して -Resume を付けて実行してください。"
        ok "クローンしました（~/projects/$REPO_NAME）。"
    fi

    step "2/3 PAT で push できるか（書き込み権限があるか）を確かめます（--dry-run なので何も送りません）"
    check_push "$dest"

    step "3/3 リポジトリに Claude Code の設定ファイルが含まれていないか確認します"
    check_claude_files "$dest"
}

check_push() {
    local dest=$1 out l
    if ! git -C "$dest" rev-parse --verify -q HEAD > /dev/null; then
        info "空のリポジトリ（コミットが無い）なので、確認を飛ばします。"
        return 0
    fi
    if out=$(git_noprompt -C "$dest" push --dry-run origin HEAD 2>&1); then
        ok "PAT で push できることを確認しました。"
        return 0
    fi
    warn "PAT で push できることを確認できませんでした（部屋の設定は続けます）。git の表示:"
    while IFS= read -r l; do printf '          %s\n' "$l" >&2; done < <(printf '%s\n' "$out")
    warn "PAT の権限（fine-grained PAT なら Contents が Read and write）と有効期限を確認してください。"
    warn "PAT を直したら、room-github.conf を直して -Resume を付けて実行してください。"
}

check_claude_files() {
    local dest=$1 f
    local -a found=()
    for f in .claude .mcp.json; do
        if [[ -e $dest/$f || -L $dest/$f ]]; then found+=("$f"); fi
    done
    if (( ${#found[@]} == 0 )); then
        ok "含まれていません。"
        return 0
    fi
    warn "このリポジトリには Claude Code の設定（${found[*]}）が含まれています。"
    warn "Claude Code を起動する前に中身を確認してください。プロジェクトの設定はこの部屋の設定より優先されるため、"
    warn "サンドボックスを弱める設定（\"sandbox\": {\"enabled\": false} など）が入っていると守りが外れます（README 6.4）。"
}

# -----------------------------------------------------------------------------

main() {
    local phase='' url=''
    while (( $# )); do
        case $1 in
            --phase)
                (( $# >= 2 )) || die "--phase の後に値を指定してください。" "$(usage)"
                phase=$2; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            -*) die "知らないオプションです: $1" "$(usage)" ;;
            *)
                [[ -z $url ]] || die "引数が多すぎます: $1" "$(usage)"
                url=$1; shift ;;
        esac
    done

    require_not_root
    load_room_conf "$SCRIPT_DIR/room.conf"
    [[ $(id -un) == "$CONF_LINUX_USER" ]] || die \
        "このスクリプトは room.conf の linux_user（$CONF_LINUX_USER）として実行してください（今は $(id -un)）。"

    case $phase in
        credentials)
            [[ -z $url ]] || die "--phase credentials では URL を引数に指定しません（標準入力で渡します）。"
            phase_credentials ;;
        clone)
            [[ -n $url ]] || die "--phase clone ではリポジトリの URL を指定してください。" "$(usage)"
            phase_clone "$url" ;;
        *) die "--phase credentials または --phase clone を指定してください。" "$(usage)" ;;
    esac
}

main "$@"
