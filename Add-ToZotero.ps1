#Requires -Version 5.1
<#
.SYNOPSIS
    Add local files (PDF/EPUB/…) to a running Zotero; optionally choose the target collection.
    将本地文件加入正在运行的 Zotero；可选择目标集合。
.DESCRIPTION
    Uses Zotero's connector server (127.0.0.1:23119): saveStandaloneAttachment to upload the file
    bytes; with -PickCollection, getSelectedCollection to list collections and updateSession to move.
    UI language is read from config.json (written by Install.ps1) or auto-detected from OS culture.
.NOTES
    Verified on Zotero 9.0.5 / 9.0.6: saveStandaloneAttachment=201, updateSession=200. Log: add-to-zotero.log
#>
[CmdletBinding()]
param(
    [switch]$PickCollection,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Path
)

$ErrorActionPreference = 'Stop'
$Base = 'http://127.0.0.1:23119'
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $env:TEMP }
$LogFile = Join-Path $ScriptDir 'add-to-zotero.log'
$CacheFile = Join-Path $ScriptDir '.session-target.json'

Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---- language ----
$Lang = if (@([System.Globalization.CultureInfo]::CurrentUICulture.Name,[System.Globalization.CultureInfo]::CurrentCulture.Name,[System.Globalization.CultureInfo]::InstalledUICulture.Name) -match '^zh') { 'zh' } else { 'en' }
try {
    $cfg = Join-Path $ScriptDir 'config.json'
    if (Test-Path -LiteralPath $cfg) {
        $cl = ((Get-Content -LiteralPath $cfg -Raw -Encoding UTF8) | ConvertFrom-Json).lang
        if ($cl -eq 'zh' -or $cl -eq 'en') { $Lang = $cl }
    }
} catch {}

if ($Lang -eq 'zh') {
    $S = @{
        errTitle = '加入 Zotero — 失败'; warnTitle = '加入 Zotero — 部分完成'; okTitle = '已加入 Zotero'
        noFile = '未指定文件。请从资源管理器右键菜单使用本工具。'
        noZotero = "无法连接到 Zotero（端口 23119）。`n`n请先打开 Zotero 桌面程序，然后重试。"
        starting = 'Zotero 未运行，正在为你启动…（最多等 60 秒）'; startTitle = '加入 Zotero'
        noCollections = '无法获取 Zotero 集合列表。请确认 Zotero 正在运行。'
        pickTitle = '加入 Zotero — 选择集合'; pickHint = '输入可筛选 · 双击或回车确认 · Esc 取消'; ok = '确定'; cancel = '取消'
        toastPick = '已加入到「{0}」（{1} 个文件），正在识别元数据…'; toastQuick = '成功加入 {0} 个文件，Zotero 正在识别元数据…'
        errBox = '完成：成功 {0}，失败 {1}'; warnBox = '已加入 {0} 个文件，但其中 {1} 个未能移动到「{2}」（可能集合已删除）。它们仍在当前文库中。'
        fatal = '发生意外错误：'; moveFailItem = '{0}：已加入但未能移动到「{1}」'; errItem = '{0}：{1}'
        rNotFound = '文件不存在'; rReadonly = '目标文库不可写'; rHttp = 'HTTP {0}'
    }
} else {
    $S = @{
        errTitle = 'Add to Zotero — Failed'; warnTitle = 'Add to Zotero — Partial'; okTitle = 'Added to Zotero'
        noFile = 'No file specified. Use this tool from the Explorer right-click menu.'
        noZotero = "Cannot connect to Zotero (port 23119).`n`nPlease open the Zotero desktop app and try again."
        starting = "Zotero isn't running — starting it for you… (up to 60s)"; startTitle = 'Add to Zotero'
        noCollections = 'Could not fetch the Zotero collection list. Make sure Zotero is running.'
        pickTitle = 'Add to Zotero — Choose Collection'; pickHint = 'Type to filter  ·  double-click / Enter to confirm  ·  Esc to cancel'; ok = 'OK'; cancel = 'Cancel'
        toastPick = 'Added to "{0}" ({1} file(s)); retrieving metadata…'; toastQuick = 'Added {0} file(s); Zotero is retrieving metadata…'
        errBox = 'Done: {0} succeeded, {1} failed'; warnBox = 'Added {0} file(s), but {1} could not be moved to "{2}" (collection may be deleted). They remain in the current library.'
        fatal = 'Unexpected error: '; moveFailItem = '{0}: added but could not move to "{1}"'; errItem = '{0}: {1}'
        rNotFound = 'File not found'; rReadonly = 'Target library is read-only'; rHttp = 'HTTP {0}'
    }
}

