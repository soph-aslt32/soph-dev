#!/usr/bin/env bash
# =============================================================================
# dcs-github — GitHub モードの PAT の保存と、リポジトリの clone（DESIGN.md の 7.1。D10・D11）
#
# イメージの中の /usr/local/bin/dcs-github（root 所有）。Windows 側の lib/Env.ps1 の Invoke-GitHubSetup が、
# コンテナのユーザー（dev）で呼びます。従来の provision-github.sh の credentials と clone を 1 つにしたもの。
# 引数は取りません。設定は、次の 4 行を base64 にしたものを、標準入力で受け取ります（ディスクに一時ファイルを作らない）。
#   user_name=... / user_email=... / pat=... / repo_url=https://github.com/OWNER/REPOSITORY.git
# PAT は、コマンドライン引数・環境変数に置かず、画面（エラーの表示を含む）に出しません。git へも標準入力で渡します。
# 保存先は /home/dev/.dcs-git/credentials（ボリューム dcs-<名前>-git。モード 600）。/etc/gitconfig の credential helper が読みます。
# 値の規則は、Windows 側の lib/Validation.ps1 と同じ（変えるときは両方）。
# 表示はすべて標準エラー出力に出します（Windows 側で、clone の進み具合をそのまま見せるため）。
# =============================================================================
set -Eeuo pipefail
exec 1>&2

readonly CRED_FILE=/home/dev/.dcs-git/credentials
# 作業フォルダ（/workspaces/<リポジトリ名>）。注文書の containerEnv が知らせる（D49）
DEST=${DCS_WORKSPACE:-}
# 認証用のユーザー名（git が PAT と組にして GitHub に送るもの）。GitHub は PAT だけでアカウントを見分けるので、空でなければ何でもよい
readonly CRED_USERNAME=pat
readonly RE_REPO_URL='^https://github\.com/[A-Za-z0-9-]+/[A-Za-z0-9._-]+\.git$'
readonly RE_PAT='^[A-Za-z0-9_]{20,255}$'
readonly RE_EMAIL='^[^[:space:]<>@]+@[^[:space:]<>@]+$'
readonly REDO_HINT='直したら、Windows 側で setup-wizard.cmd を起動し、「開発環境の設定をやり直す」で GitHub の設定を入力し直してください。'

# 色（端末に出すとき、または Windows 側が画面にそのまま出すときに付ける DCS_COLOR=1 のときだけ。ウィザードの色にそろえる）
if [[ -t 1 || ${DCS_COLOR:-} == 1 ]]; then
    readonly C_STEP=$'\e[96m' C_OK=$'\e[92m' C_NOTE=$'\e[93m' C_ERR=$'\e[91m' C_OFF=$'\e[0m'
else
    readonly C_STEP='' C_OK='' C_NOTE='' C_ERR='' C_OFF=''
fi
step() { printf '\n%s==> %s%s\n' "$C_STEP" "$1" "$C_OFF"; }
ok() { printf '  %s[完了] %s%s\n' "$C_OK" "$1" "$C_OFF"; }
info() { printf '  %s\n' "$1"; }
warn() { printf '  %s[注意] %s%s\n' "$C_NOTE" "$1" "$C_OFF"; }
die() {
    local h
    printf '%s[失敗] %s%s\n' "$C_ERR" "$1" "$C_OFF"
    shift
    for h in "$@"; do printf '  %s\n' "$h"; done
    exit 1
}
trap 'die "予期しないエラーです（$LINENO 行目）。"' ERR

# パスワードの入力を求めて止まらないようにして git を実行する（PAT が違うときは、聞き返さずに失敗させる）
git_noprompt() {
    env -u GIT_ASKPASS -u SSH_ASKPASS GIT_TERMINAL_PROMPT=0 git -c core.askPass= "$@"
}

