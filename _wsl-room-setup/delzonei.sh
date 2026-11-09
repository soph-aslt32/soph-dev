#!/usr/bin/env bash
# =============================================================================
# delzonei — カレントディレクトリ以下の Zone.Identifier ファイルを削除する
#
# Windows のエクスプローラーで部屋の中へファイルをコピーすると、ファイルごとに
# 「<元の名前>:Zone.Identifier」というファイル（Windows の代替データストリームの名残）が作られます。
# このコマンドは、カレントディレクトリとそのサブフォルダにある、それらをすべて削除します。
#
# 使い方:
#   delzonei        削除して、削除したファイルを表示する
#   delzonei -n     削除せずに、見つかったファイルを表示するだけ
#
# New-SecureRoom.ps1（provision-root.sh）が /usr/local/bin/delzonei（root 所有）として置きます。
# ご自身がサンドボックスの外で実行するコマンドなので、Claude が書き換えられない場所に置いています。
# =============================================================================
set -Eeuo pipefail

usage() {
    cat <<'EOF'
使い方:
  delzonei        カレントディレクトリ以下（サブフォルダを含む）の *:Zone.Identifier ファイルを削除する
  delzonei -n     削除せずに、見つかったファイルを表示するだけ
EOF
}

# ファイル名に含まれる制御文字（端末を操作できるエスケープシーケンスなど）を ? に置き換えて表示する
show() {
    local s=$2
    printf '%s%s\n' "$1" "${s//[[:cntrl:]]/?}"
}

main() {
    local dry_run=0 f found=0 deleted=0 failed=0
    case ${1:-} in
        '') ;;
        -n|--dry-run) dry_run=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    (( $# <= 1 )) || { usage >&2; exit 2; }

    # -xdev    : ほかのファイルシステム（マウントされたフォルダ）の中には入らない
    # -type f  : 通常のファイルだけ（フォルダやシンボリックリンクは対象外。リンク先もたどらない）
    while IFS= read -r -d '' f; do
        found=$((found + 1))
        if (( dry_run )); then
            show '' "$f"
        elif rm -f -- "$f"; then
            deleted=$((deleted + 1))
            show '削除: ' "$f"
        else
            failed=$((failed + 1))
        fi
    done < <(find . -xdev -type f -name '*:Zone.Identifier' -print0)

    if (( found == 0 )); then
        echo 'Zone.Identifier ファイルは見つかりませんでした。'
    elif (( dry_run )); then
        echo "${found} 個見つかりました（削除していません）。"
    else
        echo "${deleted} 個削除しました。"
    fi
    if (( failed > 0 )); then
        echo "${failed} 個は削除できませんでした（上のエラーを確認してください）。" >&2
        exit 1
    fi
}

main "$@"
