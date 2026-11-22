#Requires -Version 5.1
# =============================================================================
# Config.ps1 — 開発環境の名前・置き場所・注文書（devcontainer.json）などの値を組み立てる（dev-container-setup）
#
# 外部コマンドは呼ばない（値を作るだけ。Pester で確かめる）。Common.ps1 を先に dot-source しておく。
# 決まっていること: DESIGN.md の 6.3・6.4・6.4a（D34a）・6.5d・6.7、D41・D44・D45・D51。
# =============================================================================

# ツールのフォルダ（注文書のひな形 templates\devcontainer.json.tmpl を読むため。Base.ps1 と同じ決め方）
if (-not (Test-Path variable:script:ToolRoot)) { $script:ToolRoot = Split-Path -Parent $PSScriptRoot }

# 開発環境の名前から、土台の中の置き場所と、Docker の中の名前を決める（6.3・6.7）
function Get-EnvPaths([string]$Name) {
    if ($Name -cnotmatch '^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$') {
        Stop-Setup "開発環境の名前「$(Format-Safe $Name)」は使えません。" @('半角英小文字・数字・ハイフンだけで、32 文字以内にしてください（先頭と末尾はハイフン以外）。')
    }
    $root = "/home/dcs/envs/$Name"
    return [pscustomobject]@{
        Root             = $root
        Config           = "$root/config"
        DevcontainerJson = "$root/config/.devcontainer/devcontainer.json"
        Work             = "$root/work"
        Relay            = "$root/relay.git"
        DomainsFile      = "$root/allowed-domains.txt"
        ClaudeVolume     = "dcs-$Name-claude"
        GitVolume        = "dcs-$Name-git"
        Network          = "dcs-$Name"
    }
}

# コンテナの中の作業フォルダ（土台の work/ をつなぐ先。D49）。リポジトリ名は、GitHub は repo_url の最後、
# LocalGit は repo_path のフォルダ名から .git を除いたもの（Validation.ps1 の RepoName）
function Get-EnvWorkspaceDir([string]$RepoName) {
    if ($RepoName -cnotmatch '^[A-Za-z0-9._-]+$' -or $RepoName -eq '.' -or $RepoName -eq '..') {
        Stop-Setup "リポジトリの名前「$(Format-Safe $RepoName)」は、作業フォルダの名前に使えません。" @('半角英数字と . _ - だけの名前にしてください。')
    }
    return "/workspaces/$RepoName"
}

# devcontainer up・exec に渡す名札（D44）。VS Code がコンテナに付ける名札と同じにして、同じコンテナを使わせる。
# VS Code は、土台のフォルダを \\wsl.localhost\<ディストリビューション>\... の形で名札にする（VERIFY.md の V12）
function Get-EnvIdLabelArgs([string]$Name) {
    $p = Get-EnvPaths $Name
    $localFolder = '\\wsl.localhost\dcs-base' + ($p.Config -replace '/', '\')
    return @('--id-label', "devcontainer.local_folder=$localFolder", '--id-label', "devcontainer.config_file=$($p.DevcontainerJson)")
}

# JSON の文字列（" と \ と制御文字をエスケープする）
function ConvertTo-JsonString([string]$Text) {
    $e = $Text.Replace('\', '\\').Replace('"', '\"')
    $e = [regex]::Replace($e, '[\x00-\x1F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
    return '"' + $e + '"'
}

# 値（文字列・真偽値・配列・順序付きの連想配列）を、2 文字の字下げ・LF の JSON にする。
# 注文書は利用者が VS Code で開いて読むので、PowerShell 5.1 の ConvertTo-Json（字下げが崩れる）は使わない
function ConvertTo-JsonText($Value, [int]$Depth = 0) {
    $pad = '  ' * ($Depth + 1)
    $end = '  ' * $Depth
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string]) { return (ConvertTo-JsonString $Value) }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Count -eq 0) { return '{}' }
        $items = @(foreach ($k in $Value.Keys) { $pad + (ConvertTo-JsonString $k) + ': ' + (ConvertTo-JsonText $Value[$k] ($Depth + 1)) })
        return "{`n" + ($items -join ",`n") + "`n$end}"
    }
    if ($Value -is [System.Collections.IList]) {
        if ($Value.Count -eq 0) { return '[]' }
        $items = @(foreach ($v in $Value) { $pad + (ConvertTo-JsonText $v ($Depth + 1)) })
        return "[`n" + ($items -join ",`n") + "`n$end]"
    }
    throw "JSON にできない値です: $($Value.GetType().FullName)"
}

