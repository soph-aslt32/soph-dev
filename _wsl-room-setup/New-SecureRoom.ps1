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
      4. 部屋の中での設定（root 用の設定 → 再起動 → マウント設定 → 一般ユーザー用の設定
         → GitHub の設定とクローン（room-github.conf に記入があるときだけ） → 再起動）
      5. 自動検証（verify-room.sh）

    room-github.conf（room.conf と同じフォルダ）は、room.conf と違い部屋の中へコピーしません。
    中身（特に PAT）は、このスクリプトが確認したうえで標準入力で部屋に渡し、PAT は部屋の
    ~/.git-credentials（Claude Code からは読めないように設定してある）にだけ保存します。

    部屋をすでに作ってある場合は -Resume（設定のやり直し）や -VerifyOnly（検証だけ）を使います。
    このスクリプトが部屋を削除すること（wsl --unregister）はありません。

    -Interactive（room-setup-wizard.cmd から起動したとき）では、room.conf と room-github.conf を読む代わりに、
    同じ内容をこの画面で順に聞きます（行うこと・ドライランにするかも聞きます）。入力した値はファイルに保存しません。
    room.conf にあたる内容はメモリ上で組み立てて部屋の中へコピーし、GitHub の情報は上と同じく標準入力で渡します。
    部屋の中（\\wsl.localhost\... など）にあるこのスクリプトを -Interactive で実行しようとすると、停止します。

.PARAMETER Distro
    インストールするディストリビューション名（wsl -l -o の NAME 列）。省略すると質問します。

.PARAMETER RoomName
    部屋の名前（半角英小文字・数字・ハイフン）。省略すると質問します。

.PARAMETER ConfigPath
    設定ファイルのパス。省略すると、このスクリプトと同じフォルダの room.conf を使います。

.PARAMETER GitHubConfigPath
    GitHub の設定ファイルのパス。省略すると、room.conf と同じフォルダの room-github.conf を使います
    （無い場合や、すべて空欄の場合は、GitHub の設定をしません）。

.PARAMETER Resume
    途中で止まった部屋に対して、作成以外の手順をもう一度実行します（部屋は消しません）。

.PARAMETER VerifyOnly
    既存の部屋に対して、自動検証だけを実行します。

.PARAMETER DryRun
    何も変更せず、実行する予定の内容だけを表示します。

.PARAMETER Interactive
    設定ファイルを使わず、必要な値をこの画面で聞きます（room-setup-wizard.cmd はこれを付けて起動します）。
    -ConfigPath・-GitHubConfigPath とは同時に指定できません。

.EXAMPLE
    .\New-SecureRoom.ps1
    質問に答えながら、新しい部屋を作ります。

.EXAMPLE
    .\New-SecureRoom.ps1 -RoomName dev -Resume
    途中で止まった部屋「dev」の設定を、続きからやり直します。

.EXAMPLE
    .\New-SecureRoom.ps1 -RoomName dev -VerifyOnly
    部屋「dev」の自動検証だけを実行します。

.EXAMPLE
    .\New-SecureRoom.ps1 -Interactive
    設定ファイルを使わず、質問に答えながら進めます（room-setup-wizard.cmd のダブルクリックと同じ）。
#>
[CmdletBinding()]
param(
    [string]$Distro,
    [string]$RoomName,
    [string]$ConfigPath,
    [string]$GitHubConfigPath,
    [switch]$Resume,
    [switch]$VerifyOnly,
    [switch]$DryRun,
    [switch]$Interactive
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# =============================================================================
# 定数
# =============================================================================

# 部屋の中でスクリプトを置く場所（root 所有にして、部屋の一般ユーザーや Claude が書き換えられないようにする）
$script:InstallDir = '/usr/local/lib/wsl-room-setup'

# 部屋の中へコピーするファイル（room.conf は -ConfigPath のファイルをこの名前でコピーする）
# room-github.conf は PAT を含むので、ここに入れてはいけない（部屋の中の誰でも読める場所に置かれるため）
$script:PayloadFiles = @(
    'lib.sh',
    'provision-root.sh',
    'provision-user.sh',
    'provision-github.sh',
    'verify-room.sh',
    'room.conf',
    'statusline.sh',
    'delzonei.sh',
    'templates/wsl.conf.tmpl',
    'templates/claude-settings.json.tmpl'
)

# 入力チェック用の正規表現（lib.sh と同じ規則）
$script:ReRoomName  = '^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$'
$script:ReLinuxUser = '^[a-z_][a-z0-9_-]{0,31}$'
$script:ReWinUser   = '^[A-Za-z0-9._-]+$'
$script:ReDomain    = '^(\*\.)?[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$'

# room-github.conf の入力チェック用（provision-github.sh と同じ規則）
$script:ReGitHubUserNameBad = '[\x00-\x1F\x7F-\x9F<>]'   # user_name に使えない文字（制御文字と < >）
$script:ReGitHubEmail       = '^[^\s<>@]+@[^\s<>@]+$'
$script:ReGitHubPat         = '^[A-Za-z0-9_]{20,255}$'
# リポジトリの URL。末尾の .git と / は省略可（https://github.com/OWNER/REPOSITORY.git の形にそろえて使う）
$script:ReGitHubRepoUrl     = '^https://(?i:github\.com)/([A-Za-z0-9-]+)/([A-Za-z0-9._-]+?)(?:\.git)?/?$'

$script:LastWslExit = 0
$script:Conf = $null     # room.conf の内容（対話モードでは入力した内容）
$script:ConfBytes = $null   # 部屋の中へコピーする room.conf の中身（読んだ・組み立てたバイト列そのもの）
$script:GitHub = $null   # room-github.conf の内容（記入が無ければ $null。対話モードでは入力した内容）

# 対話モードの入口と、メニューの項目（やり直しの案内でも同じ名前を使う）
$script:WizardCmd = 'room-setup-wizard.cmd'
$script:WizardModeCreate = '新しい部屋を作る'
$script:WizardModeResume = '既存の部屋の設定をやり直す'
$script:WizardModeVerify = '既存の部屋の自動検証だけを行う'

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

# 入力値の誤り（何が違うか: Message、どう直すか: Hint）。値をチェックする関数は、正しければ $null、誤りならこれを返す。
# 設定ファイルを読むときは「何行目か」を付けて Stop-Setup し、対話モードでは表示して聞き直す。
function New-InputError {
    param([Parameter(Mandatory = $true)][string]$Message, [string[]]$Hint = @())
    return [pscustomobject]@{ Message = $Message; Hint = $Hint }
}

# やり直し方の案内。$Lead の {0} には「次のコマンドで」（対話モードでは「次の方法で」）が入る。$Mode は Resume か VerifyOnly。
function Get-RerunHint {
    param([Parameter(Mandatory = $true)][string]$Lead, [Parameter(Mandatory = $true)][string]$Mode, [string]$Room = $script:Room)
    if ($Interactive) {
        if ($Mode -eq 'VerifyOnly') { $label = $script:WizardModeVerify } else { $label = $script:WizardModeResume }
        return @(($Lead -f '次の方法で'), "  $($script:WizardCmd) を起動し、「$label」を選んで、部屋の名前に $Room を入力する")
    }
    return @(($Lead -f '次のコマンドで'), "  .\New-SecureRoom.ps1 -RoomName $Room -$Mode")
}

# 「-Resume を付けて実行する」の言い換え（対話モードでは、wizard を起動し直してやり直しを選ぶ）
function Get-ResumeHowTo {
    if ($Interactive) { return "$($script:WizardCmd) を起動し直して「$($script:WizardModeResume)」を選んで" }
    return '-Resume を付けて'
}

# =============================================================================
# 対話モードの画面表示と入力
# =============================================================================
# 色の使い分け:
#   Cyan     質問の印（[?]）、入力欄（>）、選択肢の番号（ほかの表示の「==>」と同じ色）
#   White    質問そのもの
#   DarkGray 質問の説明（入力の規則や例）
#   Green    Enter だけ押したときに使われる値
#   Red      入力の誤り。直し方は Yellow（[注意] と同じ色）

function Write-WizardQuestion {
    param([Parameter(Mandatory = $true)][string]$Title, [string[]]$Help = @(), [string]$Default = '')
    Write-Host ''
    Write-Host '  [?] ' -ForegroundColor Cyan -NoNewline
    Write-Host $Title -ForegroundColor White
    foreach ($h in $Help) { Write-Host "      $h" -ForegroundColor DarkGray }
    if ($Default -ne '') {
        Write-Host '      Enter だけ押すと: ' -ForegroundColor DarkGray -NoNewline
        Write-Host $Default -ForegroundColor Green
    }
}

function Write-WizardPrompt { Write-Host '  > ' -ForegroundColor Cyan -NoNewline }

# 1 行読んで、前後の空白を取り除いて返す
function Read-WizardLine {
    Write-WizardPrompt
    $v = Read-Host
    if ($null -eq $v) { Stop-Setup '入力が終わりました（標準入力が閉じられました）。' }
    return $v.Trim()
}

function Write-InputError {
    param([Parameter(Mandatory = $true)]$InputError)
    Write-Host "  [入力エラー] $($InputError.Message)" -ForegroundColor Red
    foreach ($h in $InputError.Hint) { Write-Host "      $h" -ForegroundColor Yellow }
    Write-Host '      もう一度入力してください。' -ForegroundColor DarkGray
}

# 値を 1 つ聞く。$Validate は値を受け取り、正しければ $null、誤りなら New-InputError の結果を返す。
# 正しい値が入力されるまで聞き直す。Enter だけのときは $Default（空なら「何も入力されていません」）。
function Read-WizardValue {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string[]]$Help = @(),
        [string]$Default = '',
        [Parameter(Mandatory = $true)][scriptblock]$Validate
    )
    while ($true) {
        Write-WizardQuestion $Title $Help $Default
        $v = Read-WizardLine
        if ($v -eq '') { $v = $Default }
        if ($v -eq '') {
            Write-InputError (New-InputError '何も入力されていません。')
            continue
        }
        $err = & $Validate $v
        if ($null -eq $err) { return $v }
        Write-InputError $err
    }
}