function Write-Log([string]$m) {
    $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $m
    for ($i = 0; $i -lt 5; $i++) {
        try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8; return } catch { Start-Sleep -Milliseconds 40 }
    }
}
function Get-Epoch { [long][System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Show-ErrorBox([string]$msg) { try { [System.Windows.Forms.MessageBox]::Show($msg, $S.errTitle, 'OK', 'Error') | Out-Null } catch {} }
function Show-WarnBox([string]$msg) { try { [System.Windows.Forms.MessageBox]::Show($msg, $S.warnTitle, 'OK', 'Warning') | Out-Null } catch {} }
function Show-Toast([string]$msg, [string]$title = $null) {
    if (-not $title) { $title = $S.okTitle }
    $ni = $null
    try {
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ni.Icon = [System.Drawing.SystemIcons]::Information; $ni.Visible = $true
        $ni.ShowBalloonTip(2500, $title, $msg, [System.Windows.Forms.ToolTipIcon]::Info)
        Start-Sleep -Milliseconds 2600
    } catch {} finally { if ($ni) { try { $ni.Visible = $false; $ni.Dispose() } catch {} } }
}

function Test-Zotero {
    $c = New-Object System.Net.Http.HttpClient
    try { $c.Timeout = [TimeSpan]::FromSeconds(3); return $c.GetAsync("$Base/connector/ping").GetAwaiter().GetResult().IsSuccessStatusCode }
    catch { return $false } finally { $c.Dispose() }
}
function Ensure-Zotero {
    if (Test-Zotero) { return $true }
    Write-Log 'Zotero not running, trying to start it…'
    $exe = @("$env:ProgramFiles\Zotero\zotero.exe","${env:ProgramFiles(x86)}\Zotero\zotero.exe","$env:LOCALAPPDATA\Zotero\Zotero\zotero.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $exe) { return $false }
    # Multi-select spawns one process per file; let only one launch Zotero and notify.
    $m = New-Object System.Threading.Mutex($false, 'Local\ZoteroAddFile_Launch')
    $owned = $false
    try { $owned = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
    try {
        if ($owned -and -not (Test-Zotero)) {
            try { Start-Process -FilePath $exe | Out-Null; Write-Log 'launched Zotero' } catch { Write-Log "launch failed: $($_.Exception.Message)" }
            Show-Toast $S.starting $S.startTitle   # immediate feedback; overlaps Zotero's boot
        }
    } finally { if ($owned) { try { $m.ReleaseMutex() } catch {} }; $m.Dispose() }
    for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Seconds 1; if (Test-Zotero) { return $true } }
    return (Test-Zotero)
}

function Get-Mime([string]$ext) {
    switch ($ext.ToLowerInvariant()) {
        '.pdf'  { 'application/pdf'; break }
        '.epub' { 'application/epub+zip'; break }
        '.djvu' { 'image/vnd.djvu'; break }
        '.mobi' { 'application/x-mobipocket-ebook'; break }
        '.azw3' { 'application/vnd.amazon.ebook'; break }
        '.txt'  { 'text/plain'; break }
        '.rtf'  { 'application/rtf'; break }
        '.doc'  { 'application/msword'; break }
        '.docx' { 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'; break }
        '.htm'  { 'text/html'; break }
        '.html' { 'text/html'; break }
        default { 'application/octet-stream' }
    }
}
function ConvertTo-AsciiJson($obj) {
    $json = $obj | ConvertTo-Json -Compress
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $json.ToCharArray()) {
        $code = [int][char]$ch
        if ($code -gt 127) { [void]$sb.AppendFormat('\u{0:x4}', $code) } else { [void]$sb.Append($ch) }
    }
    $sb.ToString()
}

function Get-Targets {
    $c = New-Object System.Net.Http.HttpClient
    try {
        $c.Timeout = [TimeSpan]::FromSeconds(8)
        $req = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::Post, "$Base/connector/getSelectedCollection")
        $req.Content = New-Object System.Net.Http.StringContent ('{}', [System.Text.Encoding]::UTF8, 'application/json')
        $resp = $c.SendAsync($req).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) { return $null }
        $j = ($resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()) | ConvertFrom-Json
        $cur = if ($j.id) { "C$($j.id)" } else { "L$($j.libraryID)" }
        return @{ targets = $j.targets; current = $cur }
    } catch { return $null } finally { $c.Dispose() }
}
function Move-ToTarget([string]$sessionID, [string]$target) {
    $c = New-Object System.Net.Http.HttpClient
    try {
        $c.Timeout = [TimeSpan]::FromSeconds(15)
        $req = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::Post, "$Base/connector/updateSession")
        $payload = @{ sessionID = $sessionID; target = $target } | ConvertTo-Json -Compress
        $req.Content = New-Object System.Net.Http.StringContent ($payload, [System.Text.Encoding]::UTF8, 'application/json')
        return ([int]$c.SendAsync($req).GetAwaiter().GetResult().StatusCode -eq 200)
    } catch { return $false } finally { $c.Dispose() }
}