# extensions.txt の中身を、拡張機能の ID の配列にする（# の行と空の行は飛ばす。重なりは除く）
function ConvertFrom-ExtensionsText([string]$Text) {
    $ids = New-Object System.Collections.Generic.List[string]
    $n = 0
    foreach ($line in ($Text -split "`n")) {
        $n++
        $s = $line.TrimEnd("`r").Trim()
        if ($s -eq '' -or $s.StartsWith('#')) { continue }
        if ($s -cnotmatch '^[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9][A-Za-z0-9.-]*$') {
            Stop-Setup "extensions.txt の $n 行目（$(Format-Safe $s)）は、拡張機能の ID の形ではありません。" @('「発行者.名前」の形（例: ms-python.python）で、1 行に 1 つ書いてください。')
        }
        if (-not $ids.Contains($s)) { $ids.Add($s) }
    }
    return $ids.ToArray()
}

# 注文書（devcontainer.json）の中身（6.4）。ツールのフォルダの templates\devcontainer.json.tmpl（利用者が読めるひな形。
# 変えてよい場所はひな形のコメントと README に書いてある。D51）の印を、この開発環境の値にして、LF の JSON を返す。
# // で始まる行は取り除く。印は 1 回の置き換えで値にする（値の中に印の形の文字があっても、もう一度置き換えない）。
# 知らない印・足りない印があるとき、できたものが JSON として読めないときは止める。$TemplatePath はテストのため
function New-DevcontainerJson {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('GitHub', 'LocalGit')][string]$Mode,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RepoName,
        [string[]]$Extensions = @(),
        [string]$TemplatePath = ''
    )
    $p = Get-EnvPaths $Name
    $ws = Get-EnvWorkspaceDir $RepoName
    if (-not $TemplatePath) { $TemplatePath = Join-Path $script:ToolRoot 'templates\devcontainer.json.tmpl' }
    $hint = "ツールのフォルダの templates\devcontainer.json.tmpl を確かめてください（変えてよい場所は、ひな形の最初のコメントと README の「カスタマイズ」）。"
    if ($Mode -eq 'GitHub') {
        $second = "source=$($p.GitVolume),target=/home/dev/.dcs-git,type=volume"
    } else {
        $second = "source=$($p.Relay),target=/relay.git,type=bind"
    }
    # 文字列の中に入る値（JSON のエスケープをして、前後の " を除いたもの）と、値そのものとして入る拡張機能の一覧
    $inString = @{
        '__ENV_NAME__'      = $Name
        '__NETWORK__'       = $p.Network
        '__WORK_DIR__'      = $p.Work
        '__WORKSPACE__'     = $ws
        '__CLAUDE_VOLUME__' = $p.ClaudeVolume
        '__SECOND_MOUNT__'  = $second
        '__DOMAINS_FILE__'  = $p.DomainsFile
    }
    $values = @{}
    foreach ($k in $inString.Keys) { $s = ConvertTo-JsonString $inString[$k]; $values[$k] = $s.Substring(1, $s.Length - 2) }
    # 拡張機能の一覧は、ひな形の customizations.vscode の中（字下げ 6 文字）の値になる
    $values['__EXTENSIONS__'] = ConvertTo-JsonText @($Extensions | Where-Object { $_ }) 3

    $text = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF).Replace("`r`n", "`n")
    $text = ((@($text -split "`n") | Where-Object { $_ -notmatch '^\s*//' }) -join "`n")
    $found = @([regex]::Matches($text, '__[A-Z_]+__') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    $unknown = @($found | Where-Object { -not $values.ContainsKey($_) })
    if ($unknown.Count -gt 0) { Stop-Setup "注文書のひな形に、知らない印があります: $($unknown -join ', ')" @($hint) }
    $missing = @($values.Keys | Where-Object { $found -notcontains $_ } | Sort-Object)
    if ($missing.Count -gt 0) { Stop-Setup "注文書のひな形に、ツールが使う印がありません: $($missing -join ', ')" @($hint) }
    $evaluator = { param($m) return $values[$m.Value] }.GetNewClosure()
    $json = [regex]::Replace($text, '__[A-Z_]+__', [System.Text.RegularExpressions.MatchEvaluator]$evaluator).TrimEnd("`n") + "`n"
    try { $parsed = ConvertFrom-Json -InputObject $json } catch {
        Stop-Setup '注文書のひな形（templates\devcontainer.json.tmpl）から作った注文書が、JSON として読めません。' @(
            'コメントは // で始まる行だけが使えます。足した行の最後のカンマと、" の付け忘れを確かめてください。', $hint)
    }
    # 動くプログラムを変える環境変数は書かせない（N1）。containerEnv（と remoteEnv）の PATH はイメージの PATH を置き換え、
    # Claude が書けるフォルダが前に来ると、起動のときの処理や検証で Claude のものが動く（D52 が外れる）
    foreach ($section in @('containerEnv', 'remoteEnv')) {
        $vars = Get-PropertyValue $parsed $section
        if ($null -eq $vars) { continue }
        foreach ($v in @($vars.PSObject.Properties)) {
            # 名前の形でないもの（"PATH=…"、bash の関数を差し替える BASH_FUNC_…%% など）も止める（m2）
            if ($v.Name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
                Stop-Setup "注文書のひな形の $section の名前「$(Format-Safe $v.Name)」は、環境変数の名前の形ではありません。" @('半角英数字と _ だけで、先頭は数字以外にしてください。', $hint)
            }
            if ($script:ForbiddenEnvNames -ccontains $v.Name) {
                Stop-Setup "注文書のひな形の $section に、$($v.Name) は書けません（動くプログラムを変える環境変数は、守りのために使えません）。" @(
                    '道具を VS Code の拡張機能から使いたいときは、コンテナの中で ~/.local/bin に入れる（かリンクを置く）か、image\Dockerfile の「ここに足してよい」の場所で入れてください（README の「カスタマイズ」）。',
                    $hint)
            }
        }
    }
    return $json
}

