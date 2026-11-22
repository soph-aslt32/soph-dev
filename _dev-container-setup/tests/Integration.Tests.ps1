# 実機のテスト（タグ Integration）。土台 dcs-base を作り、その中で動かす。ユーザーの了承を得てから実行する。
#   Invoke-Pester -Script .\_dev-container-setup\tests\Integration.Tests.ps1 -Tag Integration -TestName '<名前>'
# 削除（wsl --unregister、docker volume rm など）は、テストでは行わない（ユーザーが行う）。
# 本番（入口のスクリプト）と同じ条件で動かす
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\lib\Common.ps1"
. "$PSScriptRoot\..\lib\Validation.ps1"
. "$PSScriptRoot\..\lib\Base.ps1"
. "$PSScriptRoot\..\lib\Config.ps1"
. "$PSScriptRoot\..\lib\Env.ps1"
. "$PSScriptRoot\..\lib\Scripts.ps1"
. "$PSScriptRoot\TestHelpers.ps1"

Describe 'Base' -Tag Integration {
    It 'creates the base when it is missing' {
        Get-BaseState | Should Be 'Missing'
        New-Base
        Get-BaseState | Should Be 'Ready'
        Test-Base | Should Be $true
    }
    It 'does nothing and does not fail when the base is already ready' {
        { New-Base } | Should Not Throw
        Get-BaseState | Should Be 'Ready'
    }
    It 'resumes when the setup did not finish (Review Focus 2)' {
        # 設定が途中で止まった状態を作る（ツールが書いた「設定が終わった印」だけを消す）
        (Invoke-InBase -User root -ArgList @('rm', '-f', '--', '/opt/dcs/base-ready') -CaptureError).Code | Should Be 0
        Get-BaseState | Should Be 'Incomplete'
        New-Base
        Get-BaseState | Should Be 'Ready'
        Test-Base | Should Be $true
    }
}

