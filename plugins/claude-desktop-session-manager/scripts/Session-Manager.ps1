<#
.SYNOPSIS
    Claude Session Manager - a small native GUI to view Claude Desktop "Claude Code"
    sessions across every signed-in account and copy / move / remove them.

.DESCRIPTION
    Lists every session under
      <store>\claude-code-sessions\<accountUuid>\<orgUuid>\local_*.json
    with checkboxes, an account filter, and a copy/move target picker.

    - Copy selected  -> copies the chosen session list entries into the target account
                        (newest-wins: an existing entry is only refreshed when the source
                        is newer; never regresses one advanced in the target).
    - Move selected  -> same, then removes them from their source account.
    - Remove selected-> deletes the selected list entries. The actual conversation
                        transcript in %USERPROFILE%\.claude\projects is SHARED across
                        accounts and is NOT deleted, so this only removes the list entry.

    A timestamped backup of the whole store is taken automatically before the first
    change in a session. After changes, fully restart Claude Desktop to see them.

.PARAMETER SelfTest
    Build the data model and the window but do not show it; print a health line. Used
    for automated verification.

.NOTES
    Launch with STA:  powershell.exe -STA -ExecutionPolicy Bypass -File Session-Manager.ps1
#>
[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'

# ============================ Store resolution ============================
# Hardcoded primary path (the MSIX package-family hash is deterministic & stable),
# with a content-based fallback for a rename / non-packaged / in-container case.
$KnownPackageFamily = 'Claude_pzs8sxrjxfjjc'
function Resolve-ClaudeDir {
    $known = Join-Path $env:LOCALAPPDATA "Packages\$KnownPackageFamily\LocalCache\Roaming\Claude"
    if (Test-Path (Join-Path $known 'claude-code-sessions')) { return $known }
    $cands = New-Object System.Collections.Generic.List[string]
    Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { $cands.Add((Join-Path $_.FullName 'LocalCache\Roaming\Claude')) }
    $cands.Add((Join-Path $env:APPDATA 'Claude'))
    return $cands | Select-Object -Unique |
        Where-Object { Test-Path (Join-Path $_ 'claude-code-sessions') } |
        Sort-Object { (Get-Item (Join-Path $_ 'claude-code-sessions')).LastWriteTime } -Descending |
        Select-Object -First 1
}

$script:ClaudeDir = Resolve-ClaudeDir
if (-not $script:ClaudeDir) { throw "Could not locate the Claude session store." }
$script:Root       = Join-Path $script:ClaudeDir 'claude-code-sessions'
$script:ConfigPath = Join-Path $script:ClaudeDir 'config.json'
$script:CurrentAccount = (Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json).lastKnownAccountUuid
$script:BackedUp = $false

# ============================ Data layer ============================
function Get-Accounts {
    Get-ChildItem -LiteralPath $script:Root -Directory | ForEach-Object {
        $dir = $_
        $org = Get-ChildItem -LiteralPath $dir.FullName -Directory -ErrorAction SilentlyContinue |
               Sort-Object { (Get-ChildItem -LiteralPath $_.FullName -Filter 'local_*.json' -EA SilentlyContinue |
                              Measure-Object LastWriteTime -Maximum).Maximum } -Descending |
               Select-Object -First 1
        $cur = ($dir.Name -eq $script:CurrentAccount)
        [pscustomobject]@{
            Uuid      = $dir.Name
            Short     = $dir.Name.Substring(0,8)
            IsCurrent = $cur
            OrgDir    = if ($org) { $org.FullName } else { $null }
            Count     = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -Filter 'local_*.json' -EA SilentlyContinue).Count
            Label     = "$($dir.Name.Substring(0,8))$(if($cur){' (current)'})"
        }
    }
}

function Get-Sessions {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($acct in (Get-ChildItem -LiteralPath $script:Root -Directory)) {
        $isCur = ($acct.Name -eq $script:CurrentAccount)
        foreach ($f in (Get-ChildItem -LiteralPath $acct.FullName -Recurse -Filter 'local_*.json' -EA SilentlyContinue)) {
            try { $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }
            $la = $null
            if ($j.lastActivityAt) { try { $la = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$j.lastActivityAt).LocalDateTime } catch {} }
            $out.Add([pscustomobject]@{
                Account      = $acct.Name
                AccountShort = $acct.Name.Substring(0,8) + $(if($isCur){' *'}else{''})
                IsCurrent    = $isCur
                File         = $f.FullName
                Title        = if ($j.title) { [string]$j.title } else { '(untitled)' }
                Cwd          = [string]$j.cwd
                LastActivity = $la
                Turns        = [int]($j.completedTurns)
                Model        = [string]$j.model
                Archived     = [bool]$j.isArchived
            })
        }
    }
    return ,$out
}