function Read-WizardYesNo {
    param([Parameter(Mandatory = $true)][string]$Title, [string[]]$Help = @(), [bool]$Default = $false)
    if ($Default) { $choices = '[Y/n]' } else { $choices = '[y/N]' }
    while ($true) {
        Write-WizardQuestion "$Title $choices" $Help
        $v = Read-WizardLine
        if ($v -eq '') { return $Default }
        if ($v -in @('y', 'yes')) { return $true }
        if ($v -in @('n', 'no')) { return $false }
        Write-InputError (New-InputError "y か n で答えてください（入力: $v）。")
    }
}

# 番号で 1 つ選ぶ。選んだ番号（1 から）を返す。
function Read-WizardChoice {
    param([Parameter(Mandatory = $true)][string]$Title, [Parameter(Mandatory = $true)][string[]]$Items, [string[]]$Help = @())
    while ($true) {
        Write-WizardQuestion $Title $Help
        for ($i = 0; $i -lt $Items.Count; $i++) {
            Write-Host '      ' -NoNewline
            Write-Host "$($i + 1))" -ForegroundColor Cyan -NoNewline
            Write-Host " $($Items[$i])"
        }
        $v = Read-WizardLine
        if ($v -match '^[0-9]{1,3}$' -and [int]$v -ge 1 -and [int]$v -le $Items.Count) { return [int]$v }
        Write-InputError (New-InputError "1 から $($Items.Count) の番号を入力してください（入力: $v）。")
    }
}

function ConvertFrom-SecureToPlain([System.Security.SecureString]$Secure) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }   # 平文にするために使った領域はすぐ消す
}

