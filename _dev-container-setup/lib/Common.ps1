#Requires -Version 5.1
# =============================================================================
# Common.ps1 — 表示・停止・画面での入力・外部コマンドの呼び出し（dev-container-setup の共通部分）
#
# DevContainerSetup.ps1 と tests\*.Tests.ps1 が dot-source（. で読み込み）して使う。
# 従来の _wsl-room-setup の New-SecureRoom.ps1 と templates/Sync-Room.ps1.tmpl から写したもの（名前と引数は変えていない）。
# =============================================================================

# -----------------------------------------------------------------------------
# 表示
# -----------------------------------------------------------------------------

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
function New-InputError {
    param([Parameter(Mandatory = $true)][string]$Message, [string[]]$Hint = @())
    return [pscustomobject]@{ Message = $Message; Hint = $Hint }
}

# 外から来た文字列（コンテナの中のコミットの要約など）を表示する前に、制御文字と、文字の並びを入れ替える・見えなくする文字を取り除く。
# エスケープシーケンスなどで画面を書き換えて、確認の表示を偽装されないようにするため。
function Format-Safe([string]$Text) { return ($Text -replace '[\x00-\x1F\x7F-\x9F​-‏‪-‮⁠-⁩﻿]', '?') }

# -----------------------------------------------------------------------------
# 画面での質問と入力
# -----------------------------------------------------------------------------
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