function Ensure-Backup {
    if ($script:BackedUp) { return $null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bk = Join-Path $script:ClaudeDir "claude-code-sessions.backup-$stamp"
    Copy-Item -LiteralPath $script:Root -Destination $bk -Recurse
    $script:BackedUp = $true
    return $bk
}

function Copy-SessionsTo {
    param([object[]]$Sessions, [object]$TargetAcct, [switch]$Move)
    if (-not $TargetAcct.OrgDir) { throw "Target account $($TargetAcct.Short) has no workspace yet. Open Claude Desktop on it once." }
    $dest = $TargetAcct.OrgDir
    $new=0; $refresh=0; $kept=0; $moved=0
    foreach ($s in $Sessions) {
        if ($s.Account -ne $TargetAcct.Uuid) {
            $tp = Join-Path $dest (Split-Path $s.File -Leaf)
            $do = $true; $isRefresh = $false
            if (Test-Path -LiteralPath $tp) {
                $isRefresh = $true
                $sj = try { Get-Content -LiteralPath $s.File -Raw | ConvertFrom-Json } catch { $null }
                $tj = try { Get-Content -LiteralPath $tp     -Raw | ConvertFrom-Json } catch { $null }
                $sa = [double]($sj.lastActivityAt); $ta = [double]($tj.lastActivityAt)
                $do = if ($sa -and $ta) { $sa -gt $ta }
                      else { (Get-Item -LiteralPath $s.File).LastWriteTime -gt (Get-Item -LiteralPath $tp).LastWriteTime }
            }
            if ($do) { Copy-Item -LiteralPath $s.File -Destination $tp -Force; if ($isRefresh){$refresh++}else{$new++} }
            else     { $kept++ }
        }
        if ($Move) { Remove-Item -LiteralPath $s.File -Force; $moved++ }
    }
    return [pscustomobject]@{ New=$new; Refreshed=$refresh; Kept=$kept; Moved=$moved }
}

function Remove-Sessions {
    param([object[]]$Sessions)
    $n = 0
    foreach ($s in $Sessions) { Remove-Item -LiteralPath $s.File -Force; $n++ }
    return $n
}

# ============================ UI ============================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Claude Session Manager"
$form.Size = New-Object System.Drawing.Size(1060, 660)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(840, 480)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# ---- Top bar ----
$top = New-Object System.Windows.Forms.Panel
$top.Dock = 'Top'; $top.Height = 74; $top.Padding = '10,10,10,6'

$lblCur = New-Object System.Windows.Forms.Label
$lblCur.Text = "Logged-in account: $($script:CurrentAccount.Substring(0,8))    Store: $($script:Root)"
$lblCur.AutoSize = $true; $lblCur.Location = '12,6'; $lblCur.ForeColor = 'DimGray'
$top.Controls.Add($lblCur)

$lblShow = New-Object System.Windows.Forms.Label
$lblShow.Text = "Show:"; $lblShow.AutoSize=$true; $lblShow.Location = '12,36'
$top.Controls.Add($lblShow)

$cbFilter = New-Object System.Windows.Forms.ComboBox
$cbFilter.DropDownStyle = 'DropDownList'; $cbFilter.Location = '56,33'; $cbFilter.Width = 210
$top.Controls.Add($cbFilter)

$lblTo = New-Object System.Windows.Forms.Label
$lblTo.Text = "Copy / Move to:"; $lblTo.AutoSize=$true; $lblTo.Location = '300,36'
$top.Controls.Add($lblTo)

$cbTarget = New-Object System.Windows.Forms.ComboBox
$cbTarget.DropDownStyle = 'DropDownList'; $cbTarget.Location = '400,33'; $cbTarget.Width = 200
$top.Controls.Add($cbTarget)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"; $btnRefresh.Location = '620,32'; $btnRefresh.Width = 90
$top.Controls.Add($btnRefresh)

$btnAll = New-Object System.Windows.Forms.Button
$btnAll.Text = "Select all"; $btnAll.Location = '720,32'; $btnAll.Width = 80
$top.Controls.Add($btnAll)

$btnNone = New-Object System.Windows.Forms.Button
$btnNone.Text = "Clear"; $btnNone.Location = '804,32'; $btnNone.Width = 70
$top.Controls.Add($btnNone)

# ---- Bottom bar ----
$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock = 'Bottom'; $bottom.Height = 72; $bottom.Padding = '10,8,10,8'

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = "Copy selected  ->  target"; $btnCopy.Location = '12,10'; $btnCopy.Width = 180; $btnCopy.Height = 30
$bottom.Controls.Add($btnCopy)

$btnMove = New-Object System.Windows.Forms.Button
$btnMove.Text = "Move selected  ->  target"; $btnMove.Location = '200,10'; $btnMove.Width = 180; $btnMove.Height = 30
$bottom.Controls.Add($btnMove)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = "Remove selected (from list)"; $btnDelete.Location = '388,10'; $btnDelete.Width = 190; $btnDelete.Height = 30
$btnDelete.ForeColor = 'Firebrick'
$bottom.Controls.Add($btnDelete)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Dock = 'Bottom'; $lblStatus.Height = 20; $lblStatus.Text = "Ready."
$lblStatus.TextAlign = 'MiddleLeft'; $lblStatus.ForeColor = 'DarkGreen'; $lblStatus.Padding='12,0,0,0'
$bottom.Controls.Add($lblStatus)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Location = '590,14'; $lblHint.AutoSize=$true; $lblHint.ForeColor='DimGray'
$lblHint.Text = "After changes, fully restart Claude Desktop to see them."
$bottom.Controls.Add($lblHint)

# ---- Grid ----
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.AutoSizeColumnsMode = 'Fill'
$grid.MultiSelect = $true
$grid.BackgroundColor = [System.Drawing.Color]::White
$grid.EditMode = 'EditOnEnter'

function Add-Col([string]$name,[string]$header,[int]$weight,[bool]$check=$false) {
    if ($check) { $c = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn }
    else        { $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn; $c.ReadOnly = $true }
    $c.Name = $name; $c.HeaderText = $header; $c.FillWeight = $weight
    if (-not $check) { $c.SortMode = 'Automatic' } else { $c.SortMode = 'NotSortable' }
    [void]$grid.Columns.Add($c)
}
Add-Col 'Sel'      ''            5  $true
Add-Col 'Account'  'Account'     10
Add-Col 'Title'    'Title'       30
Add-Col 'Project'  'Project'     28
Add-Col 'LastActive' 'Last active' 16
Add-Col 'Turns'    'Turns'       7
Add-Col 'Model'    'Model'       16
Add-Col 'Archived' 'Arch'        6

# commit checkbox clicks immediately
$grid.add_CurrentCellDirtyStateChanged({
    if ($grid.IsCurrentCellDirty) { $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) }
})

