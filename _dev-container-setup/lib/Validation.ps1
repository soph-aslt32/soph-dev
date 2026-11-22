#Requires -Version 5.1
# =============================================================================
# Validation.ps1 — ウィザードの入力の規則（dev-container-setup）
#
# 値をチェックする関数は、正しければ $null、誤りなら New-InputError（Common.ps1）の結果を返す。
# 規則は従来の _wsl-room-setup の New-SecureRoom.ps1 と同じ（DESIGN.md の 6.8）。
# 違うのは allowed_domains の「*.」で始まる書き方を断ること（DESIGN.md の D42）。
# 正規表現は関数の中に直接書く（dot-source で読み込んだときに、スクリプトの変数が見つからないことがあるため）。
# =============================================================================

# 開発環境の名前（従来の部屋の名前と同じ規則）
function Test-EnvNameValue([string]$Value) {
    if ($Value -cnotmatch '^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$') {
        return (New-InputError "開発環境の名前「$Value」は使えません。" @(
            '半角英小文字・数字・ハイフンだけで、32 文字以内にしてください（先頭と末尾はハイフン以外）。'))
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
                '「*」はすべてのドメインへの通信を許してしまい、ファイアウォールの意味がなくなるためです。')) }
        }
        if ($d.StartsWith('*.')) {
            return [pscustomobject]@{ Domains = @(); Error = (New-InputError "*. で始まる書き方（$d）は使えません。" @(
                'この開発環境のファイアウォールは、起動のときにドメインごとに IP アドレスを引くので、サブドメインをまとめて許せません。',
                '使うサブドメインを 1 つずつ書いてください（例: api.example.com, cdn.example.com）。')) }
        }
        if ($d -cnotmatch '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$') {
            return [pscustomobject]@{ Domains = @(); Error = (New-InputError "ドメイン名として正しくありません: $d" @(
                '例: registry.npmjs.org のように書いてください（https:// やパスは不要です）。')) }
        }
        if (-not $domains.Contains($d)) { $domains.Add($d) }
    }
    return [pscustomobject]@{ Domains = $domains.ToArray(); Error = $null }
}

# このフォルダの defaults.conf（入力の既定値。今は allowed_domains だけ）の文章を読んで、ドメインの配列を返す。
# 書き方は従来の room.conf と同じ「名前 = 値」。誤りは、何行目かを付けて止める。$Name は表示に使うファイルの名前。
function ConvertFrom-DefaultsText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [string]$Name = 'defaults.conf'
    )
    $domains = @()
    $seen = $false
    $lineNo = 0
    foreach ($raw in ($Text -split "`r?`n")) {
        $lineNo++
        $line = $raw.Trim().TrimStart([char]0xFEFF)
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -cmatch '^([a-z_]+)\s*=(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()
        } else {
            Stop-Setup "$Name の $lineNo 行目の書き方が正しくありません: $line" @('「名前 = 値」の形で書いてください。')
        }
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ($key -cne 'allowed_domains') {
            Stop-Setup "$Name の $lineNo 行目: 知らない項目名です: $key" @('使える項目は allowed_domains です。')
        }
        if ($seen) { Stop-Setup "$Name の $lineNo 行目: allowed_domains が 2 回書かれています。" }
        $seen = $true
        $parsed = ConvertTo-AllowedDomains $value
        if ($null -ne $parsed.Error) { Stop-Setup "$Name の $lineNo 行目: $($parsed.Error.Message)" $parsed.Error.Hint }
        $domains = $parsed.Domains
    }
    if (-not $seen) {
        Stop-Setup "$Name に allowed_domains がありません。" @(
            '通信を許可するドメインが無い場合も「allowed_domains =」と空で書いてください。')
    }
    return $domains
}

# ----- GitHub の設定（規則は image/dcs-github.sh と同じ。変えるときは両方） -----
# PAT は、どの表示にも含めない。