# 番号で 1 つ選ぶ。選んだ番号（1 から）を返す。$Default（1 から）を指定すると、Enter だけのときにそれを選ぶ。
function Read-WizardChoice {
    param([Parameter(Mandatory = $true)][string]$Title, [Parameter(Mandatory = $true)][string[]]$Items, [string[]]$Help = @(), [int]$Default = 0)
    $defText = ''
    if ($Default -ge 1 -and $Default -le $Items.Count) { $defText = "$Default) $($Items[$Default - 1])" }
    while ($true) {
        Write-WizardQuestion $Title $Help $defText
        for ($i = 0; $i -lt $Items.Count; $i++) {
            Write-Host '      ' -NoNewline
            Write-Host "$($i + 1))" -ForegroundColor Cyan -NoNewline
            Write-Host " $($Items[$i])"
        }
        $v = Read-WizardLine
        if ($v -eq '' -and $defText -ne '') { return $Default }
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

# -----------------------------------------------------------------------------
# 外部コマンド（wsl.exe・git.exe）の呼び出し
# -----------------------------------------------------------------------------
# PowerShell 5.1 は外部コマンドへの標準入力の行末に CR を付け、" を含む引数を正しく渡せないため、
# .NET の Process で直接呼び出す。標準入力・標準出力はバイト列のまま扱う（bundle のバイナリも通すため）。
# 標準エラー出力は、ふつうはこの画面にそのまま表示する（-CaptureError のときだけ受け取る）。

# 1 つの引数を、Windows のコマンドラインの規則で囲む
function ConvertTo-CommandLineArg([string]$Arg) {
    if ($Arg -ne '' -and $Arg -notmatch '[\s"]') { return $Arg }
    $bs = [char]92   # \
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $slashes = 0
    foreach ($ch in $Arg.ToCharArray()) {
        if ($ch -eq $bs) { $slashes++; continue }
        if ($ch -eq [char]'"') { [void]$sb.Append($bs, $slashes * 2 + 1) }
        elseif ($slashes -gt 0) { [void]$sb.Append($bs, $slashes) }
        [void]$sb.Append($ch)
        $slashes = 0
    }
    [void]$sb.Append($bs, $slashes * 2).Append('"')
    return $sb.ToString()
}

# 外部コマンドを実行し、Code（終了コード）・Text（標準出力。OutputFile を指定したときは空）・
# Error（-CaptureError のときの標準エラー出力。指定しないときは画面にそのまま表示して、ここは空）を返す
function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [Parameter(Mandatory = $true)][string[]]$ArgList,
        [string]$InputText = '',
        [string]$InputFile = '',
        [string]$OutputFile = '',
        [switch]$CaptureError
    )
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = (@($ArgList | ForEach-Object { ConvertTo-CommandLineArg $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = [bool]$CaptureError
    if ($OutputFile) { $out = [System.IO.File]::Create($OutputFile) } else { $out = New-Object System.IO.MemoryStream }
    $err = New-Object System.IO.MemoryStream
    # .NET Framework の Process は、標準入力をコンソールの入力の文字コードで開き、その文字コードに BOM があると
    # 起動のときに BOM を書き込む（VERIFY.md の V9）。BOM なしの UTF-8 にしてから起動し、終わったら元に戻す。
    $savedInputEncoding = $null
    try {
        $savedInputEncoding = [Console]::InputEncoding
        [Console]::InputEncoding = $utf8
    } catch {
        $savedInputEncoding = $null
    }
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        # 出力は並行して読む（読まずに標準入力を書き続けると、出力がたまって止まることがあるため）
        $copy = $p.StandardOutput.BaseStream.CopyToAsync($out)
        $copyErr = $null
        if ($CaptureError) { $copyErr = $p.StandardError.BaseStream.CopyToAsync($err) }
        try {
            $in = $p.StandardInput.BaseStream
            $bytes = $utf8.GetBytes($InputText)
            $in.Write($bytes, 0, $bytes.Length)
            if ($InputFile) {
                $fs = [System.IO.File]::OpenRead($InputFile)
                try { $fs.CopyTo($in) } finally { $fs.Dispose() }
            }
            $in.Close()
        } catch [System.IO.IOException] {
            # 相手が先に終わった（入力を最後まで読まずに失敗したなど）。終了コードで判断する。
        }
        $copy.Wait()
        if ($null -ne $copyErr) { $copyErr.Wait() }
        $p.WaitForExit()
        $text = ''
        if (-not $OutputFile) { $text = $utf8.GetString($out.ToArray()) }
        return [pscustomobject]@{ Code = $p.ExitCode; Text = $text; Error = $utf8.GetString($err.ToArray()) }
    } finally {
        $out.Dispose()
        $err.Dispose()
        if ($null -ne $savedInputEncoding) {
            try { [Console]::InputEncoding = $savedInputEncoding } catch { }
        }
    }
}

# 出力を行に分ける（空の行は除く）。
# 配列を返す関数は、要素を 1 つずつ返す（return ,@(...) と書くと、パイプラインや @() の中で配列が 1 つのかたまりのまま渡ってしまう）。
# そのため、呼び出す側はいつも @(...) で囲んで配列として受け取る。
function ConvertTo-Lines([string]$Text) {
    return @($Text -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -ne '' })
}

# 検証のスクリプト（verify-base.sh・dcs-verify）の出力を、[OK] は緑、[WARN] は黄、ほかは赤で表示する
function Write-CheckLines([string]$Text) {
    foreach ($l in @(ConvertTo-Lines $Text)) {
        $s = Format-Safe $l
        if ($s.StartsWith('[OK]')) { Write-Host "  $s" -ForegroundColor Green }
        elseif ($s.StartsWith('[WARN]')) { Write-Host "  $s" -ForegroundColor Yellow }
        else { Write-Host "  $s" -ForegroundColor Red }
    }
}

# 検証のスクリプトの出力のうち、[NG] の行の ID（B2 など）を返す
function Get-CheckNgIds([string]$Text) {
    return @(ConvertTo-Lines $Text | ForEach-Object { if ($_ -match '^\[NG\] (\S+) ') { $Matches[1] } })
}

# -----------------------------------------------------------------------------
# 土台やコンテナに送るファイル
# -----------------------------------------------------------------------------

# 送るファイルの中身を、バイト列で返す。UTF-8 として読め、BOM が無く、改行が LF であることを確かめる（違えば止める）。
# 従来の Test-PayloadFiles・Get-PayloadBytes と同じ規則。
function Get-LfBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-Setup "必要なファイルが見つかりません: $Path" @('dev-container-setup フォルダの中身を、すべてそろえてから実行してください。')
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Stop-Setup "$Path の先頭に BOM が付いています。" @('土台やコンテナで使うファイルは「UTF-8（BOM なし）」で保存してください。')
    }
    if ([Array]::IndexOf($bytes, [byte]13) -ge 0) {
        Stop-Setup "$Path の改行コードが CRLF（Windows 形式）になっています。" @('土台やコンテナで使うファイルは、改行コードが LF でなければなりません。')
    }
    try {
        $null = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)
    } catch {
        Stop-Setup "$Path を UTF-8 として読めません。" @('UTF-8（BOM なし）で保存し直してください。')
    }
    return ,$bytes
}

# 送るファイル（Get-LfBytes で確かめたもの）の SHA256（16 進の小文字）。土台やコンテナの中のものと比べるのに使う
function Get-LfSha256([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return ([BitConverter]::ToString($sha.ComputeHash((Get-LfBytes $Path))) -replace '-', '').ToLowerInvariant()
}
