#Requires -Version 5.1
<#
.SYNOPSIS
    dev-container-setup のウィザード。Claude Code を動かす開発環境（Dev Container）を、作る・やり直す・削除する・検証する・更新する。

.DESCRIPTION
    ふだんは、同じフォルダの setup-wizard.cmd をダブルクリックして使います。引数は取りません。
    必要な値を画面で聞きます。入力した値（PAT を含む）は、Windows 側のファイルには保存しません。
    決まっていること: DESIGN.md の 6.5（D15・D16・D30）、7 章、6.5d。
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\Common.ps1"
. "$PSScriptRoot\lib\Validation.ps1"
. "$PSScriptRoot\lib\Base.ps1"
. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Env.ps1"
. "$PSScriptRoot\lib\Scripts.ps1"

# =============================================================================
# 判断だけを行う関数（外部コマンドを呼ばない。Pester で確かめる）
# =============================================================================

# 開発環境のモード（relay.git があれば LocalGit）
function Get-EnvMode([bool]$HasRelay) {
    if ($HasRelay) { return 'LocalGit' }
    return 'GitHub'
}

# docker ps の dcs.env の名札の一覧から、名前の規則に合うものだけを返す
function ConvertFrom-RunningEnvText([string]$DockerPsText) {
    return @(ConvertTo-Lines $DockerPsText | ForEach-Object { $_.Trim() } | Where-Object { $null -eq (Test-EnvNameValue $_) } | Select-Object -Unique)
}

# その名前の開発環境の残り（Get-EnvVolumeNames は Config.ps1）（フォルダ・コンテナ・ボリューム・ネットワーク）を、表示する言葉で返す。
# 引数は、ls /home/dcs/envs、docker ps -a の dcs.env の名札、docker volume ls（名前と VS Code の名札）、docker network ls の出力
function Get-EnvLeftovers([string]$Name, [string]$Folders, [string]$Containers, [string]$Volumes, [string]$Networks) {
    $found = New-Object System.Collections.Generic.List[string]
    if (@(ConvertTo-Lines $Folders | Where-Object { $_.Trim() -ceq $Name }).Count -gt 0) { $found.Add("フォルダ /home/dcs/envs/$Name") }
    $n = @(ConvertTo-Lines $Containers | Where-Object { $_.Trim() -ceq $Name }).Count
    if ($n -gt 0) { $found.Add("コンテナ（dcs.env=$Name）$n 個") }
    foreach ($v in @(Get-EnvVolumeNames $Name $Volumes)) { $found.Add("ボリューム $v") }
    if (@(ConvertTo-Lines $Networks | Where-Object { $_.Trim() -ceq "dcs-$Name" }).Count -gt 0) { $found.Add("ネットワーク dcs-$Name") }
    return $found.ToArray()
}

# 開発環境のコンテナが動いていて止まるときの案内。VS Code で開いていなくても、ほかの開発環境の VS Code が土台を動かし続けていると、
# ウィザードや同期スクリプトが起動したコンテナは動いたままになる（TEST.md の 4）。閉じたあと土台がすぐに休まないこともある（TEST.md の 6 のあと）
function Get-EnvRunningHints {
    return @(
        'その開発環境を VS Code で開いているときは、そのウィンドウを閉じてください（閉じると、コンテナは止まります）。',
        "VS Code で開いていないのに動いているときは、ほかの開発環境を VS Code で開いているか、閉じたばかりで、土台（$($script:BaseName)）がまだ動いているためです。",
        "$($script:BaseName) の VS Code のウィンドウをすべて閉じて、1 分ほど待ってから、もう一度実行してください。",
        "それでも止まらないときは、PowerShell で wsl --terminate $($script:BaseName) を実行してから、もう一度実行してください（土台を止めるだけで、中のものは消えません）。",
        '何も変更していません。')
}

# 「更新」で、開発環境ごとに作り直すときの見出し（見出しが無いと、コンテナを消した表示が、前の開発環境の続きに見える。TEST.md の 11）
function Get-UpdateEnvStepText([string]$Name, [int]$Index, [int]$Count) {
    return "開発環境（$Name）のコンテナを作り直します（$Index/$Count）"
}

# 削除が終わったときの表示。Windows 側に残るもの（LocalGit のリポジトリと同期の記録）は、LocalGit のときだけ伝える
function Get-DeleteDoneText([string]$Name, [bool]$LocalGit) {
    if ($LocalGit) { return "開発環境「$Name」を削除しました（Windows 側の LocalGit のリポジトリと、その中の dcs-sync\$Name.txt は残っています）。" }
    return "開発環境「$Name」を削除しました。"
}

# 削除する名前を聞くときの案内。残りだけ（フォルダが無い）の名前は一覧に出ないが、入力すれば消せる
function Get-DeleteNameHelp([string[]]$Names) {
    if ($Names.Count -gt 0) { $list = $Names -join '、' } else { $list = '（なし）' }
    return @(
        "今ある開発環境: $list",
        '一覧に無い名前でも、「新しい開発環境を作る」で残りがあると表示された名前は、入力して消せます。')
}

