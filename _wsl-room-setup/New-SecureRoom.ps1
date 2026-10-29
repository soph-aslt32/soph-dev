#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code を安全に動かすための、隔離された WSL2 の「部屋」を作成します。

.DESCRIPTION
    Linux のユーザー名と Windows のユーザーフォルダ名は、あらかじめ room.conf に書いておきます。
    次の作業を順番に自動で行います。
      1. 前提条件の確認（WSL、VS Code の WSL 拡張機能、設定ファイル room.conf）
      2. ディストリビューション名と部屋の名前の質問
      3. wsl --install による部屋の作成（room.conf の linux_user と同じユーザー名と、パスワードをご自身で入力します）
      4. 部屋の中での設定（root 用の設定 → 再起動 → マウント設定 → 一般ユーザー用の設定 → 再起動）
      5. 自動検証（verify-room.sh）

    部屋をすでに作ってある場合は -Resume（設定のやり直し）や -VerifyOnly（検証だけ）を使います。
    このスクリプトが部屋を削除すること（wsl --unregister）はありません。

.PARAMETER Distro
    インストールするディストリビューション名（wsl -l -o の NAME 列）。省略すると質問します。

.PARAMETER RoomName
    部屋の名前（半角英小文字・数字・ハイフン）。省略すると質問します。

.PARAMETER ConfigPath
    設定ファイルのパス。省略すると、このスクリプトと同じフォルダの room.conf を使います。

.PARAMETER Resume
    途中で止まった部屋に対して、作成以外の手順をもう一度実行します（部屋は消しません）。

.PARAMETER VerifyOnly
    既存の部屋に対して、自動検証だけを実行します。

.PARAMETER DryRun
    何も変更せず、実行する予定の内容だけを表示します。

.EXAMPLE
    .\New-SecureRoom.ps1
    質問に答えながら、新しい部屋を作ります。

.EXAMPLE
    .\New-SecureRoom.ps1 -RoomName dev -Resume
    途中で止まった部屋「dev」の設定を、続きからやり直します。

.EXAMPLE
    .\New-SecureRoom.ps1 -RoomName dev -VerifyOnly
    部屋「dev」の自動検証だけを実行します。
#>
[CmdletBinding()]
param(
    [string]$Distro,
    [string]$RoomName,
    [string]$ConfigPath,
    [switch]$Resume,
    [switch]$VerifyOnly,
    [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# =============================================================================
# 定数
# =============================================================================

# 部屋の中でスクリプトを置く場所（root 所有にして、部屋の一般ユーザーや Claude が書き換えられないようにする）
$script:InstallDir = '/usr/local/lib/wsl-room-setup'

# 部屋の中へコピーするファイル（room.conf は -ConfigPath のファイルをこの名前でコピーする）
$script:PayloadFiles = @(
    'lib.sh',
    'provision-root.sh',
    'provision-user.sh',
    'verify-room.sh',
    'room.conf',
    'statusline.sh',
    'templates/wsl.conf.tmpl',
    'templates/claude-settings.json.tmpl'
)

# 入力チェック用の正規表現（lib.sh と同じ規則）
$script:ReRoomName  = '^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$'
$script:ReLinuxUser = '^[a-z_][a-z0-9_-]{0,31}$'
$script:ReWinUser   = '^[A-Za-z0-9._-]+$'
$script:ReDomain    = '^(\*\.)?[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$'

$script:LastWslExit = 0

# =============================================================================
# 表示
# =============================================================================

function Write-Step([string]$Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "  [完了] $Text" -ForegroundColor Green }
function Write-Info([string]$Text) { Write-Host "  $Text" }
function Write-Note([string]$Text) { Write-Host "  [注意] $Text" -ForegroundColor Yellow }
function Write-DryRun([string]$Text) { Write-Host "  [dry-run] $Text" -ForegroundColor DarkGray }

# 何が起きたか（Message）と、次に何をすればよいか（Hint）を持たせて停止する
function Stop-Setup {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string[]]$Hint = @()
    )
    $ex = New-Object System.Exception $Message
    $ex.Data['Hint'] = $Hint
    throw $ex
}

# =============================================================================
# wsl.exe の呼び出し
# =============================================================================

