# ウィザード（DevContainerSetup.ps1）の判断だけを行う関数の単体テスト。WSL の中では何も実行しない。Pester 3.4 で動かす。
#   Invoke-Pester -Script .\_dev-container-setup\tests\Wizard.Tests.ps1
# DevContainerSetup.ps1 は、. で読み込んだときは Invoke-Main を呼ばない（本番と同じく StrictMode を設定する）
. "$PSScriptRoot\..\DevContainerSetup.ps1"

Describe 'ConvertFrom-RunningEnvText' {
    It 'keeps valid names' { (ConvertFrom-RunningEnvText "foo`nBad Name`n`nbar-1`n") -join '|' | Should Be 'foo|bar-1' }
}
Describe 'Get-EnvMode' {
    It 'relay => LocalGit' { Get-EnvMode $true | Should Be 'LocalGit' }
    It 'else GitHub' { Get-EnvMode $false | Should Be 'GitHub' }
}
Describe 'Get-EnvLeftovers' {
    It 'none' { @(Get-EnvLeftovers 'foo' "bar`n" '' "dcs-bar-claude`n" "dcs-bar`n").Count | Should Be 0 }
    It 'exact match only' { (Get-EnvLeftovers 'foo' '' '' "dcs-foo-claude`ndcs-food-git`n" '') -join ' ' | Should Match 'dcs-foo-claude'; @(Get-EnvLeftovers 'foo' '' '' "dcs-food-git`n" '').Count | Should Be 0 }
    It 'all kinds' { @(Get-EnvLeftovers 'foo' "foo`n" "foo`n" "dcs-foo-git `n" "dcs-foo`n").Count | Should Be 4 }
    It 'VS Code state volume by label' {
        $v = "vscode-state-config-aaa /home/dcs/envs/foo/config/.devcontainer/devcontainer.json`nvscode-state-config-bbb /home/dcs/envs/food/config/.devcontainer/devcontainer.json`n"
        $r = @(Get-EnvLeftovers 'foo' '' '' $v '')
        $r.Count | Should Be 1
        ($r -join ' ') | Should Match 'vscode-state-config-aaa'
    }
}
Describe 'Get-EnvRunningHints' {
    It 'tells to close the window, and why an env not opened in VS Code can still be running' {
        $h = (Get-EnvRunningHints) -join "`n"
        $h | Should Match 'ウィンドウを閉じて'
        $h | Should Match 'ほかの開発環境を VS Code で開いている'
        $h | Should Match 'wsl --terminate dcs-base'
        $h | Should Match '何も変更していません'
    }
}
Describe 'Get-DeleteDoneText' {
    It 'mentions the Windows repository only for LocalGit' {
        Get-DeleteDoneText 'foo' $true | Should Match 'dcs-sync\\foo\.txt'
        Get-DeleteDoneText 'foo' $false | Should Not Match 'LocalGit|dcs-sync'
        Get-DeleteDoneText 'foo' $false | Should Match '「foo」を削除しました'
    }
}
Describe 'Get-DeleteNameHelp' {
    It 'lists the envs and says a name with only leftovers can be entered' {
        $h = @(Get-DeleteNameHelp @('a', 'b'))
        $h[0] | Should Be '今ある開発環境: a、b'
        ($h -join "`n") | Should Match '残りがあると表示された名前'
    }
    It 'says none when there is no env' {
        @(Get-DeleteNameHelp @())[0] | Should Be '今ある開発環境: （なし）'
    }
}
Describe 'Get-UpdateEnvStepText' {
    It 'names the env and its place in the update, so each env has its own heading' {
        Get-UpdateEnvStepText 'e2e-lg' 2 2 | Should Be '開発環境（e2e-lg）のコンテナを作り直します（2/2）'
    }
}
Describe 'Get-GitHubSetupCommand' {
    It 'asks dcs-github for colors only when its output goes to the screen as it is (absolute paths. C1)' {
        (Get-GitHubSetupCommand $true) -join ' ' | Should Be '/usr/bin/env DCS_COLOR=1 /usr/local/bin/dcs-github'
        (Get-GitHubSetupCommand $false) -join ' ' | Should Be '/usr/local/bin/dcs-github'
    }
}
# コンテナの中のコマンドは、絶対パスで呼ぶ（C1。Claude が ~/.local/bin などに同じ名前のものを置いても使われない）
Describe 'commands in the container are called by absolute paths (C1)' {
    It 'dcs-verify' {
        Mock Invoke-InEnv { [pscustomobject]@{ Code = 0; Text = ''; Error = '' } }
        Mock Write-CheckLines {}
        Mock Write-Step {}
        $null = Test-EnvInside 'foo'
        Assert-MockCalled Invoke-InEnv -Scope It -Times 1 -Exactly -ParameterFilter { $Command[0] -eq '/usr/local/bin/dcs-verify' }
    }
    It 'dcs-settings' {
        Mock Invoke-InBase { [pscustomobject]@{ Code = 0; Text = ('{"outcome":"success","containerId":"' + ('a' * 64) + '"}'); Error = '' } }
        Mock Invoke-InEnv { [pscustomobject]@{ Code = 0; Text = ''; Error = '' } }
        Mock Write-Step {}
        Mock Write-Ok {}
        $null = Start-EnvContainer 'foo'
        Assert-MockCalled Invoke-InEnv -Scope It -Times 1 -Exactly -ParameterFilter { $Command[0] -eq '/usr/local/bin/dcs-settings' }
    }
}
# 「やり直す」の GitHub は、clone してあるリポジトリの origin と作者を、土台で work/.git/config を読んで取り出す（I1。
# コンテナを起動しない。ドライランや確認の前でも、何も変えない）
Describe 'Get-EnvRepoSettings' {
    $config = "[core]`n`tbare = false`n[remote `"origin`"]`n`turl = https://github.com/o/r.git`n[user]`n`tname = Dev`n`temail = dev@example.com`n"
    It 'reads the origin and the author from work/.git/config on the base, without starting the container (I1)' {
        Mock Invoke-InEnv { throw 'the container was started' }
        Mock Invoke-InBase { [pscustomobject]@{ Code = 0; Text = $config; Error = '' } }
        $s = Get-EnvRepoSettings 'foo'
        $s.Url | Should Be 'https://github.com/o/r.git'
        $s.UserName | Should Be 'Dev'
        $s.UserEmail | Should Be 'dev@example.com'
        Assert-MockCalled Invoke-InEnv -Scope It -Times 0 -Exactly
        Assert-MockCalled Invoke-InBase -Scope It -Times 1 -Exactly -ParameterFilter { $User -eq 'dcs' -and $ArgList[-1] -eq '/home/dcs/envs/foo/work' }
    }
    It 'is nothing before the clone' {
        Mock Invoke-InBase { [pscustomobject]@{ Code = 3; Text = ''; Error = '' } }
        Get-EnvRepoSettings 'foo' | Should BeNullOrEmpty
    }
    It 'stops when .git is not what the clone made (a symlink and so on)' {
        Mock Invoke-InBase { [pscustomobject]@{ Code = 4; Text = ''; Error = '' } }
        { Get-EnvRepoSettings 'foo' } | Should Throw '.git'
    }
    It 'stops when it cannot read the file' {
        Mock Invoke-InBase { [pscustomobject]@{ Code = 1; Text = ''; Error = 'x' } }
        { Get-EnvRepoSettings 'foo' } | Should Throw '読めませんでした'
    }
    It 'removes control characters from the values' {
        Mock Invoke-InBase { [pscustomobject]@{ Code = 0; Text = "[user]`n`tname = a$([char]27)[31mb`n"; Error = '' } }
        (Get-EnvRepoSettings 'foo').UserName | Should Be 'a?[31mb'
    }
}
# 土台の検証（Invoke-Preface）: 「更新」のときは、B2（wsl.conf）の NG で止めずに進む（更新で wsl.conf を置き直すため）
Describe 'Invoke-Preface' {
    BeforeEach {
        Mock Get-WslExe { 'wsl.exe' }
        Mock Get-BaseState { 'Ready' }
        Mock Write-CheckLines {}
        Mock Write-Note {}
        Mock Write-Ok {}
        Mock Write-Step {}
    }
    It 'goes on to the update when only B2 is NG (the wsl.conf of the tool was changed)' {
        Mock Invoke-InBase { [pscustomobject]@{ Code = 1; Text = "[OK] B1 a`n[NG] B2 b: c`n"; Error = '' } }
        { Invoke-Preface $false $true } | Should Not Throw
        { Invoke-Preface $false $false } | Should Throw '土台の検証に通りませんでした'
    }
    It 'checks the base also in a dry run, because it only reads (M1)' {
        Mock Invoke-InBase { [pscustomobject]@{ Code = 0; Text = "[OK] B1 a`n"; Error = '' } }
        $script:DryRun = $true
        try { $null = Invoke-Preface $false $false } finally { $script:DryRun = $false }
        Assert-MockCalled Invoke-InBase -Scope It -Times 1 -Exactly -ParameterFilter { ($ArgList -join ' ') -match 'verify-base\.sh' }
    }
}
Describe 'Invoke-VerifyOnly (dry run)' {
    It 'does not say that the env passed, because nothing was checked (M1)' {
        Mock Get-EnvNames { @('foo') }
        Mock Read-EnvName { 'foo' }
        Mock Test-EnvHasRelay { $false }
        Mock Get-RunningEnvNames { @() }
        Mock Start-EnvContainer { '' }
        Mock Test-Env { $true }
        Mock Write-Ok {}
        Mock Write-Step {}
        $script:DryRun = $true
        try { Invoke-VerifyOnly } finally { $script:DryRun = $false }
        Assert-MockCalled Write-Ok -Scope It -Times 0 -Exactly -ParameterFilter { $Text -like '*検証に通りました*' }
        Assert-MockCalled Write-Ok -Scope It -Times 1 -Exactly -ParameterFilter { $Text -like '*ドライランが終わりました*' }
    }
}
Describe 'Invoke-BaseChange' {
    It 'says what failed, not that it could not read (M2)' {
        Mock Invoke-InBase { [pscustomobject]@{ Code = 1; Text = ''; Error = 'boom' } }
        { Invoke-BaseChange @('docker', 'rm', '-f', 'x') 'コンテナの削除' } | Should Throw 'コンテナの削除に失敗しました（終了コード 1）。'
    }
    It 'returns quietly when it works' {
        Mock Invoke-InBase { [pscustomobject]@{ Code = 0; Text = 'x'; Error = '' } }
        { Invoke-BaseChange @('true') 'x' } | Should Not Throw
    }
}
Describe 'Get-EnvVerifyFailedHints' {
    It 'tells to choose the update when the image is older than the tool (M5)' {
        $h = (Get-EnvVerifyFailedHints '') -join "`n"
        $h | Should Match '「開発環境の設定をやり直す」'
        $h | Should Match '「更新」'
        $h | Should Match 'README の 7\.1'   # ツールの版を変えたときは、完全削除して入れ直す（D53。m3）
    }
}
Describe 'Add-SetupHint' {
    It 'adds lines to the hint of a Stop-Setup error' {
        $e = $null
        try { Stop-Setup 'm' @('a') } catch { $e = $_.Exception }
        Add-SetupHint $e @('b')
        @($e.Data['Hint']) -join '|' | Should Be 'a|b'
    }
    It 'leaves an unexpected error as it is' {
        $e = New-Object System.Exception 'x'
        Add-SetupHint $e @('b')
        $e.Data.Contains('Hint') | Should Be $false
    }
}
# 「作る」「やり直す」: 注文書のひな形の誤りは、値を聞く前に見つける（M4）
Describe 'checking the template first (M4)' {
    It 'Invoke-Create' {
        Mock Read-Extensions { @() }
        Mock Assert-DevcontainerTemplate { Stop-Setup 'the template is broken' }
        Mock Read-WizardValue { throw 'asked' }
        Mock Write-Step {}
        { Invoke-Create 'Ready' } | Should Throw 'the template is broken'
        Assert-MockCalled Read-WizardValue -Scope It -Times 0 -Exactly
    }
    It 'Invoke-Redo' {
        Mock Read-Extensions { @() }
        Mock Assert-DevcontainerTemplate { Stop-Setup 'the template is broken' }
        Mock Get-EnvNames { @('foo') }
        Mock Read-EnvName { throw 'asked' }
        Mock Write-Step {}
        { Invoke-Redo } | Should Throw 'the template is broken'
        Assert-MockCalled Read-EnvName -Scope It -Times 0 -Exactly
    }
}
# 「作る」が、開発環境のものを作り始めたあとで止まったときは、作りかけが残っていることと、続け方を伝える（M4。
# もう一度「作る」を選ぶと、残りがあって止まる）
Describe 'Invoke-Create (stops after the env was started)' {
    It 'tells how to go on or delete the env' {
        Mock Read-Extensions { @() }
        Mock Assert-DevcontainerTemplate {}
        Mock Read-WizardValue { 'foo' }
        Mock Get-EnvLeftoversNow { @() }
        Mock Read-DefaultDomains { @() }
        Mock Read-WizardChoice { 2 }
        Mock Read-WizardLocalGit { [pscustomobject]@{ RepoPath = 'C:\r.git'; RepoName = 'r' } }
        Mock Read-WizardDomains { @() }
        Mock Show-Summary {}
        Mock Read-WizardConfirm { 'y' }
        Mock Copy-ToBase {}
        Mock Build-DcsImage {}
        Mock New-EnvFiles {}
        Mock Start-EnvContainer { Stop-Setup 'up failed' @('first hint') }
        Mock Write-Step {}
        $err = $null
        try { Invoke-Create 'Ready' } catch { $err = $_.Exception }
        $err.Message | Should Be 'up failed'
        $h = @($err.Data['Hint']) -join "`n"
        $h | Should Match 'first hint'
        $h | Should Match '「開発環境の設定をやり直す」'
        $h | Should Match '「開発環境を削除する」'
    }
}
Describe 'Get-EnvVolumeNames' {
    It 'picks the volumes of the env, by name or by the VS Code label' {
        $v = "dcs-foo-claude `ndcs-foo-git `ndcs-food-claude `nvscode-state-config-aaa /home/dcs/envs/foo/config/.devcontainer/devcontainer.json`nvscode-state-config-bbb /home/dcs/envs/food/config/.devcontainer/devcontainer.json`nother `n"
        (Get-EnvVolumeNames 'foo' $v) -join '|' | Should Be 'dcs-foo-claude|dcs-foo-git|vscode-state-config-aaa'
    }
}
