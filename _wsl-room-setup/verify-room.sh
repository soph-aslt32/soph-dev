#!/usr/bin/env bash
# =============================================================================
# verify-room.sh — 部屋が仕様どおりの安全な状態になっているかを自動で検証します
#
# 使い方（部屋の中で）:
#   bash /usr/local/lib/wsl-room-setup/verify-room.sh               一般ユーザーとして行う検査
#   sudo bash /usr/local/lib/wsl-room-setup/verify-room.sh --root   root の権限が必要な検査
#
# New-SecureRoom.ps1 は両方を自動で実行します。
# 各項目を [PASS] / [FAIL] / [SKIP] で表示し、FAIL が 1 つでもあれば終了コード 1 で終わります。
#
# 項目番号:
#   01〜14  申し送り書 第 6 章の表（12 の claude doctor はログインが必要なため手動確認に回す）
#   E1〜E6  追加の申し送り EX1（重要ファイルの所有者・権限、wsl.conf と fstab の内容）
#
# 期待値（Linux ユーザー名、Windows ユーザー名、許可ドメイン）は、このスクリプトと同じフォルダの
# room.conf から読みます（部屋の中では root 所有なので、一般ユーザーや Claude は書き換えられません）。
#   R1〜R2  root でしか確認できない sudo の設定
#
# Claude Code 自体は起動しません。
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
trap 'on_error $LINENO' ERR

readonly INSTALL_DIR=/usr/local/lib/wsl-room-setup

PASS=0 FAIL=0 SKIP=0
DETAILS=()
U='' W='' MP='' FSTAB_LINE=''

usage() {
    echo '使い方: bash verify-room.sh [--root]'
}

# 結果の下に表示する説明を追加する
detail() { DETAILS+=("$*"); }

# run_check <番号> <見出し> <関数名>
# 関数は 0=PASS、1=FAIL、2=SKIP を返す。
run_check() {
    local id=$1 title=$2 fn=$3 rc=0 d
    DETAILS=()
    "$fn" || rc=$?
    case $rc in
        0) PASS=$((PASS + 1)); printf '%s[PASS]%s %-3s %s\n' "$C_GREEN" "$C_RESET" "$id" "$title" ;;
        2) SKIP=$((SKIP + 1)); printf '%s[SKIP]%s %-3s %s\n' "$C_YELLOW" "$C_RESET" "$id" "$title" ;;
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
    local bad=0
    sudo -k 2> /dev/null || true
    if sudo -n true > /dev/null 2>&1; then
        detail "パスワードなしで sudo を実行できました。"
        bad=1
    fi
    # sudo -l（権限一覧の表示）は、既定ではパスワード不要の設定が 1 つでもあるとパスワードなしで通る
    sudo -k 2> /dev/null || true
    if sudo -n -l > /dev/null 2>&1; then
        detail "パスワードなしで sudo -l を実行できました。NOPASSWD の設定がある可能性があります。"
        bad=1
    fi
    if (( bad )); then
        detail "→ Claude が root になって、ここで検査している設定を書き換えられる状態です。R1・R2 の結果も確認してください。"
        return 1
    fi
}