# wsl.exe を実行して、標準出力を行の配列で返す（画面には表示しない）。終了コードは $script:LastWslExit に入る。
function Invoke-WslCapture {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    # Windows PowerShell 5.1 では、Stop のままだと wsl.exe が標準エラーに書いただけで止まってしまうため
    $ErrorActionPreference = 'Continue'
    $output = & wsl.exe @Arguments 2>$null
    $script:LastWslExit = $LASTEXITCODE
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($output)) {
        if ($null -eq $item) { continue }
        # 古い WSL は WSL_UTF8 を無視して UTF-16 で出力するため、混ざった NUL 文字を取り除く
        $lines.Add((([string]$item) -replace "`0", '').TrimEnd())
    }
    return ,$lines.ToArray()
}

# Invoke-WslCapture を実行し、失敗したら停止する
function Invoke-WslChecked {
    param([Parameter(Mandatory = $true)][string[]]$Arguments, [Parameter(Mandatory = $true)][string]$What)
    $null = Invoke-WslCapture $Arguments
    if ($script:LastWslExit -ne 0) {
        Stop-Setup "$What に失敗しました（終了コード $($script:LastWslExit)）。" @("実行したコマンド: wsl.exe $($Arguments -join ' ')")
    }
}

# wsl.exe を、この画面にそのままつないで実行する（入力が必要なものや、進み具合を表示したいもの）。終了コードを返す。
function Start-Wsl {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $p = Start-Process -FilePath 'wsl.exe' -ArgumentList $Arguments -NoNewWindow -PassThru
    $null = $p.Handle   # これを先に取っておかないと、終了コードが取れないことがある
    $p.WaitForExit()
    return $p.ExitCode
}

# =============================================================================
# 前提条件の確認
# =============================================================================

function Test-WslAvailable {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Stop-Setup 'wsl.exe が見つかりません。' @('WSL をインストールしてください（管理者の PowerShell で: wsl --install）。')
    }
    $null = Invoke-WslCapture @('--version')
    if ($script:LastWslExit -ne 0) {
        Stop-Setup 'wsl --version が失敗しました。WSL が古いか、正しくインストールされていません。' @(
            'PowerShell で wsl --update を実行して、WSL を新しくしてください。')
    }
}

# room.conf の windows_user から、VS Code の拡張機能フォルダ（部屋に見せるフォルダ）の場所を決める
function Get-VSCodeExtensionsDir {
    return "C:\Users\$($script:Conf.WindowsUser)\.vscode\extensions"
}

function Test-VSCodeWslExtension {
    $extDir = Get-VSCodeExtensionsDir
    $found = @()
    if (Test-Path -LiteralPath $extDir -PathType Container) {
        $found = @(Get-ChildItem -LiteralPath $extDir -Directory |
            Where-Object { $_.Name -match '^ms-vscode-remote\.remote-wsl-\d' })
    }
    if ($found.Count -gt 0) { return }
    $hint = @(
        'room.conf の windows_user が、C:\Users の中にある自分のフォルダ名と同じか確認してください。',
        'VS Code の WSL 拡張機能が入っていない場合は、次のコマンドでインストールしてから、もう一度実行してください:',
        '  code --install-extension ms-vscode-remote.remote-wsl')
    if (Test-Path -LiteralPath "C:\Users\$($script:Conf.WindowsUser)\.vscode-insiders") {
        $hint += 'VS Code Insiders には対応していません。通常版の VS Code に拡張機能を入れてください。'
    }
    Stop-Setup "VS Code の WSL 拡張機能が見つかりません（$extDir）。" $hint
}

function Get-LocalPayloadPath([string]$Rel) {
    if ($Rel -eq 'room.conf') { return $script:ConfigFile }
    return Join-Path $script:ScriptRoot ($Rel.Replace('/', '\'))
}

# 部屋へコピーするファイルがそろっていて、改行コードが LF・BOM なしであることを確認する
function Test-PayloadFiles {
    foreach ($rel in $script:PayloadFiles) {
        if ($rel -eq 'room.conf') { continue }   # room.conf は Windows で編集される前提なので、部屋の中で CRLF も受け付ける
        $path = Get-LocalPayloadPath $rel
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Stop-Setup "必要なファイルが見つかりません: $path" @('wsl-room-setup フォルダの中身を、すべてそろえてから実行してください。')
        }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            Stop-Setup "$rel の先頭に BOM が付いています。" @('Linux 側で使うファイルは「UTF-8（BOM なし）」で保存してください。README の「トラブルシューティング」を参照してください。')
        }
        if ([Array]::IndexOf($bytes, [byte]13) -ge 0) {
            Stop-Setup "$rel の改行コードが CRLF（Windows 形式）になっています。" @('Linux 側で使うファイルは改行コードが LF でなければなりません。README の「トラブルシューティング」を参照してください。')
        }
    }
}