# ---- population ----
$script:AllSessions = @()
function Populate {
    $script:AllSessions = Get-Sessions
    $accounts = Get-Accounts

    # target combo (all accounts; default current)
    $cbTarget.Items.Clear()
    foreach ($a in $accounts) { [void]$cbTarget.Items.Add($a) }
    $cbTarget.DisplayMember = 'Label'
    $cur = $accounts | Where-Object IsCurrent | Select-Object -First 1
    if ($cur) { $cbTarget.SelectedItem = $cur } elseif ($cbTarget.Items.Count) { $cbTarget.SelectedIndex = 0 }

    # filter combo
    $prevFilter = if ($cbFilter.SelectedItem) { "$($cbFilter.SelectedItem)" } else { 'All accounts' }
    $cbFilter.Items.Clear()
    [void]$cbFilter.Items.Add('All accounts')
    foreach ($a in $accounts) { [void]$cbFilter.Items.Add($a.Label) }
    $idx = [Math]::Max(0, $cbFilter.Items.IndexOf($prevFilter))
    $cbFilter.SelectedIndex = $idx

    Refresh-Grid
}

function Refresh-Grid {
    $grid.Rows.Clear()
    $filter = "$($cbFilter.SelectedItem)"
    foreach ($s in $script:AllSessions) {
        if ($filter -ne 'All accounts' -and ($filter -notlike "$($s.Account.Substring(0,8))*")) { continue }
        $i = $grid.Rows.Add()
        $r = $grid.Rows[$i]
        $r.Cells['Sel'].Value        = $false
        $r.Cells['Account'].Value    = $s.AccountShort
        $r.Cells['Title'].Value      = $s.Title
        $r.Cells['Project'].Value    = $s.Cwd
        $r.Cells['LastActive'].Value = if ($s.LastActivity) { $s.LastActivity.ToString('yyyy-MM-dd HH:mm') } else { '' }
        $r.Cells['Turns'].Value      = $s.Turns
        $r.Cells['Model'].Value      = $s.Model
        $r.Cells['Archived'].Value   = if ($s.Archived) { 'yes' } else { '' }
        if ($s.IsCurrent) { $r.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(235,245,255) }
        $r.Tag = $s
    }
    $lblStatus.Text = "$($grid.Rows.Count) session(s) shown  /  $($script:AllSessions.Count) total."
}