function Test-GitHubUserNameValue([string]$Value) {
    if ($Value -match '[\x00-\x1F\x7F-\x9F<>]') {
        return (New-InputError 'user_name に使えない文字が含まれています。' @('制御文字と < > は使えません。'))
    }
    return $null
}

function Test-GitHubEmailValue([string]$Value) {
    if ($Value -notmatch '^[^\s<>@]+@[^\s<>@]+$' -or $Value -match '[\x00-\x1F\x7F-\x9F]') {
        return (New-InputError "user_email がメールアドレスの形になっていません: $Value" @('例: dev-env@example.com'))
    }
    return $null
}

function Test-GitHubPatValue([string]$Value) {
    if ($Value -cnotmatch '^[A-Za-z0-9_]{20,255}$') {
        return (New-InputError 'pat が PAT の形になっていません（内容は表示しません）。' @(
            'GitHub で作成したトークン（github_pat_ や ghp_ で始まる、英数字と _ だけの文字列）を、そのまま貼り付けてください。'))
    }
    return $null
}

# repo_url を確かめて、Owner・RepoName・RepoUrl（https://github.com/OWNER/REPOSITORY.git の形）と Error を返す。
# 末尾の .git と / は省略できる。
function ConvertFrom-GitHubRepoUrl([string]$Value) {
    $owner = ''
    $repo = ''
    $err = $null
    if ($Value -cmatch '^https://(?i:github\.com)/([A-Za-z0-9-]+)/([A-Za-z0-9._-]+?)(?:\.git)?/?$') {
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

# ----- LocalGit の設定 -----

# repo_path（Windows 側の bare リポジトリのフォルダ）を確かめて、RepoPath・RepoName・Error を返す
function ConvertFrom-LocalGitRepoPath([string]$Value) {
    $path = $Value.TrimEnd('\')
    $name = ''
    $err = $null
    $isNetwork = $false
    if ($path -match '^[A-Za-z]:\\') {
        try { $isNetwork = ((New-Object System.IO.DriveInfo $path.Substring(0, 2)).DriveType -eq [System.IO.DriveType]::Network) } catch { $isNetwork = $false }
    }
    if ($path -notmatch '^[A-Za-z]:\\.') {
        $err = New-InputError "repo_path が正しくありません: $Value" @('C:\repos\foo.git のように、ドライブ名から始まるフォルダのパスで書いてください（\\ で始まる場所は使えません）。')
    } elseif ($isNetwork) {
        $err = New-InputError "repo_path がネットワークドライブにあります: $Value" @('Windows のローカルのフォルダにある bare リポジトリを指定してください。')
    } elseif (-not (Test-Path -LiteralPath $path -PathType Container)) {
        $err = New-InputError "repo_path のフォルダが見つかりません: $Value"
    } elseif (-not (Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        $err = New-InputError 'git が見つかりません（LocalGit には Windows 側の git が必要です）。' @('Git for Windows（https://git-scm.com/）をインストールしてから、もう一度実行してください。')
    } else {
        $ErrorActionPreference = 'Continue'
        $out = & git.exe "--git-dir=$path" rev-parse --is-bare-repository 2>$null
        if ($LASTEXITCODE -ne 0 -or "$out".Trim() -ne 'true') {
            $err = New-InputError "repo_path は bare リポジトリではありません: $Value" @(
                'HEAD・config・objects・refs などが直接入っているフォルダ（git init --bare で作ったもの）を指定してください。')
        } else {
            $name = (Split-Path -Leaf $path) -replace '(?i)\.git$', ''
            if ($name -cnotmatch '^[A-Za-z0-9._-]+$' -or $name -eq '.' -or $name -eq '..') {
                $err = New-InputError "repo_path のフォルダ名「$(Split-Path -Leaf $path)」は使えません。" @(
                    'フォルダ名（末尾の .git を除く）は、半角英数字と . _ - だけにしてください。')
            }
        }
    }
    return [pscustomobject]@{ RepoPath = $path; RepoName = $name; Error = $err }
}