# room.conf を読んで内容を確認する。部屋を作る前に書き間違いに気づけるようにするための事前チェック。
# 規則は lib.sh の load_room_conf と同じ（変えるときは両方）。
function Read-RoomConf {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-Setup "設定ファイルが見つかりません: $Path"
    }
    try {
        $text = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false, $true)))
    } catch {
        Stop-Setup "設定ファイル $Path を読めません。UTF-8 で保存されていない可能性があります。" @(
            'メモ帳などで開き、文字コードを UTF-8 にして保存し直してください。')
    }
    $text = $text.TrimStart([char]0xFEFF)

    $linuxUser = ''
    $windowsUser = ''
    $domains = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $lineNo = 0
    foreach ($raw in ($text -split "`r?`n")) {
        $lineNo++
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -cmatch '^([a-z_]+)\s*=(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()
        } else {
            Stop-Setup "設定ファイルの $lineNo 行目の書き方が正しくありません: $line" @('「名前 = 値」の形で書いてください。')
        }
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ($seen.ContainsKey($key)) { Stop-Setup "設定ファイルの $lineNo 行目: $key が 2 回書かれています。" }
        $seen[$key] = $true

        if ($key -ceq 'linux_user') {
            if ($value -eq '') {
                Stop-Setup "設定ファイルの $lineNo 行目: linux_user が空です。" @('部屋の中で使う Linux のユーザー名を書いてください（例: taro）。')
            }
            if ($value -cnotmatch $script:ReLinuxUser) {
                Stop-Setup "設定ファイルの $lineNo 行目: linux_user が正しくありません: $value" @(
                    '半角英小文字で始まり、英小文字・数字・_・- だけを使った 32 文字以内の名前にしてください。')
            }
            $linuxUser = $value
        } elseif ($key -ceq 'windows_user') {
            if ($value -eq '') {
                Stop-Setup "設定ファイルの $lineNo 行目: windows_user が空です。" @('Windows のユーザーフォルダの名前（C:\Users\<ここ>）を書いてください。')
            }
            if ($value -cnotmatch $script:ReWinUser) {
                Stop-Setup "設定ファイルの $lineNo 行目: windows_user が正しくありません: $value" @(
                    '半角英数字と . _ - だけに対応しています（スペースや日本語を含む名前は、動作が未確認のため未対応）。')
            }
            $windowsUser = $value
        } elseif ($key -ceq 'allowed_domains') {
            foreach ($part in $value.Split(',')) {
                $d = $part.Trim()
                if ($d -eq '') { continue }
                if ($d -eq '*') {
                    Stop-Setup "設定ファイルの $lineNo 行目: allowed_domains に「*」は使えません。" @(
                        '「*」はすべてのドメインへの通信を許可してしまい、サンドボックスの意味がなくなるためです。')
                }
                if ($d -cnotmatch $script:ReDomain) {
                    Stop-Setup "設定ファイルの $lineNo 行目: ドメイン名として正しくありません: $d" @(
                        '例: registry.npmjs.org や *.example.com のように書いてください（https:// やパスは不要です）。')
                }
                if (-not $domains.Contains($d)) { $domains.Add($d) }
            }
        } else {
            Stop-Setup "設定ファイルの $lineNo 行目: 知らない項目名です: $key" @('使える項目は linux_user、windows_user、allowed_domains です。')
        }
    }
    foreach ($required in @('linux_user', 'windows_user', 'allowed_domains')) {
        if (-not $seen.ContainsKey($required)) {
            Stop-Setup "設定ファイルに $required がありません。" @(
                '同じフォルダにある元の room.conf を見本にして書き足してください。',
                '通信を許可するドメインが無い場合も「allowed_domains =」と空で書いてください。')
        }
    }
    return [pscustomobject]@{
        LinuxUser      = $linuxUser
        WindowsUser    = $windowsUser
        AllowedDomains = $domains.ToArray()
    }
}