# 土台が Ready であること（Describe 'Base'）を前提にする
Describe 'Image' -Tag Integration {
    It 'builds dcs-image from the files in image\' {
        Copy-ToBase
        Build-DcsImage -Refresh
        Test-DcsImageExists | Should Be $true
    }
    It 'places ~/.claude/settings.json as the preferences merged with the guard (dcs-settings)' {
        $r = Invoke-ImageTest (Join-Path $PSScriptRoot 'container\dcs-settings.test.sh')
        if ($r.Code -ne 0) { Write-Host $r.Text; Write-Host $r.Error }
        $r.Code | Should Be 0
        $r.Text.TrimEnd() | Should Match 'PASS$'
    }
    It 'passes the image checks (dcs-verify --only image)' {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $bytes = Get-LfBytes (Join-Path $PSScriptRoot '..\image\managed-settings.json')
        $hash = ([BitConverter]::ToString($sha256.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
        $r = Invoke-InBase -User dcs -ArgList @('docker', 'run', '--rm', '--pull', 'never', 'dcs-image', 'bash', '-c', "dcs-settings && dcs-verify --only image --managed-sha256 $hash") -CaptureError
        Write-Host $r.Text
        if ($r.Code -ne 0) { Write-Host $r.Error }
        $r.Code | Should Be 0
    }
    It 'tells to choose the update when the managed settings differ from the tool (M5)' {
        $r = Invoke-InBase -User dcs -ArgList @('docker', 'run', '--rm', '--pull', 'never', 'dcs-image', 'bash', '-c', ('dcs-settings > /dev/null && dcs-verify --only image --managed-sha256 ' + ('0' * 64))) -CaptureError
        Write-Host $r.Text
        $r.Code | Should Be 1
        $r.Text | Should Match '\[NG\] I4 .*「更新」'
    }
    It 'finds the system commands before the ones in the folders Claude can write (C1)' {
        $r = Invoke-ImageTest (Join-Path $PSScriptRoot 'container\path.test.sh')
        if ($r.Code -ne 0) { Write-Host $r.Text; Write-Host $r.Error }
        $r.Code | Should Be 0
        $r.Text.TrimEnd() | Should Match 'PASS$'
    }
}

# 土台が Ready であること（Describe 'Base'）を前提にする
Describe 'BaseCheck' -Tag Integration {
    It 'compares /etc/wsl.conf with the SHA256 of the wsl.conf of the tool (B2)' {
        Copy-ToBase
        $r = Invoke-BaseTest (Join-Path $PSScriptRoot 'container\verify-base.test.sh')
        if ($r.Code -ne 0) { Write-Host $r.Text; Write-Host $r.Error }
        $r.Code | Should Be 0
        $r.Text.TrimEnd() | Should Match 'PASS$'
    }
}

# 削除のときの、土台のフォルダの消し方（M3）。土台の /tmp に試しのフォルダを作って消す
Describe 'Delete' -Tag Integration {
    It 'removes a folder that has a read-only folder in it (M3)' {
        $root = '/tmp/dcs-delete-test'
        (Invoke-InBase -User dcs -ArgList @('bash', '-c', 'rm -rf -- $1; mkdir -p -- $1/work/ro && touch -- $1/work/ro/f && chmod a-w -- $1/work/ro', '_', $root) -CaptureError).Code | Should Be 0
        # ふつうの rm -rf では消せない（直す前の削除は、これで毎回失敗した）
        (Invoke-InBase -User dcs -ArgList @('rm', '-rf', '--', $root) -CaptureError).Code | Should Not Be 0
        (Invoke-InBase -User dcs -ArgList @(Get-RemoveEnvFolderArgs $root) -CaptureError).Code | Should Be 0
        (Invoke-InBase -User dcs -ArgList @('test', '-e', $root) -CaptureError).Code | Should Be 1
    }
}

# 土台が Ready であること（Describe 'Base'）を前提にする
Describe 'Firewall' -Tag Integration {
    It 'lets out only the allowed destinations, and stays closed when it fails (Review Focus 3, 4)' {
        Copy-ToBase
        Build-DcsImage -Refresh
        $r = Invoke-BaseTest (Join-Path $PSScriptRoot 'container\firewall.test.sh')
        Write-Host $r.Text
        if ($r.Code -ne 0) { Write-Host $r.Error }
        $r.Code | Should Be 0
        $r.Text.TrimEnd() | Should Match 'PASS$'
    }
}

# 土台が Ready であること（Describe 'Base'）を前提にする
Describe 'Forwarding' -Tag Integration {
    It 'warns about what VS Code forwarded into the container (dcs-check-forwarding)' {
        Copy-ToBase
        Build-DcsImage -Refresh
        $r = Invoke-ImageTest (Join-Path $PSScriptRoot 'container\check-forwarding.test.sh')
        if ($r.Code -ne 0) { Write-Host $r.Text; Write-Host $r.Error }
        $r.Code | Should Be 0
        $r.Text.TrimEnd() | Should Match 'PASS$'
    }
}

# 土台が Ready で、イメージがあること（Describe 'Base'・'Image'）を前提にする。
# 試しの開発環境 itest を作る。itest は Task 9・11 でも使うので残す（片付けはユーザーが行う）
Describe 'Env' -Tag Integration {
    It 'creates the env, and it passes the checks from outside and inside' {
        Build-DcsImage
        New-EnvFiles 'itest' 'GitHub' 'itest-repo' @('pypi.org') @()
        # 注文書を書き直したので、コンテナを作り直す（devcontainer up は、名札の合う古いコンテナをそのまま使うため。
        # ウィザードの「やり直す」「更新」と同じ）
        Remove-EnvContainer 'itest'
        Start-EnvContainer 'itest' | Should Match '^[0-9a-f]{64}$'
        Test-EnvOutside 'itest' 'GitHub' | Should Be $true
        Test-EnvInside 'itest' | Should Be $true
    }
    It 'passes arguments with spaces, quotes, $ and Japanese into the container as they are (Review Focus 5)' {
        $r = Invoke-InEnv 'itest' @('printf', '%s|', 'a b', 'c"d', "e'f", '$HOME', '日本語')
        if ($r.Code -ne 0) { Write-Host $r.Error }
        $r.Code | Should Be 0
        $r.Text | Should Be ('a b|c"d|' + "e'f" + '|$HOME|日本語|')
    }
    It 'passes standard input into the container as it is' {
        $r = Invoke-InEnv 'itest' @('cat') -InputText "x y`n日本`n"
        $r.Code | Should Be 0
        $r.Text | Should Be "x y`n日本`n"
    }
    It 'keeps ~/.claude in the volume when the container is made again' {
        $mark = '/home/dev/.claude/dcs-itest-volume-check'
        $old = Get-EnvContainerId 'itest'
        (Invoke-InEnv 'itest' @('touch', $mark)).Code | Should Be 0
        Remove-EnvContainer 'itest'
        Get-EnvContainerId 'itest' | Should BeNullOrEmpty
        $new = Start-EnvContainer 'itest'
        $new | Should Not Be $old
        # rm は、目印が無ければ失敗する（残っていることを確かめ、そのまま片付ける）
        (Invoke-InEnv 'itest' @('rm', '--', $mark)).Code | Should Be 0
        Test-EnvInside 'itest' | Should Be $true
    }
    # Claude が書ける場所に、何もしない sudo と、~/.bashrc が読まれたら印を残す行を置いてから、コンテナを止めて起動し直す
    It 'keeps the firewall after a fake sudo is put in ~/.local/bin, and does not read ~/.bashrc (C1)' {
        $plant = @(
            'set -e',
            'mkdir -p ~/.local/bin',
            "printf '#!/bin/sh\nexit 0\n' > ~/.local/bin/sudo",
            'chmod +x ~/.local/bin/sudo',
            'cp ~/.bashrc ~/.bashrc.dcs-test',
            "echo 'touch /tmp/dcs-probe-ran' >> ~/.bashrc",
            'rm -f /tmp/dcs-probe-ran') -join "`n"
        try {
            (Invoke-InEnv 'itest' @('/bin/bash', '-s') -InputText ($plant + "`n")).Code | Should Be 0
            $id = Get-EnvContainerId 'itest'
            (Invoke-InBase -User dcs -ArgList @('docker', 'stop', $id) -CaptureError).Code | Should Be 0
            # 次の起動（devcontainer up の postStartCommand）でも、本物の sudo でファイアウォールが入る
            $r = Invoke-InEnv 'itest' @('/usr/local/bin/dcs-verify', '--only', 'firewall')
            Write-Host $r.Text
            $r.Code | Should Be 0
            # 起動のときと、コマンドを実行するときに、~/.bashrc を読んでいない（userEnvProbe: none）
            (Invoke-InEnv 'itest' @('/usr/bin/test', '-e', '/tmp/dcs-probe-ran')).Code | Should Be 1
        } finally {
            $null = Invoke-InEnv 'itest' @('/bin/bash', '-c', 'rm -f ~/.local/bin/sudo /tmp/dcs-probe-ran; if [ -f ~/.bashrc.dcs-test ]; then mv -f ~/.bashrc.dcs-test ~/.bashrc; fi')
        }
    }
}

# 試しの開発環境 itest3（LocalGit モード。リポジトリ名 r）を作る（-Initialize を試すため、新しい開発環境で動かす）。Windows 側の bare リポジトリは TestDrive に作る（テストのあとで消える）。
# itest3 と、ツールのフォルダの envs\itest3\ のスクリプトは残す（片付けはユーザーが行う）
Describe 'LocalGit' -Tag Integration {
    $git = (Get-Command git.exe -CommandType Application | Select-Object -First 1).Path
    $powershell = (Get-Command powershell.exe -CommandType Application | Select-Object -First 1).Path
    $lg = 'itest3'
    $ws = '/workspaces/r'
    $bare = Join-Path $TestDrive 'r.git'
    $sync = Join-Path $script:ToolRoot "envs\$lg\Sync-$lg.ps1"
    $who = @('-c', 'user.name=T', '-c', 'user.email=t@example.com')
    function Invoke-TestGit([string[]]$GitArgs, [string]$InputText = '') {
        $r = Invoke-Native -File $git -ArgList $GitArgs -InputText $InputText -CaptureError
        if ($r.Code -ne 0) { throw "git $($GitArgs -join ' ') に失敗しました: $($r.Error)" }
        return $r.Text.Trim()
    }
    # Windows 側の bare リポジトリの main に、空のコミットを 1 つ足す
    function Add-WinCommit([string]$Message) {
        $tree = Invoke-TestGit @("--git-dir=$bare", 'mktree')
        $parent = @()
        $head = Invoke-Native -File $git -ArgList @("--git-dir=$bare", 'rev-parse', '-q', '--verify', 'refs/heads/main') -CaptureError
        if ($head.Code -eq 0) { $parent = @('-p', $head.Text.Trim()) }
        $commit = Invoke-TestGit (@("--git-dir=$bare") + $who + @('commit-tree', $tree) + $parent + @('-m', $Message))
        $null = Invoke-TestGit @("--git-dir=$bare", 'update-ref', 'refs/heads/main', $commit)
    }
    # コンテナの中でコミットして、/relay.git に push する
    function Add-EnvCommit([string]$Message) {
        (Invoke-InEnv $lg (@('git', '-C', $ws) + $who + @('commit', '-q', '--allow-empty', '-m', $Message))).Code | Should Be 0
        (Invoke-InEnv $lg @('git', '-C', $ws, 'push', '-q', 'origin', 'HEAD')).Code | Should Be 0
    }
    # 生成した同期スクリプトを、別の PowerShell で動かす（標準入力に、確かめの答えを渡す）。終了コードを返す
    function Invoke-Sync([string[]]$SyncArgs = @(), [string]$InputText = '') {
        $r = Invoke-Native -File $powershell -ArgList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $sync) + $SyncArgs) -InputText $InputText -CaptureError
        Write-Host $r.Text
        if ($r.Error.Trim()) { Write-Host $r.Error }
        return $r.Code
    }

    It 'makes the env and copies the Windows repository into it (-Initialize)' {
        $null = Invoke-TestGit @('init', '-q', '--bare', '--initial-branch=main', $bare)
        Add-WinCommit 'init'
        New-EnvFiles $lg 'LocalGit' 'r' @() @()
        Start-EnvContainer $lg | Should Match '^[0-9a-f]{64}$'
        Test-EnvOutside $lg 'LocalGit' | Should Be $true
        Write-EnvScripts $lg 'LocalGit' $bare
        Invoke-Sync @('-Initialize') | Should Be 0
        (Invoke-InEnv $lg @('git', '-C', $ws, 'log', '-1', '--format=%s')).Text.Trim() | Should Be 'init'
    }
    It 'copies a commit made in the container to Windows after y' {
        Add-EnvCommit 'from-env'
        Invoke-Sync @() "y`n" | Should Be 0
        Invoke-TestGit @("--git-dir=$bare", 'log', '-1', '--format=%s', 'refs/heads/main') | Should Be 'from-env'
    }
    It 'stops and copies nothing when both sides changed' {
        Add-EnvCommit 'env-side'
        Add-WinCommit 'win-side'
        $winBefore = Invoke-TestGit @("--git-dir=$bare", 'rev-parse', 'refs/heads/main')
        $envBefore = (Invoke-InEnv $lg @('git', '--git-dir=/relay.git', 'rev-parse', 'refs/heads/main')).Text.Trim()
        Invoke-Sync @() "y`n" | Should Be 1
        Invoke-TestGit @("--git-dir=$bare", 'rev-parse', 'refs/heads/main') | Should Be $winBefore
        (Invoke-InEnv $lg @('git', '--git-dir=/relay.git', 'rev-parse', 'refs/heads/main')).Text.Trim() | Should Be $envBefore
    }
}

# イメージがあることを前提にする。使い捨てのコンテナで動かす（作業フォルダは tmpfs。テストのあとで消える）
Describe 'GitHub' -Tag Integration {
    It 'saves the PAT without showing it, and refuses a symlink and a short input (dcs-github)' {
        $r = Invoke-ImageTest (Join-Path $PSScriptRoot 'container\dcs-github.test.sh') @(
            '--mount', 'type=tmpfs,destination=/workspaces/t,tmpfs-mode=1777', '-e', 'DCS_WORKSPACE=/workspaces/t')
        if ($r.Code -ne 0) { Write-Host $r.Text; Write-Host $r.Error }
        $r.Code | Should Be 0
        $r.Text.TrimEnd() | Should Match 'PASS$'
    }
}
