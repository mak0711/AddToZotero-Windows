#Requires -Version 5.1
# Diagnostic: connector reachability, Zotero version, attachment-upload support, and menu registration.
# 诊断：连接器可用性、Zotero 版本、附件上传支持、右键菜单注册情况。
$ErrorActionPreference = 'Stop'
$base = 'http://127.0.0.1:23119'
$InstallDir = $PSScriptRoot
Add-Type -AssemblyName System.Net.Http

$lang = if (@([System.Globalization.CultureInfo]::CurrentUICulture.Name,[System.Globalization.CultureInfo]::CurrentCulture.Name,[System.Globalization.CultureInfo]::InstalledUICulture.Name) -match '^zh') { 'zh' } else { 'en' }
try { $cfg = Join-Path $InstallDir 'config.json'; if (Test-Path -LiteralPath $cfg) { $cl = ((Get-Content -LiteralPath $cfg -Raw -Encoding UTF8) | ConvertFrom-Json).lang; if ($cl -eq 'zh' -or $cl -eq 'en') { $lang = $cl } } } catch {}
$zh = ($lang -eq 'zh')

function L($cn, $en) { if ($zh) { $cn } else { $en } }

Write-Host ''
Write-Host (L '=====  加入 Zotero · 诊断  =====' '=====  Add to Zotero · Diagnostics  =====') -ForegroundColor Cyan
Write-Host ''

$running = $false; $ver = '?'; $upload = '?'
try {
    $c = New-Object System.Net.Http.HttpClient; $c.Timeout = [TimeSpan]::FromSeconds(4)
    $req = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::Post, "$base/connector/ping")
    $req.Content = New-Object System.Net.Http.StringContent ('{}', [System.Text.Encoding]::UTF8, 'application/json')
    $resp = $c.SendAsync($req).GetAwaiter().GetResult()
    $running = $resp.IsSuccessStatusCode
    $vals = $null
    if ($resp.Headers.TryGetValues('X-Zotero-Version', [ref]$vals)) { $ver = ($vals -join '') }
    $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    try { $j = $body | ConvertFrom-Json; if ($null -ne $j.prefs.supportsAttachmentUpload) { $upload = [string]$j.prefs.supportsAttachmentUpload } } catch {}
    $c.Dispose()
} catch {}

if ($running) {
    Write-Host (L "[OK]   Zotero 正在运行，连接器可用（端口 23119）" "[OK]   Zotero is running; connector reachable (port 23119)") -ForegroundColor Green
    Write-Host (L "       Zotero 版本: $ver" "       Zotero version: $ver")
    if ($upload -eq 'True') { Write-Host (L "[OK]   supportsAttachmentUpload = True —— 本工具可用" "[OK]   supportsAttachmentUpload = True -- this tool works") -ForegroundColor Green }
    elseif ($upload -eq 'False') { Write-Host (L "[警告] supportsAttachmentUpload = False —— Zotero 版本可能过旧" "[WARN] supportsAttachmentUpload = False -- Zotero may be too old") -ForegroundColor Yellow }
    else { Write-Host "[?]    supportsAttachmentUpload = ?" -ForegroundColor Yellow }
} else {
    Write-Host (L "[警告] 未检测到运行中的 Zotero。请先打开 Zotero 再运行本诊断。" "[WARN] Zotero not detected. Open Zotero, then run this again.") -ForegroundColor Yellow
}
Write-Host ''

$exe = @("$env:ProgramFiles\Zotero\zotero.exe","${env:ProgramFiles(x86)}\Zotero\zotero.exe","$env:LOCALAPPDATA\Zotero\Zotero\zotero.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($exe) { Write-Host (L "[OK]   找到 zotero.exe: $exe" "[OK]   Found zotero.exe: $exe") -ForegroundColor Green }
else { Write-Host (L "[信息] 未找到 zotero.exe（Zotero 已运行时不影响使用）" "[INFO] zotero.exe not found (OK if Zotero is already running)") -ForegroundColor Yellow }
Write-Host ''

$root = [Microsoft.Win32.Registry]::CurrentUser
$sfa = $root.OpenSubKey('Software\Classes\SystemFileAssociations')
$quick = @(); $pick = @()
if ($sfa) {
    foreach ($e in $sfa.GetSubKeyNames()) {
        $sh = $root.OpenSubKey("Software\Classes\SystemFileAssociations\$e\shell")
        if ($sh) { $n = $sh.GetSubKeyNames(); $sh.Close(); if ($n -contains 'ZoteroAddFile') { $quick += $e }; if ($n -contains 'ZoteroAddFilePick') { $pick += $e } }
    }
    $sfa.Close()
}
if ($quick.Count -gt 0) { Write-Host (L "[OK]   快速菜单已注册: $($quick -join '  ')" "[OK]   Quick menu registered for: $($quick -join '  ')") -ForegroundColor Green }
else { Write-Host (L "[信息] 未安装 —— 请先双击 Install.bat" "[INFO] Not installed -- double-click Install.bat first") -ForegroundColor Yellow }
if ($pick.Count -gt 0) { Write-Host (L "[OK]   选择集合菜单已注册: $($pick -join '  ')" "[OK]   Choose-collection menu registered for: $($pick -join '  ')") -ForegroundColor Green }
else { Write-Host (L "[信息] 未安装『选择集合』菜单" "[INFO] Choose-collection menu not installed") -ForegroundColor Yellow }

Write-Host ''
Write-Host (L '诊断结束。' 'Diagnostics complete.')