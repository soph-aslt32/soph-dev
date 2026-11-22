# 共通部分（lib/Common.ps1）の単体テスト。Pester 3.4（Windows に最初から入っているもの）で動かす。
#   Invoke-Pester -Script .\_dev-container-setup\tests\Common.Tests.ps1
# 本番（入口のスクリプト）と同じ条件で動かす
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\lib\Common.ps1"

Describe 'ConvertTo-CommandLineArg' {
    It '<s> -> <e>' -TestCases @(
        @{s = 'a'; e = 'a'},
        @{s = 'a b'; e = '"a b"'},
        @{s = 'a"b'; e = '"a\"b"'},
        @{s = 'C:\a b\'; e = '"C:\a b\\"'},
        @{s = ''; e = '""'}) {
        param($s, $e)
        ConvertTo-CommandLineArg $s | Should Be $e
    }
}

Describe 'Get-CheckNgIds' {
    It 'lists the IDs of the NG lines' { (Get-CheckNgIds "[OK] B1 a`n[NG] B2 b: c`n[WARN] B4 d: e`n[NG] B3 f: g`n") -join '|' | Should Be 'B2|B3' }
    It 'none' { @(Get-CheckNgIds "[OK] B1 a`n").Count | Should Be 0 }
}

Describe 'Get-LfSha256' {
    It 'is the SHA256 of the file (in lowercase hex)' {
        $f = Join-Path $TestDrive 'a.txt'
        [IO.File]::WriteAllText($f, "a`n", (New-Object Text.UTF8Encoding($false)))
        Get-LfSha256 $f | Should Be '87428fc522803d31065e7bce3cf03fe475096631e5e07bbd7a0fde60c4cf25c7'
    }
}

Describe 'Format-Safe' {
    It 'replaces ESC and bidi chars' {
        Format-Safe ('a' + [char]27 + '[2Jb' + [char]0x202E + 'c') | Should Be 'a?[2Jb?c'
    }
}

Describe 'Get-LfBytes' {
    It 'accepts LF UTF-8' {
        [IO.File]::WriteAllText("$TestDrive\a", "x`ny`n", (New-Object Text.UTF8Encoding($false)))
        (Get-LfBytes "$TestDrive\a").Length | Should Be 4
    }
    It 'rejects CRLF' {
        [IO.File]::WriteAllText("$TestDrive\b", "x`r`n", (New-Object Text.UTF8Encoding($false)))
        { Get-LfBytes "$TestDrive\b" } | Should Throw
    }
    It 'rejects BOM' {
        [IO.File]::WriteAllText("$TestDrive\c", "x`n", (New-Object Text.UTF8Encoding($true)))
        { Get-LfBytes "$TestDrive\c" } | Should Throw
    }
}

# VERIFY.md の V9: コンソールの入力の文字コードが「UTF-8（BOM あり）」だと、.NET の Process は標準入力の先頭に BOM を書く。
# Invoke-Native は、起動の前に BOM なしにして、終わったら元に戻す。
Describe 'Invoke-Native' {
    It 'does not prepend a BOM to stdin even when the console input encoding has one' {
        $saved = [Console]::InputEncoding
        try {
            [Console]::InputEncoding = New-Object Text.UTF8Encoding($true)
            $r = Invoke-Native -File "$env:SystemRoot\System32\findstr.exe" -ArgList @('^') -InputText "abc`n"
        } finally {
            [Console]::InputEncoding = $saved
        }
        $r.Code | Should Be 0
        [int][char]$r.Text[0] | Should Be ([int][char]'a')
    }
    It 'restores the console input encoding' {
        $saved = [Console]::InputEncoding
        try {
            [Console]::InputEncoding = New-Object Text.UTF8Encoding($true)
            $null = Invoke-Native -File "$env:SystemRoot\System32\findstr.exe" -ArgList @('^') -InputText "abc`n"
            [Console]::InputEncoding.GetPreamble().Length | Should Be 3
        } finally {
            [Console]::InputEncoding = $saved
        }
    }
}
