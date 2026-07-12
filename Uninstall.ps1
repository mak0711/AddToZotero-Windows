#Requires -Version 5.1
<# Remove the right-click menu entries registered by this tool (ZoteroAddFile / ZoteroAddFilePick),
   then clean up the runtime copy under %LOCALAPPDATA%\AddToZotero.
   移除本工具注册的右键菜单项，并清理 %LOCALAPPDATA%\AddToZotero 下的运行文件。 #>
$ErrorActionPreference = 'Stop'
$InstallDir = $PSScriptRoot
$lang = if (@([System.Globalization.CultureInfo]::CurrentUICulture.Name,[System.Globalization.CultureInfo]::CurrentCulture.Name,[System.Globalization.CultureInfo]::InstalledUICulture.Name) -match '^zh') { 'zh' } else { 'en' }
try { $cfg = Join-Path $InstallDir 'config.json'; if (Test-Path -LiteralPath $cfg) { $cl = ((Get-Content -LiteralPath $cfg -Raw -Encoding UTF8) | ConvertFrom-Json).lang; if ($cl -eq 'zh' -or $cl -eq 'en') { $lang = $cl } } } catch {}

$root = [Microsoft.Win32.Registry]::CurrentUser
$script:removed = 0
function Remove-VerbsUnder([string]$shellPath) {
    $shell = $root.OpenSubKey($shellPath)
    if (-not $shell) { return }
    $names = $shell.GetSubKeyNames(); $shell.Close()
    foreach ($v in $names) {
        if ($v -like 'ZoteroAddFile*') {
            $root.DeleteSubKeyTree("$shellPath\$v", $false)
            Write-Host "Removed: HKCU\$shellPath\$v"
            $script:removed++
        }
    }
}
$sfaPath = 'Software\Classes\SystemFileAssociations'
$sfa = $root.OpenSubKey($sfaPath)
if ($sfa) { $exts = $sfa.GetSubKeyNames(); $sfa.Close(); foreach ($ext in $exts) { Remove-VerbsUnder "$sfaPath\$ext\shell" } }
Remove-VerbsUnder 'Software\Classes\*\shell'

# Clean up the managed runtime copy (%LOCALAPPDATA%\AddToZotero).
$managed = Join-Path $env:LOCALAPPDATA 'AddToZotero'
$selfCleanup = $false
try {
    if (Test-Path -LiteralPath $managed) {
        if ((Resolve-Path -LiteralPath $InstallDir).Path -eq (Resolve-Path -LiteralPath $managed).Path) {
            # We're running from inside it: delete after this process exits (files are locked now).
            Start-Process -FilePath 'cmd.exe' -WindowStyle Hidden -ArgumentList "/c ping 127.0.0.1 -n 4 >nul & rmdir /s /q `"$managed`"" | Out-Null
            $selfCleanup = $true
        } else {
            Remove-Item -LiteralPath $managed -Recurse -Force
        }
    }
} catch {}

# In-place install: drop the local config.json we wrote next to the scripts.
try {
    $localCfg = Join-Path $InstallDir 'config.json'
    if (-not $selfCleanup -and (Test-Path -LiteralPath $localCfg)) { Remove-Item -LiteralPath $localCfg -Force }
} catch {}

Write-Host ''
if ($lang -eq 'zh') {
    Write-Host "完成，共移除 $script:removed 项右键菜单。"
    if ($selfCleanup) { Write-Host "安装文件夹（$managed）将在几秒后自动清理。" }
} else {
    Write-Host "Done. Removed $script:removed menu item(s)."
    if ($selfCleanup) { Write-Host "The installed folder ($managed) will be cleaned up in a few seconds." }
}