# =============================================================================
# 部屋の名前など
# =============================================================================

# wsl -l -o の出力から、ディストリビューション名（NAME 列）を取り出す
function Get-OnlineDistroNames([string[]]$Lines) {
    $names = New-Object System.Collections.Generic.List[string]
    $afterHeader = $false
    foreach ($l in $Lines) {
        if (-not $afterHeader) {
            if ($l -match '^\s*NAME\s+FRIENDLY NAME') { $afterHeader = $true }
            continue
        }
        if ($l -match '^\s*(\S+)\s+\S') { $names.Add($Matches[1]) }
    }
    if (-not $afterHeader) {
        # 見出しが見つからない（表示の言語が違うなど）ときは、2 つ以上の空白で区切られた表の行だけを拾う
        foreach ($l in $Lines) {
            if ($l -match '^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s{2,}\S') { $names.Add($Matches[1]) }
        }
    }
    return ,$names.ToArray()
}

function Select-Distro([string]$Current) {
    $lines = Invoke-WslCapture @('--list', '--online')
    if ($script:LastWslExit -ne 0) {
        Stop-Setup 'インストールできるディストリビューションの一覧を取得できませんでした。' @('インターネットに接続されているか確認してください。')
    }
    $names = Get-OnlineDistroNames $lines
    if (-not $Current) {
        Write-Host ''
        Write-Info 'インストールできるディストリビューション:'
        foreach ($l in $lines) { Write-Info "  $l" }
        $Current = (Read-Host '  使うディストリビューションの名前を、NAME 列からそのまま入力してください（例: Ubuntu-26.04）').Trim()
    }
    $match = $null
    foreach ($n in $names) { if ($n -ieq $Current) { $match = $n; break } }
    if (-not $match) {
        Stop-Setup "「$Current」は、インストールできるディストリビューションの一覧にありません。" @('wsl -l -o で表示される NAME 列の名前を入力してください。')
    }
    if ($match -notlike 'Ubuntu*') {
        Stop-Setup "このスクリプトは Ubuntu でのみ動作を確認しています（指定: $match）。" @('Ubuntu-26.04 などの Ubuntu を選んでください。')
    }
    return $match
}

