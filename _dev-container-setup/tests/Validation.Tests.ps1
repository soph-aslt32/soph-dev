# 入力の規則（lib/Validation.ps1）の単体テスト。Pester 3.4（Windows に最初から入っているもの）で動かす。
#   Invoke-Pester -Script .\_dev-container-setup\tests\Validation.Tests.ps1
# 本番（入口のスクリプト）と同じ条件で動かす
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\lib\Common.ps1"
. "$PSScriptRoot\..\lib\Validation.ps1"

Describe 'Test-EnvNameValue' {
    It 'accepts <n>' -TestCases @(@{n = 'foo'}, @{n = 'a'}, @{n = 'a1-b2'}, @{n = ('a' * 32)}) {
        param($n)
        Test-EnvNameValue $n | Should BeNullOrEmpty
    }
    It 'rejects <n>' -TestCases @(@{n = 'Foo'}, @{n = '-foo'}, @{n = 'foo-'}, @{n = ('a' * 33)}, @{n = 'fo_o'}) {
        param($n)
        Test-EnvNameValue $n | Should Not BeNullOrEmpty
    }
}

Describe 'ConvertTo-AllowedDomains' {
    It 'dedups and trims' {
        (ConvertTo-AllowedDomains 'registry.npmjs.org, pypi.org,pypi.org').Domains -join '|' | Should Be 'registry.npmjs.org|pypi.org'
    }
    It 'allows empty' {
        $r = ConvertTo-AllowedDomains ''
        $r.Error | Should BeNullOrEmpty
        @($r.Domains).Count | Should Be 0
    }
    It 'rejects *' {
        (ConvertTo-AllowedDomains '*').Error.Message | Should Match '「\*」'
    }
    It 'rejects *. with the D42 hint' {
        $e = (ConvertTo-AllowedDomains 'a.com, *.example.com').Error
        $e.Message | Should Match '\*\.example\.com'
        ($e.Hint -join ' ') | Should Match 'サブドメイン'
    }
    It 'rejects <d>' -TestCases @(@{d = 'https://x.com'}, @{d = 'localhost'}, @{d = 'a..b'}, @{d = '-a.com'}) {
        param($d)
        (ConvertTo-AllowedDomains $d).Error | Should Not BeNullOrEmpty
    }
}

Describe 'ConvertFrom-DefaultsText' {
    It 'reads allowed_domains' {
        (ConvertFrom-DefaultsText "# c`r`nallowed_domains = a.com, b.org`r`n" 'x') -join '|' | Should Be 'a.com|b.org'
    }
    It 'handles BOM and empty value' {
        @(ConvertFrom-DefaultsText ([string][char]0xFEFF + 'allowed_domains =') 'x').Count | Should Be 0
    }
    It 'throws on <t>' -TestCases @(@{t = ''}, @{t = "foo = 1`n"}, @{t = "allowed_domains = a.com`nallowed_domains = b.com`n"}, @{t = "allowed_domains = *.a.com`n"}) {
        param($t)
        { ConvertFrom-DefaultsText $t 'x' } | Should Throw
    }
}

Describe 'GitHub values' {
    It 'pat ok' {
        Test-GitHubPatValue ('ghp_' + 'a' * 36) | Should BeNullOrEmpty
    }
    It 'pat error hides value' {
        $e = Test-GitHubPatValue 'secret-xyz'
        $e.Message | Should Not Match 'secret-xyz'
    }
    It 'user_name rejects <' {
        Test-GitHubUserNameValue 'a<b' | Should Not BeNullOrEmpty
    }
    It 'user_name allows quote, space, Japanese, dollar' {
        Test-GitHubUserNameValue "O'Neil 太郎 `$x" | Should BeNullOrEmpty
    }
    It 'email' {
        Test-GitHubEmailValue 'a@b.c' | Should BeNullOrEmpty
        Test-GitHubEmailValue 'a b@c' | Should Not BeNullOrEmpty
    }
    It 'repo url normalizes <u>' -TestCases @(@{u = 'https://github.com/o/r'}, @{u = 'https://GitHub.com/o/r.git/'}) {
        param($u)
        (ConvertFrom-GitHubRepoUrl $u).RepoUrl | Should Be 'https://github.com/o/r.git'
    }
    It 'repo url rejects <u>' -TestCases @(@{u = 'git@github.com:o/r.git'}, @{u = 'https://github.com/o/..'}, @{u = 'https://gitlab.com/o/r'}) {
        param($u)
        (ConvertFrom-GitHubRepoUrl $u).Error | Should Not BeNullOrEmpty
    }
}

Describe 'ConvertFrom-LocalGitRepoPath' {
    It 'accepts a bare repo' {
        & git.exe init -q --bare "$TestDrive\foo.git"
        $r = ConvertFrom-LocalGitRepoPath "$TestDrive\foo.git\"
        $r.Error | Should BeNullOrEmpty
        $r.RepoName | Should Be 'foo'
    }
    It 'rejects non-bare' {
        & git.exe init -q "$TestDrive\w"
        (ConvertFrom-LocalGitRepoPath "$TestDrive\w").Error | Should Not BeNullOrEmpty
    }
    It 'rejects UNC' {
        (ConvertFrom-LocalGitRepoPath '\\server\x.git').Error | Should Not BeNullOrEmpty
    }
    It 'rejects a folder name with a space' {
        & git.exe init -q --bare "$TestDrive\a b.git"
        (ConvertFrom-LocalGitRepoPath "$TestDrive\a b.git").Error | Should Not BeNullOrEmpty
    }
}