function ConvertTo-SecureFromPlain([string]$Plain) {
    $s = New-Object System.Security.SecureString
    foreach ($c in $Plain.ToCharArray()) { $s.AppendChar($c) }
    $s.MakeReadOnly()
    return $s
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
function Get-VSCodeExtensionsDir([string]$WindowsUser) {
    return "C:\Users\$WindowsUser\.vscode\extensions"
}

# VS Code の WSL 拡張機能があれば $null、無ければ New-InputError の結果を返す
function Test-VSCodeWslExtension([string]$WindowsUser) {
    $extDir = Get-VSCodeExtensionsDir $WindowsUser
    $found = @()
    if (Test-Path -LiteralPath $extDir -PathType Container) {
        $found = @(Get-ChildItem -LiteralPath $extDir -Directory |
            Where-Object { $_.Name -match '^ms-vscode-remote\.remote-wsl-\d' })
    }
    if ($found.Count -gt 0) { return $null }
    if ($Interactive) { $where = '入力した windows_user' } else { $where = 'room.conf の windows_user' }
    $hint = @(
        "$where が、C:\Users の中にある自分のフォルダ名と同じか確認してください。",
        'VS Code の WSL 拡張機能が入っていない場合は、次のコマンドでインストールしてから、もう一度実行してください:',
        '  code --install-extension ms-vscode-remote.remote-wsl')
    if (Test-Path -LiteralPath "C:\Users\$WindowsUser\.vscode-insiders") {
        $hint += 'VS Code Insiders には対応していません。通常版の VS Code に拡張機能を入れてください。'
    }
    return (New-InputError "VS Code の WSL 拡張機能が見つかりません（$extDir）。" $hint)
}

# 部屋へコピーするファイル（room.conf 以外）の、Windows 側の場所
function Get-LocalPayloadPath([string]$Rel) {
    return Join-Path $script:ScriptRoot ($Rel.Replace('/', '\'))
}

# 部屋へコピーするファイルの中身。room.conf は、読み込んだ（対話モードでは組み立てた）バイト列をそのまま使う。
function Get-PayloadBytes([string]$Rel) {
    if ($Rel -eq 'room.conf') { return ,$script:ConfBytes }
    return ,([System.IO.File]::ReadAllBytes((Get-LocalPayloadPath $Rel)))
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

# ----- room.conf の各項目のチェック（規則は lib.sh の load_room_conf と同じ。変えるときは両方） -----
# 正しければ $null、誤りなら New-InputError の結果を返す。

function Test-LinuxUserValue([string]$Value) {
    if ($Value -eq '') {
        return (New-InputError 'linux_user が空です。' @('部屋の中で使う Linux のユーザー名を書いてください（例: taro）。'))
    }
    if ($Value -cnotmatch $script:ReLinuxUser) {
        return (New-InputError "linux_user が正しくありません: $Value" @(
            '半角英小文字で始まり、英小文字・数字・_・- だけを使った 32 文字以内の名前にしてください。'))
    }
    return $null
}

function Test-WindowsUserValue([string]$Value) {
    if ($Value -eq '') {
        return (New-InputError 'windows_user が空です。' @('Windows のユーザーフォルダの名前（C:\Users\<ここ>）を書いてください。'))
    }
    if ($Value -cnotmatch $script:ReWinUser) {
        return (New-InputError "windows_user が正しくありません: $Value" @(
            '半角英数字と . _ - だけに対応しています（スペースや日本語を含む名前は、動作が未確認のため未対応）。'))
    }
    return $null
}

# allowed_domains の値（カンマ区切り）を、重複を除いたドメインの配列にする。
# 結果は Domains（配列）と Error（誤りが無ければ $null）を持つ。
function ConvertTo-AllowedDomains([string]$Value) {
    $domains = New-Object System.Collections.Generic.List[string]
    foreach ($part in $Value.Split(',')) {
        $d = $part.Trim()
        if ($d -eq '') { continue }
        if ($d -eq '*') {
            return [pscustomobject]@{ Domains = @(); Error = (New-InputError 'allowed_domains に「*」は使えません。' @(
                '「*」はすべてのドメインへの通信を許可してしまい、サンドボックスの意味がなくなるためです。')) }
        }
        if ($d -cnotmatch $script:ReDomain) {
            return [pscustomobject]@{ Domains = @(); Error = (New-InputError "ドメイン名として正しくありません: $d" @(
                '例: registry.npmjs.org や *.example.com のように書いてください（https:// やパスは不要です）。')) }
        }
        if (-not $domains.Contains($d)) { $domains.Add($d) }
    }
    return [pscustomobject]@{ Domains = $domains.ToArray(); Error = $null }
}

# 設定ファイルを UTF-8 として読む（読めなければ停止）。結果は Bytes（中身そのもの）と Text を持つ。
function Read-ConfFileUtf8([string]$Path) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)
    } catch {
        Stop-Setup "設定ファイル $Path を読めません。UTF-8 で保存されていない可能性があります。" @(
            'メモ帳などで開き、文字コードを UTF-8 にして保存し直してください。')
    }
    return [pscustomobject]@{ Bytes = $bytes; Text = $text.TrimStart([char]0xFEFF) }
}

# room.conf を読んで内容を確認する。部屋を作る前に書き間違いに気づけるようにするための事前チェック。
# 部屋の中へは、ここで読んだバイト列をそのままコピーする（$script:ConfBytes）。
function Read-RoomConf {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-Setup "設定ファイルが見つかりません: $Path"
    }
    $file = Read-ConfFileUtf8 $Path
    $conf = ConvertFrom-RoomConfText $file.Text
    $script:ConfBytes = $file.Bytes
    return $conf
}