# 登録済みの部屋（ディストリビューション）の名前の一覧
function Get-RoomNames {
    $lines = Invoke-WslCapture @('--list', '--quiet')
    if ($script:LastWslExit -ne 0) { return ,@() }   # 部屋が 1 つも無いときもここに来る
    return ,@($lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function Test-RoomExists([string]$Name) {
    foreach ($n in (Get-RoomNames)) { if ($n -ieq $Name) { return $true } }
    return $false
}

function Select-RoomName([string]$Current, [bool]$MustExist) {
    if (-not $Current) {
        $Current = (Read-Host '  部屋の名前を入力してください（半角英小文字・数字・ハイフン。例: dev）').Trim()
    }
    if ($Current -cnotmatch $script:ReRoomName) {
        Stop-Setup "部屋の名前「$Current」は使えません。" @('半角英小文字・数字・ハイフンだけで、32 文字以内にしてください（先頭と末尾はハイフン以外）。')
    }
    $exists = Test-RoomExists $Current
    if ($MustExist -and -not $exists) {
        Stop-Setup "部屋「$Current」が見つかりません。" @('PowerShell で wsl -l -v を実行して、部屋の名前を確認してください。')
    }
    if (-not $MustExist -and $exists) {
        Stop-Setup "部屋「$Current」はすでにあります。" @(
            '別の名前を指定してください。',
            '途中で止まった部屋の続きなら、-Resume を付けて実行してください:',
            "  .\New-SecureRoom.ps1 -RoomName $Current -Resume",
            '作り直したい場合は、部屋の中身がすべて消えることを理解したうえで、ご自身で wsl --unregister を実行してください。')
    }
    return $Current
}

function Show-Summary([bool]$Creating) {
    Write-Step '次の内容で進めます'
    if ($Creating) { Write-Info "ディストリビューション : $($script:DistroName)" }
    Write-Info "部屋の名前             : $($script:Room)"
    if ($VerifyOnly) { $mode = '自動検証だけを実行する' }
    elseif ($Resume) { $mode = '既存の部屋の設定をやり直す（部屋は消しません）' }
    else { $mode = '新しく作る' }
    Write-Info "行うこと               : $mode"
    Write-Info "Linux のユーザー名     : $($script:Conf.LinuxUser)"
    Write-Info "部屋に見せるフォルダ   : $(Get-VSCodeExtensionsDir)（読み取り専用）"
    if ($script:Conf.AllowedDomains.Count -gt 0) { $domains = $script:Conf.AllowedDomains -join ', ' } else { $domains = '（なし）' }
    Write-Info "通信を許可するドメイン : $domains"
    Write-Info "設定ファイル           : $($script:ConfigFile)"
    if ($Resume) {
        Write-Note 'この部屋を途中で 2 回再起動します。部屋の中で動いているもの（Claude Code やターミナル）はすべて終了します。'
    }
}

# =============================================================================
# 部屋の作成と設定
# =============================================================================

function New-Room {
    Write-Step "部屋「$($script:Room)」を作成します（$($script:DistroName)）"
    if ($DryRun) { Write-DryRun "wsl.exe --install $($script:DistroName) --name $($script:Room)"; return }
    Write-Info 'このあと、部屋の中で使う Linux のユーザー名とパスワードを聞かれます。'
    Write-Info "  ・ユーザー名: room.conf の linux_user と同じ「$($script:Conf.LinuxUser)」を入力してください。"
    Write-Info '  ・パスワード: 入力しても画面には何も表示されませんが、正常です。'
    Write-Info '    sudo（管理者の権限）を使うときに必要な大切なパスワードです。忘れないでください。'
    Write-Info '    Claude Code を含め、ほかの誰にも教えないでください。'
    Write-Info '入力が終わって「ユーザー名@...:~$」のような表示が出たら、exit と入力して Enter を押してください。'
    Write-Info 'そのあとは、このスクリプトが自動で続きを進めます。'
    $null = Read-Host '  準備ができたら Enter を押してください'

    $code = Start-Wsl @('--install', $script:DistroName, '--name', $script:Room)
    $resumeHint = @(
        '上に表示されたメッセージを確認してください。',
        '部屋が作られていてユーザー名・パスワードの設定も終わっている場合は、次のコマンドで続きから進められます:',
        "  .\New-SecureRoom.ps1 -RoomName $($script:Room) -Resume")
    if ($code -ne 0) { Stop-Setup "部屋の作成（wsl --install）が正常に終わりませんでした（終了コード $code）。" $resumeHint }
    if (-not (Test-RoomExists $script:Room)) { Stop-Setup "部屋「$($script:Room)」が作成されていません。" $resumeHint }
    Write-Ok "部屋「$($script:Room)」を作成しました。"
}

function Test-RoomIsWsl2 {
    $version = $null
    foreach ($l in (Invoke-WslCapture @('--list', '--verbose'))) {
        if ($l -match '^\s*\*?\s*(\S+)\s+.*\s(\d)\s*$' -and $Matches[1] -ieq $script:Room) { $version = $Matches[2] }
    }
    if ($version -ne '2') {
        Stop-Setup "部屋「$($script:Room)」が WSL2 で動いていません（VERSION: $version）。" @(
            'このスクリプトは WSL2 専用です。',
            "PowerShell で wsl --set-version $($script:Room) 2 を実行してから、-Resume を付けて続けてください。")
    }
    Write-Ok '部屋は WSL2 で動いています。'
}

# 部屋に入ったときのユーザーが、room.conf の linux_user と同じであることを確かめる
function Test-RoomDefaultUser {
    $expected = $script:Conf.LinuxUser
    $out = Invoke-WslCapture @('-d', $script:Room, '--cd', '/', '--exec', 'id', '-un')
    $user = ''
    if ($out.Count -gt 0) { $user = $out[$out.Count - 1].Trim() }
    if ($script:LastWslExit -ne 0 -or $user -eq '') {
        Stop-Setup "部屋「$($script:Room)」のユーザーを確認できませんでした。"
    }
    if ($user -eq 'root') {
        Stop-Setup "部屋「$($script:Room)」に入ると root になる状態です。" @(
            'ユーザー名とパスワードの作成が終わっていない可能性があります。',
            'いちばん確実なのは部屋を作り直すことです（中身はすべて消えます）:',
            "  wsl --unregister $($script:Room)",
            '  そのあと、このスクリプトをもう一度実行してください。')
    }
    if ($user -cne $expected) {
        Stop-Setup "部屋「$($script:Room)」のユーザー（$user）が、room.conf の linux_user（$expected）と違います。" @(
            '部屋を作るときに入力したユーザー名と、room.conf の linux_user をそろえる必要があります。',
            'room.conf のほうを直す場合は、直してから -Resume を付けて実行してください。',
            '部屋を作り直す場合は、中身がすべて消えることを理解したうえで、ご自身で wsl --unregister を実行してください。')
    }
    Write-Ok "部屋のユーザーが room.conf の linux_user（$expected）と一致しました。"
}

# 部屋の中の $InstallDir にスクリプト一式を置く。
# PowerShell 5.1 は外部コマンドへ文字列を渡すときに日本語や改行コードを変えてしまうことがあるため、
# 中身を base64（英数字だけ）にして渡し、部屋の中で元に戻す。最後にハッシュ値で一致を確かめる。
function Copy-PayloadToRoom {
    Write-Step "設定スクリプトを部屋の中（$($script:InstallDir)）に置きます"
    if ($DryRun) { Write-DryRun "スクリプト一式と room.conf を部屋の中の $($script:InstallDir) にコピーし、ハッシュ値を照合する"; return }
    $base = @('-d', $script:Room, '-u', 'root', '--cd', '/', '--exec')
    Invoke-WslChecked ($base + @('rm', '-rf', '--', $script:InstallDir)) '古いスクリプトの削除'
    Invoke-WslChecked ($base + @('install', '-d', '-m', '755', '-o', 'root', '-g', 'root', $script:InstallDir, "$($script:InstallDir)/templates")) 'フォルダの作成'

    foreach ($rel in $script:PayloadFiles) {
        $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Get-LocalPayloadPath $rel)))
        $wslArgs = $base + @('bash', '-c', 'base64 -d -i > $1', '_', "$($script:InstallDir)/$rel")
        $code = Send-TextToWsl -Text $b64 -Arguments $wslArgs
        if ($code -ne 0) { Stop-Setup "$rel を部屋の中にコピーできませんでした（終了コード $code）。" }
    }

    $paths = @($script:PayloadFiles | ForEach-Object { "$($script:InstallDir)/$_" })
    $out = Invoke-WslCapture ($base + @('sha256sum', '--') + $paths)
    if ($script:LastWslExit -ne 0) { Stop-Setup 'コピーしたファイルのハッシュ値を計算できませんでした。' }
    $remote = @{}
    foreach ($l in $out) { if ($l -match '^([0-9a-f]{64})\s+\*?(.+)$') { $remote[$Matches[2]] = $Matches[1] } }
    foreach ($rel in $script:PayloadFiles) {
        $expected = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-LocalPayloadPath $rel)).Hash.ToLowerInvariant()
        if ($remote["$($script:InstallDir)/$rel"] -ne $expected) {
            Stop-Setup "部屋の中にコピーした $rel の内容が、元のファイルと一致しません。" @('もう一度実行してください。繰り返す場合は Claude Code に相談してください。')
        }
    }
    Write-Ok "$($script:PayloadFiles.Count) 個のファイルを置き、内容が一致することを確認しました。"
}

