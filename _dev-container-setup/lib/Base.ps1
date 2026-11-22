#Requires -Version 5.1
# =============================================================================
# Base.ps1 — 土台（WSL のディストリビューション dcs-base）を作る・確かめる・ファイルを送る・中で実行する。
#            土台の Docker で、開発環境のイメージ（dcs-image）を作る
#
# Common.ps1 を先に dot-source しておく。決まっていること: DESIGN.md の 6.2（D3・D20）、6.5a（D29）、D38、D46・D47。
# 実機の確かめ: VERIFY.md の V1〜V6（作り方、wsl.conf、Docker、Dev Containers CLI、ベースのイメージ、Claude Code）。
# =============================================================================

$script:BaseName = 'dcs-base'
$script:BaseUser = 'dcs'
$script:BaseDistro = 'Ubuntu-26.04'
$script:DevcontainerCli = '/home/dcs/.devcontainers/bin/devcontainer'   # VERIFY.md の V4
$script:BaseReadyMark = '/opt/dcs/base-ready'
$script:ImageName = 'dcs-image'
$script:ImageDir = '/opt/dcs/image'   # イメージのビルドの材料（Copy-ToBase が image\ から置く）
$script:ToolRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path variable:script:DryRun)) { $script:DryRun = $false }

# wsl.exe は 3 か所に見つかる（System32・Program Files\WSL・WindowsApps の実行エイリアス）。最初の 1 つを使う（VERIFY.md の F3）
function Get-WslExe {
    $c = Get-Command wsl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $c) { Stop-Setup 'wsl.exe が見つかりません。' @('WSL が使える状態か確認してください。') }
    return $c.Path
}

# Windows のユーザーのフォルダ（C:\Users\<名前>）の <名前>。VS Code の拡張機能フォルダを土台に見せるのに使う（D20）
function Get-WinProfileName([string]$UserProfile) {
    $name = $null
    if ($UserProfile -match '^[Cc]:\\Users\\([^\\]+)\\?$') { $name = $Matches[1] }
    if ($null -eq $name -or $name -cnotmatch '^[A-Za-z0-9._-]+$') {
        Stop-Setup "Windows のユーザーのフォルダ（$UserProfile）が、このツールの前提と違います。" @(
            'VS Code の拡張機能フォルダ（C:\Users\<名前>\.vscode\extensions）を土台に見せるため、',
            'C:\Users\ の下にある、半角英数字と . _ - だけの名前のフォルダである必要があります。')
    }
    return $name
}

