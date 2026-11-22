#Requires -Version 5.1
# =============================================================================
# Env.ps1 — 開発環境（土台のフォルダ・ネットワーク・ボリューム・コンテナ）を作る・中で実行する・確かめる
#
# Common.ps1・Base.ps1・Config.ps1 を先に dot-source しておく。決まっていること: DESIGN.md の 6.3・6.4・6.5d、D44。
# 土台は、wsl.exe のプロセスが無いと約 15 秒で止まり、コンテナも止まる（VERIFY.md の F1）。そのため、コンテナの中で
# コマンドを動かすときは、毎回、同じ wsl.exe の呼び出しの中で、先に devcontainer up をしてから exec する（キープアライブは作らない）。
# =============================================================================

# 土台の dcs として、ファイルを書く（中身は base64 にして標準入力で渡す。一時ファイルに書いてから名前を変える）
function Write-BaseFile([string]$Path, [string]$Text) {
    $b64 = [Convert]::ToBase64String((New-Object System.Text.UTF8Encoding($false)).GetBytes($Text))
    # bash に渡す文には " を書かない（$1 は空白を含まない決まったパス）
    $r = Invoke-InBase -User dcs -ArgList @('bash', '-c', 'base64 -d -i > $1.tmp && chmod 644 -- $1.tmp && mv -f -- $1.tmp $1', '_', $Path) -InputText $b64 -CaptureError
    if ($r.Code -ne 0) { Stop-Setup "土台に $Path を書けませんでした（終了コード $($r.Code)）。" @($r.Error.Trim()) }
}

# 開発環境のコンテナの中で、dev としてコマンドを実行する。{Code; Text; Error} を返す。
# 先に devcontainer up（止まっていれば起動し、postStartCommand でファイアウォールを入れる）をしてから exec する。
# up に失敗したときは、終了コード 125 で、up の出力の最後を Error に入れて返す。
# -ShowError のときは、標準エラー出力を受け取らずに、この画面にそのまま出す（進み具合を見せたいもの。Error は空）
function Invoke-InEnv {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Command,
        [string]$InputText = '',
        [string]$InputFile = '',
        [string]$OutputFile = '',
        [switch]$ShowError
    )
    $p = Get-EnvPaths $Name
    $labels = @(Get-EnvIdLabelArgs $Name)
    $sh = 'cli=$1 cfg=$2 l1=$3 l2=$4; shift 4; log=$(mktemp); ' +
        '"$cli" up --workspace-folder "$cfg" --id-label "$l1" --id-label "$l2" --skip-post-attach < /dev/null > "$log" 2>&1 ' +
        '|| { tail -n 30 -- "$log" >&2; rm -f -- "$log"; exit 125; }; rm -f -- "$log"; ' +
        'exec "$cli" exec --workspace-folder "$cfg" --id-label "$l1" --id-label "$l2" "$@"'
    $argList = @('bash', '-c', $sh, '_', $script:DevcontainerCli, $p.Config, $labels[1], $labels[3]) + $Command
    return (Invoke-InBase -User dcs -ArgList $argList -InputText $InputText -InputFile $InputFile -OutputFile $OutputFile -CaptureError:(-not $ShowError))
}

# 開発環境のフォルダ・注文書・allowed-domains.txt・ネットワークを用意する（あれば書き直す。ネットワークはあれば何もしない）。
# $RepoName は、コンテナの中の作業フォルダ /workspaces/<リポジトリ名> の名前（D49）。
# 土台のリモートの設定は書かない（D34a の直し。VERIFY.md の V14）
function New-EnvFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('GitHub', 'LocalGit')][string]$Mode,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RepoName,
        [string[]]$Domains = @(),
        [string[]]$Extensions = @()
    )
    $p = Get-EnvPaths $Name
    $null = Get-EnvWorkspaceDir $RepoName   # 名前を先に確かめる
    Write-Step "開発環境（$Name）のフォルダとネットワークを用意します"
    $dirs = @($p.Root, $p.Config, "$($p.Config)/.devcontainer", $p.Work)
    if ($Mode -eq 'LocalGit') { $dirs += $p.Relay }
    if ($script:DryRun) {
        Write-DryRun "フォルダ $($dirs -join '、') を作り、$($p.DevcontainerJson) と $($p.DomainsFile) を書き、ネットワーク $($p.Network) を作る"
        return
    }
    $r = Invoke-InBase -User dcs -ArgList (@('install', '-d', '-m', '755', '--') + $dirs) -CaptureError
    if ($r.Code -ne 0) { Stop-Setup "開発環境のフォルダ（$($p.Root)）を作れませんでした（終了コード $($r.Code)）。" @($r.Error.Trim()) }
    Write-BaseFile $p.DevcontainerJson (New-DevcontainerJson $Name $Mode $RepoName $Extensions)
    Write-BaseFile $p.DomainsFile (New-DomainsFileText $Domains)
    $n = Invoke-InBase -User dcs -ArgList @('docker', 'network', 'inspect', '--format', '{{.Name}}', $p.Network) -CaptureError
    if ($n.Code -ne 0) {
        $c = Invoke-InBase -User dcs -ArgList @('docker', 'network', 'create', '--ipv6=false', '--label', 'dcs=1', '--label', "dcs.env=$Name", $p.Network) -CaptureError
        if ($c.Code -ne 0) { Stop-Setup "ネットワーク $($p.Network) を作れませんでした（終了コード $($c.Code)）。" @($c.Error.Trim()) }
    }
    Write-Ok "フォルダ（$($p.Root)）、注文書、allowed-domains.txt、ネットワーク（$($p.Network)）を用意しました。"
}