# room.conf の書式の文章を読んで内容を確認する（Read-RoomConf と、対話モードで組み立てた内容・部屋の中の room.conf の確認に使う）
function ConvertFrom-RoomConfText {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $linuxUser = ''
    $windowsUser = ''
    $domains = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $lineNo = 0
    foreach ($raw in ($Text -split "`r?`n")) {
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

        $err = $null
        if ($key -ceq 'linux_user') {
            $err = Test-LinuxUserValue $value
            $linuxUser = $value
        } elseif ($key -ceq 'windows_user') {
            $err = Test-WindowsUserValue $value
            $windowsUser = $value
        } elseif ($key -ceq 'allowed_domains') {
            $parsed = ConvertTo-AllowedDomains $value
            $err = $parsed.Error
            foreach ($d in $parsed.Domains) { if (-not $domains.Contains($d)) { $domains.Add($d) } }
        } else {
            Stop-Setup "設定ファイルの $lineNo 行目: 知らない項目名です: $key" @('使える項目は linux_user、windows_user、allowed_domains です。')
        }
        if ($null -ne $err) { Stop-Setup "設定ファイルの $lineNo 行目: $($err.Message)" $err.Hint }
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
# パスが WSL の部屋の中（\\wsl.localhost\... や \\wsl$\...）を指しているか
function Test-PathInsideWsl([string]$Path) {
    return ($Path -match '^(\\\\\?\\UNC\\|\\\\)(wsl\.localhost|wsl\$)\\')
}

# ----- room-github.conf の各項目のチェック（規則は provision-github.sh と同じ。変えるときは両方） -----
# 正しければ $null、誤りなら New-InputError の結果を返す。PAT は、どの表示にも含めない。

function Test-GitHubUserNameValue([string]$Value) {
    if ($Value -match $script:ReGitHubUserNameBad) {
        return (New-InputError 'user_name に使えない文字が含まれています。' @('制御文字と < > は使えません。'))
    }
    return $null
}

function Test-GitHubEmailValue([string]$Value) {
    if ($Value -notmatch $script:ReGitHubEmail -or $Value -match '[\x00-\x1F\x7F-\x9F]') {
        return (New-InputError "user_email がメールアドレスの形になっていません: $Value" @('例: dev-room@example.com'))
    }
    return $null
}

function Test-GitHubPatValue([string]$Value) {
    if ($Value -cnotmatch $script:ReGitHubPat) {
        return (New-InputError 'pat が PAT の形になっていません（内容は表示しません）。' @(
            'GitHub で作成したトークン（github_pat_ や ghp_ で始まる、英数字と _ だけの文字列）を、そのまま貼り付けてください。'))
    }
    return $null
}

# repo_url を確かめて、Owner・RepoName・RepoUrl（https://github.com/OWNER/REPOSITORY.git の形）と Error を返す
function ConvertFrom-GitHubRepoUrl([string]$Value) {
    $owner = ''
    $repo = ''
    $err = $null
    if ($Value -cmatch $script:ReGitHubRepoUrl) {
        $owner = $Matches[1]
        $repo = $Matches[2]
        if ($repo -eq '.' -or $repo -eq '..') {
            $err = New-InputError "リポジトリの名前が正しくありません: $Value"
        }
    } else {
        $err = New-InputError "repo_url が正しくありません: $Value" @(
            'https://github.com/OWNER/REPOSITORY.git の形で書いてください（SSH の git@github.com:... は使えません）。')
    }
    return [pscustomobject]@{ Owner = $owner; RepoName = $repo; RepoUrl = "https://github.com/$owner/$repo.git"; Error = $err }
}

# GitHub の設定の内容。Pat（平文）と PatSecure（対話モードで入力した SecureString）は、どちらか一方だけを持つ。
function New-GitHubSettings {
    param([string]$UserName, [string]$UserEmail, [string]$Pat, [System.Security.SecureString]$PatSecure, $Repo)
    return [pscustomobject]@{
        UserName  = $UserName
        UserEmail = $UserEmail
        Pat       = $Pat
        PatSecure = $PatSecure
        Owner     = $Repo.Owner
        RepoName  = $Repo.RepoName
        RepoUrl   = $Repo.RepoUrl
    }
}

# room-github.conf を読んで内容を確認する。部屋を作る前に書き間違いに気づけるようにするための事前チェック。
#   - ファイルが無い、またはすべて空欄 → $null を返す（GitHub の設定をしない）
#   - 一部だけ記入されている → 書き忘れとみなして停止する
# 書式は room.conf と同じ。
# PAT を画面に出さないよう、エラーの表示には行の中身と pat の値を含めない。
function Read-GitHubConf {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $name = Split-Path -Leaf $Path
    $text = (Read-ConfFileUtf8 $Path).Text

    $keys = @('user_name', 'user_email', 'pat', 'repo_url')
    $values = @{}
    $lineOf = @{}
    foreach ($k in $keys) { $values[$k] = ''; $lineOf[$k] = 0 }
    $lineNo = 0
    foreach ($raw in ($text -split "`r?`n")) {
        $lineNo++
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -cmatch '^([a-z_]+)\s*=(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()
        } else {
            Stop-Setup "$name の $lineNo 行目の書き方が正しくありません（PAT を含むかもしれないため、内容は表示しません）。" @(
                '「名前 = 値」の形で書いてください。')
        }
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ($keys -cnotcontains $key) {
            Stop-Setup "$name の $lineNo 行目: 知らない項目名です: $key" @('使える項目は user_name、user_email、pat、repo_url です。')
        }
        if ($lineOf[$key] -ne 0) { Stop-Setup "$name の $lineNo 行目: $key が 2 回書かれています。" }
        $lineOf[$key] = $lineNo
        $values[$key] = $value
    }

    $empty = @($keys | Where-Object { $values[$_] -eq '' })
    if ($empty.Count -eq $keys.Count) { return $null }
    if ($empty.Count -gt 0) {
        Stop-Setup "$name の一部だけが記入されています（空欄: $($empty -join '、')）。" @(
            'GitHub の設定をする場合は、user_name、user_email、pat、repo_url のすべてを記入してください。',
            'GitHub の設定をしない場合は、すべて空欄にしてください。')
    }
    if (Test-PathInsideWsl $Path) {
        Stop-Setup "記入済みの $name が、WSL の部屋の中にあります: $Path" @(
            '部屋の中のファイルは、その部屋で動く Claude Code から読めることがあります。',
            "$name は Windows 側にコピーしたフォルダ（room.conf と同じ場所）で記入し、そこにあるスクリプトを実行してください（README の 3 章）。",
            '部屋の中のファイルに書いた PAT は、念のため GitHub で削除（失効）して作り直してください。')
    }

    $checks = @(
        @('user_name', (Test-GitHubUserNameValue $values['user_name'])),
        @('user_email', (Test-GitHubEmailValue $values['user_email'])),
        @('pat', (Test-GitHubPatValue $values['pat'])))
    foreach ($c in $checks) {
        if ($null -ne $c[1]) { Stop-Setup "$name の $($lineOf[$c[0]]) 行目: $($c[1].Message)" $c[1].Hint }
    }
    $repo = ConvertFrom-GitHubRepoUrl $values['repo_url']
    if ($null -ne $repo.Error) { Stop-Setup "$name の $($lineOf['repo_url']) 行目: $($repo.Error.Message)" $repo.Error.Hint }
    return (New-GitHubSettings -UserName $values['user_name'] -UserEmail $values['user_email'] -Pat $values['pat'] -Repo $repo)
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
    $listed = $false
    while ($true) {
        if (-not $Current) {
            if (-not $listed) {
                Write-Host ''
                Write-Info 'インストールできるディストリビューション:'
                foreach ($l in $lines) { Write-Info "  $l" }
                $listed = $true
            }
            if ($Interactive) {
                Write-WizardQuestion 'ディストリビューションの名前' @('上の一覧の NAME 列から、そのまま入力してください（例: Ubuntu-26.04）。')
                $Current = Read-WizardLine
            } else {
                $Current = (Read-Host '  使うディストリビューションの名前を、NAME 列からそのまま入力してください（例: Ubuntu-26.04）').Trim()
            }
        }
        $match = $null
        foreach ($n in $names) { if ($n -ieq $Current) { $match = $n; break } }
        if (-not $match) {
            $err = New-InputError "「$Current」は、インストールできるディストリビューションの一覧にありません。" @('wsl -l -o で表示される NAME 列の名前を入力してください。')
        } elseif ($match -notlike 'Ubuntu*') {
            $err = New-InputError "このスクリプトは Ubuntu でのみ動作を確認しています（指定: $match）。" @('Ubuntu-26.04 などの Ubuntu を選んでください。')
        } else {
            return $match
        }
        if (-not $Interactive) { Stop-Setup $err.Message $err.Hint }
        Write-InputError $err
        $Current = ''
    }
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
    if ($Interactive -and $MustExist) {
        $rooms = Get-RoomNames
        Write-Host ''
        if ($rooms.Count -eq 0) {
            Stop-Setup '登録済みの部屋（ディストリビューション）がありません。' @(
                "新しく作る場合は、$($script:WizardCmd) を起動し直して「$($script:WizardModeCreate)」を選んでください。")
        }
        Write-Info "登録済みの部屋（ディストリビューション）: $($rooms -join ', ')"
    }
    while ($true) {
        if (-not $Current) {
            if ($Interactive) {
                if ($MustExist) { $help = @('対象にする既存の部屋の名前を入力してください。') }
                else { $help = @('新しく作る部屋の名前です。半角英小文字・数字・ハイフンで、32 文字以内（例: dev）。') }
                Write-WizardQuestion '部屋の名前' $help
                $Current = Read-WizardLine
            } else {
                $Current = (Read-Host '  部屋の名前を入力してください（半角英小文字・数字・ハイフン。例: dev）').Trim()
            }
        }
        $err = $null
        if ($Current -cnotmatch $script:ReRoomName) {
            $err = New-InputError "部屋の名前「$Current」は使えません。" @('半角英小文字・数字・ハイフンだけで、32 文字以内にしてください（先頭と末尾はハイフン以外）。')
        } else {
            $exists = Test-RoomExists $Current
            if ($MustExist -and -not $exists) {
                $err = New-InputError "部屋「$Current」が見つかりません。" @('PowerShell で wsl -l -v を実行して、部屋の名前を確認してください。')
            }
            if (-not $MustExist -and $exists) {
                $hint = @('別の名前を指定してください。')
                if ($Interactive) {
                    $hint += "途中で止まった部屋の続きなら、$($script:WizardCmd) を起動し直して「$($script:WizardModeResume)」を選んでください。"
                } else {
                    $hint += @('途中で止まった部屋の続きなら、-Resume を付けて実行してください:', "  .\New-SecureRoom.ps1 -RoomName $Current -Resume")
                }
                $hint += '作り直したい場合は、部屋の中身がすべて消えることを理解したうえで、ご自身で wsl --unregister を実行してください。'
                $err = New-InputError "部屋「$Current」はすでにあります。" $hint
            }
        }
        if ($null -eq $err) { return $Current }
        if (-not $Interactive) { Stop-Setup $err.Message $err.Hint }
        Write-InputError $err
        $Current = ''
    }
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
    Write-Info "部屋に見せるフォルダ   : $(Get-VSCodeExtensionsDir $script:Conf.WindowsUser)（読み取り専用）"
    if ($script:Conf.AllowedDomains.Count -gt 0) { $domains = $script:Conf.AllowedDomains -join ', ' } else { $domains = '（なし）' }
    Write-Info "通信を許可するドメイン : $domains"
    if (-not $VerifyOnly) {
        $ghName = Split-Path -Leaf $script:GitHubConfigFile
        if ($null -ne $script:GitHub) {
            if ($Interactive) { $src = 'この画面で入力。PAT は入力済み（表示しません）' } else { $src = $script:GitHubConfigFile }
            Write-Info "GitHub の設定          : する（$src）"
            Write-Info "クローンするリポジトリ : $($script:GitHub.RepoUrl) → ~/projects/$($script:GitHub.RepoName)"
            Write-Info "コミットの作者         : $($script:GitHub.UserName) <$($script:GitHub.UserEmail)>"
        } else {
            if ($Interactive) { $why = '「しない」を選んだ' }
            elseif (Test-Path -LiteralPath $script:GitHubConfigFile -PathType Leaf) { $why = "$ghName が空欄" } else { $why = "$ghName が無い" }
            if ($Resume) { $why += '。すでにある GitHub の設定はそのまま' }
            Write-Info "GitHub の設定          : しない（$why）"
        }
    }
    if ($Interactive) { Write-Info '設定の入力元           : この画面で入力（ファイルには保存しません）' }
    else { Write-Info "設定ファイル           : $($script:ConfigFile)" }
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
    Write-Info "  ・ユーザー名: $($script:LinuxUserLabel) と同じ「$($script:Conf.LinuxUser)」を入力してください。"
    Write-Info '  ・パスワード: 入力しても画面には何も表示されませんが、正常です。'
    Write-Info '    部屋の設定が終わると、このユーザーは sudo（管理者の権限）を使えなくなります。'
    Write-Info '    それでも、Claude Code を含め、ほかの誰にも教えないでください。'
    Write-Info '入力が終わって「ユーザー名@...:~$」のような表示が出たら、exit と入力して Enter を押してください。'
    Write-Info 'そのあとは、このスクリプトが自動で続きを進めます。'
    $null = Read-Host '  準備ができたら Enter を押してください'

    $code = Start-Wsl @('--install', $script:DistroName, '--name', $script:Room)
    $resumeHint = @('上に表示されたメッセージを確認してください。') + (Get-RerunHint `
        '部屋が作られていてユーザー名・パスワードの設定も終わっている場合は、{0}続きから進められます:' 'Resume')
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
            "PowerShell で wsl --set-version $($script:Room) 2 を実行してから、$(Get-ResumeHowTo)続けてください。")
    }
    Write-Ok '部屋は WSL2 で動いています。'
}

# 部屋に入ったときのユーザーが、room.conf の linux_user（対話モードでは入力した linux_user）と同じであることを確かめる
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
        if ($Interactive) {
            $fix = "入力した linux_user のほうを直す場合は、$($script:WizardCmd) を起動し直して「$($script:WizardModeResume)」を選び、linux_user に $user を入力してください。"
        } else {
            $fix = 'room.conf のほうを直す場合は、直してから -Resume を付けて実行してください。'
        }
        Stop-Setup "部屋「$($script:Room)」のユーザー（$user）が、$($script:LinuxUserLabel)（$expected）と違います。" @(
            "部屋を作るときに入力したユーザー名と、$($script:LinuxUserLabel) をそろえる必要があります。",
            $fix,
            '部屋を作り直す場合は、中身がすべて消えることを理解したうえで、ご自身で wsl --unregister を実行してください。')
    }
    Write-Ok "部屋のユーザーが $($script:LinuxUserLabel)（$expected）と一致しました。"
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

    # ハッシュ値は、送ったバイト列そのものから計算する（送ったあとで Windows 側のファイルが変わっても正しく照合できるように）
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $sent = @{}
    foreach ($rel in $script:PayloadFiles) {
        $bytes = Get-PayloadBytes $rel
        $sent[$rel] = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
        $b64 = [Convert]::ToBase64String($bytes)
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
        if ($remote["$($script:InstallDir)/$rel"] -ne $sent[$rel]) {
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
        Stop-Setup "「$What」に失敗しました（終了コード $code）。" (@('上に表示されたメッセージを確認してください。') +
            (Get-RerunHint '原因を取り除いたら、{0}続きからやり直せます（部屋は消えません）:' 'Resume'))
    }
}

# 文字列を標準入力として wsl.exe に渡して実行し、部屋の中の表示はこの画面にそのまま出す。終了コードを返す。
function Invoke-WslWithInput {
    param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $Text | & wsl.exe @Arguments | Out-Host
    return $LASTEXITCODE
}

# room-github.conf に記入があるとき（対話モードでは「する」を選んだとき）だけ、git の設定と PAT の保存、リポジトリのクローンを行う。
# room-github.conf は部屋の中にコピーせず、内容（PAT を含む）は base64 にして標準入力で渡す
# （コマンドライン引数は部屋の中のほかのプロセスから見えるため使わない）。
# 対話モードで入力した PAT は、ここで初めて平文に戻す（それまでは SecureString のまま持つ）。
function Invoke-GitHubSetup {
    $gh = $script:GitHub
    if ($null -eq $gh) { return }
    $user = $script:LinuxUser
    $what = "GitHub の設定（$user）: git の設定と PAT の保存"
    $wslArgs = @('-d', $script:Room, '-u', $user, '--cd', '~', '--exec', 'bash',
        "$($script:InstallDir)/provision-github.sh", '--phase', 'credentials')
    Write-Step $what
    if ($DryRun) {
        Write-DryRun ('wsl.exe ' + ($wslArgs -join ' ') + '（user_name・user_email・PAT・リポジトリの URL は標準入力で渡す）')
    } else {
        $pat = $gh.Pat
        if ($null -ne $gh.PatSecure) { $pat = ConvertFrom-SecureToPlain $gh.PatSecure }
        $payload = "user_name=$($gh.UserName)`nuser_email=$($gh.UserEmail)`npat=$pat`nrepo_url=$($gh.RepoUrl)`n"
        $b64 = [Convert]::ToBase64String((New-Object System.Text.UTF8Encoding($false)).GetBytes($payload))
        $payload = $null
        $pat = $null
        $code = Invoke-WslWithInput -Text $b64 -Arguments $wslArgs
        $b64 = $null
        if ($code -ne 0) {
            Stop-Setup "「$what」に失敗しました（終了コード $code）。" (@('上に表示されたメッセージを確認してください。') +
                (Get-RerunHint '原因を取り除いたら、{0}続きからやり直せます（部屋は消えません）:' 'Resume'))
        }
    }
    Invoke-ProvisionStep -User $user -ScriptName 'provision-github.sh' -ScriptArgs @('--phase', 'clone', $gh.RepoUrl) `
        -What "リポジトリのクローン（$user）: $($gh.RepoUrl) → ~/projects/$($gh.RepoName)"
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
            Stop-Setup '部屋が 60 秒たっても停止しませんでした。' @("PowerShell で wsl --terminate $($script:Room) を実行してから、$(Get-ResumeHowTo)やり直してください。")
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
        Stop-Setup '自動検証で FAIL になった項目があります。' (@('上の [FAIL] の行と、その下の説明を確認してください。') +
            (Get-RerunHint '直したあと、{0}検証だけをやり直せます:' 'VerifyOnly'))
    }
    Write-Ok '自動検証で FAIL はありませんでした（SKIP の項目は、ログイン後に手動で確認します。WARN の項目があれば、その説明を確認してください）。'
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
    Write-Info "   部屋の中では sudo を使えません。パッケージの追加などの管理作業は、Windows の PowerShell から入って行います:"
    Write-Info "     wsl -d $room -u root"
    if ($null -ne $script:GitHub) {
        $repo = $script:GitHub.RepoName
        Write-Info "4. GitHub のリポジトリを ~/projects/$repo にクローンしてあります。VS Code で開くときは:"
        Write-Info "     code --remote wsl+$room /home/$user/projects/$repo"
        Write-Info '   README の「GitHub の設定」（6.6）の確認も行ってください。'
        if ($Interactive) {
            Write-Info '   入力した PAT は、部屋の ~/.git-credentials のほかには保存していません。'
        } else {
            Write-Note "$(Split-Path -Leaf $script:GitHubConfigFile) の PAT などは、もう不要です。空欄に戻してください（$($script:GitHubConfigFile)）。"
        }
    }
}

# =============================================================================
# 対話モード（-Interactive。room-setup-wizard.cmd から起動したとき）
# =============================================================================
# 設定ファイルを読む代わりに、同じ内容をこの画面で聞く。値のチェックは、設定ファイルを読むときと同じ関数で行う。
# 入力した値はファイルに保存しない。room.conf にあたる内容はメモリ上で組み立てて部屋の中へコピーし（$script:ConfBytes）、
# GitHub の情報（PAT を含む）は Invoke-GitHubSetup が標準入力で部屋に渡す。

# このスクリプトが WSL の部屋の中にあるときは停止する。部屋の中のファイルは部屋の中のプログラム（Claude Code を含む）が
# 書き換えられるため、書き換えられたスクリプトに PAT を入力したり、Windows の権限で実行したりしてしまうおそれがある。
function Test-WizardLocation {
    # 「Microsoft.PowerShell.Core\FileSystem::\\wsl.localhost\...」の形で渡されることがあるので、前置きを外して調べる
    $root = $script:ScriptRoot -replace '^Microsoft\.PowerShell\.Core\\FileSystem::', ''
    $hint = @(
        '部屋の中のファイルは、部屋の中のプログラム（Claude Code を含む）が書き換えられます。',
        '書き換えられたスクリプトに PAT などを入力してしまわないよう、対話モードは部屋の中にあるファイルからは起動できません。',
        "wsl-room-setup フォルダを Windows 側の自分のフォルダにコピーし、中身を確かめてから、コピーしたほうの $($script:WizardCmd) を起動してください（README の 3 章）。")
    if (Test-PathInsideWsl $root) { Stop-Setup "このスクリプトは WSL の部屋の中にあります: $root" $hint }
    # \\wsl.localhost\... をドライブ文字に割り当てて開いた場合も止める
    if ($root -match '^([A-Za-z]):') {
        $drive = "$($Matches[1].ToUpperInvariant()):"
        $isNetwork = $false
        try { $isNetwork = ((New-Object System.IO.DriveInfo $drive).DriveType -eq [System.IO.DriveType]::Network) } catch { $isNetwork = $false }
        if ($isNetwork) {
            $unc = $null
            try { $unc = (Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction Stop).ProviderName } catch { $unc = $null }
            if (-not $unc) {
                Stop-Setup "このスクリプトがあるネットワークドライブ（$drive）の接続先を確認できませんでした: $root" $hint
            }
            if (Test-PathInsideWsl $unc) {
                Stop-Setup "このスクリプトは、WSL の部屋の中を割り当てたドライブ（$drive → $unc）にあります: $root" $hint
            }
        }
    }
}

# 行うこと（新規作成・やり直し・検証だけ）と、ドライランにするかを聞く。コマンドラインで指定されたものは聞かない。
function Start-Wizard {
    if ($ConfigPath -or $GitHubConfigPath) {
        Stop-Setup '-Interactive と、-ConfigPath・-GitHubConfigPath は同時に指定できません。' @(
            '対話モードでは設定ファイルを使わず、必要な値をこの画面で入力します。')
    }
    Test-WizardLocation
    Write-Host ''
    Write-Info '設定ファイル（room.conf・room-github.conf）の代わりに、必要な値をこの画面で順に聞きます。'
    Write-Info '入力した値は、ファイルには保存しません。'
    Write-Info '途中でやめるときは Ctrl+C を押してください（最後の確認で y を入力するまでは、何も変更しません）。'
    if (-not ($Resume -or $VerifyOnly)) {
        Write-Step '何をするかを選びます'
        $n = Read-WizardChoice '行うことを番号で選んでください' @(
            $script:WizardModeCreate,
            "$($script:WizardModeResume)（途中で止まったとき、設定を元に戻したいとき。部屋は消しません）",
            $script:WizardModeVerify)
        if ($n -eq 2) { $script:Resume = [switch]$true }
        elseif ($n -eq 3) { $script:VerifyOnly = [switch]$true }
    }
    if (-not $DryRun) {
        $dry = Read-WizardYesNo 'ドライランにしますか？' @(
            'ドライランでは何も変更せず、実行する予定の内容だけを表示します。',
            '初めて使うときは、まずドライランで流れを確かめるのがおすすめです。') $false
        if ($dry) { $script:DryRun = [switch]$true }
    }
}

# 部屋の中の room.conf（前回この部屋を設定したときの内容。root 所有）を読む。読めなければ $null。
function Read-RoomConfFromRoom {
    $path = "$($script:InstallDir)/room.conf"
    $out = Invoke-WslCapture @('-d', $script:Room, '-u', 'root', '--cd', '/', '--exec', 'cat', '--', $path)
    if ($script:LastWslExit -ne 0 -or $out.Count -eq 0) {
        Write-Note "部屋の中の room.conf（$path）を読めませんでした。すべての値を入力してください。"
        return $null
    }
    try {
        $conf = ConvertFrom-RoomConfText ($out -join "`n")
    } catch {
        Write-Note "部屋の中の room.conf（$path）の内容が正しくないため、使いません。すべての値を入力してください。"
        return $null
    }
    Write-Info "部屋の中の room.conf（$path）の内容を、Enter だけ押したときの値にします。"
    return $conf
}

# このフォルダの room.conf の allowed_domains（linux_user などが空欄でも読む）。使えなければ空文字列。
function Get-DefaultAllowedDomains {
    $path = Join-Path $script:ScriptRoot 'room.conf'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    try { $text = (Read-ConfFileUtf8 $path).Text } catch { return '' }
    foreach ($raw in ($text -split "`r?`n")) {
        if ($raw.Trim() -cmatch '^allowed_domains\s*=(.*)$') {
            $value = $Matches[1].Trim()
            if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) { $value = $value.Substring(1, $value.Length - 2) }
            $parsed = ConvertTo-AllowedDomains $value
            if ($null -ne $parsed.Error) { return '' }
            if ($parsed.Domains.Count -eq 0) { return '-' }
            return ($parsed.Domains -join ', ')
        }
    }
    return ''
}