# 文字列を標準入力として wsl.exe に渡して実行し、終了コードを返す
function Send-TextToWsl {
    param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $null = $Text | & wsl.exe @Arguments 2>$null
    return $LASTEXITCODE
}

# 部屋の中のスクリプトを実行する。$User を空にすると、部屋に入ったときの既定のユーザーで実行する。
function Invoke-RoomScript {
    param(
        [string]$User,
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [string[]]$ScriptArgs = @(),
        [Parameter(Mandatory = $true)][string]$What
    )
    $wslArgs = @('-d', $script:Room)
    if ($User) { $wslArgs += @('-u', $User) }
    if ($User -eq 'root') { $cd = '/' } else { $cd = '~' }
    $wslArgs += @('--cd', $cd, '--exec', 'bash', "$($script:InstallDir)/$ScriptName")
    $wslArgs += $ScriptArgs
    Write-Step $What
    if ($DryRun) { Write-DryRun ('wsl.exe ' + ($wslArgs -join ' ')); return 0 }
    return (Start-Wsl $wslArgs)
}

function Invoke-ProvisionStep {
    param([string]$User, [string]$ScriptName, [string[]]$ScriptArgs = @(), [string]$What)
    $code = Invoke-RoomScript -User $User -ScriptName $ScriptName -ScriptArgs $ScriptArgs -What $What
    if ($code -ne 0) {
        Stop-Setup "「$What」に失敗しました（終了コード $code）。" @(
            '上に表示されたメッセージを確認してください。',
            '原因を取り除いたら、次のコマンドで続きからやり直せます（部屋は消えません）:',
            "  .\New-SecureRoom.ps1 -RoomName $($script:Room) -Resume")
    }
}

