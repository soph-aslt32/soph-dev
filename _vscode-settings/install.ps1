<#
  VS Code 環境セットアップ
    - 拡張機能 (.vsix) を追加インストール（既存の拡張機能はそのまま）
    - settings.json / keybindings.json を配布版で上書き
  以下をすべて同じフォルダに置き、install.bat から実行する。
    install.bat / install.ps1 / *.vsix（1つだけ。ファイル名は自由） / settings.json / keybindings.json

  ※ このファイルは「UTF-8 (BOM 付き)」で保存すること。
     BOM なしだと Windows PowerShell 5.1 が Shift-JIS として読み、日本語が化けて動かない。
#>

$ErrorActionPreference = 'Stop'
$success = $false
$summary = New-Object System.Collections.Generic.List[string]   # 最後に表示する結果一覧

# ----- ログ出力（例: 10:15:32 [INFO]  メッセージ   ※ WARN / ERROR は行全体を色付け）
function Write-Log {
    param([string]$Level, [string]$Message)
    $color = @{ INFO = 'Blue'; OK = 'Green'; WARN = 'Yellow'; ERROR = 'Red' }[$Level]
    Write-Host (Get-Date -Format 'HH:mm:ss ') -NoNewline -ForegroundColor DarkGray
    Write-Host ("[$Level]".PadRight(8)) -NoNewline -ForegroundColor $color
    if ($Level -in 'WARN', 'ERROR') { Write-Host $Message -ForegroundColor $color }
    else                            { Write-Host $Message }
}
function Write-Step {
    param([string]$Title)
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
}

# ===== メイン処理 ==============================================================
try {
    Write-Log INFO "実行ユーザー : $env:USERNAME"
    Write-Log INFO "配布フォルダ : $PSScriptRoot"

    # ---- 1. 配布ファイルの確認（途中まで適用されるのを防ぐため、先にまとめて確認）
    Write-Step '[1/3] 配布ファイルの確認'
    # 同じフォルダの .vsix を探す（1つだけのときのみ続行）
    $vsixFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.vsix' -File)
    if ($vsixFiles.Count -eq 0) { throw "配布フォルダに .vsix ファイルがありません: $PSScriptRoot" }
    if ($vsixFiles.Count -gt 1) { throw "配布フォルダに .vsix ファイルが複数あります。1つだけにしてください: $($vsixFiles.Name -join ', ')" }
    $vsix   = $vsixFiles[0].FullName
    $config = 'settings.json', 'keybindings.json' | ForEach-Object { Join-Path $PSScriptRoot $_ }
    foreach ($f in @($vsix) + $config) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "配布ファイルが見つかりません: $f" }
        Write-Log OK $f
    }

    # ---- 2. 拡張機能のインストール
    Write-Step '[2/3] 拡張機能のインストール'
    # code.cmd を 標準のインストール先 → PATH の順に探す
    $code = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"   # ユーザーインストール（既定）
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd"            # システムインストール
        (Get-Command code.cmd -ErrorAction SilentlyContinue | Select-Object -First 1).Path
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $code) { throw 'VS Code が見つかりません。VS Code をインストールしてから再実行してください。' }
    Write-Log INFO "VS Code : $code"

    if (Get-Process -Name Code -ErrorAction SilentlyContinue) {
        Write-Log WARN 'VS Code が起動中です。拡張機能は VS Code の再起動後に有効になります。'
    }

    # --force : 同じ拡張機能が既に入っていても配布版で入れ直す
    Write-Log INFO "実行 : code --install-extension `"$vsix`" --force"
    $ErrorActionPreference = 'Continue'                  # CLI の stderr 出力で止まらないようにする
    $out = & $code --install-extension $vsix --force 2>&1
    $rc  = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $out | ForEach-Object { Write-Host "                 | $_" -ForegroundColor DarkGray }   # CLI の出力（灰色）
    if ($rc -ne 0) { throw "拡張機能のインストールに失敗しました（終了コード: $($rc)）" }

    $vsixName = Split-Path -Leaf $vsix
    Write-Log OK "$vsixName をインストールしました"
    $summary.Add("拡張機能 : $vsixName をインストール")

    # ---- 3. 設定ファイルの上書き
    Write-Step '[3/3] 設定ファイルの上書き'
    $userDir = Join-Path $env:APPDATA 'Code\User'
    New-Item -ItemType Directory -Path $userDir -Force | Out-Null     # 未起動の VS Code 用（既にあれば何もしない）

    foreach ($src in $config) {
        $name   = Split-Path -Leaf $src
        $dst    = Join-Path $userDir $name
        $action = if (Test-Path -LiteralPath $dst) { '上書き' } else { '新規作成' }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Log OK "$name を$action : $dst"
        $summary.Add("$name : $action")
    }

    $success = $true
}
catch {
    $errorMessage = $_.Exception.Message
    Write-Log ERROR $errorMessage
}

# ===== 結果一覧 ================================================================
Write-Step '結果'
foreach ($s in $summary) { Write-Log OK $s }

if ($success) {
    Write-Host "`nセットアップが完了しました。" -ForegroundColor Green
    exit 0
}
Write-Log ERROR $errorMessage
Write-Host "`nセットアップに失敗しました。上の [ERROR] の内容を確認してください。" -ForegroundColor Red
exit 1