check_09() {
    detail "sudo の設定ファイルは root しか読めないため、R1 で確認します。"
    return 2
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

check_12() {
    detail "claude doctor はログイン後に手動で確認します（README「ログイン後の手動確認」）。"
    return 2
}

check_13() {
    local f="$HOME/.claude/settings.json" owner domains_json bad=0
    if [[ ! -f $f ]]; then detail "$f がありません。"; return 1; fi
    owner=$(stat -c %U -- "$f")
    if [[ $owner != "$U" ]]; then
        detail "所有者が $owner になっています（期待: $U）。"
        bad=1
    fi
    if ! command -v jq > /dev/null 2>&1; then detail "jq が見つからないため検査できません。"; return 1; fi
    if ! jq -e . "$f" > /dev/null 2>&1; then detail "JSON として読めません（書き方の誤り）。"; return 1; fi

    # want <説明> <jq の条件式>
    want() {
        if ! jq -e "$2" "$f" > /dev/null 2>&1; then
            detail "NG: $1"
            bad=1
        fi
    }
    want 'sandbox.enabled が true' '.sandbox.enabled == true'
    want 'sandbox.failIfUnavailable が true' '.sandbox.failIfUnavailable == true'
    want 'sandbox.allowUnsandboxedCommands が false' '.sandbox.allowUnsandboxedCommands == false'
    want 'permissions.blockReadsOutsideWorkingDirectories が true' '.permissions.blockReadsOutsideWorkingDirectories == true'
    want 'permissions.deny に "Read(//mnt/**)" がある' '(.permissions.deny // []) | any(.[]; . == "Read(//mnt/**)")'
    want 'sandbox.filesystem.denyRead に "/mnt" がある' '(.sandbox.filesystem.denyRead // []) | any(.[]; . == "/mnt")'
    want 'sandbox.credentials.files で ~/.ssh が deny' '(.sandbox.credentials.files // []) | any(.[]; .path == "~/.ssh" and .mode == "deny")'
    want 'sandbox.credentials.files で ~/.aws が deny' '(.sandbox.credentials.files // []) | any(.[]; .path == "~/.aws" and .mode == "deny")'
    want 'sandbox.credentials.files で ~/.git-credentials が deny' '(.sandbox.credentials.files // []) | any(.[]; .path == "~/.git-credentials" and .mode == "deny")'
    want 'permissions.defaultMode が bypassPermissions ではない' '(.permissions.defaultMode // "") != "bypassPermissions"'
    want 'sandbox.allowNestedUserNamespaces が有効ではない' '(.sandbox.allowNestedUserNamespaces // false) != true'
    want 'sandbox.filesystem.disabled が有効ではない' '(.sandbox.filesystem.disabled // false) != true'
    want 'sandbox.enableWeakerNestedSandbox が有効ではない' '(.sandbox.enableWeakerNestedSandbox // false) != true'
    want 'sandbox.excludedCommands が空' '((.sandbox.excludedCommands // []) | length) == 0'

    domains_json=$(jq -nc '$ARGS.positional' --args "${CONF_ALLOWED_DOMAINS[@]}")
    if ! jq -e --argjson want "$domains_json" '.sandbox.network.allowedDomains == $want' "$f" > /dev/null 2>&1; then
        detail "NG: sandbox.network.allowedDomains が room.conf の allowed_domains と一致しない"
        detail "    room.conf: ${CONF_ALLOWED_DOMAINS[*]:-（なし）}"
        detail "    実際    : $(jq -c '.sandbox.network.allowedDomains' "$f" 2> /dev/null)"
        bad=1
    fi
    if (( bad )); then
        detail "→ 仕様（3.6）どおりに戻すには、Windows 側で New-SecureRoom.ps1 -RoomName <部屋の名前> -Resume を実行してください。"
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
EOF
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

# =============================================================================
# root として行う検査
# =============================================================================

check_R1() {
    local hits l
    local -a files=(/etc/sudoers)
    shopt -s dotglob nullglob
    files+=(/etc/sudoers.d/*)
    shopt -u dotglob nullglob
    hits=$(grep -HnE '^[^#]*(NOPASSWD|!authenticate)' -- "${files[@]}" 2> /dev/null || true)
    if [[ -z $hits ]]; then
        return 0
    fi
    detail "パスワードなしで sudo できる設定が見つかりました:"
    while IFS= read -r l; do detail "  $l"; done <<< "$hits"
    detail "→ 該当する行を削除してください（sudo visudo、または sudo visudo -f <ファイル>）。"
    return 1
}

check_R2() {
    local out l
    out=$(LC_ALL=C sudo -l -U "$U" 2>&1) || true
    if ! grep -qE 'NOPASSWD|!authenticate' <<< "$out"; then
        return 0
    fi
    detail "$U の sudo の権限に、パスワード不要のものが含まれています:"
    while IFS= read -r l; do detail "  $l"; done < <(grep -E 'NOPASSWD|!authenticate' <<< "$out" || true)
    return 1
}

# =============================================================================

summary() {
    printf '\n----------------------------------------------------------------\n'
    printf '結果: PASS %d / FAIL %d / SKIP %d\n' "$PASS" "$FAIL" "$SKIP"
    if (( FAIL > 0 )); then
        printf '%sFAIL の項目があります。上の説明を確認してください。%s\n' "$C_RED" "$C_RESET"
        return 1
    fi
    printf '%sFAIL はありません。%s\n' "$C_GREEN" "$C_RESET"
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
        run_check R1 'sudo の設定ファイルに NOPASSWD などが無い' check_R1
        run_check R2 "$U の sudo 権限にパスワード不要のものが無い" check_R2
        run_check E3 '/etc/sudoers と /etc/sudoers.d/ が root 所有で root 以外は書き込めない' check_E3
    else
        [[ $(id -u) != 0 ]] || die "一般ユーザーとして実行してください（root の検査は --root を付けます）。"
        printf '== 部屋の検証（一般ユーザーとして行う項目）==\n'
        run_check 01 'C ドライブ全体が見えない' check_01
        run_check 02 'Windows への窓は VS Code 拡張フォルダの 1 つだけで、読み取り専用' check_02
        run_check 03 "/mnt/c/Users/$W には .vscode しか見えない" check_03
        run_check 04 'VS Code 拡張フォルダに書き込めない' check_04
        run_check 05 'VS Code が使うパス変換（wslpath）が一致する' check_05
        run_check 06 'Windows のプログラムを呼べない（interop 無効）' check_06
        run_check 07 "部屋に入ると $U になる（root ではない）" check_07
        run_check 08 'パスワードなしで sudo できない' check_08
        run_check 09 'sudo の設定に NOPASSWD が無い' check_09
        run_check 10 'サンドボックスの土台（bubblewrap・socat）が動く' check_10
        run_check 11 "claude は部屋の中のもの（$HOME/.local/bin/claude）が使われる" check_11
        run_check 12 'claude doctor' check_12
        run_check 13 '~/.claude/settings.json が仕様（3.6）どおり' check_13
        run_check 14 '~/projects がある' check_14
        run_check E1 '/etc/wsl.conf が root 所有で root 以外は書き込めない' check_E1
        run_check E2 '/etc/fstab が root 所有で root 以外は書き込めない' check_E2
        run_check E3 '/etc/sudoers と /etc/sudoers.d/ が root 所有で root 以外は書き込めない' check_E3
        run_check E4 '/etc/wsl.conf の内容が仕様（3.2）と一致する' check_E4
        run_check E5 '/etc/fstab の Windows 関連の行が仕様（3.3）の 1 行だけ' check_E5
        run_check E6 '検証の基準ファイル（部屋の中のスクリプトと room.conf）が root 所有で root 以外は書き込めない' check_E6
    fi

    summary || exit 1
}

main "$@"
