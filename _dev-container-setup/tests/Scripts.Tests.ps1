# 開発環境ごとの Windows 側のスクリプト（lib/Scripts.ps1 と templates/Sync-Env.ps1.tmpl）の単体テスト。
# WSL の中では何も実行しない。Pester 3.4 で動かす。
#   Invoke-Pester -Script .\_dev-container-setup\tests\Scripts.Tests.ps1
# 本番（入口のスクリプト）と同じ条件で動かす
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\lib\Common.ps1"
. "$PSScriptRoot\..\lib\Base.ps1"
. "$PSScriptRoot\..\lib\Scripts.ps1"

Describe 'New-SyncScriptText' {
    $p = "C:\it's 日本\a b.git"
    $t = New-SyncScriptText 'foo' $p '2026-11-21 10:00'
    It 'no markers left' { $t | Should Not Match '__[A-Z_]+__' }
    It 'parses' { { [scriptblock]::Create($t) } | Should Not Throw }
    It 'escapes quote' { $t | Should Match ([regex]::Escape("`$RepoPath    = 'C:\it''s 日本\a b.git'")) }
    It 'keeps other kinds of single quotes inside the string (Review Focus 5)' {
        $q = "C:\a$([char]0x2019)b$([char]0x2018)c\r.git"
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput((New-SyncScriptText 'foo' $q 'x'), [ref]$null, [ref]$errors)
        @($errors).Count | Should Be 0
        $a = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$RepoPath' }, $true)
        $a.Right.Expression.Value | Should Be $q
    }
    It 'does not replace a marker that comes from a value' { New-SyncScriptText 'foo' 'C:\__GENERATED_AT__\r.git' 'x' | Should Match ([regex]::Escape("'C:\__GENERATED_AT__\r.git'")) }
    It 'sets the env name and the CLI' {
        $t | Should Match ([regex]::Escape("`$EnvName     = 'foo'"))
        $t | Should Match ([regex]::Escape("`$DevcontainerCli = '/home/dcs/.devcontainers/bin/devcontainer'"))
    }
    It 'shows the workspace folder that the container reports after the clone (-Initialize)' {
        $t | Should Match ([regex]::Escape('git clone -q -- "$repo" "$proj"') + '\r?\n\s*' + [regex]::Escape('printf ''%s\n'' "$proj"'))
        $t | Should Not Match ([regex]::Escape('（/workspaces/<リポジトリ名>）に clone してあります'))
    }
}
Describe 'Sync functions' {
    BeforeAll { $f = "$TestDrive\s.ps1"; [IO.File]::WriteAllText($f, (New-SyncScriptText 'foo' 'C:\r.git' 'x'), (New-Object Text.UTF8Encoding($true))); . $f }
    It 'state text is sorted' { (ConvertFrom-StateText ("HEAD refs/heads/main`n" + ('b' * 40) + " refs/tags/v1`n" + ('a' * 40) + " refs/heads/main`n") 'x').Text | Should Be ("HEAD refs/heads/main`n" + ('a' * 40) + " refs/heads/main`n" + ('b' * 40) + " refs/tags/v1`n") }
    It 'rejects bad ref' { { ConvertFrom-StateText ("HEAD refs/heads/main`n" + ('a' * 40) + " refs/heads/a;b`n") 'x' } | Should Throw }
    It 'update-ref lines' {
        $from = ConvertFrom-StateText ("HEAD refs/heads/main`n" + ('a' * 40) + " refs/heads/main`n" + ('c' * 40) + " refs/heads/new`n") 'f'
        $to = ConvertFrom-StateText ("HEAD refs/heads/main`n" + ('b' * 40) + " refs/heads/main`n" + ('d' * 40) + " refs/heads/old`n") 't'
        (Get-UpdateRefLines (Get-Changes $from $to)) -join '|' | Should Be ("update refs/heads/main $('a' * 40) $('b' * 40)|create refs/heads/new $('c' * 40)|delete refs/heads/old $('d' * 40)")
    }
    It 'the base file is in dcs-sync' { $BaseFile | Should Be 'C:\r.git\dcs-sync\foo.txt' }
    # コンテナからの標準エラー出力は、受け取ってから、制御文字を除いて表示する（I6。確認の表示を見えなくされないように）
    It 'reads the messages from the container, and shows them without control characters (I6)' {
        Mock Invoke-Native { [pscustomobject]@{ Code = 1; Text = ''; Error = "bad$([char]27)[30m hidden`nnext`n" } }
        Mock Write-Host {}
        $script:WslExe = 'wsl.exe'
        (Invoke-Env 'list').Code | Should Be 1
        Assert-MockCalled Invoke-Native -Scope It -Times 1 -Exactly -ParameterFilter { $CaptureError }
        Assert-MockCalled Write-Host -Scope It -ParameterFilter { "$Object" -match 'bad\?\[30m hidden' }
        Assert-MockCalled Write-Host -Scope It -Times 0 -Exactly -ParameterFilter { "$Object" -match [char]27 }
    }
    # コンテナの中のコマンドは、絶対パスで呼び、中のコードは最初に PATH を決める（C1）
    It 'calls bash and base64 in the container by absolute paths, and the code sets PATH first (C1)' {
        Mock Invoke-Native { [pscustomobject]@{ Code = 0; Text = ''; Error = '' } }
        $script:WslExe = 'wsl.exe'
        $null = Invoke-Env 'list'
        Assert-MockCalled Invoke-Native -Scope It -Times 1 -Exactly -ParameterFilter {
            $i = [array]::IndexOf($ArgList, '. <(/usr/bin/base64 -d <<< $1)')
            $i -ge 2 -and $ArgList[$i - 2] -eq '/bin/bash' -and $ArgList[$i - 1] -eq '-c'
        }
        $EnvCode | Should Match '(?m)^export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\r?$'
    }
}
# Code-<名前>.cmd を、偽の VS Code（PATH の先の bin\code.cmd と、その 1 つ上の Code.exe）に対して実際に動かす。
# code コマンド（code.cmd → cli.js）から開くと、新しく立ち上がった VS Code の本体がこの窓のコンソールを受け継ぎ、
# VS Code をすべて閉じるまで窓が閉じなかった（2026-11-23 に実機で確かめた）。そのため Code.exe を start で直接起動する
Describe 'New-CodeCmdLines' {
    BeforeAll {
        $vsc = Join-Path $TestDrive 'Microsoft VS Code'
        $null = New-Item -ItemType Directory -Force (Join-Path $vsc 'bin')
        $noExe = Join-Path $TestDrive 'No Exe'
        $null = New-Item -ItemType Directory -Force (Join-Path $noExe 'bin')
        # 偽の code コマンド: 呼ばれたら印を残すだけ
        foreach ($d in $vsc, $noExe) {
            [IO.File]::WriteAllText((Join-Path $d 'bin\code.cmd'), "@echo off`r`necho cli> `"%~dp0..\cli-called.txt`"`r`n", [Text.Encoding]::ASCII)
        }
        # 偽の Code.exe（本物と同じ GUI のプログラム）: 受け取った引数と、VS Code の本体が見る環境変数を書き残す
        Add-Type -OutputType WindowsApplication -OutputAssembly (Join-Path $vsc 'Code.exe') -TypeDefinition @'
using System;
using System.IO;
public static class FakeCode {
    static string Env(string name) { return Environment.GetEnvironmentVariable(name) ?? "(unset)"; }
    public static void Main(string[] args) {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        File.WriteAllText(Path.Combine(dir, "started.tmp"),
            string.Join("|", args) + "\r\n" +
            "ELECTRON_NO_ATTACH_CONSOLE=" + Env("ELECTRON_NO_ATTACH_CONSOLE") + "\r\n" +
            "ELECTRON_RUN_AS_NODE=" + Env("ELECTRON_RUN_AS_NODE") + "\r\n" +
            "VSCODE_DEV=" + Env("VSCODE_DEV") + "\r\n");
        File.Move(Path.Combine(dir, "started.tmp"), Path.Combine(dir, "started.txt"));
    }
}
'@
        $cmd = Join-Path $TestDrive 'Code-foo.cmd'
        Write-AsciiCmd $cmd (New-CodeCmdLines 'foo')
    }
    # PATH を $PathDirs だけにして、ダブルクリックと同じく cmd.exe /c で動かす（入力は空。pause で止まらない）。
    # 開発の PC の環境変数に左右されないよう、VS Code の本体が見る環境変数は、わざと逆の値にしておく
    function Invoke-CodeCmd([string[]]$PathDirs) {
        foreach ($d in $vsc, $noExe) { Remove-Item (Join-Path $d '*.txt') -ErrorAction SilentlyContinue }
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
        $psi.Arguments = "/d /s /c `"`"$cmd`"`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.EnvironmentVariables['PATH'] = (@($PathDirs) + (Join-Path $env:SystemRoot 'System32')) -join ';'
        $psi.EnvironmentVariables.Remove('ELECTRON_NO_ATTACH_CONSOLE')
        $psi.EnvironmentVariables['ELECTRON_RUN_AS_NODE'] = '1'
        $psi.EnvironmentVariables['VSCODE_DEV'] = '1'
        $p = [Diagnostics.Process]::Start($psi)
        $p.StandardInput.Close()
        $out = $p.StandardOutput.ReadToEnd()
        if (-not $p.WaitForExit(20000)) { $p.Kill(); throw 'Code-foo.cmd did not finish in 20 seconds.' }
        return [pscustomobject]@{ Code = $p.ExitCode; Text = $out }
    }
    function Wait-Started([string]$Dir, [int]$Seconds) {
        $f = Join-Path $Dir 'started.txt'
        $deadline = (Get-Date).AddSeconds($Seconds)
        while (-not (Test-Path $f) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
        if (Test-Path $f) { return [IO.File]::ReadAllText($f) }
        return $null
    }

    It 'is ASCII' { ((New-CodeCmdLines 'foo') -join '') -match '[^\x00-\x7F]' | Should Be $false }
    It 'starts Code.exe next to the code command with the same arguments, not the code command itself' {
        $r = Invoke-CodeCmd @((Join-Path $vsc 'bin'))
        $r.Code | Should Be 0
        $started = Wait-Started $vsc 10
        $started | Should Match ([regex]::Escape('--remote|wsl+dcs-base|/home/dcs/envs/foo/config') + '\r\n')
        Test-Path (Join-Path $vsc 'cli-called.txt') | Should Be $false
    }
    It 'gives Code.exe the environment that the code command gives it (does not attach to this console)' {
        $null = Invoke-CodeCmd @((Join-Path $vsc 'bin'))
        $started = Wait-Started $vsc 10
        $started | Should Match 'ELECTRON_NO_ATTACH_CONSOLE=1\r\n'
        $started | Should Match 'ELECTRON_RUN_AS_NODE=\(unset\)\r\n'
        $started | Should Match 'VSCODE_DEV=\(unset\)\r\n'
    }
    It 'stops with a message when the code command is not on PATH' {
        $r = Invoke-CodeCmd @()
        $r.Code | Should Be 1
        $r.Text | Should Match 'was not found'
        Wait-Started $vsc 2 | Should Be $null
    }
    It 'stops with a message when Code.exe is not next to the code command' {
        $r = Invoke-CodeCmd @((Join-Path $noExe 'bin'))
        $r.Code | Should Be 1
        $r.Text | Should Match 'was not found'
        Test-Path (Join-Path $noExe 'cli-called.txt') | Should Be $false
    }
}
Describe 'Write-EnvScripts and Get-PreviousRepoPath' {
    $savedRoot = $script:ToolRoot
    $repo = "C:\x$([char]0x2019)y\it's\r.git"
    It 'writes Code (ASCII, CRLF), and for LocalGit Sync .ps1 (UTF-8 BOM, CRLF) and .cmd, and reads the repo path back' {
        try {
            # テンプレートはツールのフォルダから読み、書く先だけを TestDrive にする
            Copy-Item -Recurse -LiteralPath (Join-Path $savedRoot 'templates') -Destination $TestDrive
            $script:ToolRoot = $TestDrive
            Write-EnvScripts 'foo' 'LocalGit' $repo
            $dir = Join-Path $TestDrive 'envs\foo'
            $code = [IO.File]::ReadAllBytes((Join-Path $dir 'Code-foo.cmd'))
            @($code | Where-Object { $_ -gt 127 }).Count | Should Be 0
            [Text.Encoding]::ASCII.GetString($code) | Should Match "config`r`n"
            $ps1 = [IO.File]::ReadAllBytes((Join-Path $dir 'Sync-foo.ps1'))
            ($ps1[0] -eq 0xEF -and $ps1[1] -eq 0xBB -and $ps1[2] -eq 0xBF) | Should Be $true
            [regex]::Matches([Text.Encoding]::UTF8.GetString($ps1), "(?<!`r)`n").Count | Should Be 0
            [IO.File]::ReadAllText((Join-Path $dir 'Sync-foo.cmd')) | Should Match 'Sync-foo\.ps1'
            Get-PreviousRepoPath 'foo' | Should Be $repo
            Get-PreviousRepoPath 'bar' | Should Be ''
        } finally {
            $script:ToolRoot = $savedRoot
        }
    }
    It 'stops when the template has a marker it does not know' {
        try {
            $null = New-Item -ItemType Directory -Force (Join-Path $TestDrive 'bad\templates')
            [IO.File]::WriteAllText((Join-Path $TestDrive 'bad\templates\Sync-Env.ps1.tmpl'), "`$x = '__ENV_NAME__'`r`n`$y = '__UNKNOWN_MARK__'`r`n", (New-Object Text.UTF8Encoding($true)))
            $script:ToolRoot = Join-Path $TestDrive 'bad'
            { New-SyncScriptText 'foo' 'C:\r.git' 'x' } | Should Throw '__UNKNOWN_MARK__'
        } finally {
            $script:ToolRoot = $savedRoot
        }
    }
    It 'writes only Code for GitHub' {
        try {
            $script:ToolRoot = $TestDrive
            Write-EnvScripts 'gh' 'GitHub' ''
            Test-Path (Join-Path $TestDrive 'envs\gh\Code-gh.cmd') | Should Be $true
            Test-Path (Join-Path $TestDrive 'envs\gh\Sync-gh.ps1') | Should Be $false
        } finally {
            $script:ToolRoot = $savedRoot
        }
    }
}
