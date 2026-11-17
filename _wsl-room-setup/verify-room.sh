#!/usr/bin/env bash
# =============================================================================
# verify-room.sh — 部屋が仕様どおりの安全な状態になっているかを自動で検証します
#
# 使い方（部屋の中で）:
#   bash /usr/local/lib/wsl-room-setup/verify-room.sh               一般ユーザーとして行う検査
#   root の権限が必要な検査は、部屋のユーザーは sudo を使えないので、Windows の PowerShell から:
#     wsl -d <部屋の名前> -u root --cd / --exec bash /usr/local/lib/wsl-room-setup/verify-room.sh --root
#
# New-SecureRoom.ps1 は両方を自動で実行します。
# 各項目を [PASS] / [FAIL] / [SKIP] / [WARN] で表示し、FAIL が 1 つでもあれば終了コード 1 で終わります。
# [WARN] は失敗ではなく、部屋の設定では止められないが知っておいてほしいこと（WSL 全体の設定で決まるものなど）です。
#
# 項目番号:
#   01〜14  申し送り書 第 6 章の表（09 と 12 は欠番。09 の sudo の設定は R1 で確かめ、
#           12 の claude doctor はログインが必要なため手動で確認する）
#   E1〜E6  追加の申し送り EX1（重要ファイルの所有者・権限、wsl.conf と fstab の内容）
#   E7      delzonei（/usr/local/bin/delzonei）の所有者・権限・内容
#   E8      部屋のユーザーが管理者のグループ（sudo など）に入っていない（部屋の中で root になれない）
#   E9      ホスト名と /etc/hosts に、Windows の情報（コンピューター名、Windows の hosts ファイルの項目）が無い
#   A1〜A4  apt（CVE-2026-109518 への対策）: 取得先が https、apt が修正版、Apache が入っていない、
#           適用していない更新（A4 は警告。段階的配信で保留中のものは数えない）
#   G1〜G2  GitHub の PAT（room-github.conf で設定したもの）が保存先以外に漏れていないこと
#   W1〜W2  （警告）WSLg、/mnt/wsl など、WSL の仕組みとして部屋から Windows やほかのディストリに届く窓口
#   W3      （警告）初回起動時に WSL が作ったドライブ用のフォルダ（/mnt/d など）の残りと、/mnt/c の権限
#
# 期待値（Linux ユーザー名、Windows ユーザー名、許可ドメイン）は、このスクリプトと同じフォルダの
# room.conf から読みます（部屋の中では root 所有なので、一般ユーザーや Claude は書き換えられません）。
# 部屋の名前（E4・E9）は、WSL が設定する環境変数 WSL_DISTRO_NAME から読みます。
#   R1      root でしか確認できない sudo の権限（パスワードが必要なものも含めて、一つも無いこと）
#
# Claude Code 自体は起動しません。
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
trap 'on_error $LINENO' ERR

readonly INSTALL_DIR=/usr/local/lib/wsl-room-setup

PASS=0 FAIL=0 SKIP=0 WARN=0
DETAILS=()
U='' W='' MP='' FSTAB_LINE='' ROOM=''

usage() {
    echo '使い方: bash verify-room.sh [--root]'
}

# 結果の下に表示する説明を追加する
detail() { DETAILS+=("$*"); }

# run_check <番号> <見出し> <関数名>
# 関数は 0=PASS、1=FAIL、2=SKIP、3=WARN を返す。
run_check() {
    local id=$1 title=$2 fn=$3 rc=0 d
    DETAILS=()
    "$fn" || rc=$?
    case $rc in
        0) PASS=$((PASS + 1)); printf '%s[PASS]%s %-3s %s\n' "$C_GREEN" "$C_RESET" "$id" "$title" ;;
        2) SKIP=$((SKIP + 1)); printf '%s[SKIP]%s %-3s %s\n' "$C_YELLOW" "$C_RESET" "$id" "$title" ;;
        3) WARN=$((WARN + 1)); printf '%s[WARN]%s %-3s %s\n' "$C_YELLOW" "$C_RESET" "$id" "$title" ;;
        *) FAIL=$((FAIL + 1)); printf '%s[FAIL]%s %-3s %s\n' "$C_RED" "$C_RESET" "$id" "$title" ;;
    esac
    for d in "${DETAILS[@]}"; do printf '           %s\n' "$d"; done
}