# room.conf にあたる値を聞き、$script:Conf・$script:ConfBytes・$script:LinuxUser を決める。
# 入力し直すとき（$script:Conf がある）は、前回の入力を Enter だけ押したときの値にする。
function Read-WizardSettings([bool]$Creating) {
    Write-Step '部屋の設定を入力します（room.conf に書く内容と同じです）'
    $prev = $script:Conf
    if ($null -eq $prev -and -not $Creating) { $prev = Read-RoomConfFromRoom }

    $defLinux = ''
    $defWin = ''
    $defDomains = ''
    if ($null -ne $prev) {
        $defLinux = $prev.LinuxUser
        $defWin = $prev.WindowsUser
        if ($prev.AllowedDomains.Count -gt 0) { $defDomains = $prev.AllowedDomains -join ', ' } else { $defDomains = '-' }
    } else {
        $defDomains = Get-DefaultAllowedDomains
    }

    if ($Creating) { $sameAs = 'このあと部屋を作る画面で聞かれるユーザー名にも、同じ名前を入力します。' }
    else { $sameAs = '部屋を作ったときに入力したユーザー名と同じにしてください。' }
    $linuxUser = Read-WizardValue -Title 'linux_user（部屋の中で使う Linux のユーザー名）' -Default $defLinux -Help @(
        '半角英小文字で始まり、英小文字・数字・_・- だけを使った 32 文字以内の名前（例: taro）。',
        $sameAs) -Validate { param($v) Test-LinuxUserValue $v }

    $windowsUser = Read-WizardValue -Title 'windows_user（Windows のユーザーフォルダの名前: C:\Users\<ここ>）' -Default $defWin -Help @(
        'エクスプローラーで C:\Users を開くと確認できます。半角英数字と . _ - だけに対応しています。',
        'VS Code の拡張機能フォルダ（C:\Users\<ここ>\.vscode\extensions）を、部屋に読み取り専用で見せるために使います。') -Validate {
        param($v)
        $e = Test-WindowsUserValue $v
        if ($null -ne $e) { return $e }
        return (Test-VSCodeWslExtension $v)
    }
    Write-Ok "VS Code の WSL 拡張機能があります（$(Get-VSCodeExtensionsDir $windowsUser)）。"

    $domainsText = Read-WizardValue -Title 'allowed_domains（Claude Code のサンドボックスの中から通信してよいドメイン）' -Default $defDomains -Help @(
        'カンマ区切りで入力します（例: registry.npmjs.org, pypi.org）。ここに無いドメインへの通信はブロックされます。',
        '*.example.com のように先頭に *. を付けると、サブドメインをまとめて許可できます。「*」（すべて許可）は使えません。',
        '通信を許可するドメインが無い場合は - を入力してください。') -Validate {
        param($v)
        if ($v -eq '-') { return $null }
        return (ConvertTo-AllowedDomains $v).Error
    }
    if ($domainsText -eq '-') { $domains = @() } else { $domains = (ConvertTo-AllowedDomains $domainsText).Domains }

    # 設定ファイルを読む場合と同じ形・同じチェックを通してから使う
    $text = (@(
        '# New-SecureRoom.ps1 の対話モード（room-setup-wizard.cmd）で入力した内容',
        "linux_user = $linuxUser",
        "windows_user = $windowsUser",
        "allowed_domains = $($domains -join ', ')") -join "`n") + "`n"
    $script:Conf = ConvertFrom-RoomConfText $text
    $script:ConfBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)
    $script:LinuxUser = $script:Conf.LinuxUser
    Write-Ok '部屋の設定の入力を確認しました。'
}