# 注文書の containerEnv・remoteEnv に書かせない環境変数（動くプログラムやライブラリ、bash が最初に読むファイル・動きを変えるもの。N1・m2。
# ENV は対話の sh だけが読み、アプリの変数の名前としてありうるので入れない。m4）
$script:ForbiddenEnvNames = @('PATH', 'LD_PRELOAD', 'LD_LIBRARY_PATH', 'LD_AUDIT', 'BASH_ENV', 'SHELLOPTS', 'BASHOPTS', 'PS4')

# 注文書のひな形から注文書を作れるかを、決まった値で先に確かめる（誤りがあれば止める）。「作る」「やり直す」で、
# 値を聞く前・何かを作る前に、ひな形の誤りを見つけるため（M4）。$TemplatePath はテストのため
function Assert-DevcontainerTemplate([string[]]$Extensions = @(), [string]$TemplatePath = '') {
    $null = New-DevcontainerJson -Name 'check' -Mode 'GitHub' -RepoName 'check' -Extensions $Extensions -TemplatePath $TemplatePath
}

# 開発環境の土台のフォルダを消すコマンド（土台の dcs で動かす）。work/ に書き込みの無いフォルダ（chmod -w したものや、
# ビルドの道具が作るもの）があると rm -rf が失敗するので、先に持ち主（dcs）が書けるようにする（M3）。
# chmod の失敗（持ち主の違うものなど）は無視し、rm の結果で判断する。$1 は空白を含まない決まったパス
function Get-RemoveEnvFolderArgs([string]$Root) {
    return @('bash', '-c', 'chmod -R u+rwX -- $1 2> /dev/null; rm -rf -- $1', '_', $Root)
}

# docker volume ls（「名前 VS Code の名札」の行）から、その開発環境のボリュームの名前を返す。
# dcs-<名前>-claude・dcs-<名前>-git と、名札がその開発環境の注文書の vscode-state-… のボリューム（VERIFY.md の V14）。行全体・名札の全体で比べる
function Get-EnvVolumeNames([string]$Name, [string]$VolumesText) {
    $config = (Get-EnvPaths $Name).DevcontainerJson
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($line in @(ConvertTo-Lines $VolumesText)) {
        $parts = $line.Split([char[]]@(' '), 2)
        $vol = $parts[0]
        $label = ''
        if ($parts.Count -gt 1) { $label = $parts[1].Trim() }
        if ($vol -ceq "dcs-$Name-claude" -or $vol -ceq "dcs-$Name-git" -or $label -ceq $config) {
            if (-not $names.Contains($vol)) { $names.Add($vol) }
        }
    }
    return $names.ToArray()
}