# 開発環境のコンテナの ID（止まっているものを含む）。無ければ $null。2 つ以上あれば止める
function Get-EnvContainerId([string]$Name) {
    $null = Get-EnvPaths $Name
    $r = Invoke-InBase -User dcs -ArgList @('docker', 'ps', '-a', '-q', '--no-trunc', '--filter', 'label=dcs=1', '--filter', "label=dcs.env=$Name") -CaptureError
    if ($r.Code -ne 0) { Stop-Setup "開発環境（$Name）のコンテナを探せませんでした（終了コード $($r.Code)）。" @($r.Error.Trim()) }
    $ids = @(ConvertTo-Lines $r.Text)
    if ($ids.Count -gt 1) { Stop-Setup "開発環境（$Name）のコンテナが $($ids.Count) 個あります。" @('Docker の中を確かめてください（README の「困ったとき」）。') }
    if ($ids.Count -eq 0) { return $null }
    return $ids[0]
}

# 開発環境のコンテナを作って起動し（devcontainer up）、~/.claude/settings.json を置く（dcs-settings）。containerId を返す。
# postAttachCommand（VS Code の受け渡しの確かめ）は、VS Code がつながるときのものなので、ここでは動かさない
function Start-EnvContainer([string]$Name) {
    $p = Get-EnvPaths $Name
    Write-Step "開発環境（$Name）のコンテナを起動します（devcontainer up）"
    $argList = @($script:DevcontainerCli, 'up', '--workspace-folder', $p.Config) + @(Get-EnvIdLabelArgs $Name) + @('--skip-post-attach')
    if ($script:DryRun) { Write-DryRun ($argList -join ' '); return '' }
    # 進み具合（標準エラー出力）は、この画面にそのまま出す。標準出力の最後の行が結果の JSON（VERIFY.md の V8）
    $r = Invoke-InBase -User dcs -ArgList $argList
    $id = ConvertFrom-UpResultText $r.Text
    if ($r.Code -ne 0 -or -not $id) {
        Stop-Setup "開発環境（$Name）のコンテナを起動できませんでした（終了コード $($r.Code)）。" @(
            '上に表示されたメッセージを確かめてください（ファイアウォールの [失敗] の行があれば、その理由も）。',
            '原因を取り除いてから、「開発環境の設定をやり直す」を選んでください。')
    }
    # コンテナの中のコマンドは、絶対パスで呼ぶ（Claude が ~/.local/bin などに同じ名前のものを置いても使われないように。C1）
    $s = Invoke-InEnv $Name @('/usr/local/bin/dcs-settings')
    if ($s.Code -ne 0) { Stop-Setup "コンテナの ~/.claude/settings.json を置けませんでした（終了コード $($s.Code)）。" @($s.Error.Trim()) }
    Write-Ok "コンテナを起動し、~/.claude/settings.json を置きました（$($id.Substring(0, 12))）。"
    return $id
}

# 開発環境のコンテナを消す（ボリューム・フォルダ・ネットワークは消さない）
function Remove-EnvContainer([string]$Name) {
    $id = Get-EnvContainerId $Name
    if (-not $id) { return }
    if ($script:DryRun) { Write-DryRun "docker rm -f $id"; return }
    $r = Invoke-InBase -User dcs -ArgList @('docker', 'rm', '-f', $id) -CaptureError
    if ($r.Code -ne 0) { Stop-Setup "開発環境（$Name）のコンテナを消せませんでした（終了コード $($r.Code)）。" @($r.Error.Trim()) }
    Write-Ok "開発環境（$Name）のコンテナを消しました（ボリュームとフォルダは残っています）。"
}

# コンテナの中で dcs-github を動かすコマンド。表示を画面にそのまま出すとき（$ToScreen）は、色を付けるよう DCS_COLOR=1 を渡す
# （コンテナの中の dcs-github からは端末に見えないので、自分では色を付けてよいか分からない）
function Get-GitHubSetupCommand([bool]$ToScreen) {
    if ($ToScreen) { return @('/usr/bin/env', 'DCS_COLOR=1', '/usr/local/bin/dcs-github') }
    return @('/usr/local/bin/dcs-github')
}