# 所有者が root で、root 以外に書き込み権限が無いことを確認する（問題があれば detail に書いて 1 を返す）
check_root_only_writable() {
    local p=$1 uid mode lsout bad=0
    if [[ -L $p ]]; then detail "$p がシンボリックリンクになっています（想定外）。"; return 1; fi
    if [[ ! -e $p ]]; then detail "$p がありません。"; return 1; fi
    uid=$(stat -c %u -- "$p")
    mode=$(stat -c %a -- "$p")
    if [[ $uid != 0 ]]; then
        detail "$p の所有者が root ではありません（$(stat -c %U -- "$p")）。"
        bad=1
    fi
    if (( (8#$mode & 8#022) != 0 )); then
        detail "$p に root 以外の書き込み権限があります（モード $mode）。"
        bad=1
    fi
    lsout=$(ls -ld -- "$p")
    if [[ ${lsout%% *} == *+ ]]; then
        detail "$p に ACL（追加のアクセス権）が設定されています。"
        bad=1
    fi
    return $bad
}

# =============================================================================
# 一般ユーザーとして行う検査
# =============================================================================

check_01() {
    if [[ -e /mnt/c/Windows ]] || mountpoint -q /mnt/c; then
        detail "C ドライブ全体（/mnt/c）が部屋から見えています。"
        detail "→ /etc/wsl.conf の [automount] enabled=false を確認し、部屋を再起動してください。"
        return 1
    fi
}

check_02() {
    local src mp type opts rest found=0 bad=0
    # 書き込み可能な Windows への窓が無いことを、カーネルのマウント一覧で確認する。
    # /usr/lib/wsl は GPU ドライバーの共有（読み取り専用）なので除外する（9 章）。
    while read -r src mp type opts rest; do
        case $type in drvfs|9p|virtiofs) ;; *) continue ;; esac
        case $mp in /usr/lib/wsl|/usr/lib/wsl/*) continue ;; esac
        if [[ $mp == "$MP" && ,$opts, == *,ro,* ]]; then
            found=$((found + 1))
        elif [[ $mp == "$MP" ]]; then
            detail "$mp が書き込み可能な状態でマウントされています（オプション: $opts）。"
            bad=1
        else
            detail "想定外の Windows 由来のマウント: $mp（$src、種類 $type）"
            bad=1
        fi
    done < /proc/self/mounts
    if (( bad )); then
        detail "→ 公開してよいのは $MP（読み取り専用）だけです。/etc/fstab を確認してください。"
        return 1
    fi
    if (( found != 1 )); then
        detail "$MP がマウントされていません。VS Code の接続に必要です。"
        detail "→ /etc/fstab の設定と、部屋の起動時に自動でマウントされているかを確認してください。"
        return 1
    fi
}

check_03() {
    local dir="/mnt/c/Users/$W" e
    local -a entries=() names=()
    if [[ ! -d $dir ]]; then detail "$dir がありません。"; return 1; fi
    shopt -s dotglob nullglob
    entries=("$dir"/*)
    shopt -u dotglob nullglob
    for e in "${entries[@]}"; do names+=("${e##*/}"); done
    if (( ${#names[@]} == 1 )) && [[ ${names[0]} == .vscode ]]; then
        return 0
    fi
    detail "$dir の中身: ${names[*]:-（空）}"
    detail "→ .vscode だけが見えるはずです。"
    return 1
}

check_04() {
    local probe="$MP/.wsl-room-probe-$$" err
    if err=$(LC_ALL=C touch -- "$probe" 2>&1); then
        rm -f -- "$probe"
        detail "$MP に書き込めてしまいました。部屋から Windows 側のファイルを改ざんできる状態です。"
        detail "→ /etc/fstab の該当行に ro が付いているか確認してください。"
        return 1
    fi
    if [[ $err == *"Read-only file system"* ]]; then
        return 0
    fi
    detail "書き込みは失敗しましたが、理由が想定（Read-only file system）と違います: $err"
    detail "→ $MP がマウントされていない可能性があります（02 の結果も確認してください）。"
    return 1
}

check_05() {
    local expected="/mnt/c/Users/$W/.vscode/extensions" out
    out=$(wslpath -u 'C:\Users\'"$W"'\.vscode\extensions' 2>&1) || true
    if [[ $out == "$expected" ]]; then
        return 0
    fi
    detail "変換結果: ${out:-（なし）}（期待: $expected）"
    detail "→ 一致しないと VS Code の接続が「WSL Daemon exited with code 0」で失敗します。"
    return 1
}

check_06() {
    # 注意: /proc/sys/fs/binfmt_misc/WSLInterop は WSL2 では仮想マシン全体で 1 つ登録されるもので
    # （WSL 公式の技術資料 wsl.dev「Interop」）、部屋ごとの [interop] enabled=false を反映しない。
    # そのため、ここでは判定に使わない。
    local c bad=0
    for c in cmd.exe wsl.exe powershell.exe explorer.exe; do
        if command -v "$c" > /dev/null 2>&1; then
            detail "$c が見つかりました: $(command -v "$c")"
            bad=1
        fi
    done
    if [[ :$PATH: == *:/mnt/* ]]; then
        detail "PATH に Windows 側のフォルダ（/mnt/...）が含まれています: $PATH"
        bad=1
    fi
    if (( bad )); then
        detail "→ 部屋の中から wsl.exe を呼べると、パスワードなしで root になれてしまいます。"
        detail "→ /etc/wsl.conf の [interop] enabled=false と appendWindowsPath=false を確認し、部屋を再起動してください。"
        return 1
    fi
}

check_07() {
    local me uid0
    me=$(id -un)
    if [[ $me != "$U" ]]; then
        detail "部屋に入ったときのユーザー: $me（期待: $U）"
        detail "→ /etc/wsl.conf の [user] default= を確認してください。"
        return 1
    fi
    uid0=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd | paste -sd ' ')
    if [[ $uid0 != root ]]; then
        detail "root と同じ権限（UID 0）のアカウントが root 以外にもあります: $uid0"
        return 1
    fi
}

check_08() {
    sudo -k 2> /dev/null || true
    # sudo -l（権限一覧の表示）は、既定ではパスワード不要の設定が 1 つでもあるとパスワードなしで通る。
    # パスワードが必要な権限は、一般ユーザーからは見分けられないので R1 で確かめる
    if sudo -n -l > /dev/null 2>&1; then
        detail "パスワードなしで sudo -l を実行できました。NOPASSWD の設定がある可能性があります。"
        detail "→ Claude が root になって、ここで検査している設定を書き換えられる状態です。R1 の結果も確認してください。"
        return 1
    fi
}

check_10() {
    local err c bad=0
    for c in bwrap socat; do
        if ! command -v "$c" > /dev/null 2>&1; then
            detail "$c がインストールされていません。"
            bad=1
        fi
    done
    (( bad )) && return 1
    if ! err=$(bwrap --ro-bind / / --dev /dev --unshare-all true 2>&1); then
        detail "bwrap の試験実行に失敗しました: $err"
        detail "→ README のトラブルシューティング（AppArmor）を参照してください。"
        return 1
    fi
}

check_11() {
    local expected="$HOME/.local/bin/claude" resolved
    if [[ ! -x $expected ]]; then
        detail "$expected がありません（Claude Code がインストールされていません）。"
        return 1
    fi
    # ターミナルで claude と打ったときに実際に使われるものを確かめる。
    # 部屋のターミナルと同じ状態にするため、ログインシェルかつ対話シェルとして起動する
    # （~/.profile と ~/.bashrc の両方が読み込まれる）。
    # 対話シェルは端末につながっていると端末の操作権を取ろうとして止まってしまう（timeout も
    # 巻き添えで止まる）ため、setsid で端末から切り離して起動する。
    resolved=$(timeout -k 5 20 setsid -w env -i HOME="$HOME" USER="$(id -un)" \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        bash -lic 'command -v claude' < /dev/null 2> /dev/null | tail -n 1) || true
    if [[ $resolved != "$expected" ]]; then
        detail "ターミナルで claude と打ったときに使われるもの: ${resolved:-（見つからない）}（期待: $expected）"
        detail "→ ~/.bashrc に $PATH_LINE があるか確認してください。"
        return 1
    fi
}

# Claude Code の設定。守りの設定（サンドボックスと権限ルール）は managed settings（root 所有）に置き、Claude Code は
# それをユーザー設定・プロジェクト設定より優先する。ただし一覧の形の設定は、すべてのファイルの内容が足し合わされ、
# permissions.defaultMode はユーザー設定で決まるので、それらは ~/.claude/settings.json も確かめる。
check_13() {
    local m=$MANAGED_SETTINGS f="$HOME/.claude/settings.json" owner domains_json rule p bad=0
    if ! command -v jq > /dev/null 2>&1; then detail "jq が見つからないため検査できません。"; return 1; fi

    # want <ファイル> <説明> <jq の条件式>
    want() {
        if ! jq -e "$3" "$1" > /dev/null 2>&1; then
            detail "NG: ${1/#"$HOME"/\~} の $2"
            bad=1
        fi
    }

    # --- managed settings（templates/managed-settings.json.tmpl と同じ内容のはず） ---
    check_root_only_writable "${m%/*}" || bad=1
    if ! check_root_only_writable "$m"; then
        bad=1
    elif ! jq -e . "$m" > /dev/null 2>&1; then
        detail "$m が JSON として読めません（書き方の誤り）。"
        bad=1
    else
        want "$m" 'sandbox.enabled が true' '.sandbox.enabled == true'
        want "$m" 'sandbox.failIfUnavailable が true' '.sandbox.failIfUnavailable == true'
        want "$m" 'sandbox.allowUnsandboxedCommands が false' '.sandbox.allowUnsandboxedCommands == false'
        # 次の 3 つは既定値も false だが、managed で false に固定して、ほかの設定ファイルから有効にできないようにしている
        want "$m" 'sandbox.enableWeakerNestedSandbox が false' '.sandbox.enableWeakerNestedSandbox == false'
        want "$m" 'sandbox.filesystem.disabled が false' '.sandbox.filesystem.disabled == false'
        want "$m" 'sandbox.network.allowAllUnixSockets が false' '.sandbox.network.allowAllUnixSockets == false'
        want "$m" 'sandbox.excludedCommands が空' '((.sandbox.excludedCommands // []) | length) == 0'
        want "$m" 'sandbox.filesystem.denyRead に "/mnt" がある' '(.sandbox.filesystem.denyRead // []) | any(.[]; . == "/mnt")'
        # permissions.blockReadsOutsideWorkingDirectories は設定しない（README「このツールの考え方」・6.4）。
        # 部屋の中では作業フォルダの外も Claude に読ませる設計で、読ませないものは下の Read(...) で個別に禁止する。
        # true にすると、サンドボックスの中のコマンドもホームフォルダの中を読めなくなり、uv や Rust を使えなくなる見込み。
        # sandbox.credentials はサンドボックスの中のコマンドにしか効かないので、Claude のファイル読み取り機能は Read(...) で止める。
        # Edit(...) は、Claude のファイル編集機能（Edit・Write など）で書き換えさせないもの。どれも、サンドボックスの外で
        # 自動で実行されるか（シェルの起動、git、VS Code、Claude Code 自身）、LocalGit の部屋の bare リポジトリ（~/repos）。
        # ~/**/.git と ~/**/.claude/settings*.json は、ホームフォルダの下のどこにあるものも（~/.git、~/projects/<名前>/.git など）。
        # templates/managed-settings.json.tmpl の permissions.deny と同じ一覧（変えるときは両方）
        for rule in 'Read(//mnt/**)' 'Read(~/.git-credentials)' 'Read(~/.claude/.credentials.json)' \
            'Read(~/.ssh/**)' 'Read(~/.aws/**)' \
            'Edit(~/repos/**)' \
            'Edit(~/.bash*)' 'Edit(~/.profile)' 'Edit(~/.gitconfig)' 'Edit(~/**/.git)' 'Edit(~/**/.git/**)' \
            'Edit(~/.config/**)' \
            'Edit(~/.local/**)' 'Edit(~/.cargo/**)' 'Edit(~/.rustup/**)' 'Edit(~/.vscode-server/**)' \
            'Edit(~/.ssh/**)' 'Edit(~/.npmrc)' \
            'Edit(~/.claude/settings.json)' 'Edit(~/**/.claude/settings.json)' 'Edit(~/**/.claude/settings.local.json)' \
            'Edit(~/.claude/statusline.sh)' 'Edit(~/.claude.json)' \
            'Edit(~/.claude/plugins/**)' 'Edit(~/.claude/dev-mods/**)'; do
            if ! jq -e --arg r "$rule" '(.permissions.deny // []) | any(.[]; . == $r)' "$m" > /dev/null 2>&1; then
                detail "NG: $m の permissions.deny に \"$rule\" がない"
                bad=1
            fi
        done
        # 設定ファイルに書かれた文字列のまま比べるので、~ は展開しない
        # shellcheck disable=SC2088
        for p in '~/.ssh' '~/.aws' '~/.git-credentials' '~/.claude/.credentials.json'; do
            if ! jq -e --arg p "$p" '(.sandbox.credentials.files // []) | any(.[]; .path == $p and .mode == "deny")' "$m" > /dev/null 2>&1; then
                detail "NG: $m の sandbox.credentials.files で $p が deny になっていない"
                bad=1
            fi
        done
        domains_json=$(jq -nc '$ARGS.positional' --args "${CONF_ALLOWED_DOMAINS[@]}")
        if ! jq -e --argjson want "$domains_json" '.sandbox.network.allowedDomains == $want' "$m" > /dev/null 2>&1; then
            detail "NG: $m の sandbox.network.allowedDomains が room.conf の allowed_domains と一致しない"
            detail "    room.conf: ${CONF_ALLOWED_DOMAINS[*]:-（なし）}"
            detail "    実際    : $(jq -c '.sandbox.network.allowedDomains' "$m" 2> /dev/null)"
            bad=1
        fi
    fi

    # --- ~/.claude/settings.json（managed では止められない、守りを弱める設定が無いこと） ---
    # 通信を許可するドメインの追加（sandbox.network.allowedDomains）は、ここやプロジェクトの設定で行ってよい（README 6.8）
    if [[ ! -f $f ]]; then
        detail "$f がありません。"
        bad=1
    else
        owner=$(stat -c %U -- "$f")
        if [[ $owner != "$U" ]]; then
            detail "$f の所有者が $owner になっています（期待: $U）。"
            bad=1
        fi
        if ! jq -e . "$f" > /dev/null 2>&1; then
            detail "$f が JSON として読めません（書き方の誤り）。"
            bad=1
        else
            want "$f" 'permissions.defaultMode が bypassPermissions ではない' '(.permissions.defaultMode // "") != "bypassPermissions"'
            want "$f" 'sandbox.excludedCommands が空' '((.sandbox.excludedCommands // []) | length) == 0'
            want "$f" 'sandbox.filesystem.allowWrite が空' '((.sandbox.filesystem.allowWrite // []) | length) == 0'
            want "$f" 'permissions.additionalDirectories が空' '((.permissions.additionalDirectories // []) | length) == 0'
        fi
    fi
    if (( bad )); then
        detail "→ 仕様どおりに戻すには、Windows 側で New-SecureRoom.ps1 -RoomName <部屋の名前> -Resume を実行してください。"
    fi
    return $bad
}

check_14() {
    local d="$HOME/projects"
    if [[ ! -d $d ]]; then detail "$d がありません。"; return 1; fi
    if [[ $(stat -c %U -- "$d") != "$U" ]]; then detail "$d の所有者が $U ではありません。"; return 1; fi
}

check_E1() { check_root_only_writable /etc/wsl.conf; }
check_E2() { check_root_only_writable /etc/fstab; }

check_E3() {
    local bad=0 f
    local -a entries=()
    check_root_only_writable /etc/sudoers || bad=1
    check_root_only_writable /etc/sudoers.d || bad=1
    if [[ -r /etc/sudoers.d && -x /etc/sudoers.d ]]; then
        shopt -s dotglob nullglob
        entries=(/etc/sudoers.d/*)
        shopt -u dotglob nullglob
        for f in "${entries[@]}"; do
            check_root_only_writable "$f" || bad=1
        done
    else
        detail "/etc/sudoers.d の中を一覧できないため、中のファイルは --root の検査で確認します。"
        (( bad )) && return 1
        return 2
    fi
    return $bad
}

# 仕様 3.2 の写し。テンプレート（templates/wsl.conf.tmpl）とは別に持つことで、
# テンプレートが書き換えられても、仕様からずれたことをここで検出できるようにしている。
expected_wsl_conf() {
    cat <<EOF
[boot]
systemd=true
[user]
default=$U
[automount]
enabled=false
mountFsTab=true
[interop]
enabled=false
appendWindowsPath=false
[network]
hostname=$ROOM
generateHosts=false
EOF
}

# 部屋の名前が分からないとき（WSL_DISTRO_NAME が無い）に、検証を飛ばす理由を書く
detail_no_room_name() {
    detail "部屋の名前（環境変数 WSL_DISTRO_NAME）が分からないため、確認できません。"
    detail "→ Windows から「wsl -d <部屋の名前>」で入ったターミナルで実行してください（su - などで入ると消えます）。"
}

# 標準入力の ini 形式を比較用に整える。
# 改行コード・前後の空白・空行・コメント・「=」まわりの空白の違いを取り除き、
# 差分が読みやすいように各行の先頭にセクション名を付ける（例: "[interop] enabled=false"）。
normalize_ini() {
    sed 's/\r$//' | awk '
        { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
        $0 == "" || /^[#;]/ { next }
        /^\[.*\]$/ { section = $0; print; next }
        { gsub(/[ \t]*=[ \t]*/, "="); print section " " $0 }'
}

check_E4() {
    local expected actual l
    if [[ ! -r /etc/wsl.conf ]]; then detail "/etc/wsl.conf が読めません。"; return 1; fi
    if [[ -z $ROOM ]]; then detail_no_room_name; return 2; fi
    expected=$(expected_wsl_conf | normalize_ini)
    actual=$(normalize_ini < /etc/wsl.conf)
    if [[ $expected == "$actual" ]]; then
        return 0
    fi
    detail "/etc/wsl.conf の内容が仕様（3.2）と違います。違う行（- 仕様 / + 実際）:"
    while IFS= read -r l; do
        detail "  $l"
    done < <(diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed -n 's/^< /- /p; s/^> /+ /p' || true)
    return 1
}

check_E5() {
    local l f1 f3 ok_count=0
    local -a fields=() others=()
    if [[ ! -r /etc/fstab ]]; then detail "/etc/fstab が読めません。"; return 1; fi
    while IFS= read -r l || [[ -n $l ]]; do
        l=${l%$'\r'}
        [[ $l =~ $RE_SKIP_LINE ]] && continue
        read -ra fields <<< "$l"
        f1=${fields[0]:-} f3=${fields[2]:-}
        # Windows につながる行（drvfs 等の種類、または C: のようなドライブ名で始まる行）だけを見る
        if [[ $f3 == drvfs || $f3 == 9p || $f3 == virtiofs || $f1 =~ ^[A-Za-z]: || $f1 == '\\'* ]]; then
            if [[ "${fields[*]}" == "$FSTAB_LINE" ]]; then
                ok_count=$((ok_count + 1))
            else
                others+=("$l")
            fi
        fi
    done < /etc/fstab
    if (( ok_count == 1 && ${#others[@]} == 0 )); then
        return 0
    fi
    if (( ok_count == 0 )); then
        detail "仕様（3.3）の行がありません: $FSTAB_LINE"
    elif (( ok_count > 1 )); then
        detail "仕様（3.3）の行が $ok_count 回書かれています（1 回だけにしてください）。"
    fi
    for l in "${others[@]}"; do
        detail "仕様に無い Windows 関連の行: $l"
    done
    return 1
}

check_E6() {
    local bad=0 f
    local -a entries=()
    if [[ $SCRIPT_DIR != "$INSTALL_DIR" ]]; then
        detail "このスクリプトが $INSTALL_DIR 以外の場所から実行されたため、確認しません。"
        return 2
    fi
    shopt -s dotglob nullglob
    entries=("$INSTALL_DIR" "$INSTALL_DIR"/* "$INSTALL_DIR"/templates/*)
    shopt -u dotglob nullglob
    for f in "${entries[@]}"; do
        check_root_only_writable "$f" || bad=1
    done
    if (( bad )); then
        detail "→ 検証の基準になるファイルが書き換えられる状態では、検証結果を信用できません。"
    fi
    return $bad
}

check_E7() {
    local dest=/usr/local/bin/delzonei src="$SCRIPT_DIR/delzonei.sh" bad=0
    check_root_only_writable /usr/local/bin || bad=1
    if check_root_only_writable "$dest"; then
        if [[ ! -x $dest ]]; then
            detail "$dest を実行できません（モード $(stat -c %a -- "$dest")）。"
            bad=1
        fi
        if [[ -r $src ]] && ! cmp -s -- "$src" "$dest"; then
            detail "$dest の中身が $src と違います。"
            bad=1
        fi
    else
        bad=1
    fi
    if (( bad )); then
        detail "→ Windows 側で New-SecureRoom.ps1 -RoomName <部屋の名前> -Resume を実行すると置き直します。"
    fi
    return $bad
}

# PAT の保存先 ~/.git-credentials は、ある場合、本人だけが読み書きできること
check_G1() {
    local f="$HOME/.git-credentials" owner mode lsout bad=0
    if [[ ! -e $f && ! -L $f ]]; then
        return 0   # GitHub の設定をしていない部屋では無いのが正常
    fi
    if [[ -L $f ]]; then detail "$f がシンボリックリンクになっています（想定外）。"; return 1; fi
    if [[ ! -f $f ]]; then detail "$f が通常のファイルではありません。"; return 1; fi
    owner=$(stat -c %U -- "$f")
    mode=$(stat -c %a -- "$f")
    if [[ $owner != "$U" ]]; then
        detail "$f の所有者が $owner になっています（期待: $U）。"
        bad=1
    fi
    if (( (8#$mode & 8#077) != 0 )); then
        detail "$f のモードが $mode です。$U 以外も読み書きできる状態です。"
        detail "→ chmod 600 ~/.git-credentials を実行してください。"
        bad=1
    fi
    lsout=$(ls -ld -- "$f")
    if [[ ${lsout%% *} == *+ ]]; then
        detail "$f に ACL（追加のアクセス権）が設定されています。"
        bad=1
    fi
    return $bad
}

# PAT が保存先（~/.git-credentials）以外に書かれていないこと。
#   - git の設定ファイルの URL に認証情報が埋め込まれていない（~/projects/*/.git/config は Claude から読める）
#   - 部屋の中のスクリプト置き場（誰でも読める）に room-github.conf が無い
# 見つけた場合も、PAT を画面に出さないよう、ファイル名と行番号だけを表示する。
check_G2() {
    local f lines bad=0
    local -a files=()
    # https://ユーザー:パスワード@... と、GitHub のトークンをユーザー名の位置に書いた https://ghp_...@...
    local re='[A-Za-z][A-Za-z0-9+.-]*://[^/@[:space:]]*:[^/@[:space:]]*@|https?://(gh[pousr]_|github_pat_)[A-Za-z0-9_]+@'
    files=("$HOME/.gitconfig" "${XDG_CONFIG_HOME:-$HOME/.config}/git/config")
    shopt -s dotglob nullglob
    files+=("$HOME"/projects/*/.git/config)
    shopt -u dotglob nullglob
    for f in "${files[@]}"; do
        [[ -f $f && -r $f ]] || continue
        lines=$(grep -nE -- "$re" "$f" 2> /dev/null | cut -d: -f1 | paste -sd, -) || true
        if [[ -n $lines ]]; then
            detail "${f/#"$HOME"/\~} の $lines 行目に、認証情報（PAT など）を含む URL があります（内容は表示しません）。"
            bad=1
        fi
    done
    if (( bad )); then
        detail "→ git remote set-url origin https://github.com/OWNER/REPOSITORY.git のように、認証情報を含まない URL に直してください。"
        detail "→ Claude から読める場所に書かれていたので、その PAT は GitHub で削除（失効）して作り直してください。"
    fi
    if [[ -e $INSTALL_DIR/room-github.conf ]]; then
        detail "$INSTALL_DIR/room-github.conf があります（New-SecureRoom.ps1 は部屋の中にコピーしないファイルです）。"
        detail "→ 中身に PAT が書かれていれば、GitHub で削除（失効）して作り直し、このファイルを削除してください（sudo rm）。"
        bad=1
    fi
    return $bad
}

# -----------------------------------------------------------------------------
# 警告（WARN）: 部屋の設定（wsl.conf など）では止められない、WSL の仕組みとしての窓口
# Claude Code が実行するコマンドからは、/mnt の読み取り禁止とローカルソケット（Unix ドメインソケット）の
# 禁止によって使えない。部屋の中でサンドボックスの外で動くプログラムから届くことを知らせる。
# -----------------------------------------------------------------------------

# WSLg（Linux の GUI アプリ機能）。有効だと、GUI の仕組みを通じて Windows のクリップボードなどに届く可能性がある。
# Windows 側の %USERPROFILE%\.wslconfig で止める（WSL 全体の設定）ので、ここでは警告にとどめる。
check_W1() {
    local d
    local -a found=()
    if mountpoint -q /mnt/wslg 2> /dev/null; then found+=('/mnt/wslg がマウントされています。'); fi
    if compgen -G '/tmp/.X11-unix/X*' > /dev/null; then found+=('X11 のソケット（/tmp/.X11-unix）があります。'); fi
    (( ${#found[@]} > 0 )) || return 0
    detail 'WSLg（Linux の GUI アプリ機能）が有効です:'
    for d in "${found[@]}"; do detail "  $d"; done
    detail '部屋の中でサンドボックスの外で動くプログラム（ご自身が実行するもの、VS Code の拡張機能など）が、'
    detail 'Windows のクリップボードなどを使える可能性があります（Claude Code が実行するコマンドからは使えません）。'
    detail '→ 止める場合は、Windows の %USERPROFILE%\.wslconfig の [wsl2] に guiApplications=false と書き、'
    detail '  PowerShell で wsl --shutdown を実行してください（WSL 全体の設定なので、ほかのディストリでも GUI アプリが使えなくなります）。'
    return 3
}

# /mnt/wsl は WSL2 のすべてのディストリビューションで共有される場所。WSL 自身が置く resolv.conf のほかに何かあれば、
# ほかのディストリ（Docker Desktop など）が置いたものか、wsl --mount で取り付けたディスクで、部屋からも見える。
check_W2() {
    local e n
    local -a others=()
    [[ -d /mnt/wsl ]] || return 0
    if [[ ! -r /mnt/wsl || ! -x /mnt/wsl ]]; then
        detail '/mnt/wsl の中を一覧できないため、確認できませんでした。'
        return 3
    fi
    shopt -s dotglob nullglob
    for e in /mnt/wsl/*; do
        n=${e##*/}
        [[ $n == resolv.conf ]] && continue
        others+=("${n//[[:cntrl:]]/?}")
    done
    shopt -u dotglob nullglob
    (( ${#others[@]} > 0 )) || return 0
    detail '/mnt/wsl（WSL2 のすべてのディストリビューションで共有される場所）に、次のものがあります:'
    for n in "${others[@]}"; do detail "  $n"; done
    detail 'ほかのディストリビューション（Docker Desktop など）が置いたものや、wsl --mount で取り付けたディスクは、この部屋からも見えます。'
    detail '→ 中身が部屋から見えてよいものか確認してください。Docker Desktop の場合は、WSL integration の対象にこの部屋を入れないでください。'
    return 3
}

# 初回起動時（wsl.conf が反映される前）に WSL が作ったドライブ用のフォルダ（誰でも書き込める 777）の残り。
# provision-root.sh --phase mount が、c 以外は削除し、/mnt/c から取り付け先までは root 所有・755 にする。
check_W3() {
    local d bad=0
    local -a drives=()
    shopt -s nullglob
    drives=(/mnt/[a-z])
    shopt -u nullglob
    for d in "${drives[@]}"; do
        [[ $d != /mnt/c ]] || continue
        detail "$d が残っています（初回起動時に WSL が作ったドライブ用のフォルダで、今は使っていません）。"
        bad=1
    done
    for d in /mnt/c /mnt/c/Users "/mnt/c/Users/$W" "/mnt/c/Users/$W/.vscode"; do
        [[ -e $d || -L $d ]] || continue
        check_root_only_writable "$d" || bad=1
    done
    (( bad )) || return 0
    detail '→ Windows 側で New-SecureRoom.ps1 -RoomName <部屋の名前> -Resume を実行すると片付けます。'
    return 3
}

# =============================================================================
# root として行う検査
# =============================================================================

# 部屋のユーザーに sudo の権限が一つも無いこと（パスワードが必要なものも含む。部屋の中では sudo を使わない設計）
check_R1() {
    local out l
    command -v sudo > /dev/null 2>&1 || return 0
    out=$(LC_ALL=C sudo -l -U "$U" 2>&1) || true
    [[ $out != *"is not allowed to run sudo"* ]] || return 0
    detail "$U に sudo の権限があります（sudo -l -U $U の結果）:"
    while IFS= read -r l; do detail "  $l"; done <<< "$out"
    detail "→ 管理者のグループに入っている場合は、-Resume でやり直すと外します（E8）。"
    detail "→ sudo の設定ファイルに $U の行がある場合は、その行を削除してください（visudo、または visudo -f <ファイル>）。"
    return 1
}

check_E8() {
    local found
    found=$(user_admin_groups "$U")
    [[ -n $found ]] || return 0
    detail "$U が管理者のグループに入っています: ${found//$'\n'/ }"
    detail "→ 部屋の中で sudo などを使って root になれる状態です。-Resume でやり直すと、グループから外します。"
    return 1
}

# /etc/hosts の仕様（コメントと空行を除き、空白を 1 つにそろえた形）。
# provision-root.sh の install_host_files と同じ内容（変えるときは両方）。先頭の 2 行は欠けてはいけない行
expected_hosts() {
    cat <<EOF
127.0.0.1 localhost
127.0.1.1 $ROOM
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
}

# ホスト名と /etc/hosts に、Windows の情報（コンピューター名、Windows の hosts ファイルの項目）が無いこと。
# 仕様に無い行は、6.8 の方法で管理者が足したものと区別できないので、FAIL ではなく WARN にする
check_E9() {
    local name l i bad=0 warn=0
    local -a actual=() expected=() missing=() extra=()
    local -A have=() want=()
    if [[ -z $ROOM ]]; then detail_no_room_name; return 2; fi

    name=$(uname -n)
    if [[ $name != "$ROOM" ]]; then
        detail "ホスト名が「${name//[[:cntrl:]]/?}」です（期待: $ROOM）。"
        bad=1
    fi
    if [[ -e /etc/hostname ]]; then
        name=$(trim "$(< /etc/hostname)")
        if [[ $name != "$ROOM" ]]; then
            detail "/etc/hostname の内容が「${name//[[:cntrl:]]/?}」です（期待: $ROOM）。"
            bad=1
        fi
    fi

    check_root_only_writable /etc/hosts || bad=1
    if [[ ! -r /etc/hosts ]]; then detail "/etc/hosts が読めません。"; return 1; fi
    if grep -q 'automatically generated by WSL' /etc/hosts; then
        detail "/etc/hosts が WSL によって作り直されています（Windows の hosts ファイルの項目が写されている可能性があります）。"
        detail "→ /etc/wsl.conf の [network] generateHosts=false が反映されているか確認してください（E4）。"
        bad=1
    fi
    mapfile -t actual < <(sed -e 's/#.*$//' -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' /etc/hosts | grep -v '^$' || true)
    mapfile -t expected < <(expected_hosts)
    for l in "${actual[@]}"; do have[$l]=1; done
    for l in "${expected[@]}"; do want[$l]=1; done
    for (( i = 0; i < ${#expected[@]}; i++ )); do
        l=${expected[$i]}
        [[ -z ${have[$l]:-} ]] || continue
        if (( i < 2 )); then
            detail "/etc/hosts に、仕様の行「$l」がありません。"
            bad=1
        else
            missing+=("$l")
        fi
    done
    for l in "${actual[@]}"; do
        [[ -n ${want[$l]:-} ]] || extra+=("${l//[[:cntrl:]]/?}")
    done
    if (( ${#missing[@]} > 0 )); then
        detail "/etc/hosts に、仕様の次の行がありません:"
        for l in "${missing[@]}"; do detail "  $l"; done
        warn=1
    fi
    if (( ${#extra[@]} > 0 )); then
        detail "/etc/hosts に、仕様に無い行があります:"
        for l in "${extra[@]:0:10}"; do detail "  $l"; done
        if (( ${#extra[@]} > 10 )); then detail "  ...（ほか $(( ${#extra[@]} - 10 )) 行）"; fi
        warn=1
    fi

    if (( bad )); then
        detail "→ Windows 側で New-SecureRoom.ps1 -RoomName <部屋の名前> -Resume を実行すると、仕様どおりに戻します。"
        return 1
    fi
    if (( warn )); then
        detail "→ ご自身で足した・消したものでなければ、Windows 側で New-SecureRoom.ps1 -RoomName <部屋の名前> -Resume を実行して戻してください。"
        return 3
    fi
}

check_A1() {
    local bad l
    if [[ ! -f $APT_SOURCES ]]; then
        detail "apt の取得先の設定ファイル（$APT_SOURCES）がありません。"
        return 1
    fi
    bad=$(apt_non_https_uris)
    [[ -n $bad ]] || return 0
    detail "https でない取得先があります（CVE-2026-109518 の対象になります）:"
    while IFS= read -r l; do detail "  $l"; done <<< "$bad"
    detail "→ -Resume でやり直すと、https に書き換えます。"
    return 1
}

check_A2() {
    local v
    v=$(dpkg-query -W -f='${Version}' apt 2> /dev/null) || v=''
    if [[ -n $v ]] && dpkg --compare-versions "$v" ge "$APT_MIN_VERSION"; then return 0; fi
    detail "apt の版（${v:-不明}）が、CVE-2026-109518 の修正版（$APT_MIN_VERSION）より古いです。"
    detail "→ 取得先が https であること（A1）を確かめてから、Windows の PowerShell で wsl -d <部屋の名前> -u root と入力して入り、"
    detail "  apt update と apt upgrade を実行してください。"
    return 1
}

check_A3() {
    local out
    out=$(dpkg-query -W -f='${binary:Package} ${db:Status-Status}\n' 'apache2*' 2> /dev/null |
        awk '$2 == "installed" { print $1 }') || true
    [[ -n $out ]] || return 0
    detail "Apache HTTP Server のパッケージが入っています: ${out//$'\n'/ }"
    detail "→ このスクリプトは Apache を入れません。不要なら、wsl -d <部屋の名前> -u root で入り、apt purge で削除してください。"
    return 1
}

check_A4() {
    local out n deferred l
    if ! out=$(LC_ALL=C apt-get -s -o Debug::NoLocking=1 upgrade 2> /dev/null); then
        detail "apt-get -s upgrade（更新の模擬実行）ができませんでした。"
        return 3
    fi
    n=$(grep -c '^Inst ' <<< "$out" || true)
    # 段階的配信（phased updates）で保留中のものは、apt が「deferred due to phasing」の下に字下げして並べる
    deferred=$(sed -n '/deferred due to phasing/,/^[^ ]/{/^ /p}' <<< "$out" | wc -w)
    if (( deferred > 0 )); then
        detail "段階的配信（phased updates）で保留中の更新が $deferred 件あります（数えていません）。"
    fi
    (( n > 0 )) || return 0
    detail "適用していない更新が $n 件あります（最後に apt update したときの一覧で判定）:"
    while IFS= read -r l; do detail "  ${l#Inst }"; done < <(grep '^Inst ' <<< "$out" | head -n 20)
    detail "→ Windows の PowerShell で wsl -d <部屋の名前> -u root と入力して入り、apt update と apt upgrade を実行してください。"
    return 3
}

# =============================================================================

summary() {
    printf '\n----------------------------------------------------------------\n'
    printf '結果: PASS %d / FAIL %d / SKIP %d / WARN %d\n' "$PASS" "$FAIL" "$SKIP" "$WARN"
    if (( FAIL > 0 )); then
        printf '%sFAIL の項目があります。上の説明を確認してください。%s\n' "$C_RED" "$C_RESET"
        return 1
    fi
    printf '%sFAIL はありません。%s\n' "$C_GREEN" "$C_RESET"
    if (( WARN > 0 )); then
        printf '%sWARN の項目は失敗ではありませんが、上の説明を確認してください。%s\n' "$C_YELLOW" "$C_RESET"
    fi
}

main() {
    local mode=user
    case ${1:-} in
        '') ;;
        --root) mode=root ;;
        -h|--help) usage; exit 0 ;;
        *) die "知らないオプションです: $1" "$(usage)" ;;
    esac

    load_room_conf "$SCRIPT_DIR/room.conf"
    U=$CONF_LINUX_USER
    W=$CONF_WINDOWS_USER
    MP=$(win_ext_mountpoint "$W")
    FSTAB_LINE=$(fstab_expected_line "$W")

    if [[ $mode == root ]]; then
        require_root
        printf '== 部屋の検証（root の権限で行う項目）==\n'
        run_check R1 "$U に sudo の権限が無い（パスワードが必要なものも含む）" check_R1
        run_check E3 '/etc/sudoers と /etc/sudoers.d/ が root 所有で root 以外は書き込めない' check_E3
    else
        [[ $(id -u) != 0 ]] || die "一般ユーザーとして実行してください（root の検査は --root を付けます）。"
        # 分からないときは、部屋の名前を使う検証（E4・E9）だけを飛ばす
        if load_room_name; then ROOM=$CONF_ROOM_NAME; else ROOM=''; fi
        printf '== 部屋の検証（一般ユーザーとして行う項目）==\n'
        run_check 01 'C ドライブ全体が見えない' check_01
        run_check 02 'Windows への窓は VS Code 拡張フォルダの 1 つだけで、読み取り専用' check_02
        run_check 03 "/mnt/c/Users/$W には .vscode しか見えない" check_03
        run_check 04 'VS Code 拡張フォルダに書き込めない' check_04
        run_check 05 'VS Code が使うパス変換（wslpath）が一致する' check_05
        run_check 06 'Windows のプログラムを呼べない（interop 無効）' check_06
        run_check 07 "部屋に入ると $U になる（root ではない）" check_07
        run_check 08 'パスワードなしで sudo できない' check_08
        run_check 10 'サンドボックスの土台（bubblewrap・socat）が動く' check_10
        run_check 11 "claude は部屋の中のもの（$HOME/.local/bin/claude）が使われる" check_11
        run_check 13 "Claude Code の守りの設定（$MANAGED_SETTINGS）が仕様どおりで、~/.claude/settings.json に守りを弱める設定が無い" check_13
        run_check 14 '~/projects がある' check_14
        run_check E1 '/etc/wsl.conf が root 所有で root 以外は書き込めない' check_E1
        run_check E2 '/etc/fstab が root 所有で root 以外は書き込めない' check_E2
        run_check E3 '/etc/sudoers と /etc/sudoers.d/ が root 所有で root 以外は書き込めない' check_E3
        run_check E4 '/etc/wsl.conf の内容が仕様（3.2）と一致する' check_E4
        run_check E5 '/etc/fstab の Windows 関連の行が仕様（3.3）の 1 行だけ' check_E5
        run_check E6 '検証の基準ファイル（部屋の中のスクリプトと room.conf）が root 所有で root 以外は書き込めない' check_E6
        run_check E7 'delzonei（/usr/local/bin/delzonei）が root 所有で root 以外は書き込めず、中身が仕様どおり' check_E7
        run_check E8 "$U が管理者のグループ（${ADMIN_GROUPS[*]}）に入っていない" check_E8
        run_check E9 'ホスト名と /etc/hosts に Windows の情報が無い（部屋の名前だけ）' check_E9
        run_check A1 'apt の取得先がすべて https（CVE-2026-109518 への対策）' check_A1
        run_check A2 "apt が CVE-2026-109518 の修正版（$APT_MIN_VERSION）以上" check_A2
        run_check A3 'Apache HTTP Server（apache2）が入っていない' check_A3
        run_check A4 '適用していない更新が残っていない（段階的配信で保留中のものを除く）' check_A4
        run_check G1 "~/.git-credentials（PAT の保存先）は、ある場合、$U だけが読み書きできる" check_G1
        run_check G2 'PAT が保存先以外（git の設定の URL、部屋の中の room-github.conf）に書かれていない' check_G2
        run_check W1 'WSLg（Linux の GUI アプリ機能）が無効で、Windows のクリップボードなどに届かない' check_W1
        run_check W2 '/mnt/wsl（全ディストリで共有）に、ほかのディストリやディスク由来のものが無い' check_W2
        run_check W3 '/mnt に使っていないドライブ用のフォルダが無く、/mnt/c は root 以外書き込めない' check_W3
    fi

    summary || exit 1
}

main "$@"