function Read-TargetCache([int]$maxAgeSec) {
    try {
        if (-not (Test-Path -LiteralPath $CacheFile)) { return $null }
        $o = (Get-Content -LiteralPath $CacheFile -Raw -Encoding UTF8) | ConvertFrom-Json
        if (((Get-Epoch) - [long]$o.epoch) -gt $maxAgeSec) { return $null }
        if ($o.decision -eq 'ok') { return @{ id = [string]$o.id; name = [string]$o.name } }
        return $null
    } catch { return $null }
}
function Write-TargetCache($picked) {
    try {
        if ($picked) { $o = @{ decision = 'ok'; id = $picked.id; name = $picked.name; epoch = (Get-Epoch) } }
        else { $o = @{ decision = 'cancel'; epoch = (Get-Epoch) } }
        ($o | ConvertTo-Json -Compress) | Set-Content -LiteralPath $CacheFile -Encoding UTF8
    } catch {}
}

function Show-CollectionPicker($targets, $currentId) {
    try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch {}
    $all = @()
    foreach ($t in $targets) { $all += [pscustomobject]@{ Id = [string]$t.id; Name = [string]$t.name; Display = (('    ' * [int]$t.level) + $t.name) } }
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $S.pickTitle
    $form.ClientSize = New-Object System.Drawing.Size(404, 486)
    $form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false; $form.MinimizeBox = $false; $form.TopMost = $true; $form.ShowInTaskbar = $false
    try { if ($Lang -eq 'zh') { $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9) } else { $form.Font = New-Object System.Drawing.Font('Segoe UI', 9) } } catch {}

    $filter = New-Object System.Windows.Forms.TextBox; $filter.SetBounds(12, 12, 380, 25)
    $lbl = New-Object System.Windows.Forms.Label; $lbl.SetBounds(12, 42, 380, 18); $lbl.Text = $S.pickHint; $lbl.ForeColor = [System.Drawing.Color]::Gray
    $list = New-Object System.Windows.Forms.ListBox; $list.SetBounds(12, 64, 380, 356); $list.DisplayMember = 'Display'
    $ok = New-Object System.Windows.Forms.Button; $ok.Text = $S.ok; $ok.SetBounds(212, 430, 85, 32); $ok.DialogResult = 'OK'
    $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = $S.cancel; $cancel.SetBounds(305, 430, 85, 32); $cancel.DialogResult = 'Cancel'
    $form.AcceptButton = $ok; $form.CancelButton = $cancel
    $form.Controls.AddRange(@($filter, $lbl, $list, $ok, $cancel))

    $fill = {
        $text = $filter.Text.Trim().ToLower()
        $list.BeginUpdate(); $list.Items.Clear()
        foreach ($a in $all) { if ($text -eq '' -or $a.Name.ToLower().Contains($text)) { [void]$list.Items.Add($a) } }
        $list.EndUpdate()
        if ($list.Items.Count -gt 0 -and $list.SelectedIndex -lt 0) { $list.SelectedIndex = 0 }
    }
    & $fill
    for ($i = 0; $i -lt $list.Items.Count; $i++) { if ($list.Items[$i].Id -eq $currentId) { $list.SelectedIndex = $i; break } }
    $filter.Add_TextChanged($fill)
    $list.Add_DoubleClick({ if ($list.SelectedItem) { $form.DialogResult = 'OK'; $form.Close() } })
    $form.Add_Shown({ try { $form.Activate(); $filter.Focus() } catch {} })

    $res = $form.ShowDialog()
    $sel = $list.SelectedItem
    $form.Dispose()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK -and $sel) { return @{ id = $sel.Id; name = $sel.Name } }
    return $null
}