# 開発環境の検証に通らなかったときの案内。ツールを新しくしたあと（image\ のファイルが変わったあと）は、「作る」「やり直す」は
# 今あるイメージをそのまま使うので、managed settings（I4）などは「更新」でないと直らない（M5）。$Again は「もう一度」など
function Get-EnvVerifyFailedHints([string]$Again) {
    return @(
        "理由を取り除いてから、$Again「開発環境の設定をやり直す」を選んでください。",
        'ツールを新しくしたあとや、ツールの image\ のファイルを変えたあとで通らないとき（I4 の managed settings など）は、「更新」を選んでください（イメージを作り直します。「やり直す」では作り直しません）。',
        'ツールの版を変えたときは、README の 7.1 のとおり、完全に消してから入れ直してください。')
}

# Stop-Setup で止まったときの案内（Hint）に、行を足す（予期しないエラーには足さない）
function Add-SetupHint([System.Exception]$Exception, [string[]]$Lines) {
    if (-not $Exception.Data.Contains('Hint')) { return }
    $Exception.Data['Hint'] = @(@($Exception.Data['Hint']) + $Lines)
}

# =============================================================================
# 土台と開発環境の今の状態を読む（読むだけ）
# =============================================================================

# 土台の中で読むだけのコマンドを実行し、標準出力を返す（失敗したら止める）
function Get-BaseText([string[]]$ArgList, [string]$What) {
    $r = Invoke-InBase -User dcs -ArgList $ArgList -CaptureError
    if ($r.Code -ne 0) { Stop-Setup "${What}を読めませんでした（終了コード $($r.Code)）。" @($r.Error.Trim()) }
    return $r.Text
}

# 土台の中で、何かを変えるコマンド（削除など）を実行する（失敗したら、何に失敗したかを表示して止める。M2）
function Invoke-BaseChange([string[]]$ArgList, [string]$What) {
    $r = Invoke-InBase -User dcs -ArgList $ArgList -CaptureError
    if ($r.Code -ne 0) { Stop-Setup "${What}に失敗しました（終了コード $($r.Code)）。" @($r.Error.Trim()) }
}

function Get-EnvFolderText { return (Get-BaseText @('bash', '-c', 'ls -1 /home/dcs/envs 2> /dev/null || true') '開発環境のフォルダの一覧') }
function Get-VolumeText { return (Get-BaseText @('docker', 'volume', 'ls', '--format', '{{.Name}} {{.Label "vscode.dev-container-state.label.devcontainer.config_file"}}') 'ボリュームの一覧') }

# 今ある開発環境の名前（土台の /home/dcs/envs の下のフォルダ）
function Get-EnvNames { return @(ConvertTo-Lines (Get-EnvFolderText) | ForEach-Object { $_.Trim() } | Where-Object { $null -eq (Test-EnvNameValue $_) } | Sort-Object) }

# その名前の残り（Get-EnvLeftovers）を、今の土台から調べる
function Get-EnvLeftoversNow([string]$Name) {
    $containers = Get-BaseText @('docker', 'ps', '-a', '--filter', 'label=dcs=1', '--format', '{{.Label "dcs.env"}}') 'コンテナの一覧'
    $networks = Get-BaseText @('docker', 'network', 'ls', '--format', '{{.Name}}') 'ネットワークの一覧'
    return @(Get-EnvLeftovers $Name (Get-EnvFolderText) $containers (Get-VolumeText) $networks)
}

# 動いている開発環境のコンテナの名前（VS Code で開いているもの）
function Get-RunningEnvNames {
    return @(ConvertFrom-RunningEnvText (Get-BaseText @('docker', 'ps', '--filter', 'label=dcs=1', '--format', '{{.Label "dcs.env"}}') '動いているコンテナの一覧'))
}

# 開発環境が動いていれば（VS Code で開いていれば）、閉じるよう表示して止まる（Review Focus 1）
function Assert-EnvNotRunning([string[]]$Names) {
    $running = @(Get-RunningEnvNames | Where-Object { $Names -contains $_ })
    if ($running.Count -eq 0) { return }
    Stop-Setup "開発環境（$($running -join '、')）のコンテナが動いています。" @(Get-EnvRunningHints)
}

function Test-EnvHasRelay([string]$Name) {
    $p = Get-EnvPaths $Name
    return ((Invoke-InBase -User dcs -ArgList @('test', '-d', $p.Relay) -CaptureError).Code -eq 0)
}

