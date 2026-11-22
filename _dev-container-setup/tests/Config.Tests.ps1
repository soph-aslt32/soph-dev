# 開発環境の値の組み立て（lib/Config.ps1）の単体テスト。WSL の中では何も実行しない。Pester 3.4 で動かす。
#   Invoke-Pester -Script .\_dev-container-setup\tests\Config.Tests.ps1
# 本番（入口のスクリプト）と同じ条件で動かす
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\lib\Common.ps1"
. "$PSScriptRoot\..\lib\Config.ps1"

Describe 'Get-EnvPaths' {
    It 'names and places' {
        $p = Get-EnvPaths 'foo'
        $p.Root | Should Be '/home/dcs/envs/foo'
        $p.Config | Should Be '/home/dcs/envs/foo/config'
        $p.DevcontainerJson | Should Be '/home/dcs/envs/foo/config/.devcontainer/devcontainer.json'
        $p.Work | Should Be '/home/dcs/envs/foo/work'
        $p.Relay | Should Be '/home/dcs/envs/foo/relay.git'
        $p.DomainsFile | Should Be '/home/dcs/envs/foo/allowed-domains.txt'
        $p.ClaudeVolume | Should Be 'dcs-foo-claude'
        $p.GitVolume | Should Be 'dcs-foo-git'
        $p.Network | Should Be 'dcs-foo'
    }
    It 'rejects a bad name' { { Get-EnvPaths 'a b' } | Should Throw }
}
Describe 'Get-EnvIdLabelArgs' {
    It 'the same labels as VS Code (D44)' {
        (Get-EnvIdLabelArgs 'foo') -join ' ' | Should Be '--id-label devcontainer.local_folder=\\wsl.localhost\dcs-base\home\dcs\envs\foo\config --id-label devcontainer.config_file=/home/dcs/envs/foo/config/.devcontainer/devcontainer.json'
    }
}
Describe 'Get-EnvWorkspaceDir' {
    It 'is /workspaces/<repository name> (D49)' { Get-EnvWorkspaceDir 'repo-a.v2_x' | Should Be '/workspaces/repo-a.v2_x' }
    It 'rejects <s>' -TestCases @(@{s = ''}, @{s = '.'}, @{s = '..'}, @{s = 'a b'}, @{s = 'a/b'}, @{s = '日本'}) {
        param($s)
        { Get-EnvWorkspaceDir $s } | Should Throw
    }
}
Describe 'New-DevcontainerJson' {
    $g = New-DevcontainerJson 'foo' 'GitHub' 'repo-a' @('a.b') | ConvertFrom-Json
    $l = New-DevcontainerJson 'foo' 'LocalGit' 'repo-b' @() | ConvertFrom-Json
    It 'runArgs' { $g.runArgs -join ' ' | Should Be '--network=dcs-foo --cap-add=NET_ADMIN --cap-add=NET_RAW --label=dcs=1 --label=dcs.env=foo' }
    It 'workspace' { $g.workspaceMount | Should Be 'source=/home/dcs/envs/foo/work,target=/workspaces/repo-a,type=bind'; $g.workspaceFolder | Should Be '/workspaces/repo-a'; $l.workspaceFolder | Should Be '/workspaces/repo-b' }
    It 'tells the scripts in the container where the workspace is' { $g.containerEnv.DCS_WORKSPACE | Should Be '/workspaces/repo-a'; @($g.containerEnv.PSObject.Properties).Count | Should Be 1 }
    It 'rejects a bad repository name' { { New-DevcontainerJson 'foo' 'GitHub' '..' @() } | Should Throw }
    It 'GitHub mounts' { $g.mounts -join '|' | Should Be 'source=dcs-foo-claude,target=/home/dev/.claude,type=volume|source=dcs-foo-git,target=/home/dev/.dcs-git,type=volume|source=/home/dcs/envs/foo/allowed-domains.txt,target=/etc/dcs/allowed-domains.txt,type=bind,readonly' }
    It 'LocalGit mounts' { $l.mounts -join '|' | Should Be 'source=dcs-foo-claude,target=/home/dev/.claude,type=volume|source=/home/dcs/envs/foo/relay.git,target=/relay.git,type=bind|source=/home/dcs/envs/foo/allowed-domains.txt,target=/etc/dcs/allowed-domains.txt,type=bind,readonly' }
    It 'users and commands' { $g.remoteUser | Should Be 'dev'; $g.containerUser | Should Be 'dev'; $g.updateRemoteUserUID | Should Be $false; $g.postStartCommand | Should Be '/usr/bin/sudo /usr/local/bin/init-firewall.sh'; $g.waitFor | Should Be 'postStartCommand'; $g.postAttachCommand | Should Be '/usr/local/bin/dcs-check-forwarding' }
    # Claude が書ける ~/.bashrc などを、起動やコマンドの実行の前に読ませない（C1。読ませると、ファイアウォールの前に何かを動かせる）
    It 'does not read the shell files of the user to get the environment (C1)' { $g.userEnvProbe | Should Be 'none' }
    It 'name and image' { $g.name | Should Be 'dcs-foo'; $g.image | Should Be 'dcs-image' }
    It 'no risky keys' { foreach ($k in 'forwardPorts','appPort','privileged','capAdd','securityOpt','features','shutdownAction') { $g.PSObject.Properties.Name -contains $k | Should Be $false } }
    It 'vscode settings' { $s = $g.customizations.vscode.settings
        $s.'dev.containers.copyGitConfig' | Should Be $false; $s.'dev.containers.gitCredentialHelperConfigLocation' | Should Be 'none'
        $s.'dev.containers.dockerCredentialHelper' | Should Be $false; $s.'git.terminalAuthentication' | Should Be $false
        $s.'git.useIntegratedAskPass' | Should Be $false; $s.'github.gitAuthentication' | Should Be $false
        $s.'remote.containers.copyGitConfig' | Should Be $false; $s.'remote.containers.dockerCredentialHelper' | Should Be $false
        @($s.PSObject.Properties).Count | Should Be 8 }
    It 'extensions' { @($g.customizations.vscode.extensions) -join '|' | Should Be 'a.b'; @($l.customizations.vscode.extensions).Count | Should Be 0 }
    It 'LF only' { New-DevcontainerJson 'foo' 'GitHub' 'r' @() | Should Not Match "`r" }
}
# 注文書は、ツールのフォルダの templates\devcontainer.json.tmpl（利用者が読める・決まった場所を変えられる）から作る
Describe 'New-DevcontainerJson (template)' {
    $shipped = [IO.File]::ReadAllText("$PSScriptRoot\..\templates\devcontainer.json.tmpl", [Text.Encoding]::UTF8)
    function Write-Template([string]$Text) { $f = Join-Path $TestDrive 't.tmpl'; [IO.File]::WriteAllText($f, $Text, (New-Object Text.UTF8Encoding($false))); return $f }
    It 'drops the // comment lines of the template' { New-DevcontainerJson 'foo' 'GitHub' 'r' @() | Should Not Match '(?m)^\s*//' }
    It 'uses what the user added in the place the template allows' {
        $t = $shipped -replace '(?m)^(\s*)"dev\.containers\.copyGitConfig"', ('$1"editor.fontSize": 15,' + "`n" + '$1"dev.containers.copyGitConfig"')
        $j = New-DevcontainerJson 'foo' 'GitHub' 'r' @() -TemplatePath (Write-Template $t) | ConvertFrom-Json
        $j.customizations.vscode.settings.'editor.fontSize' | Should Be 15
        $j.customizations.vscode.settings.'github.gitAuthentication' | Should Be $false
    }
    It 'refuses an unknown marker' { { New-DevcontainerJson 'foo' 'GitHub' 'r' @() -TemplatePath (Write-Template ($shipped -replace 'dcs-image', '__IMAGE__')) } | Should Throw '__IMAGE__' }
    It 'refuses a template without a marker the tool needs' { { New-DevcontainerJson 'foo' 'GitHub' 'r' @() -TemplatePath (Write-Template ($shipped -replace '__DOMAINS_FILE__', '/tmp/x')) } | Should Throw '__DOMAINS_FILE__' }
    It 'refuses a template that does not make JSON' { { New-DevcontainerJson 'foo' 'GitHub' 'r' @() -TemplatePath (Write-Template ($shipped -replace '"image": "dcs-image",', '"image": "dcs-image",,')) } | Should Throw 'devcontainer.json.tmpl' }
    It 'does not replace a marker that comes from a value' { (New-DevcontainerJson 'foo' 'GitHub' '__ENV_NAME__' @() | ConvertFrom-Json).workspaceFolder | Should Be '/workspaces/__ENV_NAME__' }
    # 動くプログラムを変える環境変数は、注文書に書かせない（N1。PATH の前に Claude が書けるフォルダが来ると、C1 と同じ形に戻る）
    It 'refuses <n> in containerEnv (N1)' -TestCases @(@{n = 'PATH'}, @{n = 'LD_PRELOAD'}, @{n = 'LD_LIBRARY_PATH'}, @{n = 'LD_AUDIT'}, @{n = 'BASH_ENV'}, @{n = 'SHELLOPTS'}, @{n = 'BASHOPTS'}, @{n = 'PS4'}) {
        param($n)
        $t = $shipped -replace '(?m)^(\s*)"DCS_WORKSPACE"', ('$1"' + $n + '": "/workspaces/r/.venv/bin",' + "`n" + '$1"DCS_WORKSPACE"')
        { New-DevcontainerJson 'foo' 'GitHub' 'r' @() -TemplatePath (Write-Template $t) } | Should Throw "、$n は書けません"
    }
    # 環境変数の名前の形でないもの（"PATH=…" や、bash の関数を差し替える BASH_FUNC_…%%）も止める（m2）
    It 'refuses a name that is not the shape of a variable name: <n> (m2)' -TestCases @(@{n = 'PATH=/home/dev/.local/bin:/usr/bin'}, @{n = 'BASH_FUNC_curl%%'}) {
        param($n)
        $t = $shipped -replace '(?m)^(\s*)"DCS_WORKSPACE"', ('$1"' + $n + '": ":/bin",' + "`n" + '$1"DCS_WORKSPACE"')
        { New-DevcontainerJson 'foo' 'GitHub' 'r' @() -TemplatePath (Write-Template $t) } | Should Throw "「$n」"
    }
    It 'refuses PATH in remoteEnv too (N1)' {
        $t = $shipped -replace '(?m)^(\s*)"containerEnv"', ('$1"remoteEnv": { "PATH": "$${containerEnv:PATH}:/x" },' + "`n" + '$1"containerEnv"')
        { New-DevcontainerJson 'foo' 'GitHub' 'r' @() -TemplatePath (Write-Template $t) } | Should Throw '、PATH は書けません'
    }
    # ENV は、アプリの変数の名前としてありうるので止めない（m4。読むのは対話の sh だけ）
    It 'allows other variables in containerEnv: <n>' -TestCases @(@{n = 'MY_SETTING'}, @{n = 'ENV'}) {
        param($n)
        $t = $shipped -replace '(?m)^(\s*)"DCS_WORKSPACE"', ('$1"' + $n + '": "1",' + "`n" + '$1"DCS_WORKSPACE"')
        (New-DevcontainerJson 'foo' 'GitHub' 'r' @() -TemplatePath (Write-Template $t) | ConvertFrom-Json).containerEnv.$n | Should Be '1'
    }
}
# ひな形の誤りは、何かを作る前（値を聞く前）に見つける（M4）
Describe 'Assert-DevcontainerTemplate' {
    $shipped = [IO.File]::ReadAllText("$PSScriptRoot\..\templates\devcontainer.json.tmpl", [Text.Encoding]::UTF8)
    It 'passes the template of the tool' { { Assert-DevcontainerTemplate @('a.b') } | Should Not Throw }
    It 'stops on a broken template' {
        $f = Join-Path $TestDrive 'broken.tmpl'
        [IO.File]::WriteAllText($f, ($shipped -replace '"image": "dcs-image",', '"image": "dcs-image",,'), (New-Object Text.UTF8Encoding($false)))
        { Assert-DevcontainerTemplate @() -TemplatePath $f } | Should Throw 'devcontainer.json.tmpl'
    }
}
# 削除のときの、土台のフォルダの消し方（M3。work/ に書き込みの無いフォルダがあっても消す）
Describe 'Get-RemoveEnvFolderArgs' {
    It 'makes every folder writable before removing it' {
        $a = @(Get-RemoveEnvFolderArgs '/home/dcs/envs/foo')
        $a[0] | Should Be 'bash'
        $a[1] | Should Be '-c'
        $a[2] | Should Match 'chmod -R u\+rwX -- \$1 .*; rm -rf -- \$1$'
        $a[-1] | Should Be '/home/dcs/envs/foo'
    }
}
# 作業フォルダの .git/config を、土台で文字として読んで取り出す（I1。git は土台で動かさない。D10）
Describe 'ConvertFrom-GitConfigText' {
    It 'reads the values that git writes' {
        $c = ConvertFrom-GitConfigText "[core]`n`trepositoryformatversion = 0`n`tbare = false`n[remote `"origin`"]`n`turl = https://github.com/o/r.git`n`tfetch = +refs/heads/*:refs/remotes/origin/*`n[user]`n`tname = Dev Env`n`temail = dev@example.com`n"
        $c['remote.origin.url'] | Should Be 'https://github.com/o/r.git'
        $c['user.name'] | Should Be 'Dev Env'
        $c['user.email'] | Should Be 'dev@example.com'
    }
    It 'section and key names are not case sensitive, the subsection is' {
        $c = ConvertFrom-GitConfigText "[Remote `"Origin`"]`n`tURL = https://x/a.git`n[REMOTE `"origin`"]`n`tUrl = https://x/b.git`n"
        $c['remote.origin.url'] | Should Be 'https://x/b.git'
        $c['remote.Origin.url'] | Should Be 'https://x/a.git'
    }
    It 'takes the last value, and drops comments and the quotes' {
        $c = ConvertFrom-GitConfigText "[user]`n`tname = first`n`tname = `"A ; B`" # comment`n`temail = a@example.com ; comment`n"
        $c['user.name'] | Should Be 'A ; B'
        $c['user.email'] | Should Be 'a@example.com'
    }
    It 'reads escaped characters in quotes' { (ConvertFrom-GitConfigText "[user]`n`tname = `"a\`"b\\c`"`n")['user.name'] | Should Be 'a"b\c' }
    It 'reads the old [section.subsection] form' { (ConvertFrom-GitConfigText "[remote.origin]`n`turl = https://x/c.git`n")['remote.origin.url'] | Should Be 'https://x/c.git' }
    It 'skips lines it cannot read' { (ConvertFrom-GitConfigText "garbage`n[user]`n`tname = ok`n")['user.name'] | Should Be 'ok' }
}
Describe 'ConvertFrom-ExtensionsText' {
    It 'parses' { (ConvertFrom-ExtensionsText "# x`r`nms-python.python`r`n`r`nrust-lang.rust-analyzer`r`n") -join '|' | Should Be 'ms-python.python|rust-lang.rust-analyzer' }
    It 'throws on bad id with line number' { { ConvertFrom-ExtensionsText "ok.one`nbad id`n" } | Should Throw '2' }
}
Describe 'ConvertFrom-UpResultText' {
    $id = 'a' * 64
    It 'takes containerId from the last line' { ConvertFrom-UpResultText ("log line`n" + '{"outcome":"success","containerId":"' + $id + '","remoteUser":"dev"}' + "`n") | Should Be $id }
    It 'error outcome' { ConvertFrom-UpResultText '{"outcome":"error","message":"x","description":"y"}' | Should BeNullOrEmpty }
    It 'no outcome' { ConvertFrom-UpResultText ('{"containerId":"' + $id + '"}') | Should BeNullOrEmpty }
    It 'no containerId' { ConvertFrom-UpResultText '{"outcome":"success"}' | Should BeNullOrEmpty }
    It 'bad containerId' { ConvertFrom-UpResultText '{"outcome":"success","containerId":"xyz"}' | Should BeNullOrEmpty }
    It 'not JSON' { ConvertFrom-UpResultText "Error: something`n" | Should BeNullOrEmpty }
    It 'empty' { ConvertFrom-UpResultText '' | Should BeNullOrEmpty }
}
Describe 'New-DomainsFileText' {
    It 'one per line, LF' { New-DomainsFileText @('a.com', 'b.org') | Should Be "# allowed_domains（dev-container-setup が書きます）`na.com`nb.org`n" }
}
Describe 'Test-ContainerInspect' {
    BeforeEach { $c = Get-Content "$PSScriptRoot\fixtures\inspect-container.json" -Raw | ConvertFrom-Json; $n = Get-Content "$PSScriptRoot\fixtures\inspect-network.json" -Raw | ConvertFrom-Json }
    It 'fixture passes' { @(Test-ContainerInspect $c $n 'foo' 'GitHub').Count | Should Be 0 }
    It 'privileged' { $c.HostConfig.Privileged = $true; (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'privileged' }
    It 'extra cap' { $c.HostConfig.CapAdd += 'SYS_ADMIN'; (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'SYS_ADMIN' }
    It 'seccomp unconfined' { $c.HostConfig.SecurityOpt = @('seccomp=unconfined'); (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'seccomp' }
    It 'published port' { $c.HostConfig.PortBindings = [pscustomobject]@{'22/tcp' = @([pscustomobject]@{HostIp = ''; HostPort = '2222'})}; (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match '2222' }
    It 'docker.sock' { $c.Mounts += [pscustomobject]@{Type='bind'; Source='/var/run/docker.sock'; Destination='/var/run/docker.sock'; RW=$true}; (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'docker.sock' }
    It 'domains file writable' { ($c.Mounts | Where-Object Destination -eq '/etc/dcs/allowed-domains.txt').RW = $true; (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'allowed-domains' }
    It 'other network' { $c.NetworkSettings.Networks | Add-Member -NotePropertyName bridge -NotePropertyValue ([pscustomobject]@{}); (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'bridge' }
    It 'ipv6' { $n.EnableIPv6 = $true; (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'IPv6' }
    It 'wrong mode' { @(Test-ContainerInspect $c $n 'foo' 'LocalGit').Count | Should Not Be 0 }
    It 'allows the VS Code state volume of the env' { $c.Mounts += [pscustomobject]@{Type='volume'; Name='vscode-state-config-abc123'; Source='/var/lib/docker/volumes/vscode-state-config-abc123/_data'; Destination='/.vscode-volume'; RW=$true}; @(Test-ContainerInspect $c $n 'foo' 'GitHub' @('vscode-state-config-abc123')).Count | Should Be 0 }
    It 'refuses the VS Code state volume of another env (I2)' { $c.Mounts += [pscustomobject]@{Type='volume'; Name='vscode-state-config-abc123'; Source='/var/lib/docker/volumes/vscode-state-config-abc123/_data'; Destination='/.vscode-volume'; RW=$true}; (Test-ContainerInspect $c $n 'foo' 'GitHub' @('vscode-state-config-other')) -join ' ' | Should Match 'vscode-state-config-abc123' }
    # ホストやほかのコンテナと分けるもの（I2。--pid=host などは、土台の dcs のファイルに届く）
    It 'shares the <k> namespace with the host (I2)' -TestCases @(@{k = 'PidMode'}, @{k = 'IpcMode'}, @{k = 'UTSMode'}, @{k = 'UsernsMode'}, @{k = 'CgroupnsMode'}) {
        param($k)
        $c.HostConfig.$k = 'host'
        (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match $k
    }
    It 'shares the PID namespace with another container (I2)' { $c.HostConfig.PidMode = 'container:abc'; (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'PidMode' }
    It 'a device (I2)' { $c.HostConfig.Devices = @([pscustomobject]@{PathOnHost='/dev/kvm'; PathInContainer='/dev/kvm'; CgroupPermissions='rwm'}); (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match '/dev/kvm' }
    It 'a device request, such as a GPU (I2)' { $c.HostConfig.DeviceRequests = @([pscustomobject]@{Driver=''; Count=-1}); (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'DeviceRequests' }
    It 'device cgroup rules (I2)' { $c.HostConfig.DeviceCgroupRules = @('c 1:3 rwm'); (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'DeviceCgroupRules' }
    It 'other security options: <o> (I2)' -TestCases @(@{o = 'label=disable'}, @{o = 'apparmor=other'}, @{o = 'systempaths=unconfined'}) {
        param($o)
        $c.HostConfig.SecurityOpt = @($o)
        (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match ([regex]::Escape($o))
    }
    It 'allows no-new-privileges' { $c.HostConfig.SecurityOpt = @('no-new-privileges:true'); @(Test-ContainerInspect $c $n 'foo' 'GitHub').Count | Should Be 0 }
    It 'no masked paths in /proc and /sys (I2)' { $c.HostConfig.MaskedPaths = @(); (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'MaskedPaths' }
    It 'no read-only paths in /proc (I2)' { $c.HostConfig.ReadonlyPaths = $null; (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'ReadonlyPaths' }
    It 'another container on the network of the env (I2)' { $n.Containers | Add-Member -NotePropertyName ('f' * 64) -NotePropertyValue ([pscustomobject]@{Name = 'other'}); (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'other' }
    It 'shared vscode cache volume' { $c.Mounts += [pscustomobject]@{Type='volume'; Name='vscode'; Source='/var/lib/docker/volumes/vscode/_data'; Destination='/vscode'; RW=$true}; (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'vscode' }
    It 'a mount without Source and Name (tmpfs)' { $c.Mounts += [pscustomobject]@{Type='tmpfs'; Destination='/run/x'; RW=$true}; (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match '/run/x' }
    It 'missing mount' { $c.Mounts = @($c.Mounts | Where-Object Source -ne '/home/dcs/envs/foo/work'); (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match 'work' }
    It 'work mounted outside /workspaces' { ($c.Mounts | Where-Object Source -eq '/home/dcs/envs/foo/work').Destination = '/etc'; (Test-ContainerInspect $c $n 'foo' 'GitHub') -join ' ' | Should Match '/etc' }
    It 'work mounted on /workspaces/..' { ($c.Mounts | Where-Object Source -eq '/home/dcs/envs/foo/work').Destination = '/workspaces/..'; @(Test-ContainerInspect $c $n 'foo' 'GitHub').Count | Should Not Be 0 }
    It 'capabilities without the CAP_ prefix' { $c.HostConfig.CapAdd = @('NET_ADMIN', 'NET_RAW'); @(Test-ContainerInspect $c $n 'foo' 'GitHub').Count | Should Be 0 }
}