function Get-CheckedSessions {
    $grid.EndEdit() | Out-Null
    $sel = New-Object System.Collections.Generic.List[object]
    foreach ($r in $grid.Rows) { if ($r.Cells['Sel'].Value -eq $true) { $sel.Add($r.Tag) } }
    return ,$sel.ToArray()
}

function Set-AllChecks([bool]$v) {
    foreach ($r in $grid.Rows) { $r.Cells['Sel'].Value = $v }
}

# ---- events ----
$btnRefresh.add_Click({ Populate })
$cbFilter.add_SelectedIndexChanged({ Refresh-Grid })
$btnAll.add_Click({ Set-AllChecks $true })
$btnNone.add_Click({ Set-AllChecks $false })

$btnCopy.add_Click({
    $sel = Get-CheckedSessions
    if (-not $sel.Count) { [System.Windows.Forms.MessageBox]::Show("Select at least one session.","Session Manager") | Out-Null; return }
    $tgt = $cbTarget.SelectedItem
    if (-not $tgt) { return }
    $r = Copy-SessionsTo -Sessions $sel -TargetAcct $tgt
    $lblStatus.Text = "Copied into $($tgt.Short).  New:$($r.New)  Refreshed:$($r.Refreshed)  Kept:$($r.Kept). Restart Claude Desktop to see changes."
    Populate
})

$btnMove.add_Click({
    $sel = Get-CheckedSessions
    if (-not $sel.Count) { [System.Windows.Forms.MessageBox]::Show("Select at least one session.","Session Manager") | Out-Null; return }
    $tgt = $cbTarget.SelectedItem
    if (-not $tgt) { return }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "Move $($sel.Count) session(s) into $($tgt.Short)? They will be removed from their source account (a backup is taken first).",
        "Confirm Move", 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    $bk = Ensure-Backup
    $r = Copy-SessionsTo -Sessions $sel -TargetAcct $tgt -Move
    $lblStatus.Text = "Moved into $($tgt.Short).  New:$($r.New)  Refreshed:$($r.Refreshed)  Kept:$($r.Kept)  Moved:$($r.Moved). Restart Claude Desktop."
    Populate
})

$btnDelete.add_Click({
    $sel = Get-CheckedSessions
    if (-not $sel.Count) { [System.Windows.Forms.MessageBox]::Show("Select at least one session.","Session Manager") | Out-Null; return }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "Remove $($sel.Count) session(s) from the list?`n`nThis deletes only the list entry. The conversation transcript in %USERPROFILE%\.claude\projects is shared and is NOT deleted. A backup is taken first.",
        "Confirm Remove", 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    $bk = Ensure-Backup
    $n = Remove-Sessions -Sessions $sel
    $lblStatus.Text = "Removed $n list entry/entries. Restart Claude Desktop to see changes."
    Populate
})

# ---- assemble (add fill last, bring to front) ----
$form.Controls.Add($top)
$form.Controls.Add($bottom)
$form.Controls.Add($grid)
$grid.BringToFront()

Populate

if ($SelfTest) {
    Write-Host ("SELFTEST OK: store='{0}'  accounts={1}  sessionsLoaded={2}  rowsShown={3}  current={4}" -f `
        $script:Root, (Get-Accounts).Count, $script:AllSessions.Count, $grid.Rows.Count, $script:CurrentAccount.Substring(0,8))
    $form.Dispose()
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
