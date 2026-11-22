# 実機のテストの道具（tests\Integration.Tests.ps1 が dot-source する）。lib\Common.ps1 と lib\Base.ps1 を先に読み込んでおく。
# テストのスクリプト（tests\container\*.test.sh）は土台に置かず、中身を標準入力で渡して動かす。

# テストのスクリプトの中身を、土台の dcs の bash -s に渡して動かす
function Invoke-BaseTest([string]$ScriptPath) {
    $text = (New-Object System.Text.UTF8Encoding($false)).GetString((Get-LfBytes $ScriptPath))
    return (Invoke-InBase -User dcs -ArgList @('bash', '-s') -InputText $text -CaptureError)
}

# テストのスクリプトの中身を、dcs-image から作ったコンテナの bash -s に渡して動かす（コンテナは終わると消える）。
# イメージが無いときに Docker Hub へ取りに行かないよう、--pull never を付ける
function Invoke-ImageTest([string]$ScriptPath, [string[]]$DockerArgs = @()) {
    $text = (New-Object System.Text.UTF8Encoding($false)).GetString((Get-LfBytes $ScriptPath))
    return (Invoke-InBase -User dcs -ArgList (@('docker', 'run', '--rm', '-i', '--pull', 'never') + $DockerArgs + @('dcs-image', 'bash', '-s')) -InputText $text -CaptureError)
}