# PAT を聞く。画面には * で表示し、SecureString で返す（平文は確かめるあいだだけ持つ）。
function Read-WizardPat([System.Security.SecureString]$Previous) {
    $default = ''
    if ($null -ne $Previous) { $default = '（前回入力した PAT。内容は表示しません）' }
    while ($true) {
        Write-WizardQuestion 'pat（GitHub の Personal Access Token）' @(
            'fine-grained PAT（対象のリポジトリだけ・Contents の Read and write・有効期限付き）がおすすめです。',
            '入力（貼り付け）した文字は * で表示されます。PAT はファイルに保存せず、部屋の ~/.git-credentials にだけ保存します。') $default
        Write-WizardPrompt
        $secure = Read-Host -AsSecureString
        if ($null -eq $secure) { Stop-Setup '入力が終わりました（標準入力が閉じられました）。' }
        if ($secure.Length -eq 0) {
            if ($null -ne $Previous) { return $Previous }
            Write-InputError (New-InputError '何も入力されていません。')
            continue
        }
        $plain = (ConvertFrom-SecureToPlain $secure).Trim()
        $secure.Dispose()
        $err = Test-GitHubPatValue $plain
        if ($null -eq $err) {
            $result = ConvertTo-SecureFromPlain $plain
            $plain = $null
            return $result
        }
        $plain = $null
        Write-InputError $err
    }
}