# 1. 標準入力の設定を読み、値を確かめる（name・email・pat・url に入れる）
read_settings() {
    local payload line key value repo
    local -A seen=()
    [[ ! -t 0 ]] || die '設定を標準入力で渡してください。' 'このコマンドは、Windows 側のツールから実行します。'
    payload=$(base64 -d -i) || die '標準入力で受け取った設定を読めませんでした（base64 として正しくありません）。'
    # 一時ファイルを作らないよう、プロセス置換（パイプ）で 1 行ずつ読む
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        # 行の中身は PAT を含むことがあるので、エラーの表示に含めない
        [[ $line == *=* ]] || die '標準入力で受け取った設定の形式が正しくありません。'
        key=${line%%=*}
        value=${line#*=}
        [[ -z ${seen[$key]:-} ]] || die "標準入力で受け取った設定に、同じ項目が 2 回あります: ${key//[[:cntrl:]]/?}"
        seen[$key]=1
        case $key in
            user_name) name=$value ;;
            user_email) email=$value ;;
            pat) pat=$value ;;
            repo_url) url=$value ;;
            *) die "標準入力で受け取った設定に、知らない項目があります: ${key//[[:cntrl:]]/?}" ;;
        esac
    done < <(printf '%s\n' "$payload")

    [[ -n $name ]] || die 'user_name が空です。'
    if [[ $name =~ [[:cntrl:]] || $name == *[\<\>]* ]]; then
        die 'user_name に使えない文字が含まれています（制御文字と < > は使えません）。'
    fi
    if [[ ! $email =~ $RE_EMAIL || $email =~ [[:cntrl:]] ]]; then
        die "user_email がメールアドレスの形になっていません: ${email//[[:cntrl:]]/?}"
    fi
    [[ $pat =~ $RE_PAT ]] || die 'pat が PAT の形になっていません（内容は表示しません）。'
    [[ $url =~ $RE_REPO_URL ]] || die "リポジトリの URL が正しくありません: ${url//[[:cntrl:]]/?}" \
        'https://github.com/OWNER/REPOSITORY.git の形で指定してください。'
    repo=${url##*/}
    repo=${repo%.git}
    [[ -n $repo && $repo != . && $repo != .. ]] || die "リポジトリの名前が正しくありません: $url"
}