# 今の allowed-domains.txt のドメイン（やり直しのときの既定値）
function Get-CurrentDomains([string]$Name) {
    $p = Get-EnvPaths $Name
    $r = Invoke-InBase -User dcs -ArgList @('cat', '--', $p.DomainsFile) -CaptureError
    if ($r.Code -ne 0) { return @() }
    return @(ConvertTo-Lines $r.Text | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') })
}

# 作業フォルダの .git/config の中身（土台の dcs で、文字として読むだけ。git は土台で動かさない。D10）。
# コンテナは起動しない（ドライランや確認の前でも、何も変えない。I1）。まだ clone されていなければ（.git が無ければ）$null。
# .git と config は Claude が置き換えられるので、シンボリックリンクなら止める（ほかの開発環境のファイルを読まないように）。大きさも限る
function Get-EnvGitConfigText([string]$Name) {
    $p = Get-EnvPaths $Name
    # bash に渡す文には " を書かない（$1 は空白を含まない決まったパス）。3: .git が無い、4: 形が違う
    $sh = 'd=$1/.git; f=$d/config; test -e $d || test -L $d || exit 3; test ! -L $d && test -d $d && test ! -L $f && test -f $f || exit 4; head -c 65536 -- $f'
    $r = Invoke-InBase -User dcs -ArgList @('bash', '-c', $sh, '_', $p.Work) -CaptureError
    if ($r.Code -eq 3) { return $null }
    if ($r.Code -eq 4) {
        Stop-Setup "作業フォルダの .git（$($p.Work)/.git）が、clone したときの形ではありません（シンボリックリンクなど）。" @('作業フォルダの中身を確かめてください。', '何も変更していません。')
    }
    if ($r.Code -ne 0) {
        Stop-Setup "作業フォルダの .git/config を読めませんでした（終了コード $($r.Code)）。" @((Format-Safe $r.Error.Trim()), '何も変更していません。')
    }
    return $r.Text
}

# clone してあるリポジトリの origin の URL と、コミットの作者（{Url; UserName; UserEmail}。無いものは空文字列）。
# まだ clone されていなければ $null。Claude が書き換えられる値なので、画面に出す前に制御文字などを取り除く
function Get-EnvRepoSettings([string]$Name) {
    $text = Get-EnvGitConfigText $Name
    if ($null -eq $text) { return $null }
    $c = ConvertFrom-GitConfigText $text
    $get = { param($k) if ($c.ContainsKey($k)) { return (Format-Safe $c[$k].Trim()) }; return '' }
    return [pscustomobject]@{ Url = (& $get 'remote.origin.url'); UserName = (& $get 'user.name'); UserEmail = (& $get 'user.email') }
}

# =============================================================================
# 入力
# =============================================================================

function Read-EnvName([string[]]$Names, [string]$What) {
    if ($Names.Count -eq 0) { Stop-Setup '開発環境がありません。' @('先に「新しい開発環境を作る」を選んでください。') }
    $i = Read-WizardChoice "$What 開発環境を番号で選んでください" $Names
    return $Names[$i - 1]
}

# allowed_domains（カンマ区切り。- は「なし」）を聞いて、ドメインの配列を返す
function Read-WizardDomains([string[]]$Default) {
    if ($Default.Count -gt 0) { $def = $Default -join ', ' } else { $def = '-' }
    $text = Read-WizardValue -Title 'allowed_domains（開発環境のコンテナから通信してよいドメイン）' -Default $def -Help @(
        'カンマ区切りで入力します（例: registry.npmjs.org, repo1.maven.org）。Claude Code・VS Code・GitHub・Rust・Python（PyPI・uv）の通信先は、ツールが許可します。',
        '*.example.com のような書き方は使えません。使うサブドメインを 1 つずつ書いてください。「*」（すべて許可）も使えません。',
        '通信を許可するドメインが無い場合は - を入力してください。') -Validate {
        param($v)
        if ($v -eq '-') { return $null }
        return (ConvertTo-AllowedDomains $v).Error
    }
    if ($text -eq '-') { return @() }
    return @((ConvertTo-AllowedDomains $text).Domains)
}

# PAT を聞く。画面には * で表示し、SecureString で返す（平文は確かめるあいだだけ持つ）
function Read-WizardPat {
    while ($true) {
        Write-WizardQuestion 'pat（GitHub の Personal Access Token）' @(
            'fine-grained PAT（対象のリポジトリだけ・Contents の Read and write・有効期限付き）を使ってください。',
            '入力（貼り付け）した文字は * で表示されます。PAT は Windows 側には保存せず、開発環境のボリュームにだけ保存します。')
        Write-WizardPrompt
        $secure = Read-Host -AsSecureString
        if ($null -eq $secure) { Stop-Setup '入力が終わりました（標準入力が閉じられました）。' }
        if ($secure.Length -eq 0) {
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

# コミットの作者と PAT を聞く（repo_url は $RepoUrl を使う。空なら聞く）
function Read-WizardGitHub([string]$RepoUrl, [string]$DefaultName = '', [string]$DefaultEmail = '') {
    Write-Step 'GitHub の設定を入力します'
    if (-not $RepoUrl) {
        $url = Read-WizardValue -Title 'repo_url（clone するリポジトリの URL）' -Help @(
            'https://github.com/OWNER/REPOSITORY.git の形で入力します（SSH の git@github.com:... は使えません）。',
            'コンテナの中の /workspaces/<リポジトリ名> に clone します。') -Validate { param($v) (ConvertFrom-GitHubRepoUrl $v).Error }
        $RepoUrl = $url
    }
    $repo = ConvertFrom-GitHubRepoUrl $RepoUrl
    if ($null -ne $repo.Error) { Stop-Setup $repo.Error.Message $repo.Error.Hint }
    $userName = Read-WizardValue -Title 'user_name（コミットの作者の名前: git の user.name）' -Default $DefaultName -Help @(
        'GitHub のアカウントと関係のないものでかまいません（例: dev-env）。') -Validate { param($v) Test-GitHubUserNameValue $v }
    $email = Read-WizardValue -Title 'user_email（コミットの作者のメールアドレス: git の user.email）' -Default $DefaultEmail -Help @(
        '実在する誰かのアドレスと一致しないよう、example.com などの例示用のドメインがおすすめです（例: dev-env@example.com）。') -Validate {
        param($v) Test-GitHubEmailValue $v }
    $pat = Read-WizardPat
    Write-Ok 'GitHub の設定の入力を確認しました（PAT は表示しません）。'
    return [pscustomobject]@{ UserName = $userName; UserEmail = $email; PatSecure = $pat; RepoUrl = $repo.RepoUrl; RepoName = $repo.RepoName }
}

function Read-WizardLocalGit([string]$Default = '') {
    Write-Step 'LocalGit の設定を入力します'
    $path = Read-WizardValue -Title 'repo_path（Windows 側の bare リポジトリのフォルダ）' -Default $Default -Help @(
        'HEAD・config・objects・refs などが直接入っているフォルダを、ドライブ名から入力します（例: C:\repos\foo.git）。',
        'コンテナの中の作業フォルダの名前は、フォルダ名（末尾の .git を除く）になります（/workspaces/<名前>）。') -Validate {
        param($v) (ConvertFrom-LocalGitRepoPath $v).Error }
    $lg = ConvertFrom-LocalGitRepoPath $path
    Write-Ok "LocalGit の設定の入力を確認しました（名前: $($lg.RepoName)）。"
    return $lg
}

# 最後の確認。y（進める）・r（入力し直す）・n（中止）のどれかを返す
function Read-WizardConfirm {
    while ($true) {
        Write-WizardQuestion 'この内容で進めますか？' @('y: 進める', 'r: 入力し直す', 'n: 中止する（何も変更しません）')
        $v = Read-WizardLine
        if ($v -in @('y', 'yes')) { return 'y' }
        if ($v -eq 'r') { return 'r' }
        if ($v -in @('n', 'no')) { return 'n' }
        Write-InputError (New-InputError "y・r・n のどれかを入力してください（入力: $v）。")
    }
}

function Show-Summary([string]$What, [string]$Name, [string]$Mode, [string[]]$Domains, $GitHub, $LocalGit, [string]$RepoName) {
    Write-Step '次の内容で進めます'
    Write-Info "行うこと               : $What"
    Write-Info "開発環境の名前         : $Name"
    Write-Info "モード                 : $Mode"
    Write-Info "作業フォルダ（コンテナ）: $(Get-EnvWorkspaceDir $RepoName)（土台の /home/dcs/envs/$Name/work）"
    if ($Domains.Count -gt 0) { $d = $Domains -join ', ' } else { $d = '（なし）' }
    Write-Info "通信を許可するドメイン : $d（このほかに、Claude Code・GitHub・VS Code などの決まった通信先）"
    if ($null -ne $GitHub) {
        Write-Info "clone するリポジトリ   : $($GitHub.RepoUrl)"
        Write-Info "コミットの作者         : $($GitHub.UserName) <$($GitHub.UserEmail)>"
        Write-Info 'PAT                    : 入力済み（表示しません。開発環境のボリュームにだけ保存します）'
    }
    if ($null -ne $LocalGit) {
        Write-Info "同期するリポジトリ     : $($LocalGit.RepoPath) ⇔ 開発環境の /relay.git"
        Write-Info "同期スクリプト         : $(Get-EnvScriptDir $Name)\Sync-$Name.cmd"
    }
    Write-Info "VS Code で開くファイル : $(Get-EnvScriptDir $Name)\Code-$Name.cmd"
}

# =============================================================================
# 共通の作業
# =============================================================================

# 土台の状態を見て、D16 のメッセージを表示する。Ready なら土台を検証する（WARN は表示して続ける。D46・D47）。
# 検証は読むだけなので、ドライランでも行う（M1）。「更新」（$Updating）のときは、B2（/etc/wsl.conf がツールのものと違う）の
# NG では止めない（ツールを新しくして wsl.conf が変わったとき、更新が置き直すため）
function Invoke-Preface([bool]$Creating, [bool]$Updating = $false) {
    Write-Step '土台を確かめます'
    $null = Get-WslExe
    $state = Get-BaseState
    if ($state -eq 'Missing') {
        if (-not $Creating) { Stop-Setup "土台（$($script:BaseName)）がまだありません。" @('先に「新しい開発環境を作る」を選んでください（土台も一緒に作ります）。') }
        Write-Note "土台（$($script:BaseName)）がまだ無いので、先に作ります（初回だけ時間がかかります）。"
        return $state
    }
    Write-Ok "既にある土台（$($script:BaseName)）を使います。"
    if ($state -eq 'Incomplete') {
        if (-not $Creating) { Stop-Setup "土台（$($script:BaseName)）の設定が途中で止まっています。" @('「新しい開発環境を作る」を選ぶと、続きから設定します。') }
        Write-Note '土台の設定が途中で止まっているので、続きから設定します。'
        return $state
    }
    $tolerate = @()
    if ($Updating) { $tolerate = @('B2') }
    if (-not (Test-Base -Always -Tolerate $tolerate)) {
        Stop-Setup '土台の検証に通りませんでした（上の [NG] の行）。' @('表示された理由を確かめてください（README の「困ったとき」）。')
    }
    return $state
}

# 生成した同期スクリプトを、この画面にそのままつないで実行する
function Invoke-SyncScript([string]$Name, [string[]]$SyncArgs) {
    $ps1 = Join-Path (Get-EnvScriptDir $Name) "Sync-$Name.ps1"
    Write-Step "同期スクリプトを実行します（Sync-$Name.ps1 $($SyncArgs -join ' ')）"
    if ($script:DryRun) { Write-DryRun "$ps1 $($SyncArgs -join ' ')"; return }
    $argText = (@(@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps1) + $SyncArgs | ForEach-Object { ConvertTo-CommandLineArg $_ }) -join ' ')
    $p = Start-Process -FilePath (Get-Command powershell.exe -CommandType Application | Select-Object -First 1).Path -ArgumentList $argText -NoNewWindow -PassThru
    $null = $p.Handle   # これを先に取っておかないと、終了コードが取れないことがある
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        Stop-Setup "同期スクリプトが失敗しました（終了コード $($p.ExitCode)）。" @('上に表示されたメッセージを確かめてください。')
    }
}

# 外と中から検証する。合格なら $true
function Test-Env([string]$Name, [string]$Mode) {
    $outside = Test-EnvOutside $Name $Mode
    $inside = Test-EnvInside $Name
    return ($outside -and $inside)
}

function Read-Extensions { return @(ConvertFrom-ExtensionsText ([System.IO.File]::ReadAllText((Join-Path $script:ToolRoot 'extensions.txt'), [System.Text.Encoding]::UTF8))) }
function Read-DefaultDomains { return @(ConvertFrom-DefaultsText ([System.IO.File]::ReadAllText((Join-Path $script:ToolRoot 'defaults.conf'), [System.Text.Encoding]::UTF8))) }

function Show-NextSteps([string]$Name, [string]$Mode, [string]$RepoName) {
    $dir = Get-EnvScriptDir $Name
    Write-Step '開発環境の準備ができました。続けて次の作業をしてください（README の「作ったあとの作業」）'
    Write-Info '1. Windows の VS Code のユーザーの設定（settings.json）に、次の 5 つがあることを確かめる（初めてのときだけ）:'
    Write-Info '     "dev.containers.mountWaylandSocket": false,'
    Write-Info '     "dev.containers.forwardWSLServices": false,'
    Write-Info '     "dev.containers.executeInWSL": true,'
    Write-Info '     "dev.containers.executeInWSLDistro": "dcs-base",'
    Write-Info '     "dev.containers.cacheVolume": false'
    Write-Info '2. %USERPROFILE%\.wslconfig の [wsl2] に guiApplications=false があり、hostFileSystemAccess=false の行が無いことを確かめる'
    Write-Info '   （直したら、PowerShell で wsl --shutdown を実行する）。'
    Write-Info '3. VS Code で開く: 次のファイルをダブルクリックし、右下の「Reopen in Container」を押す。'
    Write-Info "     $dir\Code-$Name.cmd"
    Write-Info "   コンテナの中の作業フォルダは $(Get-EnvWorkspaceDir $RepoName) です。"
    Write-Info '   拡張機能が自動で入らなかったときは、拡張機能のビューの「Install」で入れてください（README）。'
    Write-Info '4. コンテナのターミナルで claude を起動し、ログインする（開発環境ごとに別々にログインします）。'
    Write-Info '   コンテナを止めるときは、VS Code のウィンドウを閉じます。docker start で直接起動しないでください（ファイアウォールが入りません）。'
    if ($Mode -eq 'LocalGit') {
        Write-Info '5. Windows 側のリポジトリと同期するときは、次のファイルをダブルクリックします:'
        Write-Info "     $dir\Sync-$Name.cmd"
        Write-Info '   コミットする前に、作業フォルダで git config user.name・user.email を設定してください（--global は使いません。README）。'
    }
}

# =============================================================================
# 5 つの行うこと
# =============================================================================

function Invoke-Create([string]$BaseState) {
    # 注文書のひな形と extensions.txt の誤りは、値を聞く前に見つける（M4）
    $extensions = Read-Extensions
    Assert-DevcontainerTemplate $extensions
    Write-Step '開発環境の名前を決めます'
    $name = Read-WizardValue -Title '開発環境の名前' -Help @(
        '半角英小文字・数字・ハイフンだけで、32 文字以内（先頭と末尾はハイフン以外。例: myapp）。') -Validate { param($v) Test-EnvNameValue $v }
    # 土台の設定が途中のときは、まだ Docker が入っていないことがあるので、Ready のときだけ確かめる
    if ($BaseState -eq 'Ready') {
        $left = @(Get-EnvLeftoversNow $name)
        if ($left.Count -gt 0) {
            Stop-Setup "開発環境「$name」の残りが、土台にあります: $($left -join '、')" @(
                '同じ名前で作り直すときは、先に「開発環境を削除する」で消してください（別の名前で作ることもできます）。',
                '何も変更していません。')
        }
    }
    $defaults = Read-DefaultDomains
    while ($true) {
        $m = Read-WizardChoice 'リポジトリの使い方を番号で選んでください' @(
            'GitHub（GitHub のリポジトリを clone し、PAT で push する）',
            'LocalGit（Windows 側の bare リポジトリを写し、同期スクリプトで行き来する）')
        $gh = $null
        $lg = $null
        if ($m -eq 1) { $mode = 'GitHub'; $gh = Read-WizardGitHub ''; $repoName = $gh.RepoName }
        else { $mode = 'LocalGit'; $lg = Read-WizardLocalGit; $repoName = $lg.RepoName }
        $domains = @(Read-WizardDomains $defaults)
        Show-Summary '新しく作る' $name $mode $domains $gh $lg $repoName
        if ($script:DryRun) { break }
        $answer = Read-WizardConfirm
        if ($answer -eq 'y') { break }
        if ($answer -eq 'n') { Write-Info '中止しました。何も変更していません。'; return }
    }

    if ($BaseState -ne 'Ready') { New-Base }
    Copy-ToBase
    Build-DcsImage
    # ここから先で止まると、作りかけの開発環境が土台に残る（もう一度「作る」を選ぶと、残りがあって止まる。M4）
    try {
        New-EnvFiles $name $mode $repoName $domains $extensions
        $null = Start-EnvContainer $name
        if ($mode -eq 'GitHub') { Invoke-GitHubSetup $name $gh }
        if ($mode -eq 'LocalGit') { Write-EnvScripts $name $mode $lg.RepoPath; Invoke-SyncScript $name @('-Initialize') }
        else { Write-EnvScripts $name $mode '' }
        if (-not (Test-Env $name $mode)) {
            Stop-Setup '開発環境の検証に通りませんでした（上の [NG] の行）。' @(Get-EnvVerifyFailedHints '')
        }
    } catch {
        if (-not $script:DryRun) {
            Add-SetupHint $_.Exception @(
                "作りかけの開発環境「$name」が、土台に残っています（「新しい開発環境を作る」では、同じ名前で作れません）。",
                '原因を取り除いてから「開発環境の設定をやり直す」で続けるか、「開発環境を削除する」で消してください。')
        }
        throw
    }
    if ($script:DryRun) { Write-Ok 'ドライランが終わりました。何も変更していません。'; return }
    Show-NextSteps $name $mode $repoName
}

function Invoke-Redo {
    # 注文書のひな形と extensions.txt の誤りは、値を聞く前に見つける（M4）
    $extensions = Read-Extensions
    Assert-DevcontainerTemplate $extensions
    Write-Step 'やり直す開発環境を選びます'
    $name = Read-EnvName @(Get-EnvNames) 'やり直す'
    Assert-EnvNotRunning @($name)
    $mode = Get-EnvMode (Test-EnvHasRelay $name)
    Write-Info "この開発環境は $mode モードです（モードは変えられません）。"
    $current = @(Get-CurrentDomains $name)
    $gh = $null
    $lg = $null
    $repoUrl = ''
    $repo = $null
    if ($mode -eq 'GitHub') {
        # clone 済みなら、そのリポジトリを使う（別のリポジトリには変えられない）。土台で .git/config を読む（コンテナは起動しない。I1）
        $repo = Get-EnvRepoSettings $name
        if ($null -ne $repo) { $repoUrl = $repo.Url }
        if ($repoUrl -and $null -ne (ConvertFrom-GitHubRepoUrl $repoUrl).Error) {
            Stop-Setup "作業フォルダのリポジトリの origin（$repoUrl）が、GitHub の https の URL ではありません。" @('作業フォルダの中身を確かめてください。', '何も変更していません。')
        }
    }
    while ($true) {
        if ($mode -eq 'GitHub') {
            $again = $true
            if ($repoUrl) {
                Write-Info "clone してあるリポジトリ: $repoUrl"
                $again = Read-WizardYesNo 'PAT（とコミットの作者）を入れ直しますか？' @('PAT の期限が切れたときや、作者を変えたいときに入れ直します。') $false
            } else {
                Write-Note 'まだ clone されていないので、GitHub の設定を入力してください。'
            }
            if ($again) {
                $defName = ''; $defEmail = ''
                if ($null -ne $repo) { $defName = $repo.UserName; $defEmail = $repo.UserEmail }
                $gh = Read-WizardGitHub $repoUrl $defName $defEmail
                $repoName = $gh.RepoName
            } else {
                $gh = $null
                $repoName = (ConvertFrom-GitHubRepoUrl $repoUrl).RepoName
            }
        } else {
            $lg = Read-WizardLocalGit (Get-PreviousRepoPath $name)
            $repoName = $lg.RepoName
        }
        $domains = @(Read-WizardDomains $current)
        Show-Summary '設定をやり直す（コンテナを作り直す。work/ とボリュームは残る）' $name $mode $domains $gh $lg $repoName
        if ($script:DryRun) { break }
        $answer = Read-WizardConfirm
        if ($answer -eq 'y') { break }
        if ($answer -eq 'n') { Write-Info '中止しました。何も変更していません。'; return }
    }

    Copy-ToBase
    Build-DcsImage
    New-EnvFiles $name $mode $repoName $domains $extensions
    # 注文書を書き直したので、コンテナを作り直す（devcontainer up は、名札の合う古いコンテナをそのまま使うため）
    Remove-EnvContainer $name
    $null = Start-EnvContainer $name
    if ($null -ne $gh) { Invoke-GitHubSetup $name $gh }
    if ($mode -eq 'LocalGit') { Write-EnvScripts $name $mode $lg.RepoPath; Invoke-SyncScript $name @('-Initialize') }
    else { Write-EnvScripts $name $mode '' }
    if (-not (Test-Env $name $mode)) {
        Stop-Setup '開発環境の検証に通りませんでした（上の [NG] の行）。' @(Get-EnvVerifyFailedHints 'もう一度')
    }
    if ($script:DryRun) { Write-Ok 'ドライランが終わりました。何も変更していません。'; return }
    Show-NextSteps $name $mode $repoName
}

function Invoke-Delete {
    Write-Step '削除する開発環境を選びます'
    $name = Read-WizardValue -Title '削除する開発環境の名前' -Help @(Get-DeleteNameHelp @(Get-EnvNames)) -Validate {
        param($v)
        $e = Test-EnvNameValue $v
        if ($null -ne $e) { return $e }
        if (@(Get-EnvLeftoversNow $v).Count -eq 0) { return (New-InputError "開発環境「$v」は見つかりません（土台に、その名前のものがありません）。") }
        return $null
    }
    Assert-EnvNotRunning @($name)
    $left = @(Get-EnvLeftoversNow $name)
    $winDir = Get-EnvScriptDir $name
    Write-Step "開発環境「$name」の次のものを消します"
    foreach ($l in $left) { Write-Info "- $l" }
    if (Test-Path -LiteralPath $winDir) { Write-Info "- Windows 側のスクリプトのフォルダ $winDir" }
    Write-Note 'コンテナの中の作業フォルダ（work/）の、push や同期をしていない変更も消えます。Claude Code の会話の履歴とログイン、PAT も消えます。'
    Write-WizardQuestion '確かめのため、開発環境の名前をもう一度入力してください（違う文字なら中止します）'
    $again = Read-WizardLine
    if ($again -cne $name) { Write-Info '中止しました。何も変更していません。'; return }

    Write-Step "開発環境「$name」を削除します"
    $p = Get-EnvPaths $name
    $isLocalGit = Test-EnvHasRelay $name   # 消す前に見る（relay.git があれば LocalGit）
    if ($script:DryRun) {
        Write-DryRun "コンテナ（dcs.env=$name）、ボリューム、ネットワーク $($p.Network)、$($p.Root)、$winDir を消す"
        Write-Ok 'ドライランが終わりました。何も変更していません。'
        return
    }
    $ids = @(ConvertTo-Lines (Get-BaseText @('docker', 'ps', '-a', '-q', '--no-trunc', '--filter', 'label=dcs=1', '--filter', "label=dcs.env=$name") 'コンテナの一覧'))
    if ($ids.Count -gt 0) { Invoke-BaseChange (@('docker', 'rm', '-f') + $ids) 'コンテナの削除' }
    $vols = @(Get-EnvVolumeNames $name (Get-VolumeText))
    if ($vols.Count -gt 0) { Invoke-BaseChange (@('docker', 'volume', 'rm') + $vols) 'ボリュームの削除' }
    if (@(ConvertTo-Lines (Get-BaseText @('docker', 'network', 'ls', '--format', '{{.Name}}') 'ネットワークの一覧') | Where-Object { $_.Trim() -ceq $p.Network }).Count -gt 0) {
        Invoke-BaseChange @('docker', 'network', 'rm', $p.Network) 'ネットワークの削除'
    }
    # work/ に書き込みの無いフォルダがあっても消す（M3）
    Invoke-BaseChange @(Get-RemoveEnvFolderArgs $p.Root) "フォルダ $($p.Root) の削除"
    if (Test-Path -LiteralPath $winDir) { Remove-Item -LiteralPath $winDir -Recurse -Force }
    $rest = @(Get-EnvLeftoversNow $name)
    if ($rest.Count -gt 0) {
        Stop-Setup "消しきれなかったものがあります: $($rest -join '、')" @('もう一度「開発環境を削除する」を選んでください。')
    }
    Write-Ok (Get-DeleteDoneText $name $isLocalGit)
}

function Invoke-VerifyOnly {
    Write-Step '検証する開発環境を選びます'
    $name = Read-EnvName @(Get-EnvNames) '検証する'
    $mode = Get-EnvMode (Test-EnvHasRelay $name)
    if (@(Get-RunningEnvNames) -notcontains $name) { $null = Start-EnvContainer $name }
    if (-not (Test-Env $name $mode)) { Stop-Setup '開発環境の検証に通りませんでした（上の [NG] の行）。' @(Get-EnvVerifyFailedHints '') }
    # ドライランでは何も確かめていないので、通ったとは言わない（M1）
    if ($script:DryRun) { Write-Ok 'ドライランが終わりました。何も変更していません。'; return }
    Write-Ok "開発環境「$name」は、検証に通りました。"
}

function Invoke-Update {
    $names = @(Get-EnvNames)
    Write-Step '更新します（土台の Ubuntu と Docker Engine、Dev Containers CLI、イメージ、各開発環境のコンテナ）'
    Assert-EnvNotRunning $names
    if ($names.Count -gt 0) { Write-Info "作り直す開発環境: $($names -join '、')（work/ とボリュームはそのまま）" }
    $ok = Read-WizardYesNo '更新を始めますか？' @('Docker Hub から、イメージのベース（ubuntu:26.04）を取り直します。数分から十数分かかります。') $true
    if (-not $ok) { Write-Info '中止しました。何も変更していません。'; return }
    # 新しい setup-base.sh で更新するため、先にツールのファイルを置き直す
    Copy-ToBase
    # upgrade は /etc/wsl.conf も、ツールのものに置き直す。効かせるために土台を起動し直し、検証し直す（B2）
    Invoke-BaseSetup -Phase upgrade
    Write-Step "土台（$($script:BaseName)）を起動し直します（/etc/wsl.conf を効かせるため）"
    if ($script:DryRun) { Write-DryRun "wsl.exe --terminate $($script:BaseName)" }
    else { Stop-Base; Write-Ok '土台を止めました（次に使うときに起動します）。' }
    if (-not (Test-Base)) {
        Stop-Setup '更新のあとの、土台の検証に通りませんでした（上の [NG] の行）。' @('表示された理由を確かめてください（README の「困ったとき」）。')
    }
    Build-DcsImage -Refresh
    $failed = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $names.Count; $i++) {
        $name = $names[$i]
        Write-Step (Get-UpdateEnvStepText $name ($i + 1) $names.Count)
        try {
            $mode = Get-EnvMode (Test-EnvHasRelay $name)
            Remove-EnvContainer $name
            $null = Start-EnvContainer $name
            if (-not (Test-Env $name $mode)) { $failed.Add("$name（検証に通らない）") }
        } catch {
            Write-Host "  [NG] $name : $(Format-Safe $_.Exception.Message)" -ForegroundColor Red
            $failed.Add("$name（$(Format-Safe $_.Exception.Message)）")
        }
    }
    Write-Step '古いイメージを消して、ディスクを空けます'
    if ($script:DryRun) { Write-DryRun 'docker image prune -f --filter label=dcs=1' }
    else { Invoke-BaseChange @('docker', 'image', 'prune', '-f', '--filter', 'label=dcs=1') '古いイメージの削除'; Write-Ok '古いイメージを消しました。' }
    if ($failed.Count -gt 0) {
        Stop-Setup "更新は終わりましたが、次の開発環境が検証に通りませんでした: $($failed -join '、')" @('それぞれ「開発環境の設定をやり直す」を選んでください。')
    }
    if ($script:DryRun) { Write-Ok 'ドライランが終わりました。何も変更していません。'; return }
    Write-Ok '更新が終わりました。'
}

# =============================================================================
# 本体
# =============================================================================

function Invoke-Main {
    Write-Host ''
    Write-Host '=== Claude Code の開発環境（Dev Container）を用意します（dev-container-setup）===' -ForegroundColor Cyan
    Write-Info '必要な値を、この画面で順に聞きます。入力した値は、Windows 側のファイルには保存しません。'
    Write-Info '途中でやめるときは Ctrl+C を押してください（最後の確認で y を入力するまでは、何も変更しません）。'
    Write-Step '何をするかを選びます'
    $action = Read-WizardChoice '行うことを番号で選んでください' @(
        '新しい開発環境を作る（土台が無ければ、先に作ります）',
        '開発環境の設定をやり直す（通信先・PAT の入れ直し、注文書とスクリプトの作り直し。コンテナを作り直します）',
        '開発環境を削除する',
        '検証だけ',
        '更新（土台の Ubuntu と Docker Engine、イメージ、各開発環境のコンテナを新しくします）')
    $script:DryRun = Read-WizardYesNo 'ドライランにしますか？' @(
        'ドライランでは何も変更せず、実行する予定の内容だけを表示します。',
        '初めて使うときは、まずドライランで流れを確かめるのがおすすめです。') $false
    if ($script:DryRun) { Write-Note 'ドライランです。何も変更せず、実行する予定の内容だけを表示します。' }
    $state = Invoke-Preface ($action -eq 1) ($action -eq 5)
    switch ($action) {
        1 { Invoke-Create $state }
        2 { Invoke-Redo }
        3 { Invoke-Delete }
        4 { Invoke-VerifyOnly }
        5 { Invoke-Update }
    }
}

# テストで関数だけを読み込む（. で読み込む）ときは、ここから下を実行しない
if ($MyInvocation.InvocationName -ne '.') {
    $exitCode = 0
    $savedConsoleEncoding = $null
    try {
        # コンテナと土台の日本語の表示を、この画面にそのまま出す（従来と同じ）
        try {
            $savedConsoleEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        } catch {
            $savedConsoleEncoding = $null
        }
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
    }
    exit $exitCode
}
