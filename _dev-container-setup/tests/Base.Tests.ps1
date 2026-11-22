# 土台（lib/Base.ps1）の単体テスト。WSL の中では何も実行しない。Pester 3.4 で動かす。
#   Invoke-Pester -Script .\_dev-container-setup\tests\Base.Tests.ps1
# 本番（入口のスクリプト）と同じ条件で動かす
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\lib\Common.ps1"
. "$PSScriptRoot\..\lib\Base.ps1"

Describe 'Get-WinProfileName' {
    It 'takes the leaf' {
        Get-WinProfileName 'C:\Users\taro' | Should Be 'taro'
    }
    It 'rejects <p>' -TestCases @(@{p = 'D:\Users\taro'}, @{p = 'C:\Users\山田'}, @{p = 'C:\Users\a b'}, @{p = 'C:\x\taro'}) {
        param($p)
        { Get-WinProfileName $p } | Should Throw
    }
}

Describe 'ConvertFrom-WslListText' {
    It 'strips NUL and blanks' {
        (ConvertFrom-WslListText ("U`0b`0u`0n`0t`0u`0`r`n`r`ndcs-base`r`n")) -join '|' | Should Be 'Ubuntu|dcs-base'
    }
}

# ドライランでは WSL の中で何も実行しない（土台の状態を見る関数だけを置き換える）
Describe 'New-Base (dry run)' {
    It 'does not say that the base setup is done' {
        Mock Get-BaseState { 'Missing' }
        Mock Write-Ok {}
        $script:DryRun = $true
        try { New-Base } finally { $script:DryRun = $false }
        Assert-MockCalled Write-Ok -Scope It -Times 0 -Exactly -ParameterFilter { $Text -like '*設定が終わりました*' }
    }
}

Describe 'Build-DcsImage (dry run)' {
    It 'builds with the plain progress output (one line per step, not redrawn)' {
        Mock Write-DryRun {}
        $script:DryRun = $true
        try { Build-DcsImage -Refresh } finally { $script:DryRun = $false }
        Assert-MockCalled Write-DryRun -Scope It -Times 1 -Exactly -ParameterFilter { $Text -like '*docker build --progress=plain *' }
    }
    It 'uses the image that is already there, also in a dry run, because looking only reads (M1)' {
        Mock Test-DcsImageExists { $true }
        Mock Write-Ok {}
        Mock Write-DryRun {}
        $script:DryRun = $true
        try { Build-DcsImage } finally { $script:DryRun = $false }
        Assert-MockCalled Write-Ok -Scope It -Times 1 -Exactly -ParameterFilter { $Text -like '*既にあるイメージ*' }
        Assert-MockCalled Write-DryRun -Scope It -Times 0 -Exactly
    }
}

# 土台の検証。B2 は、/etc/wsl.conf を、Windows 側のツールの base\wsl.conf と比べる（土台に置いたファイルが古くても、正しく判定する）
Describe 'Test-Base' {
    BeforeEach {
        Mock Write-CheckLines {}
        Mock Write-Note {}
        Mock Write-Step {}
        Mock Write-DryRun {}
    }
    It 'passes the SHA256 of the wsl.conf of the tool on Windows (B2)' {
        Mock Invoke-InBase { [pscustomobject]@{ Code = 0; Text = "[OK] B1 a`n"; Error = '' } }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $want = ([BitConverter]::ToString($sha.ComputeHash((Get-LfBytes (Join-Path $script:ToolRoot 'base\wsl.conf')))) -replace '-', '').ToLowerInvariant()
        Test-Base | Should Be $true
        Assert-MockCalled Invoke-InBase -Scope It -Times 1 -Exactly -ParameterFilter { ($ArgList -join ' ') -match 'verify-base\.sh' -and $ArgList[-1] -eq $want }
    }
    It 'checks even in a dry run when asked (-Always), because it only reads (M1)' {
        Mock Invoke-InBase { [pscustomobject]@{ Code = 0; Text = "[OK] B1 a`n"; Error = '' } }
        $script:DryRun = $true
        try { Test-Base -Always | Should Be $true } finally { $script:DryRun = $false }
        Assert-MockCalled Invoke-InBase -Scope It -Times 1 -Exactly
    }
    It 'treats the NG of the listed checks as passed, and only those' {
        Mock Invoke-InBase { [pscustomobject]@{ Code = 1; Text = "[OK] B1 a`n[NG] B2 b: c`n"; Error = '' } }
        Test-Base -Tolerate @('B2') | Should Be $true
        Test-Base | Should Be $false
        Test-Base -Tolerate @('B3') | Should Be $false
        Mock Invoke-InBase { [pscustomobject]@{ Code = 1; Text = "[NG] B1 a: x`n[NG] B2 b: c`n"; Error = '' } }
        Test-Base -Tolerate @('B2') | Should Be $false
    }
}

