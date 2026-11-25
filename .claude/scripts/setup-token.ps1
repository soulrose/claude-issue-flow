# Token setup window (double-click ..\setup-token.cmd). Checks the token with the server and saves it through
# issue-flow.ps1 (Save-Token). Nothing is saved if the token does not work.

. (Join-Path $PSScriptRoot 'issue-flow.ps1')

if ($MyInvocation.InvocationName -eq '.') { return }   # dot-sourced: functions only
Set-Location $PSScriptRoot   # inside the repo, so the host can be read from origin

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
try { $TokenPage = Get-TokenPage; $TokenHelp = Get-TokenHelp } catch {
  [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Token setup', 'OK', 'Warning')
  exit 1
}


$font = New-Object System.Drawing.Font('Segoe UI', 10)
$form = New-Object System.Windows.Forms.Form
$form.Text = "Token for $(Get-HostName)"
$form.Font = $font
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true
$form.ClientSize = New-Object System.Drawing.Size(520, 268)

$steps = New-Object System.Windows.Forms.Label
$steps.Location = New-Object System.Drawing.Point(18, 14)
$steps.Size = New-Object System.Drawing.Size(486, 92)
$steps.Text = "1. Create a token:`n    $TokenHelp`n2. Paste it below (Ctrl+V) and press Save.`n    It is checked with $(Get-HostName) before it is saved."
$form.Controls.Add($steps)

$box = New-Object System.Windows.Forms.TextBox
$box.Location = New-Object System.Drawing.Point(20, 112)
$box.Size = New-Object System.Drawing.Size(480, 28)
$box.UseSystemPasswordChar = $true
$form.Controls.Add($box)

$show = New-Object System.Windows.Forms.CheckBox
$show.Location = New-Object System.Drawing.Point(20, 144)
$show.Size = New-Object System.Drawing.Size(200, 24)
$show.Text = 'Show token'
$show.Add_CheckedChanged({ $box.UseSystemPasswordChar = -not $show.Checked })
$form.Controls.Add($show)

$reopen = New-Object System.Windows.Forms.LinkLabel
$reopen.Location = New-Object System.Drawing.Point(250, 146)
$reopen.Size = New-Object System.Drawing.Size(250, 24)
$reopen.TextAlign = 'TopRight'
$reopen.Text = 'Open the token page'
$reopen.Add_LinkClicked({ Start-Process $TokenPage })
$form.Controls.Add($reopen)

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(18, 174)
$status.Size = New-Object System.Drawing.Size(486, 44)
$status.ForeColor = [System.Drawing.Color]::Firebrick
$form.Controls.Add($status)

$save = New-Object System.Windows.Forms.Button
$save.Text = 'Save'
$save.Location = New-Object System.Drawing.Point(300, 224)
$save.Size = New-Object System.Drawing.Size(96, 32)
$form.Controls.Add($save)
$form.AcceptButton = $save

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Cancel'
$cancel.Location = New-Object System.Drawing.Point(404, 224)
$cancel.Size = New-Object System.Drawing.Size(96, 32)
$cancel.DialogResult = 'Cancel'
$form.Controls.Add($cancel)
$form.CancelButton = $cancel

$save.Add_Click({
  $t = $box.Text.Trim()
  if (-not $t) { $status.Text = 'Paste the token first'; return }
  $status.ForeColor = [System.Drawing.Color]::DimGray
  $status.Text = 'Checking...'
  $form.Cursor = 'WaitCursor'; $save.Enabled = $false; $form.Refresh()
  $r = Save-Token $t
  $form.Cursor = 'Default'; $save.Enabled = $true
  if ($r.Ok) {
    $form.Hide()
    [void][System.Windows.Forms.MessageBox]::Show("Done`n`n$($r.Text)", 'Token setup', 'OK', 'Information')
    $form.DialogResult = 'OK'
    $form.Close()
  } else {
    $status.ForeColor = [System.Drawing.Color]::Firebrick
    $status.Text = if ($r.Text) { $r.Text } else { 'Could not save. Try again.' }
    $box.SelectAll(); $box.Focus()
  }
})

$form.Add_Shown({ $form.Activate(); $box.Focus() })
[void]$form.ShowDialog()
