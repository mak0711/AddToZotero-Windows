#Requires -Version 5.1
<#
.SYNOPSIS
    Register the right-click menu (HKCU, no admin) and set UI language.
    注册右键菜单（HKCU，无需管理员）并设置界面语言。
.DESCRIPTION
    By default the runtime files are copied to %LOCALAPPDATA%\AddToZotero and the menu points
    there, so the downloaded folder can be safely deleted afterwards. Use -InPlace to register
    the current folder instead (then don't move/delete it).
    默认把运行文件复制到 %LOCALAPPDATA%\AddToZotero 并让菜单指向那里，因此装完可删除下载的
    文件夹。加 -InPlace 则就地注册当前文件夹（之后勿移动/删除）。
.PARAMETER Extensions
    File extensions to add the menu to. Default: common reading/reference formats.
.PARAMETER AllFiles
    Also add the menu for "All files" (*).
.PARAMETER NoPicker
    Only install the quick "Add to Zotero" item (no "choose collection" item).
.PARAMETER InPlace
    Register the current folder instead of copying the runtime to %LOCALAPPDATA%.
.PARAMETER Language
    UI language: auto (default, from OS), zh, or en. Written to config.json for the worker.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Language en -Extensions '.pdf','.docx'
#>
[CmdletBinding()]
param(
    [string[]]$Extensions = @('.pdf', '.epub', '.djvu', '.mobi', '.azw3', '.caj'),
    [switch]$AllFiles,
    [switch]$NoPicker,
    [switch]$InPlace,
    [ValidateSet('auto', 'zh', 'en')][string]$Language = 'auto'
)
$ErrorActionPreference = 'Stop'
$SourceDir = $PSScriptRoot
if (-not (Test-Path (Join-Path $SourceDir 'launch.vbs'))) { throw "launch.vbs not found in $SourceDir" }

# Where the menu will point. Default: a stable per-user location so the download can be deleted.
if ($InPlace) {
    $InstallDir = $SourceDir
} else {
    $InstallDir = Join-Path $env:LOCALAPPDATA 'AddToZotero'
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    if ((Resolve-Path -LiteralPath $SourceDir).Path -ne (Resolve-Path -LiteralPath $InstallDir).Path) {
        foreach ($f in @('Add-ToZotero.ps1', 'launch.vbs', 'Uninstall.ps1', 'Uninstall.bat', 'Test-Zotero.ps1', 'Diagnose.bat')) {
            $s = Join-Path $SourceDir $f
            if (Test-Path -LiteralPath $s) { Copy-Item -LiteralPath $s -Destination (Join-Path $InstallDir $f) -Force }
        }
    }
}
$vbs = Join-Path $InstallDir 'launch.vbs'

$lang = $Language
if ($lang -eq 'auto') { $lang = if (@([System.Globalization.CultureInfo]::CurrentUICulture.Name,[System.Globalization.CultureInfo]::CurrentCulture.Name,[System.Globalization.CultureInfo]::InstalledUICulture.Name) -match '^zh') { 'zh' } else { 'en' } }
# persist language for the worker (next to the worker script)
(@{ lang = $lang } | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $InstallDir 'config.json') -Encoding UTF8

if ($lang -eq 'zh') { $lblQuick = '加入 Zotero'; $lblPick = '加入 Zotero（选择集合）…' }
else { $lblQuick = 'Add to Zotero'; $lblPick = 'Add to Zotero (choose collection)…' }

$zotero = @("$env:ProgramFiles\Zotero\zotero.exe","${env:ProgramFiles(x86)}\Zotero\zotero.exe","$env:LOCALAPPDATA\Zotero\Zotero\zotero.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$icon = if ($zotero) { "$zotero,0" } else { $null }

$verbs = @( @{ key = 'ZoteroAddFile'; label = $lblQuick; command = "wscript.exe `"$vbs`" `"%1`"" } )
if (-not $NoPicker) { $verbs += @{ key = 'ZoteroAddFilePick'; label = $lblPick; command = "wscript.exe `"$vbs`" /pick `"%1`"" } }

$bases = @()
foreach ($e in $Extensions) { $ext = if ($e.StartsWith('.')) { $e } else { ".$e" }; $bases += "Software\Classes\SystemFileAssociations\$ext\shell" }
if ($AllFiles) { $bases += "Software\Classes\*\shell" }

$root = [Microsoft.Win32.Registry]::CurrentUser
foreach ($b in $bases) {
    foreach ($v in $verbs) {
        $k = $root.CreateSubKey("$b\$($v.key)")
        $k.SetValue('', $v.label)
        if ($icon) { $k.SetValue('Icon', $icon) }
        $c = $k.CreateSubKey('command'); $c.SetValue('', $v.command); $c.Close(); $k.Close()
    }
    Write-Host "Registered: HKCU\$b"
}
Write-Host ''
if ($lang -eq 'zh') {
    Write-Host "完成（语言：中文）。右键文件 →（Windows 11 需点『显示更多选项』）→ $lblQuick / $lblPick"
    if (-not $InPlace) {
        Write-Host "运行文件已安装到：$InstallDir"
        Write-Host "现在可以安全删除下载的文件夹了。卸载：运行 $InstallDir\Uninstall.bat"
    }
} else {
    Write-Host "Done (language: English). Right-click a file -> (Windows 11: 'Show more options') -> $lblQuick / $lblPick"
    if (-not $InPlace) {
        Write-Host "Runtime installed to: $InstallDir"
        Write-Host "You can now delete the downloaded folder. To uninstall: run $InstallDir\Uninstall.bat"
    }
}
if (-not $zotero) { Write-Host 'Note: zotero.exe not found; menu has no icon (does not affect function).' }