# 2. PAT を保存して、git が取り出せることを確かめる（通信はしない。PAT は変数の中で比べるだけで表示しない）
save_pat() {
    local got mode
    step "1/5 PAT を保存します（$CRED_FILE。あなただけが読めるモード 600）"
    umask 077
    [[ -d ${CRED_FILE%/*} && ! -L ${CRED_FILE%/*} ]] || die "${CRED_FILE%/*} がありません（ボリュームがつながっていない見込みです）。"
    [[ ! -L $CRED_FILE ]] || die "$CRED_FILE がシンボリックリンクになっています。" \
        'PAT を思わぬ場所に書き込まないよう、ここで止めます。中身を確かめて消してから、もう一度実行してください。'
    [[ ! -e $CRED_FILE || -f $CRED_FILE ]] || die "$CRED_FILE が通常のファイルではありません。"
    touch -- "$CRED_FILE"
    chmod 600 -- "$CRED_FILE"
    # このリポジトリ用の古い認証情報を消してから保存する（古いものが前に残っていると、そちらが先に使われるため）
    printf 'url=%s\n\n' "$url" | git credential reject
    printf 'url=%s\nusername=%s\npassword=%s\n\n' "$url" "$CRED_USERNAME" "$pat" | git credential approve
    got=$(printf 'url=%s\n\n' "$url" | git_noprompt credential fill 2> /dev/null) || got=''
    [[ $'\n'$got$'\n' == *$'\n'"password=$pat"$'\n'* ]] || die '保存した PAT を git が取り出せませんでした。' \
        '/etc/gitconfig の credential helper と、コンテナのボリューム（~/.dcs-git）を確かめてください。'
    mode=$(stat -c %a -- "$CRED_FILE")
    [[ $mode == 600 ]] || die "$CRED_FILE のモードが $mode になっています（600 のはずです）。"
    ok "保存しました（リポジトリ $url 用）。"
}

# 3. 作業フォルダが空なら clone する。空でなければ、同じリポジトリの clone であることだけを確かめる（cloned に 1 か 0）
clone_repo() {
    local origin=''
    step "2/5 $url を $DEST に clone します"
    if [[ -z $(ls -A -- "$DEST") ]]; then
        git_noprompt clone -- "$url" "$DEST" || die 'リポジトリを clone できませんでした。' \
            '次の点を確かめてください:' \
            '  - 入力した repo_url が正しいか' \
            '  - PAT が有効か（有効期限が切れていないか）' \
            '  - PAT がこのリポジトリに届くか（fine-grained PAT なら Repository access と Contents の権限）' \
            "$REDO_HINT"
        cloned=1
        ok "clone しました（$DEST）。"
        return 0
    fi
    # すでにあるリポジトリの中で git を動かさず、設定ファイルを直接読んで origin を確かめる
    if [[ -f $DEST/.git/config && ! -L $DEST/.git/config ]]; then
        origin=$(git config --file "$DEST/.git/config" --get remote.origin.url 2> /dev/null) || origin=''
    fi
    [[ $origin == "$url" ]] || die "$DEST は空でなく、$url の clone でもありません。" \
        '安全のため、自動では消しません。中身を確かめて、別の場所へ移すか消してから、もう一度実行してください。'
    cloned=0
    ok 'すでに clone してあります（変更なし）。'
}

# 4. コミットの作者を、このリポジトリの設定に書く（~/.gitconfig は作らない。あれば VS Code の受け渡しの印になるため）
set_author() {
    step '3/5 コミットの作者を設定します（このリポジトリの .git/config）'
    git config --file "$DEST/.git/config" user.name "$name"
    git config --file "$DEST/.git/config" user.email "$email"
    info "user.name : $name"
    info "user.email: $email"
    ok '設定しました。'
}

# 5. 新しく clone したときだけ、PAT で push できるかを確かめる（--dry-run なので何も送らない。確かめられなくても続ける）
check_push() {
    local out l
    step '4/5 PAT で push できるか（書き込み権限があるか）を確かめます（--dry-run なので何も送りません）'
    if (( ! cloned )); then
        info 'すでにあった clone なので、確かめません（そのリポジトリの git の設定を、PAT を渡す操作で動かさないため）。'
        return 0
    fi
    if ! git -C "$DEST" rev-parse --verify -q HEAD > /dev/null; then
        info '空のリポジトリ（コミットが無い）なので、確かめを飛ばします。'
        return 0
    fi
    if out=$(git_noprompt -C "$DEST" push --dry-run origin HEAD 2>&1); then
        ok 'PAT で push できることを確かめました。'
        return 0
    fi
    warn 'PAT で push できることを確かめられませんでした（設定は続けます）。git の表示:'
    while IFS= read -r l; do printf '          %s\n' "${l//[[:cntrl:]]/?}"; done < <(printf '%s\n' "$out")
    warn 'PAT の権限（fine-grained PAT なら Contents が Read and write）と有効期限を確かめてください。'
    warn "$REDO_HINT"
}

# 6. リポジトリに Claude Code の設定が入っていれば知らせる
check_claude_files() {
    local f
    local -a found=()
    step '5/5 リポジトリに Claude Code の設定が入っていないかを確かめます'
    for f in .claude .mcp.json; do
        if [[ -e $DEST/$f || -L $DEST/$f ]]; then found+=("$f"); fi
    done
    if (( ${#found[@]} == 0 )); then
        ok '入っていません。'
        return 0
    fi
    warn "このリポジトリには Claude Code の設定（${found[*]}）が入っています。"
    warn 'Claude Code を起動する前に、中身を確かめてください（hooks や MCP サーバーの設定は、起動したときに効きます）。'
}

main() {
    local name='' email='' pat='' url='' cloned=0
    (( $# == 0 )) || { echo '使い方: dcs-github（設定は標準入力で渡します。引数は取りません）'; exit 2; }
    [[ $EUID != 0 ]] || die 'root ではなく、コンテナのユーザー（dev）で実行してください。'
    # カレントフォルダの .git の設定を git に使わせないため、/ で動かす（このスクリプトで使うパスは、すべて絶対パス）
    [[ $DEST =~ ^/workspaces/[A-Za-z0-9._-]+$ && $DEST != /workspaces/. && $DEST != /workspaces/.. && -d $DEST && ! -L $DEST ]] ||
        die "作業フォルダ（DCS_WORKSPACE=${DEST//[[:cntrl:]]/?}）が正しくありません。" 'このコマンドは、開発環境のコンテナの中で、Windows 側のツールから実行します。'
    cd /
    read_settings
    save_pat
    clone_repo
    set_author
    check_push
    check_claude_files
}

main "$@"