# GitHub モードの設定（DESIGN.md の 7.1）。コンテナの中の dcs-github が、PAT を保存して作業フォルダ（/workspaces/<リポジトリ名>。D49）に clone する。
# $GitHub は {UserName; UserEmail; PatSecure; RepoUrl}（値はウィザードで確かめたもの。RepoUrl は https://github.com/OWNER/REPOSITORY.git の形）。
# PAT は、ここで初めて平文に戻し、base64 にして標準入力で渡す（画面・コマンドの引数・環境変数・Windows 側のファイルに出さない。D11）
function Invoke-GitHubSetup([string]$Name, $GitHub) {
    Write-Step "GitHub の設定をします（開発環境 $Name。PAT の保存と、リポジトリの clone）"
    if ($script:DryRun) { Write-DryRun 'dcs-github（user_name・user_email・PAT・リポジトリの URL は標準入力で渡す）'; return }
    $pat = ConvertFrom-SecureToPlain $GitHub.PatSecure
    $payload = "user_name=$($GitHub.UserName)`nuser_email=$($GitHub.UserEmail)`npat=$pat`nrepo_url=$($GitHub.RepoUrl)`n"
    $b64 = [Convert]::ToBase64String((New-Object System.Text.UTF8Encoding($false)).GetBytes($payload))
    $pat = $null
    $payload = $null
    # dcs-github は、表示をすべて標準エラー出力に出す（clone の進み具合を、そのまま見せる）
    $r = Invoke-InEnv $Name (Get-GitHubSetupCommand (-not [Console]::IsErrorRedirected)) -InputText $b64 -ShowError
    $b64 = $null
    if ($r.Code -ne 0) {
        Stop-Setup "GitHub の設定に失敗しました（終了コード $($r.Code)）。" @('上に表示されたメッセージを確かめてください。')
    }
    Write-Ok 'GitHub の設定が終わりました。'
}

# 外からの検証（docker inspect と docker network inspect を Test-ContainerInspect で比べる）。合格なら $true
function Test-EnvOutside([string]$Name, [string]$Mode) {
    $p = Get-EnvPaths $Name
    Write-Step "開発環境（$Name）を外から検証します（docker inspect）"
    if ($script:DryRun) { Write-DryRun "docker inspect と docker network inspect $($p.Network)"; return $true }
    $id = Get-EnvContainerId $Name
    if (-not $id) { Write-Host '  [NG] 開発環境のコンテナがありません。' -ForegroundColor Red; return $false }
    $c = Invoke-InBase -User dcs -ArgList @('docker', 'inspect', $id) -CaptureError
    $n = Invoke-InBase -User dcs -ArgList @('docker', 'network', 'inspect', $p.Network) -CaptureError
    $v = Invoke-InBase -User dcs -ArgList @('docker', 'volume', 'ls', '--format', '{{.Name}} {{.Label "vscode.dev-container-state.label.devcontainer.config_file"}}') -CaptureError
    if ($c.Code -ne 0 -or $n.Code -ne 0 -or $v.Code -ne 0) {
        Write-Host "  [NG] docker inspect に失敗しました: $(Format-Safe ($c.Error + $n.Error + $v.Error).Trim())" -ForegroundColor Red
        return $false
    }
    # VS Code がつなぐ vscode-state-… のボリュームは、名札がこの開発環境の注文書のものだけを許す（I2）
    $state = @(Get-EnvVolumeNames $Name $v.Text | Where-Object { $_ -like 'vscode-state-*' })
    # PowerShell 5.1 の ConvertFrom-Json は、JSON の配列を 1 つのかたまりとして返す
    $container = ConvertFrom-Json -InputObject $c.Text
    if ($container -is [array]) { $container = $container[0] }
    $network = ConvertFrom-Json -InputObject $n.Text
    if ($network -is [array]) { $network = $network[0] }
    $problems = @(Test-ContainerInspect $container $network $Name $Mode $state)
    if ($problems.Count -eq 0) {
        Write-Host '  [OK] ネットワーク・ポート・つないでいるもの・特権・権限・名前空間・デバイス・seccomp などが、決めたとおり' -ForegroundColor Green
        return $true
    }
    foreach ($m in $problems) { Write-Host "  [NG] $(Format-Safe $m)" -ForegroundColor Red }
    return $false
}

# 中からの検証（コンテナの中の dcs-verify）。合格なら $true
function Test-EnvInside([string]$Name) {
    Write-Step "開発環境（$Name）を中から検証します（dcs-verify）"
    if ($script:DryRun) { Write-DryRun '/usr/local/bin/dcs-verify --managed-sha256 <image\managed-settings.json の SHA256>'; return $true }
    $hash = Get-LfSha256 (Join-Path $script:ToolRoot 'image\managed-settings.json')
    # 絶対パスで呼ぶ（Claude が ~/.local/bin に偽の dcs-verify を置いても使われないように。C1）
    $r = Invoke-InEnv $Name @('/usr/local/bin/dcs-verify', '--managed-sha256', $hash)
    Write-CheckLines $r.Text
    if ($r.Code -ne 0 -and $r.Error.Trim()) { Write-Host "  $(Format-Safe $r.Error.Trim())" -ForegroundColor Red }
    return ($r.Code -eq 0)
}