# 部屋を停止して起動し直す（wsl.conf の変更は、これをしないと反映されない）
function Restart-Room {
    Write-Step "部屋「$($script:Room)」を再起動します（設定を反映させるため）"
    if ($DryRun) { Write-DryRun "wsl.exe --terminate $($script:Room) → 停止を確認 → 起動"; return }
    # すでに止まっている場合の終了コードに頼らず、下の一覧で停止を確かめる
    $null = Invoke-WslCapture @('--terminate', $script:Room)
    $deadline = (Get-Date).AddSeconds(60)
    while ($true) {
        $running = $false
        foreach ($n in (Invoke-WslCapture @('--list', '--running', '--quiet'))) {
            if ($n.Trim() -ieq $script:Room) { $running = $true }
        }
        if (-not $running) { break }
        if ((Get-Date) -gt $deadline) {
            Stop-Setup '部屋が 60 秒たっても停止しませんでした。' @("PowerShell で wsl --terminate $($script:Room) を実行してから、-Resume を付けてやり直してください。")
        }
        Start-Sleep -Seconds 1
    }
    Write-Info '停止したことを確認しました。起動します...'
    $code = Start-Wsl @('-d', $script:Room, '--cd', '/', '--exec', 'true')
    if ($code -ne 0) { Stop-Setup "部屋「$($script:Room)」を起動できませんでした（終了コード $code）。" }
    Write-Ok '再起動しました。'
}

function Invoke-Verify {
    $rootCode = Invoke-RoomScript -User 'root' -ScriptName 'verify-room.sh' -ScriptArgs @('--root') `
        -What '自動検証（root の権限で行う項目）'
    # 「部屋に入ったときのユーザーが正しいか」も確かめるため、ユーザーを指定せずに実行する
    $userCode = Invoke-RoomScript -User '' -ScriptName 'verify-room.sh' `
        -What '自動検証（部屋に入ったときのユーザーで行う項目）'
    if ($DryRun) { return }
    if ($rootCode -ne 0 -or $userCode -ne 0) {
        Stop-Setup '自動検証で FAIL になった項目があります。' @(
            '上の [FAIL] の行と、その下の説明を確認してください。',
            '直したあと、次のコマンドで検証だけをやり直せます:',
            "  .\New-SecureRoom.ps1 -RoomName $($script:Room) -VerifyOnly")
    }
    Write-Ok '自動検証で FAIL はありませんでした（SKIP の項目は、ログイン後に手動で確認します）。'
}

function Show-NextSteps {
    $room = $script:Room
    $user = $script:LinuxUser
    Write-Step '部屋の準備ができました。続けて次の作業をしてください（README の「構築後の作業」と同じです）'
    Write-Info '1. Claude Code にログインする'
    Write-Info "     wsl -d $room --cd ~"
    Write-Info '     claude'
    Write-Info '   表示された URL をコピーして、Windows のブラウザに貼り付けてください（ブラウザは自動では開きません）。'
    Write-Info '2. README の「ログイン後の手動確認」を行う（claude doctor やサンドボックスの動作確認）'
    Write-Info '3. VS Code で開くときは、Windows の PowerShell から:'
    Write-Info "     code --remote wsl+$room /home/$user/projects/<プロジェクト名>"
    Write-Info '   Claude Code は必ず ~/projects/<プロジェクト名> の中で起動してください。'
}