# GitHub の設定をするかを聞き、する場合は room-github.conf にあたる値を聞いて $script:GitHub を決める
function Read-WizardGitHub {
    Write-Step 'GitHub の設定を決めます（room-github.conf に書く内容と同じです）'
    $prev = $script:GitHub
    if ($Resume) { $skip = 'n を選ぶと、この部屋にすでにある GitHub の設定はそのまま残します。' }
    else { $skip = 'n を選ぶと GitHub の設定をしません（あとで GitHub.md の手順で設定することもできます）。' }
    $do = Read-WizardYesNo 'GitHub の設定（git の設定・PAT の保存・リポジトリのクローン）をしますか？' @(
        'y を選ぶと、user_name・user_email・pat・repo_url の 4 つを続けて聞きます。',
        $skip) ($null -ne $prev)
    if (-not $do) {
        $script:GitHub = $null
        return
    }
    $defName = ''
    $defEmail = ''
    $defUrl = ''
    $prevPat = $null
    if ($null -ne $prev) {
        $defName = $prev.UserName
        $defEmail = $prev.UserEmail
        $defUrl = $prev.RepoUrl
        $prevPat = $prev.PatSecure
    }
    $userName = Read-WizardValue -Title 'user_name（コミットの作者名: git の user.name）' -Default $defName -Help @(
        'GitHub のアカウントと関係のないダミーで構いません（例: dev-room）。') -Validate { param($v) Test-GitHubUserNameValue $v }
    $email = Read-WizardValue -Title 'user_email（コミットの作者のメールアドレス: git の user.email）' -Default $defEmail -Help @(
        '実在する誰かのアドレスと一致しないよう、example.com などの例示用のドメインがおすすめです（例: dev-room@example.com）。') -Validate {
        param($v) Test-GitHubEmailValue $v }
    $pat = Read-WizardPat $prevPat
    $url = Read-WizardValue -Title 'repo_url（クローンするリポジトリの URL）' -Default $defUrl -Help @(
        'https://github.com/OWNER/REPOSITORY.git の形で入力します（SSH の git@github.com:... は使えません）。',
        '部屋の ~/projects/<リポジトリ名> にクローンします。') -Validate { param($v) (ConvertFrom-GitHubRepoUrl $v).Error }
    $script:GitHub = New-GitHubSettings -UserName $userName -UserEmail $email -PatSecure $pat -Repo (ConvertFrom-GitHubRepoUrl $url)
    Write-Ok 'GitHub の設定の入力を確認しました（PAT は表示しません）。'
}