# wsl --list --quiet の出力を、ディストリビューションの名前の配列にする（古い WSL が混ぜる NUL と、空の行を除く）
function ConvertFrom-WslListText([string]$Text) {
    return @(($Text -replace "`0", '') -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

# wsl.exe を Invoke-Native で呼ぶ（出力を UTF-8 にそろえる）
function Invoke-Wsl {
    param([Parameter(Mandatory = $true)][string[]]$ArgList, [string]$InputText = '', [string]$InputFile = '', [string]$OutputFile = '', [switch]$CaptureError)
    $saved = $env:WSL_UTF8
    $env:WSL_UTF8 = '1'
    try {
        return (Invoke-Native -File (Get-WslExe) -ArgList $ArgList -InputText $InputText -InputFile $InputFile -OutputFile $OutputFile -CaptureError:$CaptureError)
    } finally {
        $env:WSL_UTF8 = $saved
    }
}

# 土台の中でコマンドを実行する（出力は受け取る）。$User は root か dcs
function Invoke-InBase {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('root', 'dcs')][string]$User,
        [Parameter(Mandatory = $true)][string[]]$ArgList,
        [string]$InputText = '',
        [string]$InputFile = '',
        [string]$OutputFile = '',
        [switch]$CaptureError
    )
    return (Invoke-Wsl -ArgList (@('-d', $script:BaseName, '-u', $User, '--cd', '/', '--exec') + $ArgList) `
        -InputText $InputText -InputFile $InputFile -OutputFile $OutputFile -CaptureError:$CaptureError)
}

# wsl.exe を、この画面にそのままつないで実行する（進み具合を表示したいもの）。終了コードを返す
function Start-Wsl {
    param([Parameter(Mandatory = $true)][string[]]$ArgList)
    $saved = $env:WSL_UTF8
    $env:WSL_UTF8 = '1'
    try {
        $argText = (@($ArgList | ForEach-Object { ConvertTo-CommandLineArg $_ }) -join ' ')
        $p = Start-Process -FilePath (Get-WslExe) -ArgumentList $argText -NoNewWindow -PassThru
        $null = $p.Handle   # これを先に取っておかないと、終了コードが取れないことがある
        $p.WaitForExit()
        return $p.ExitCode
    } finally {
        $env:WSL_UTF8 = $saved
    }
}

function Test-BaseExists {
    $r = Invoke-Wsl -ArgList @('--list', '--quiet') -CaptureError
    return (@(ConvertFrom-WslListText $r.Text) -contains $script:BaseName)
}

# 'Missing'（無い）・'Incomplete'（あるが、設定が終わった印が無い）・'Ready'
function Get-BaseState {
    if (-not (Test-BaseExists)) { return 'Missing' }
    $r = Invoke-InBase -User root -ArgList @('test', '-f', $script:BaseReadyMark) -CaptureError
    if ($r.Code -eq 0) { return 'Ready' }
    return 'Incomplete'
}

# 土台を止める（wsl.conf を効かせるため）。次に wsl.exe を使ったときに起動し直す
function Stop-Base {
    $r = Invoke-Wsl -ArgList @('--terminate', $script:BaseName) -CaptureError
    if ($r.Code -ne 0) { Stop-Setup "土台（$($script:BaseName)）を止められませんでした（終了コード $($r.Code)）。" @($r.Error.Trim()) }
}

# base\ と image\ の直下のファイルを、土台の /opt/dcs/base・/opt/dcs/image に root 所有で置く（image\ が無ければ飛ばす）。
# PowerShell 5.1 は外部コマンドへ文字列を渡すときに日本語や改行コードを変えてしまうことがあるため、
# 中身を base64 にして標準入力で渡し、土台の中で元に戻す。ハッシュ値で一致を確かめる（従来の Copy-PayloadToRoom と同じ）。
# 途中で失敗しても、前に置いたものを壊さない（I4。壊すと、次の実行の最初の土台の検証で止まり、抜け出せなくなる）:
# すべてのファイルを先に確かめてから、別の場所（<置き先>.new）に書き、ハッシュ値が一致したあとで入れ替える
function Copy-ToBase {
    Write-Step 'ツールのファイルを土台に置きます（/opt/dcs）'
    $sets = @(@{ Local = 'base'; Remote = '/opt/dcs/base' }, @{ Local = 'image'; Remote = '/opt/dcs/image' })
    if ($script:DryRun) { Write-DryRun 'base\ と image\ のファイルを、土台の /opt/dcs/base・/opt/dcs/image に置き、ハッシュ値を照合する'; return }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    # 1. すべてのファイルを読んで確かめる（土台には、まだ何もしない）
    $plan = @()
    foreach ($set in $sets) {
        $dir = Join-Path $script:ToolRoot $set.Local
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        $files = @()
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File)) {
            if ($f.Name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
                Stop-Setup "ファイル名に使えない文字があります: $($f.FullName)" @('半角英数字と . _ - だけの名前にしてください。')
            }
            $bytes = Get-LfBytes $f.FullName
            $files += [pscustomobject]@{ Name = $f.Name; Bytes = $bytes; Hash = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant() }
        }
        if ($files.Count -gt 0) { $plan += [pscustomobject]@{ Local = $set.Local; Remote = $set.Remote; Files = $files } }
    }
    $count = 0
    foreach ($set in $plan) {
        $remote = $set.Remote
        $new = "$remote.new"
        # 2. 別の場所に書く。bash に渡す文には " を書かない（wsl.exe のコマンドラインの読み方で壊れないように）。$1 は空白を含まない決まったパス
        $r = Invoke-InBase -User root -ArgList @('bash', '-c', 'rm -rf -- $1.new && install -d -m 755 -o root -g root /opt/dcs $1.new', '_', $remote) -CaptureError
        if ($r.Code -ne 0) { Stop-Setup "土台に $new を用意できませんでした（終了コード $($r.Code)）。" @($r.Error.Trim()) }
        foreach ($f in $set.Files) {
            $b64 = [Convert]::ToBase64String($f.Bytes)
            $w = Invoke-InBase -User root -ArgList @('bash', '-c', 'base64 -d -i > $1 && chmod 644 -- $1', '_', "$new/$($f.Name)") -InputText $b64 -CaptureError
            if ($w.Code -ne 0) { Stop-Setup "$($f.Name) を土台に置けませんでした（終了コード $($w.Code)）。" @($w.Error.Trim()) }
        }
        # 3. ハッシュ値で一致を確かめる
        $h = Invoke-InBase -User root -ArgList (@('sha256sum', '--') + @($set.Files | ForEach-Object { "$new/$($_.Name)" })) -CaptureError
        if ($h.Code -ne 0) { Stop-Setup '土台に置いたファイルのハッシュ値を計算できませんでした。' @($h.Error.Trim()) }
        $got = @{}
        foreach ($l in @(ConvertTo-Lines $h.Text)) { if ($l -match '^([0-9a-f]{64})\s+\*?(.+)$') { $got[$Matches[2]] = $Matches[1] } }
        foreach ($f in $set.Files) {
            if ($got["$new/$($f.Name)"] -ne $f.Hash) {
                Stop-Setup "土台に置いた $($set.Local)\$($f.Name) の内容が、元のファイルと一致しません。" @('もう一度実行してください（前に置いたものは、そのまま残っています）。')
            }
        }
        # 4. 入れ替える（前のものを .old にしてから、新しいものを置き先にする）
        $s = Invoke-InBase -User root -ArgList @('bash', '-c', 'rm -rf -- $1.old && { test ! -e $1 || mv -- $1 $1.old; } && mv -- $1.new $1 && rm -rf -- $1.old', '_', $remote) -CaptureError
        if ($s.Code -ne 0) { Stop-Setup "土台の $remote を新しいものに入れ替えられませんでした（終了コード $($s.Code)）。" @($s.Error.Trim()) }
        $count += $set.Files.Count
    }
    Write-Ok "$count 個のファイルを置き、内容が一致することを確かめました。"
}

# 土台の中の setup-base.sh を、root で、この画面にそのままつないで実行する
function Invoke-BaseSetup {
    param([Parameter(Mandatory = $true)][ValidateSet('main', 'mount', 'upgrade')][string]$Phase, [string]$ProfileName = '')
    $argList = @('-d', $script:BaseName, '-u', 'root', '--cd', '/', '--exec', 'bash', '/opt/dcs/base/setup-base.sh', '--phase', $Phase)
    if ($ProfileName) { $argList += $ProfileName }
    Write-Step "土台の設定（setup-base.sh --phase $Phase）"
    if ($script:DryRun) { Write-DryRun ('wsl.exe ' + ($argList -join ' ')); return }
    $code = Start-Wsl $argList
    if ($code -ne 0) {
        Stop-Setup "土台の設定（--phase $Phase）に失敗しました（終了コード $code）。" @(
            '上に表示されたメッセージを確かめてください。',
            '原因を取り除いてから、もう一度実行すると、続きから設定します（土台は消えません）。')
    }
}

# 土台を検証する（verify-base.sh）。結果を表示し、NG が無ければ $true を返す（WARN は失敗に数えない）。
# B2 は、/etc/wsl.conf を、Windows 側のツールの base\wsl.conf と比べる（SHA256 を渡す。土台に置いたファイルが古くても、正しく判定する）。
# -Always: 読むだけなので、ドライランでも行う（土台があると分かっているとき。M1）。
# -Tolerate: この ID の NG だけなら、通ったものとして扱う（「更新」の前の B2。更新が直す）
function Test-Base {
    param([switch]$Always, [string[]]$Tolerate = @())
    Write-Step "土台（$($script:BaseName)）を検証します"
    if ($script:DryRun -and -not $Always) { Write-DryRun 'bash /opt/dcs/base/verify-base.sh <プロファイル名> <wsl.conf の SHA256>（dcs で）'; return $true }
    $profileName = Get-WinProfileName $env:USERPROFILE
    $wslConf = Get-LfSha256 (Join-Path $script:ToolRoot 'base\wsl.conf')
    $r = Invoke-InBase -User dcs -ArgList @('bash', '/opt/dcs/base/verify-base.sh', $profileName, $wslConf) -CaptureError
    Write-CheckLines $r.Text
    if ($r.Code -eq 0) { return $true }
    $ng = @(Get-CheckNgIds $r.Text)
    if ($r.Code -eq 1 -and $ng.Count -gt 0 -and @($ng | Where-Object { $Tolerate -notcontains $_ }).Count -eq 0) {
        Write-Note "$($ng -join '、') の NG は、このあとの更新で直します。"
        return $true
    }
    if ($r.Error.Trim()) { Write-Host "  $(Format-Safe $r.Error.Trim())" -ForegroundColor Red }
    return $false
}

# 土台を作る（Missing）か、途中から続ける（Incomplete）。Ready なら何もしない。
function New-Base {
    $state = Get-BaseState
    if ($state -eq 'Ready') { Write-Ok "土台（$($script:BaseName)）は、設定が終わっています。"; return }
    $profileName = Get-WinProfileName $env:USERPROFILE
    if ($state -eq 'Missing') {
        Write-Step "土台（$($script:BaseName)）を作ります（$($script:BaseDistro)）"
        $argList = @('--install', $script:BaseDistro, '--name', $script:BaseName, '--no-launch')
        if ($script:DryRun) {
            Write-DryRun ('wsl.exe ' + ($argList -join ' '))
        } else {
            $code = Start-Wsl $argList
            if ($code -ne 0) { Stop-Setup "土台の作成（wsl --install）が正常に終わりませんでした（終了コード $code）。" @('上に表示されたメッセージを確かめてください。') }
            if (-not (Test-BaseExists)) { Stop-Setup "土台（$($script:BaseName)）が作成されていません。" @('上に表示されたメッセージを確かめてください。') }
            Write-Ok "土台（$($script:BaseName)）を作りました。"
        }
    } else {
        Write-Note "土台（$($script:BaseName)）の設定が途中で止まっていたので、続きから設定します。"
    }
    Copy-ToBase
    Invoke-BaseSetup -Phase main -ProfileName $profileName
    if (-not $script:DryRun) { Stop-Base }   # wsl.conf を効かせる
    Invoke-BaseSetup -Phase mount -ProfileName $profileName
    if (-not $script:DryRun) { Stop-Base }   # fstab のマウントが起動のときに効くことを、続く検証で確かめる
    if (-not (Test-Base)) {
        Stop-Setup '土台の検証に通りませんでした（上の [NG] の行）。' @('表示された理由を取り除いてから、もう一度実行してください。')
    }
    # ドライランでは何もしていないので、終わったとは言わない
    if (-not $script:DryRun) { Write-Ok "土台（$($script:BaseName)）の設定が終わりました。" }
}

# 土台の Docker に、イメージ dcs-image があるか
function Test-DcsImageExists {
    $r = Invoke-InBase -User dcs -ArgList @('docker', 'image', 'inspect', '--format', '{{.Id}}', $script:ImageName) -CaptureError
    return ($r.Code -eq 0)
}

# イメージ dcs-image を、土台の /opt/dcs/image から作る（材料は先に Copy-ToBase で置いておく）。
# 通常は、イメージがあれば作らない（D38。Docker Hub からベースのイメージを取るのは、初めて作るときと「更新」のときだけ）。
# -Refresh は --pull --no-cache を付けて、いつも作り直す（「更新」と、開発の途中で材料を変えたとき）
function Build-DcsImage {
    param([switch]$Refresh)
    # あるかどうかを見るのは読むだけなので、ドライランでも見る（M1。土台がまだ無ければ、無いと分かる）
    if (-not $Refresh -and (Test-DcsImageExists)) {
        Write-Ok "既にあるイメージ（$($script:ImageName)）を使います。"
        return
    }
    Write-Step "イメージ（$($script:ImageName)）を作ります（数分かかります）"
    $uid = '<土台の id -u dcs>'
    if (-not $script:DryRun) {
        $u = Invoke-InBase -User dcs -ArgList @('id', '-u') -CaptureError
        $uid = $u.Text.Trim()
        if ($u.Code -ne 0 -or $uid -notmatch '^[1-9][0-9]*$') {
            Stop-Setup "土台のユーザー（$($script:BaseUser)）の UID を読めませんでした（終了コード $($u.Code)）。" @($u.Error.Trim())
        }
    }
    # --progress=plain: 手順ごとに行を足していく表示にする（既定の表示は行を書き換えるので、ウィザードの画面では行が積み重なって読めない。TEST.md の 2）
    $argList = @('-d', $script:BaseName, '-u', 'dcs', '--cd', '/', '--exec', 'docker', 'build', '--progress=plain', '--label', 'dcs=1', '--build-arg', "DCS_UID=$uid", '-t', $script:ImageName)
    if ($Refresh) { $argList += @('--pull', '--no-cache') }
    $argList += $script:ImageDir
    if ($script:DryRun) { Write-DryRun ('wsl.exe ' + ($argList -join ' ')); return }
    $code = Start-Wsl $argList
    if ($code -ne 0) {
        Stop-Setup "イメージ（$($script:ImageName)）を作れませんでした（終了コード $code）。" @(
            '上に表示されたメッセージを確かめてください（ネットワークにつながっているか、など）。',
            '原因を取り除いてから、もう一度実行してください。')
    }
    Write-Ok "イメージ（$($script:ImageName)）を作りました。"
}