function Get-ChosenTarget {
    $mutex = New-Object System.Threading.Mutex($false, 'Local\ZoteroAddFile_Picker')
    $owned = $false
    try { $owned = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
    try {
        if (-not $owned) {
            try { $owned = $mutex.WaitOne(180000) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
            if ($owned) { return (Read-TargetCache 300) } else { return $null }
        }
        $fresh = Read-TargetCache 6
        if ($fresh) { return $fresh }
        $info = Get-Targets
        if (-not $info) { Show-ErrorBox $S.noCollections; Write-TargetCache $null; return $null }
        $picked = Show-CollectionPicker $info.targets $info.current
        Write-TargetCache $picked
        return $picked
    }
    finally {
        if ($owned) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
    }
}

function Add-OneFile($p, $chosen) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return 'notfound' }
    $item = Get-Item -LiteralPath $p
    $guid = [guid]::NewGuid().ToString()
    $meta = ConvertTo-AsciiJson ([ordered]@{ sessionID = $guid; url = ([System.Uri]$item.FullName).AbsoluteUri; title = $item.BaseName })
    $bytes = [System.IO.File]::ReadAllBytes($item.FullName)
    $client = New-Object System.Net.Http.HttpClient
    try {
        $client.Timeout = [TimeSpan]::FromSeconds(180)
        $req = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::Post, "$Base/connector/saveStandaloneAttachment?sessionID=$guid")
        $req.Headers.ExpectContinue = $false
        [void]$req.Headers.TryAddWithoutValidation('X-Metadata', $meta)
        $bc = New-Object System.Net.Http.ByteArrayContent (,$bytes)
        $bc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse((Get-Mime $item.Extension))
        $req.Content = $bc
        $status = [int]$client.SendAsync($req).GetAwaiter().GetResult().StatusCode
    } finally { $client.Dispose() }
    if ($status -eq 201) {
        if ($chosen) { if (Move-ToTarget $guid $chosen.id) { return 'ok' } else { return 'movefail' } }
        return 'ok'
    }
    elseif ($status -eq 200) { return 'readonly' }
    else { return "http:$status" }
}

# ------------------------------ main ------------------------------
try {
    $fileCount = if ($Path) { @($Path).Count } else { 0 }
    Write-Log ("START pid=$PID lang=$Lang files=$fileCount pick=" + [bool]$PickCollection)

    if ($fileCount -eq 0) { Write-Log 'ABORT no file'; Show-ErrorBox $S.noFile; exit 1 }
    if (-not (Ensure-Zotero)) { Write-Log 'ABORT cannot reach Zotero'; Show-ErrorBox $S.noZotero; exit 1 }

    $chosen = $null
    if ($PickCollection) {
        $chosen = Get-ChosenTarget
        if (-not $chosen) { Write-Log 'CANCEL'; exit 0 }
        Write-Log "TARGET $($chosen.id) $($chosen.name)"
    }

    $ok = 0; $moveFail = 0
    $errs = New-Object System.Collections.Generic.List[string]
    foreach ($p in $Path) {
        $name = try { Split-Path -Leaf $p } catch { "$p" }
        try {
            $r = Add-OneFile $p $chosen
            if ($r -eq 'ok') { $ok++; Write-Log "OK $name" }
            elseif ($r -eq 'movefail') { $ok++; $moveFail++; Write-Log "MOVEFAIL $name"; $errs.Add(($S.moveFailItem -f $name, $chosen.name)) }
            elseif ($r -eq 'notfound') { Write-Log "FAIL notfound $name"; $errs.Add(($S.errItem -f $name, $S.rNotFound)) }
            elseif ($r -eq 'readonly') { Write-Log "FAIL readonly $name"; $errs.Add(($S.errItem -f $name, $S.rReadonly)) }
            else { $code = $r -replace '^http:',''; Write-Log "FAIL http:$code $name"; $errs.Add(($S.errItem -f $name, ($S.rHttp -f $code))) }
        } catch {
            $reason = $_.Exception.GetBaseException().Message
            Write-Log "ERROR $name : $reason"; $errs.Add(($S.errItem -f $name, $reason))
        }
    }
    $failCount = $fileCount - $ok
    Write-Log "DONE ok=$ok fail=$failCount moveFail=$moveFail"

    if ($failCount -gt 0) { Show-ErrorBox (($S.errBox -f $ok, $failCount) + "`n`n" + ($errs -join "`n")); exit 1 }
    elseif ($moveFail -gt 0) { Show-WarnBox ($S.warnBox -f $ok, $moveFail, $chosen.name) }
    elseif ($chosen) { Show-Toast ($S.toastPick -f $chosen.name, $ok) }
    else { Show-Toast ($S.toastQuick -f $ok) }
}
catch {
    $reason = $_.Exception.GetBaseException().Message
    try { Write-Log "FATAL $reason" } catch {}
    Show-ErrorBox ($S.fatal + $reason)
    exit 1
}