# 最後の確認。y（進める）・r（設定の値を入力し直す）・n（中止）のどれかを返す。
function Read-WizardConfirm {
    while ($true) {
        Write-WizardQuestion 'この内容で進めますか？' @(
            'y: 進める',
            'r: 設定の値（linux_user から）を入力し直す',
            'n: 中止する（何も変更しません）')
        $v = Read-WizardLine
        if ($v -in @('y', 'yes')) { return 'y' }
        if ($v -eq 'r') { return 'r' }
        if ($v -in @('n', 'no')) { return 'n' }
        Write-InputError (New-InputError "y・r・n のどれかを入力してください（入力: $v）。")
    }
}

# =============================================================================
# 本体
# =============================================================================

function Invoke-Main {
    Write-Host ''
    Write-Host '=== Claude Code 用の隔離された WSL の部屋をつくります（wsl-room-setup）===' -ForegroundColor Cyan
    if ($Interactive) { Start-Wizard }
    if ($DryRun) { Write-Note 'ドライランです。何も変更せず、実行する予定の内容だけを表示します。' }
    if ($Resume -and $VerifyOnly) { Stop-Setup '-Resume と -VerifyOnly は同時に指定できません。' }
    $creating = -not ($Resume -or $VerifyOnly)

    Write-Step '前提条件を確認します'
    Test-WslAvailable
    Write-Ok 'WSL が使えます。'
    Test-PayloadFiles
    Write-Ok 'スクリプト一式がそろっています。'
    # 対話モードでは、設定ファイルを読む代わりに、部屋の名前を決めたあとで同じ内容を聞く（Read-WizardSettings）
    if (-not $Interactive) {
        $script:Conf = Read-RoomConf $script:ConfigFile
        $script:LinuxUser = $script:Conf.LinuxUser
        Write-Ok "設定ファイルを確認しました（$($script:ConfigFile)）。"
        if (-not $VerifyOnly) {
            if ($GitHubConfigPath -and -not (Test-Path -LiteralPath $script:GitHubConfigFile -PathType Leaf)) {
                Stop-Setup "GitHub の設定ファイルが見つかりません: $($script:GitHubConfigFile)"
            }
            $script:GitHub = Read-GitHubConf $script:GitHubConfigFile
            if ($null -ne $script:GitHub) {
                Write-Ok "GitHub の設定ファイルを確認しました（$($script:GitHubConfigFile)）。"
            }
        }
        $err = Test-VSCodeWslExtension $script:Conf.WindowsUser
        if ($null -ne $err) { Stop-Setup $err.Message $err.Hint }
        Write-Ok "VS Code の WSL 拡張機能があります（$(Get-VSCodeExtensionsDir $script:Conf.WindowsUser)）。"
    }

    Write-Step '部屋の名前などを決めます'
    if ($creating) { $script:DistroName = Select-Distro $Distro }
    $script:Room = Select-RoomName $RoomName (-not $creating)

    while ($true) {
        if ($Interactive) {
            Read-WizardSettings $creating
            if (-not $VerifyOnly) { Read-WizardGitHub }
        }
        Show-Summary $creating
        if ($DryRun) { break }
        if ($Interactive) {
            $answer = Read-WizardConfirm
            if ($answer -eq 'y') { break }
            if ($answer -eq 'r') { continue }
        } else {
            $answer = Read-Host '  この内容で進めますか？ 進める場合は y を入力して Enter（それ以外は中止）'
            if ($answer.Trim() -in @('y', 'Y', 'yes')) { break }
        }
        Write-Info '中止しました。何も変更していません。'
        return
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
            -What '部屋の基本設定（root）: パッケージ、wsl.conf、AppArmor、delzonei'
        Restart-Room
        Invoke-ProvisionStep -User 'root' -ScriptName 'provision-root.sh' -ScriptArgs @('--phase', 'mount') `
            -What 'VS Code 拡張フォルダの読み取り専用マウントと /mnt の片付け（root）'
        Invoke-ProvisionStep -User $script:LinuxUser -ScriptName 'provision-user.sh' `
            -What "一般ユーザーの設定（$($script:LinuxUser)）: Claude Code、PATH、uv、Rust、settings.json、ステータスライン、~/projects"
        Invoke-GitHubSetup
        Restart-Room
    }
    Invoke-Verify
    if (-not $DryRun -and -not $VerifyOnly) { Show-NextSteps }
}

$script:ScriptRoot = $PSScriptRoot
# 表示に使う「linux_user をどこで決めたか」
if ($Interactive) { $script:LinuxUserLabel = '入力した linux_user' } else { $script:LinuxUserLabel = 'room.conf の linux_user' }
if ($ConfigPath) {
    $script:ConfigFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)
} else {
    $script:ConfigFile = Join-Path $script:ScriptRoot 'room.conf'
}
if ($GitHubConfigPath) {
    $script:GitHubConfigFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($GitHubConfigPath)
} else {
    # room.conf と同じフォルダの room-github.conf（-ConfigPath で別の場所を指定したときは、そのフォルダ）
    $script:GitHubConfigFile = Join-Path (Split-Path -Parent $script:ConfigFile) 'room-github.conf'
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