# ツールのファイルを土台に置く（I4。途中で失敗しても、前のものを消したままにしない）
Describe 'Copy-ToBase' {
    $savedRoot = $script:ToolRoot
    function New-ToolDir([string]$Name, [hashtable]$Files) {
        $root = Join-Path $TestDrive $Name
        $null = New-Item -ItemType Directory -Force (Join-Path $root 'base')
        foreach ($k in $Files.Keys) { [IO.File]::WriteAllText((Join-Path $root "base\$k"), $Files[$k], (New-Object Text.UTF8Encoding($false))) }
        return $root
    }
    BeforeEach { Mock Write-Step {}; Mock Write-Ok {} }
    It 'checks every file before it touches the base' {
        try {
            $script:ToolRoot = New-ToolDir 't1' @{ 'a.sh' = "ok`n"; 'b.sh' = "bad`r`n" }
            Mock Invoke-InBase { [pscustomobject]@{ Code = 0; Text = ''; Error = '' } }
            { Copy-ToBase } | Should Throw 'CRLF'
            Assert-MockCalled Invoke-InBase -Scope It -Times 0 -Exactly
        } finally { $script:ToolRoot = $savedRoot }
    }
    It 'writes into a new folder, and does not put it in place when the hashes do not match' {
        try {
            $script:ToolRoot = New-ToolDir 't2' @{ 'a.sh' = "ok`n" }
            Mock Invoke-InBase {
                if ($ArgList[0] -eq 'sha256sum') { return [pscustomobject]@{ Code = 0; Text = (('0' * 64) + '  /opt/dcs/base.new/a.sh' + "`n"); Error = '' } }
                return [pscustomobject]@{ Code = 0; Text = ''; Error = '' }
            }
            { Copy-ToBase } | Should Throw '一致しません'
            Assert-MockCalled Invoke-InBase -Scope It -Times 1 -Exactly -ParameterFilter { ($ArgList -join ' ') -match 'base64 -d' -and $ArgList[-1] -eq '/opt/dcs/base.new/a.sh' }
            Assert-MockCalled Invoke-InBase -Scope It -Times 0 -Exactly -ParameterFilter { ($ArgList -join ' ') -match '\bmv\b' }
        } finally { $script:ToolRoot = $savedRoot }
    }
    It 'puts the new folder in place after the hashes match' {
        try {
            $script:ToolRoot = New-ToolDir 't3' @{ 'a.sh' = "ok`n" }
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $script:hashA = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes("ok`n"))) -replace '-', '').ToLowerInvariant()
            Mock Invoke-InBase {
                if ($ArgList[0] -eq 'sha256sum') { return [pscustomobject]@{ Code = 0; Text = ($script:hashA + '  /opt/dcs/base.new/a.sh' + "`n"); Error = '' } }
                return [pscustomobject]@{ Code = 0; Text = ''; Error = '' }
            }
            Copy-ToBase
            Assert-MockCalled Invoke-InBase -Scope It -Times 1 -Exactly -ParameterFilter { ($ArgList -join ' ') -match '\bmv\b' -and $ArgList[-1] -eq '/opt/dcs/base' }
        } finally { $script:ToolRoot = $savedRoot }
    }
}