# =============================================================================
# 本体
# =============================================================================

function Invoke-Main {
    Write-Host ''
    Write-Host '=== Claude Code 用の隔離された WSL の部屋をつくります（wsl-room-setup）===' -ForegroundColor Cyan
    if ($DryRun) { Write-Note 'ドライランです。何も変更せず、実行する予定の内容だけを表示します。' }
    if ($Resume -and $VerifyOnly) { Stop-Setup '-Resume と -VerifyOnly は同時に指定できません。' }
    $creating = -not ($Resume -or $VerifyOnly)

    Write-Step '前提条件を確認します'
    Test-WslAvailable
    Write-Ok 'WSL が使えます。'
    Test-PayloadFiles
    Write-Ok 'スクリプト一式がそろっています。'
    $script:Conf = Read-RoomConf $script:ConfigFile
    $script:LinuxUser = $script:Conf.LinuxUser
    Write-Ok "設定ファイルを確認しました（$($script:ConfigFile)）。"
    Test-VSCodeWslExtension
    Write-Ok "VS Code の WSL 拡張機能があります（$(Get-VSCodeExtensionsDir)）。"

    Write-Step '部屋の名前などを決めます'
    if ($creating) { $script:DistroName = Select-Distro $Distro }
    $script:Room = Select-RoomName $RoomName (-not $creating)

    Show-Summary $creating
    if (-not $DryRun) {
        $answer = Read-Host '  この内容で進めますか？ 進める場合は y を入力して Enter（それ以外は中止）'
        if ($answer.Trim() -notin @('y', 'Y', 'yes')) {
            Write-Info '中止しました。何も変更していません。'
            return
        }
    }

    if ($creating) { New-Room }
    if (-not ($DryRun -and $creating)) {
        Test-RoomIsWsl2
        Test-RoomDefaultUser
    }

    Copy-PayloadToRoom
    if (-not $VerifyOnly) {
        Invoke-ProvisionStep -User 'root' -ScriptName 'provision-root.sh' `
            -ScriptArgs @('--phase', 'base') `
            -What '部屋の基本設定（root）: パッケージ、wsl.conf、AppArmor'
        Restart-Room
        Invoke-ProvisionStep -User 'root' -ScriptName 'provision-root.sh' -ScriptArgs @('--phase', 'mount') `
            -What 'VS Code 拡張フォルダの読み取り専用マウント（root）'
        Invoke-ProvisionStep -User $script:LinuxUser -ScriptName 'provision-user.sh' `
            -What "一般ユーザーの設定（$($script:LinuxUser)）: Claude Code、PATH、settings.json、ステータスライン、~/projects"
        Restart-Room
    }
    Invoke-Verify
    if (-not $DryRun -and -not $VerifyOnly) { Show-NextSteps }
}

$script:ScriptRoot = $PSScriptRoot
if ($ConfigPath) {
    $script:ConfigFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)
} else {
    $script:ConfigFile = Join-Path $script:ScriptRoot 'room.conf'
}

$exitCode = 0
$savedConsoleEncoding = $null
$savedWslUtf8 = $env:WSL_UTF8
try {
    # wsl.exe の出力を UTF-8 にそろえる（既定の UTF-16 だと文字列の比較がうまくいかない）
    $env:WSL_UTF8 = '1'
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    try {
        $savedConsoleEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = $utf8NoBom
    } catch {
        $savedConsoleEncoding = $null
    }
    $OutputEncoding = $utf8NoBom
    Invoke-Main
} catch {
    $exitCode = 1
    $ex = $_.Exception
    Write-Host ''
    Write-Host "[エラー] $($ex.Message)" -ForegroundColor Red
    if ($ex.Data.Contains('Hint')) {
        foreach ($h in $ex.Data['Hint']) { Write-Host "        $h" }
    } else {
        Write-Host '        予期しないエラーです。次の表示を Claude Code に伝えると、原因を調べられます:'
        Write-Host "        $($_.InvocationInfo.PositionMessage)"
    }
} finally {
    if ($null -ne $savedConsoleEncoding) {
        try { [Console]::OutputEncoding = $savedConsoleEncoding } catch { }
    }
    $env:WSL_UTF8 = $savedWslUtf8
}
exit $exitCode
