#!/usr/bin/env bash
# =============================================================================
# verify-base.sh — 土台（dcs-base）の自動検証（最小限。DESIGN.md の 6.5d）
#
# Windows 側の lib/Base.ps1 の Test-Base が、土台のユーザー（dcs）で呼びます。
#   bash /opt/dcs/base/verify-base.sh <Windows のプロファイル名> <Windows 側のツールの base\wsl.conf の SHA256>
# 出力: 1 項目 1 行。「[OK] <ID> <説明>」「[NG] <ID> <説明>: <理由>」「[WARN] <ID> <説明>: <理由>」
# 終了コード: NG が無ければ 0、あれば 1、引数の誤りは 2。WARN は失敗に数えない（D46・D47）。
# =============================================================================
set -Eeuo pipefail

ng=0
# 色（端末に出すときだけ。Windows 側の Test-Base が受け取るときは付けない。ウィザードの色にそろえる）
if [[ -t 1 ]]; then
    readonly C_OK=$'\e[92m' C_NOTE=$'\e[93m' C_ERR=$'\e[91m' C_OFF=$'\e[0m'
else
    readonly C_OK='' C_NOTE='' C_ERR='' C_OFF=''
fi
pass() { printf '%s[OK] %s %s%s\n' "$C_OK" "$1" "$2" "$C_OFF"; }
fail() { printf '%s[NG] %s %s: %s%s\n' "$C_ERR" "$1" "$2" "$3" "$C_OFF"; ng=1; }
warn() { printf '%s[WARN] %s %s: %s%s\n' "$C_NOTE" "$1" "$2" "$3" "$C_OFF"; }

profile=${1:-} wsl_conf_sha=${2:-}
[[ $# == 2 && $profile =~ ^[A-Za-z0-9._-]+$ && $wsl_conf_sha =~ ^[0-9a-f]{64}$ ]] || {
    echo '使い方: bash verify-base.sh <Windows のプロファイル名> <ツールの wsl.conf の SHA256>' >&2
    exit 2
}

# B1: Docker Engine が動いている（dcs は docker グループにいる）
if docker info > /dev/null 2>&1; then
    pass B1 'Docker Engine が動いている'
else
    fail B1 'Docker Engine が動いている' 'docker info が失敗しました（systemctl status docker で確かめてください）'
fi

# B2: /etc/wsl.conf がツールのもの（C ドライブの自動マウントと interop の無効を含む）。
# 土台に置いた /opt/dcs/base/wsl.conf ではなく、Windows 側のツールのもの（SHA256）と比べる（土台に置いたものが古くても、正しく判定する）
if [[ -f /etc/wsl.conf && $(sha256sum /etc/wsl.conf | cut -d ' ' -f 1) == "$wsl_conf_sha" ]]; then
    pass B2 '/etc/wsl.conf がツールの wsl.conf と同じ'
else
    fail B2 '/etc/wsl.conf がツールの wsl.conf と同じ' '違っています（ツールを新しくしたときなど。ウィザードの「更新」で置き直します）'
fi

# B3: C ドライブが見えず、Windows のプログラムを動かせない。
# /proc/sys/fs/binfmt_misc/WSLInterop は VM 全体で 1 つの登録で、ディストリビューションごとの設定を反映しないので使わない（VERIFY.md の V2）
reasons=''
[[ ! -e /mnt/c/Windows ]] || reasons+='/mnt/c/Windows が見えます。'
for c in cmd.exe wsl.exe powershell.exe explorer.exe; do
    if command -v "$c" > /dev/null 2>&1; then reasons+="$c が見つかります。"; fi
done
[[ :$PATH: != *:/mnt/* ]] || reasons+='PATH に /mnt/ のフォルダがあります。'
if [[ -z $reasons ]]; then
    pass B3 'C ドライブが見えず、Windows のプログラムを動かせない'
else
    fail B3 'C ドライブが見えず、Windows のプログラムを動かせない' "$reasons"
fi

# B4（警告だけ。D46）: WSLg が止まっている（WSLg の X のサーバーのソケットが無い）
if [[ -S /tmp/.X11-unix/X0 || -S /mnt/wslg/.X11-unix/X0 ]]; then
    warn B4 'WSLg が止まっている' 'WSLg が動いています。Windows の %USERPROFILE%\.wslconfig の [wsl2] に guiApplications=false を書き、PowerShell で wsl --shutdown を実行してください（README）'
else
    pass B4 'WSLg が止まっている'
fi

# B5（警告だけ。D47）: VS Code の拡張機能フォルダがマウントされている（無いと VS Code から土台につなげない）
mp="/mnt/c/Users/$profile/.vscode/extensions"
if awk -v mp="$mp" '$2 == mp && $4 ~ /(^|,)ro(,|$)/ { found = 1 } END { exit !found }' /proc/self/mounts; then
    pass B5 'VS Code の拡張機能フォルダが読み取り専用でマウントされている'
else
    warn B5 'VS Code の拡張機能フォルダが読み取り専用でマウントされている' "マウントされていません（$mp）。このままでは VS Code から土台につなげません。%USERPROFILE%\.wslconfig に hostFileSystemAccess=false の行があれば消し、PowerShell で wsl --shutdown を実行してください（README）"
fi

exit "$ng"