# git の設定ファイルの値（= のあと）を読む。前後の空白・引用符の外のコメント（# と ;）を除き、引用符の中のエスケープを戻す。
# 行の続き（行末の \）と、知らないエスケープのあとは読まない
function ConvertFrom-GitConfigValue([string]$Raw) {
    $sb = New-Object System.Text.StringBuilder
    $space = ''
    $quoted = $false
    $s = $Raw.TrimStart()
    $i = 0
    while ($i -lt $s.Length) {
        $ch = $s[$i]
        if ($ch -eq [char]'\') {
            if ($i + 1 -ge $s.Length) { break }
            $e = $null
            switch -CaseSensitive ([string]$s[$i + 1]) { 'n' { $e = "`n" } 't' { $e = "`t" } 'b' { $e = "`b" } '"' { $e = '"' } '\' { $e = '\' } }
            if ($null -eq $e) { break }
            [void]$sb.Append($space).Append($e)
            $space = ''
            $i += 2
            continue
        }
        if ($ch -eq [char]'"') { [void]$sb.Append($space); $space = ''; $quoted = -not $quoted; $i++; continue }
        if (-not $quoted -and ($ch -eq [char]'#' -or $ch -eq [char]';')) { break }
        if (-not $quoted -and [char]::IsWhiteSpace($ch)) { $space += $ch; $i++; continue }
        [void]$sb.Append($space).Append($ch)
        $space = ''
        $i++
    }
    return $sb.ToString()
}

# git の設定ファイル（.git/config）の中身を、「セクション.サブセクション.キー」→ 値 の表にする（同じキーは後のものが勝つ）。
# git と同じく、セクションとキーの名前は小文字にそろえ、サブセクション（[remote "origin"] の origin）は大文字と小文字を区別する。
# 読めない行は飛ばす。作業フォルダの .git/config は Claude が書き換えられるので、値は呼び出す側が確かめる（I1）
function ConvertFrom-GitConfigText([string]$Text) {
    $values = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    $section = ''
    foreach ($raw in ($Text -split "`n")) {
        $line = $raw.TrimEnd("`r")
        $h = [regex]::Match($line, '^\s*\[\s*([A-Za-z0-9.-]+)(\s+"((?:[^"\\]|\\.)*)")?\s*\](.*)$')
        if ($h.Success) {
            $section = $h.Groups[1].Value.ToLowerInvariant()
            if ($h.Groups[2].Success) { $section += '.' + [regex]::Replace($h.Groups[3].Value, '\\(.)', '$1') }
            $line = $h.Groups[4].Value
        }
        $k = [regex]::Match($line, '^\s*([A-Za-z][A-Za-z0-9-]*)\s*(=(.*))?$')
        if (-not $k.Success -or -not $section) { continue }
        $value = 'true'
        if ($k.Groups[2].Success) { $value = ConvertFrom-GitConfigValue $k.Groups[3].Value }
        $values["$section.$($k.Groups[1].Value.ToLowerInvariant())"] = $value
    }
    return $values
}

# devcontainer up の標準出力の最後の行（結果の JSON。VERIFY.md の V8）から、成功したときの containerId を取り出す。
# 失敗のとき・形が違うときは $null（StrictMode でも落ちないよう、キーがあるかを先に確かめる）
function ConvertFrom-UpResultText([string]$Text) {
    $last = @(ConvertTo-Lines $Text) | Select-Object -Last 1
    if (-not $last) { return $null }
    try { $j = ConvertFrom-Json -InputObject $last } catch { return $null }
    if ($j -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    $props = $j.PSObject.Properties
    if ($null -eq $props['outcome'] -or "$($j.outcome)" -ne 'success') { return $null }
    if ($null -eq $props['containerId'] -or "$($j.containerId)" -notmatch '^[0-9a-f]{64}$') { return $null }
    return "$($j.containerId)"
}

# 土台の allowed-domains.txt の中身（1 行目はコメント。そのあと 1 行に 1 ドメイン。LF）
function New-DomainsFileText([string[]]$Domains = @()) {
    $lines = @('# allowed_domains（dev-container-setup が書きます）') + @($Domains | Where-Object { $_ })
    return (($lines -join "`n") + "`n")
}

# オブジェクトのプロパティの値（無ければ $null。StrictMode でも落ちないように）
function Get-PropertyValue($Object, [string]$Name) {
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return $null }
    return $Object.$Name
}

# docker inspect（コンテナ）と docker network inspect（ネットワーク）の結果を、決めた守りと比べる（6.5d の 2 行目）。
# 守れていない項目の説明を 1 つずつ返す（無ければ何も返さない。呼び出す側は @() で受け取る）。
# $StateVolumes は、VS Code がつなぐ vscode-state-… のボリュームのうち、名札がこの開発環境の注文書のもの（Get-EnvVolumeNames）
function Test-ContainerInspect($Container, $Network, [string]$Name, [string]$Mode, [string[]]$StateVolumes = @()) {
    $p = Get-EnvPaths $Name
    $problems = New-Object System.Collections.Generic.List[string]
    $hc = $Container.HostConfig

    # ネットワーク: 開発環境専用のもの 1 つだけで、IPv6 なし。そのネットワークには、このコンテナのほかにつながっていない
    $nets = @($Container.NetworkSettings.Networks.PSObject.Properties | ForEach-Object { $_.Name })
    if ($nets.Count -ne 1 -or $nets[0] -ne $p.Network) {
        $problems.Add("つながっているネットワークが $($p.Network) の 1 つだけではありません（$($nets -join ', ')）。")
    }
    if ($Network.EnableIPv6) { $problems.Add("ネットワーク $($p.Network) で IPv6 が有効です。") }
    $attached = Get-PropertyValue $Network 'Containers'
    if ($null -ne $attached) {
        foreach ($a in @($attached.PSObject.Properties)) {
            if ($a.Name -ne "$($Container.Id)") {
                $problems.Add("ネットワーク $($p.Network) に、ほかのコンテナ（$(Get-PropertyValue $a.Value 'Name')）がつながっています。")
            }
        }
    }

    # ホストやほかのコンテナと名前空間を分ける（--pid=host などは、土台の dcs のファイルに届く。I2）
    $allowed = @{ PidMode = @(''); IpcMode = @('', 'private', 'shareable'); UTSMode = @(''); UsernsMode = @(''); CgroupnsMode = @('', 'private') }
    foreach ($k in @('PidMode', 'IpcMode', 'UTSMode', 'UsernsMode', 'CgroupnsMode')) {
        $v = "$(Get-PropertyValue $hc $k)"
        if ($allowed[$k] -notcontains $v) { $problems.Add("$k が「$v」です（ホストやほかのコンテナと、名前空間を分けるはず）。") }
    }
    # 土台のデバイスを渡さない
    foreach ($d in @(Get-PropertyValue $hc 'Devices' | Where-Object { $_ })) {
        $problems.Add("土台のデバイス（$(Get-PropertyValue $d 'PathOnHost')）が渡されています。")
    }
    if (@(Get-PropertyValue $hc 'DeviceRequests' | Where-Object { $_ }).Count -gt 0) { $problems.Add('DeviceRequests（GPU など）があります。') }
    if (@(Get-PropertyValue $hc 'DeviceCgroupRules' | Where-Object { $_ }).Count -gt 0) { $problems.Add('DeviceCgroupRules（デバイスを使う許可）があります。') }
    # /proc と /sys の一部を、隠す・読み取り専用にする（Docker の既定。systempaths=unconfined や privileged で無くなる）
    foreach ($k in @('MaskedPaths', 'ReadonlyPaths')) {
        if (@(Get-PropertyValue $hc $k | Where-Object { $_ }).Count -eq 0) { $problems.Add("$k（/proc と /sys の守り）がありません。") }
    }

    # ポートの公開が無い
    $bindings = @()
    if ($null -ne $Container.HostConfig.PortBindings) { $bindings += @($Container.HostConfig.PortBindings.PSObject.Properties) }
    if ($null -ne $Container.NetworkSettings.Ports) { $bindings += @($Container.NetworkSettings.Ports.PSObject.Properties) }
    foreach ($b in $bindings) {
        foreach ($h in @($b.Value | Where-Object { $_ -and $_.HostPort })) {
            $problems.Add("ポート $($b.Name) が、土台の $($h.HostPort) 番に公開されています。")
        }
    }

    # 特権・足した権限・seccomp と AppArmor
    if ($Container.HostConfig.Privileged) { $problems.Add('privileged（特権）が有効です。') }
    foreach ($cap in @($Container.HostConfig.CapAdd | Where-Object { $_ })) {
        $c = ($cap -replace '^CAP_', '').ToUpperInvariant()
        if ($c -ne 'NET_ADMIN' -and $c -ne 'NET_RAW') { $problems.Add("足した権限に $cap があります（NET_ADMIN と NET_RAW だけのはず）。") }
    }
    # SecurityOpt は、no-new-privileges のほかは付けない（seccomp・AppArmor・SELinux の label・systempaths は既定のまま）
    foreach ($o in @($Container.HostConfig.SecurityOpt | Where-Object { $_ })) {
        if ($o -notmatch '^no-new-privileges([=:]true)?$') {
            $problems.Add("SecurityOpt に $o があります（seccomp・AppArmor などは既定のままのはず）。")
        }
    }

    # つないでいるもの: 決めた 4 つ（と、VS Code の開発環境ごとの vscode-state-… のボリューム）だけ。
    # work/ のつなぐ先は /workspaces/<リポジトリ名>（D49。名前は見た目のためのもので、守りには関わらないので、形だけを確かめる）
    $workTo = $null
    foreach ($m in @($Container.Mounts | Where-Object { $_ -and $_.Type -eq 'bind' })) {
        if ($null -ne $m.PSObject.Properties['Source'] -and "$($m.Source)" -eq $p.Work) { $workTo = "$($m.Destination)" }
    }
    if ($null -eq $workTo -or $workTo -cnotmatch '^/workspaces/[A-Za-z0-9._-]+$' -or $workTo -eq '/workspaces/.' -or $workTo -eq '/workspaces/..') {
        $workTo = '/workspaces/<リポジトリ名>'
    }
    $expected = @(
        @{ Type = 'bind'; From = $p.Work; To = $workTo },
        @{ Type = 'volume'; From = $p.ClaudeVolume; To = '/home/dev/.claude' },
        @{ Type = 'bind'; From = $p.DomainsFile; To = '/etc/dcs/allowed-domains.txt' })
    if ($Mode -eq 'GitHub') {
        $expected += @{ Type = 'volume'; From = $p.GitVolume; To = '/home/dev/.dcs-git' }
    } else {
        $expected += @{ Type = 'bind'; From = $p.Relay; To = '/relay.git' }
    }
    $seen = @{}
    foreach ($m in @($Container.Mounts | Where-Object { $_ })) {
        # 種類によって無いキーがある（bind には Name が無い、tmpfs には Source が無いなど）ので、あるものだけを読む
        $src = ''; if ($null -ne $m.PSObject.Properties['Source']) { $src = "$($m.Source)" }
        $vol = ''; if ($null -ne $m.PSObject.Properties['Name']) { $vol = "$($m.Name)" }
        if ($m.Type -eq 'volume') { $from = $vol } else { $from = $src }
        $desc = "$($m.Type) $from → $($m.Destination)"
        if ($src -match 'docker\.sock' -or $m.Destination -match 'docker\.sock') {
            $problems.Add("Docker のソケットがつながっています（$desc）。")
            continue
        }
        if ($m.Type -eq 'volume' -and $m.Destination -eq '/.vscode-volume' -and $vol -like 'vscode-state-*' -and $StateVolumes -contains $vol) { continue }
        if ($m.Type -eq 'volume' -and $vol -eq 'vscode') {
            $problems.Add("すべての開発環境で共有の vscode のボリュームがつながっています（$desc）。Windows の VS Code の設定に dev.containers.cacheVolume: false を置いてください。")
            continue
        }
        $hit = $expected | Where-Object { $_.Type -eq $m.Type -and $_.From -eq $from -and $_.To -eq $m.Destination } | Select-Object -First 1
        if ($null -eq $hit) {
            $problems.Add("決めていないものがつながっています（$desc）。")
            continue
        }
        $seen[$hit.To] = $true
        if ($hit.To -eq '/etc/dcs/allowed-domains.txt' -and $m.RW) {
            $problems.Add('allowed-domains.txt が、書き込める形でつながっています（読み取り専用のはず）。')
        }
    }
    foreach ($e in $expected) {
        if (-not $seen.ContainsKey($e.To)) { $problems.Add("決めたもの（$($e.Type) $($e.From) → $($e.To)）がつながっていません。") }
    }
    return $problems.ToArray()
}
